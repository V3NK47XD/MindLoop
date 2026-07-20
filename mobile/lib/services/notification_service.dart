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

  // Helper to check if all cards under a tag have been viewed
  Future<bool> _isTagFullyViewed(String tag, List<Flashcard> cards) async {
    final prefs = await SharedPreferences.getInstance();
    final countsRaw = prefs.getString('card_view_counts');
    if (countsRaw == null) return false;
    try {
      final Map<String, dynamic> counts = jsonDecode(countsRaw);
      final tagCards = cards.where((c) => c.tags.contains(tag)).toList();
      if (tagCards.isEmpty) return true;
      return tagCards.every((c) => (counts[c.id] ?? 0) > 0);
    } catch (_) {
      return false;
    }
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

        for (final slot in oldSlots) {
          final timeStr = slot['time'] as String;
          final time = DateTime.parse(timeStr);
          if (!time.isBefore(now)) {
            remainingSlots.add(slot);
          }
        }

        if (remainingSlots.length != oldSlots.length) {
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

    // Auto-complete tags that are fully viewed in library
    bool completedChanged = false;
    for (final tag in shuffledTags) {
      if (!completedTags.contains(tag)) {
        final isViewed = await _isTagFullyViewed(tag, cards);
        if (isViewed) {
          completedTags.add(tag);
          completedChanged = true;
        }
      }
    }

    // Reset round if all tags are marked completed (either manually checked or fully viewed)
    if (completedTags.length >= shuffledTags.length && shuffledTags.isNotEmpty) {
      completedTags = [];
      shuffledTags.shuffle();
      completedChanged = true;
    }

    if (completedChanged) {
      await prefs.setStringList('shuffled_hashtags', shuffledTags);
      await prefs.setStringList('completed_hashtags', completedTags);
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

    // 5. Generate rotational schedule sequence for the active tag group
    List<Map<String, dynamic>> scheduledSlotsData = [];
    int slotIndex = 1;

    // Find the active tag (first incomplete tag)
    String? activeTag;
    for (final tag in shuffledTags) {
      if (!completedTags.contains(tag)) {
        activeTag = tag;
        break;
      }
    }

    if (activeTag == null) {
      print("All tags completed, could not resolve active tag.");
      return;
    }

    // Load view counts for prioritizing unviewed cards
    final countsRaw = prefs.getString('card_view_counts');
    Map<String, int> counts = {};
    if (countsRaw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(countsRaw);
        decoded.forEach((key, val) {
          if (val is int) {
            counts[key] = val;
          }
        });
      } catch (_) {}
    }

    // Get cards under activeTag and sort: unviewed cards first
    final tagCards = cards.where((c) => c.tags.contains(activeTag)).toList();
    tagCards.sort((a, b) {
      final viewA = counts[a.id] ?? 0;
      final viewB = counts[b.id] ?? 0;
      return viewA.compareTo(viewB);
    });

    if (tagCards.isEmpty) {
      print("No cards found for active tag: $activeTag");
      return;
    }

    print("Scheduling next $slotsCount reminders, every $frequencyHours hours... (Active Tag: $activeTag)");

    int cardIndex = 0;
    while (slotIndex <= slotsCount) {
      final card = tagCards[cardIndex % tagCards.length];
      cardIndex++;

      final scheduledTime = tz.TZDateTime.now(tz.local).add(Duration(hours: frequencyHours * slotIndex));

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

      // Log notification history (now standardizes automatically to UTC inside logNotification)
      await StorageService().logNotification(
        card.id,
        'MindLoop Review - #$activeTag',
        card.question,
        scheduledTime,
      );

      scheduledSlotsData.add({
        'time': scheduledTime.toIso8601String(),
        'tag': activeTag,
        'is_last_for_tag': false,
      });

      print("Scheduled reminder #$slotIndex at $scheduledTime (Tag: $activeTag | Card: ${card.id})");
      slotIndex++;
    }

    // Save scheduled slots
    await prefs.setString('scheduled_slots', jsonEncode(scheduledSlotsData));
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
