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

    final countsRaw = prefs.getString('card_view_counts');
    Map<String, int> counts = {};
    if (countsRaw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(countsRaw);
        decoded.forEach((key, val) {
          if (val is int) counts[key] = val;
        });
      } catch (_) {}
    }

    final allHashtags = cards
        .expand((c) => c.tags)
        .map((t) => t.trim())
        .where((t) => t.isNotEmpty)
        .toSet()
        .toList();
    allHashtags.sort();

    List<String> shuffledTags = prefs.getStringList('shuffled_hashtags') ?? [];
    List<String> completedTags = prefs.getStringList('completed_hashtags') ?? [];

    // Reconcile tag set
    final setA = allHashtags.toSet();
    final setB = shuffledTags.toSet();
    if (setA.length != setB.length || !setA.containsAll(setB)) {
      shuffledTags = List<String>.from(allHashtags)..shuffle();
      completedTags = [];
    }

    // Auto-mark tags as completed if all their cards have view_count > 0
    for (final tag in shuffledTags) {
      final tagCards = cards.where((c) => c.tags.any((t) => t.trim().toLowerCase() == tag.trim().toLowerCase())).toList();
      if (tagCards.isNotEmpty && tagCards.every((c) => (counts[c.id] ?? 0) > 0)) {
        if (!completedTags.contains(tag)) {
          completedTags.add(tag);
        }
      }
    }

    // Reset round if all tags are marked completed
    if (completedTags.length >= shuffledTags.length && shuffledTags.isNotEmpty) {
      completedTags = [];
      shuffledTags.shuffle();
    }

    await prefs.setStringList('shuffled_hashtags', shuffledTags);
    await prefs.setStringList('completed_hashtags', completedTags);

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

    List<String> activeTags = shuffledTags.where((t) => !completedTags.contains(t)).toList();
    if (activeTags.isEmpty && shuffledTags.isNotEmpty) {
      completedTags = [];
      activeTags = List<String>.from(shuffledTags);
      await prefs.setStringList('completed_hashtags', completedTags);
    }

    if (activeTags.isEmpty) {
      print("No active hashtags found to schedule reminders.");
      return;
    }

    // 4. Calculate total slots for 7 days
    int slotsCount = (7 * 24 / frequencyHours).floor();
    if (slotsCount > 48) slotsCount = 48; // Android safety cap

    const androidDetails = AndroidNotificationDetails(
      'mindloop_reminders',
      'MindLoop Reminders',
      channelDescription: 'Rotational hashtag flashcard alerts',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
      largeIcon: DrawableResourceAndroidBitmap('@mipmap/ic_launcher'),
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const notificationDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);

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

    print("Scheduling next $slotsCount reminders, every $frequencyHours hours... (Active Tags: $activeTags)");

    List<Map<String, dynamic>> scheduledSlotsData = [];
    Map<String, int> tagPointers = {};

    for (int slotIndex = 1; slotIndex <= slotsCount; slotIndex++) {
      // Pick active tag in rotation
      final tag = activeTags[(slotIndex - 1) % activeTags.length];

      // Get cards for tag, sorted by view count (unviewed first), then by card ID
      final tagCards = cards.where((c) => c.tags.any((t) => t.trim().toLowerCase() == tag.trim().toLowerCase())).toList();
      tagCards.sort((a, b) {
        final viewA = counts[a.id] ?? 0;
        final viewB = counts[b.id] ?? 0;
        if (viewA != viewB) return viewA.compareTo(viewB);
        return a.id.compareTo(b.id);
      });

      if (tagCards.isEmpty) continue;

      final ptr = tagPointers[tag] ?? 0;
      final card = tagCards[ptr % tagCards.length];
      tagPointers[tag] = ptr + 1;

      final scheduledTime = tz.TZDateTime.now(tz.local).add(Duration(hours: frequencyHours * slotIndex));

      // Schedule local notification
      await _notificationsPlugin.zonedSchedule(
        id: slotIndex,
        title: 'MindLoop Review - #$tag',
        body: card.question,
        scheduledDate: scheduledTime,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: card.id,
      );

      // Log notification history
      await StorageService().logNotification(
        card.id,
        'MindLoop Review - #$tag',
        card.question,
        scheduledTime,
      );

      scheduledSlotsData.add({
        'time': scheduledTime.toIso8601String(),
        'tag': tag,
      });

      print("Scheduled reminder #$slotIndex at $scheduledTime (Tag: $tag | Card: ${card.id})");
    }

    // Save scheduled slots
    await prefs.setString('scheduled_slots', jsonEncode(scheduledSlotsData));
  }

  // Helper to schedule the next notification in rotation after a 5-second delay
  Future<Flashcard?> scheduleNextNotificationAfter5Seconds() async {
    await updateNotificationProgress();

    final cards = await StorageService().getAllCards();
    if (cards.isEmpty) return null;

    final prefs = await SharedPreferences.getInstance();
    List<String> shuffledTags = prefs.getStringList('shuffled_hashtags') ?? [];
    List<String> completedTags = prefs.getStringList('completed_hashtags') ?? [];

    List<String> activeTags = shuffledTags.where((t) => !completedTags.contains(t)).toList();
    if (activeTags.isEmpty && shuffledTags.isNotEmpty) {
      completedTags = [];
      activeTags = List<String>.from(shuffledTags);
      await prefs.setStringList('completed_hashtags', completedTags);
    }
    if (activeTags.isEmpty) return null;

    // Get current global rotation step pointer
    int stepPointer = prefs.getInt('global_rotation_step_pointer') ?? 0;

    // Pick tag from activeTags rotationally
    final tag = activeTags[stepPointer % activeTags.length];

    // Load view counts
    final countsRaw = prefs.getString('card_view_counts');
    Map<String, int> counts = {};
    if (countsRaw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(countsRaw);
        decoded.forEach((key, val) {
          if (val is int) counts[key] = val;
        });
      } catch (_) {}
    }

    // Get cards for tag, unviewed first, then by ID
    final tagCards = cards.where((c) => c.tags.any((t) => t.trim().toLowerCase() == tag.trim().toLowerCase())).toList();
    tagCards.sort((a, b) {
      final viewA = counts[a.id] ?? 0;
      final viewB = counts[b.id] ?? 0;
      if (viewA != viewB) return viewA.compareTo(viewB);
      return a.id.compareTo(b.id);
    });

    final cardPointer = (stepPointer ~/ activeTags.length);
    final card = tagCards.isNotEmpty
        ? tagCards[cardPointer % tagCards.length]
        : cards[stepPointer % cards.length];

    // Increment global step pointer for next tap
    await prefs.setInt('global_rotation_step_pointer', stepPointer + 1);

    final title = 'MindLoop Review - #$tag';
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'mindloop_reminders',
      'MindLoop Reminders',
      channelDescription: 'Rotational hashtag flashcard alerts',
      importance: Importance.max,
      priority: Priority.max,
      playSound: true,
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
      id: DateTime.now().millisecondsSinceEpoch % 100000,
      title: title,
      body: card.question,
      scheduledDate: scheduledTime,
      notificationDetails: details,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
      payload: card.id,
    );

    // Log notification in history
    await StorageService().logNotification(
      card.id,
      title,
      card.question,
      scheduledTime,
    );
    print("Scheduled next notification (#$tag - ${card.question}) to fire in 5 seconds at: $scheduledTime");
    return card;
  }
}
