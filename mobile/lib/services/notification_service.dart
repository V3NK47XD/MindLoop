import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:mobile/models/flashcard.dart';
import 'package:mobile/services/storage_service.dart';

class NotificationService {
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _notificationsPlugin = FlutterLocalNotificationsPlugin();
  
  // Stream to notify the main app when a deep link is clicked
  final StreamController<String> _selectNotificationStream = StreamController<String>.broadcast();
  Stream<String> get selectNotificationStream => _selectNotificationStream.stream;

  Future<void> init() async {
    // 1. Initialize Timezones
    tz.initializeTimeZones();
    try {
      final timeZoneInfo = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = timeZoneInfo.identifier;
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      print("Local timezone initialized: $timeZoneName");
    } catch (e) {
      print("Could not initialize local timezone, defaulting to UTC: $e");
    }

    // 2. Android Initialization
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // 3. iOS Initialization
    const DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    // 4. Initialize Plugin
    await _notificationsPlugin.initialize(
      settings: initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        final String? payload = response.payload;
        if (payload != null && payload.isNotEmpty) {
          _selectNotificationStream.add(payload);
        }
      },
    );

    // Request permissions for Android 13+
    final androidPlugin = _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
        
    await androidPlugin?.requestNotificationsPermission();
    await androidPlugin?.requestExactAlarmsPermission();
  }

  // Read background alert schedule history and synchronize the checklist progression
  Future<void> updateNotificationProgress() async {
    final prefs = await SharedPreferences.getInstance();
    final cards = await StorageService().getAllCards();
    if (cards.isEmpty) return;

    final allHashtags = cards
        .expand((c) => c.tags)
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    allHashtags.sort();

    List<String> shuffledTags = prefs.getStringList('shuffled_hashtags') ?? [];
    List<String> completedTags = prefs.getStringList('completed_hashtags') ?? [];

    // Reconcile active tag set
    final setA = allHashtags.toSet();
    final setB = shuffledTags.toSet();
    if (setA.length != setB.length || !setA.containsAll(setB)) {
      shuffledTags = List<String>.from(allHashtags)..shuffle();
      completedTags = [];
      await prefs.setStringList('shuffled_hashtags', shuffledTags);
      await prefs.setStringList('completed_hashtags', completedTags);
    }

    final slotsRaw = prefs.getString('scheduled_slots');
    if (slotsRaw != null) {
      try {
        final List<dynamic> oldSlots = jsonDecode(slotsRaw);
        final now = DateTime.now();
        List<dynamic> remainingSlots = [];
        bool changed = false;

        for (final slot in oldSlots) {
          final timeStr = slot['time'] as String;
          final time = DateTime.parse(timeStr);
          if (time.isBefore(now)) {
            final tag = slot['tag'] as String;
            final isLast = slot['is_last_for_tag'] as bool? ?? false;
            if (isLast) {
              if (!completedTags.contains(tag)) {
                completedTags.add(tag);
                changed = true;
              }
            }
          } else {
            remainingSlots.add(slot);
          }
        }

        // Reset round if all tags are marked completed
        if (completedTags.length >= shuffledTags.length && shuffledTags.isNotEmpty) {
          completedTags = [];
          shuffledTags.shuffle();
          changed = true;
        }

        if (changed || remainingSlots.length != oldSlots.length) {
          await prefs.setStringList('shuffled_hashtags', shuffledTags);
          await prefs.setStringList('completed_hashtags', completedTags);
          await prefs.setString('scheduled_slots', jsonEncode(remainingSlots));
        }
      } catch (e) {
        print("Error updating notification progress: $e");
      }
    }
  }

  // Schedule rotational hashtag reminders covering the next 7 days (capped at 48 safety limit)
  Future<void> rescheduleReminders(int frequencyHours) async {
    // 1. Process past alerts to synchronize checklist state
    await updateNotificationProgress();

    // 2. Cancel all scheduled alerts
    await _notificationsPlugin.cancelAll();
    await StorageService().clearFutureNotifications();
    
    if (frequencyHours <= 0) {
      print("Reminders disabled (frequency set to 0).");
      return;
    }

    // 3. Get all cards
    final cards = await StorageService().getAllCards();
    if (cards.isEmpty) {
      print("No cards available to schedule reminders.");
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    List<String> shuffledTags = prefs.getStringList('shuffled_hashtags') ?? [];
    List<String> completedTags = prefs.getStringList('completed_hashtags') ?? [];

    final allHashtags = cards
        .expand((c) => c.tags)
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    allHashtags.sort();

    // Reconcile active tag set
    final setA = allHashtags.toSet();
    final setB = shuffledTags.toSet();
    if (setA.length != setB.length || !setA.containsAll(setB)) {
      shuffledTags = List<String>.from(allHashtags)..shuffle();
      completedTags = [];
      await prefs.setStringList('shuffled_hashtags', shuffledTags);
      await prefs.setStringList('completed_hashtags', completedTags);
    }

    if (shuffledTags.isEmpty) {
      print("No hashtags found to schedule reminders.");
      return;
    }

    // 4. Calculate total slots for 7 days
    int slotsCount = (7 * 24 / frequencyHours).floor();
    if (slotsCount > 48) slotsCount = 48; // Android safety cap

    final androidDetails = const AndroidNotificationDetails(
      'mindloop_reminders',
      'MindLoop Reminders',
      channelDescription: 'Rotational hashtag flashcard alerts',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );
    final iosDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final notificationDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);

    // 5. Generate rotational schedule sequence
    List<Map<String, dynamic>> scheduledSlotsData = [];
    List<String> localCompleted = List<String>.from(completedTags);
    List<String> localShuffled = List<String>.from(shuffledTags);
    
    // Map of tag -> list of cards left to schedule in this round
    Map<String, List<Flashcard>> tagCardQueues = {};
    int slotIndex = 1;

    print("Scheduling next $slotsCount reminders, every $frequencyHours hours...");

    while (slotIndex <= slotsCount) {
      // Check if current round is fully complete
      if (localCompleted.length >= localShuffled.length && localShuffled.isNotEmpty) {
        localCompleted.clear();
        localShuffled.shuffle();
      }

      // Find the next incomplete tag
      String? activeTag;
      for (final tag in localShuffled) {
        if (!localCompleted.contains(tag)) {
          activeTag = tag;
          break;
        }
      }

      if (activeTag == null) {
        break;
      }

      // Fill card queue for activeTag if empty
      if (!tagCardQueues.containsKey(activeTag) || tagCardQueues[activeTag]!.isEmpty) {
        final tagCards = cards.where((c) => c.tags.contains(activeTag)).toList();
        tagCards.shuffle();
        tagCardQueues[activeTag] = tagCards;
      }

      final queue = tagCardQueues[activeTag]!;
      if (queue.isEmpty) {
        // Tag has no cards, mark completed and proceed
        localCompleted.add(activeTag);
        continue;
      }

      final card = queue.removeLast();
      final scheduledTime = tz.TZDateTime.now(tz.local).add(Duration(hours: frequencyHours * slotIndex));

      // Is this the last card in queue for this tag?
      final bool isLast = queue.isEmpty;

      // Schedule local notification
      await _notificationsPlugin.zonedSchedule(
        id: slotIndex,
        title: 'MindLoop Review - #$activeTag',
        body: card.question,
        scheduledDate: scheduledTime,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: card.id,
      );

      // Log notification history
      await StorageService().logNotification(
        card.id,
        'MindLoop Review - #$activeTag',
        card.question,
        scheduledTime,
      );

      scheduledSlotsData.add({
        'time': scheduledTime.toIso8601String(),
        'tag': activeTag,
        'is_last_for_tag': isLast,
      });

      if (isLast) {
        localCompleted.add(activeTag);
      }

      print("Scheduled reminder #$slotIndex at $scheduledTime (Tag: $activeTag | Card: ${card.id})");
      slotIndex++;
    }

    // Save scheduled slots and updated states
    await prefs.setString('scheduled_slots', jsonEncode(scheduledSlotsData));
    await prefs.setStringList('shuffled_hashtags', shuffledTags);
    await prefs.setStringList('completed_hashtags', completedTags);
  }

  // Helper to schedule a test notification after 5 seconds
  Future<void> scheduleTestNotificationAfter5Seconds(String title, String body, String payload) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'mindloop_test',
      'Test Channel',
      importance: Importance.max,
      priority: Priority.max,
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );
    const DarwinNotificationDetails iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails, iOS: iosDetails);
    
    final scheduledTime = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5));
    
    await _notificationsPlugin.zonedSchedule(
      id: 999,
      title: title,
      body: body,
      scheduledDate: scheduledTime,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: payload,
    );
    
    // Log test notification in history
    await StorageService().logNotification(
      payload,
      title,
      body,
      scheduledTime,
    );
    print("Scheduled test notification to fire in 5 seconds at: $scheduledTime");
  }
}
