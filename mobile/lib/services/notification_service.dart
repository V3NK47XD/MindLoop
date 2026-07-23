import 'dart:async';
import 'dart:convert';
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
      final dynamic tzRes = await FlutterTimezone.getLocalTimezone();
      final String timeZoneName = tzRes is String ? tzRes : tzRes.toString();
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      print("Local timezone initialized: $timeZoneName");
    } catch (e) {
      print("Could not initialize local timezone: $e");
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

  // Normalize a tag string for consistent comparison
  static String _normalizeTag(String tag) => tag.trim().toLowerCase();

  // Get cards matching a tag (case-insensitive, trimmed)
  static List<Flashcard> _cardsForTag(List<Flashcard> cards, String tag) {
    final normalizedTag = _normalizeTag(tag);
    return cards.where((c) => c.tags.any((t) => _normalizeTag(t) == normalizedTag)).toList();
  }

  // Process scheduled notifications in SQLite whose scheduled_time has elapsed
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

    // Filter out orphan tags that no longer exist in current cards
    shuffledTags = shuffledTags.where((tag) => _cardsForTag(cards, tag).isNotEmpty).toList();
    completedTags = completedTags.where((tag) => _cardsForTag(cards, tag).isNotEmpty).toList();

    // Reconcile tag set
    final setA = allHashtags.map(_normalizeTag).toSet();
    final setB = shuffledTags.map(_normalizeTag).toSet();
    if (setA.length != setB.length || !setA.containsAll(setB)) {
      shuffledTags = List<String>.from(allHashtags)..shuffle();
      completedTags = [];
      await prefs.setInt('global_rotation_step_pointer', 0);
    }

    // Auto-mark tags as completed if all their cards have view_count > 0
    for (final tag in shuffledTags) {
      final tagCards = _cardsForTag(cards, tag);
      if (tagCards.isNotEmpty && tagCards.every((c) => (counts[c.id] ?? 0) > 0)) {
        if (!completedTags.contains(tag)) {
          completedTags.add(tag);
        }
        await StorageService().markScheduledNotificationsForTagSent(tag);
      }
    }

    // Reset round if all tags are marked completed
    if (completedTags.length >= shuffledTags.length && shuffledTags.isNotEmpty) {
      completedTags = [];
      shuffledTags.shuffle();
      await prefs.setInt('global_rotation_step_pointer', 0);
      await rescheduleReminders(prefs.getInt('notification_frequency') ?? 3, forceReset: true);
    }

    await prefs.setStringList('shuffled_hashtags', shuffledTags);
    await prefs.setStringList('completed_hashtags', completedTags);

    // Process pending scheduled notifications in SQLite
    final pendingList = await StorageService().getScheduledNotifications(pendingOnly: true);
    final now = DateTime.now();

    for (final item in pendingList) {
      final timeStr = item['scheduled_time'] as String;
      final scheduledTime = DateTime.parse(timeStr);
      if (scheduledTime.isBefore(now)) {
        final id = item['id'] as int;
        final cardId = item['card_id'] as String;
        final title = item['title'] as String;
        final body = item['body'] as String;

        // Mark as sent in SQLite
        await StorageService().markScheduledNotificationSent(id);

        // Log into notifications_history
        await StorageService().logNotification(cardId, title, body, scheduledTime);
      }
    }
  }

  // Schedule rotational hashtag reminders into SQLite scheduled_notifications table & Flutter Local Notifications plugin
  // Cycle contains EXACTLY 1 slot per flashcard (e.g. 12 cards = 12 records), grouped by tag.
  Future<void> rescheduleReminders(int frequencyHours, {bool forceReset = false}) async {
    // 1. Clear pending schedule queue in SQLite (preserves sent history unless forceReset = true)
    await StorageService().clearScheduledNotifications(clearSent: forceReset);
    await _notificationsPlugin.cancelAll();
    await StorageService().clearFutureNotifications();

    if (frequencyHours <= 0) {
      print("Reminders disabled (frequency set to 0).");
      return;
    }

    // 2. Load cards
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

    // Read existing items in SQLite to preserve sent history
    final existingItems = await StorageService().getScheduledNotifications();
    final Set<String> processedCardIds = existingItems
        .where((i) => i['status'] == 'sent')
        .map((i) => i['card_id'] as String)
        .toSet();

    int maxSentOrder = 0;
    for (final item in existingItems) {
      if (item['status'] == 'sent') {
        final order = item['slot_order'] as int? ?? 0;
        if (order > maxSentOrder) maxSentOrder = order;
      }
    }

    // Group remaining un-sent flashcards by tag in active tag rotation order
    List<Map<String, dynamic>> scheduledItems = [];

    for (final tag in activeTags) {
      final tagCards = _cardsForTag(cards, tag);
      tagCards.sort((a, b) {
        final viewA = counts[a.id] ?? 0;
        final viewB = counts[b.id] ?? 0;
        if (viewA != viewB) return viewA.compareTo(viewB);
        return a.id.compareTo(b.id);
      });

      for (final card in tagCards) {
        if (!processedCardIds.contains(card.id)) {
          processedCardIds.add(card.id);
          scheduledItems.add({
            'card': card,
            'tag': tag,
          });
        }
      }
    }

    // Include any remaining cards not covered by activeTags
    for (final card in cards) {
      if (!processedCardIds.contains(card.id)) {
        processedCardIds.add(card.id);
        final firstTag = card.tags.isNotEmpty ? card.tags.first.trim() : 'general';
        scheduledItems.add({
          'card': card,
          'tag': firstTag,
        });
      }
    }

    print("Building remaining cycle schedule of ${scheduledItems.length} notifications (starting slot #${maxSentOrder + 1})...");

    List<Map<String, dynamic>> sqliteSlots = [];
    for (int i = 0; i < scheduledItems.length; i++) {
      final slotIndex = maxSentOrder + i + 1;
      final item = scheduledItems[i];
      final card = item['card'] as Flashcard;
      final tag = item['tag'] as String;

      final scheduledTime = tz.TZDateTime.now(tz.local).add(Duration(hours: frequencyHours * (i + 1)));
      final title = 'MindLoop Review - #$tag';
      final body = card.question;

      // Local plugin schedule
      await _notificationsPlugin.zonedSchedule(
        id: slotIndex,
        title: title,
        body: body,
        scheduledDate: scheduledTime,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: card.id,
      );

      // Data for SQLite scheduled_notifications table
      sqliteSlots.add({
        'notification_id': slotIndex,
        'card_id': card.id,
        'tag': tag,
        'title': title,
        'body': body,
        'scheduled_time': scheduledTime.toIso8601String(),
        'slot_order': slotIndex,
        'status': 'pending',
      });
    }

    // Save batch to SQLite scheduled_notifications table
    if (sqliteSlots.isNotEmpty) {
      await StorageService().saveScheduledNotificationsBatch(sqliteSlots);
    }
    print("Saved ${sqliteSlots.length} pending items to scheduled_notifications table in SQLite.");
  }

  // "Send Next Notification" logic:
  // Reads the next pending notification pointer from scheduled_notifications table in SQLite.
  // Cancels its plugin background timer, fires it in 5s, updates status to 'sent', and advances pointer.
  Future<Flashcard?> scheduleNextNotificationAfter5Seconds() async {
    await updateNotificationProgress();

    final prefs = await SharedPreferences.getInstance();
    final frequencyHours = prefs.getInt('notification_frequency') ?? 3;

    // Fetch the single next pending notification from SQLite table pointer
    Map<String, dynamic>? nextItem = await StorageService().getNextPendingScheduledNotification();

    // If queue is empty (all items in current cycle sent), auto-renew cycle and fetch again
    if (nextItem == null) {
      print("No pending scheduled notifications in SQLite. Generating new cycle...");
      await rescheduleReminders(frequencyHours > 0 ? frequencyHours : 3, forceReset: true);
      nextItem = await StorageService().getNextPendingScheduledNotification();
    }

    if (nextItem == null) return null;

    final int rowId = nextItem['id'] as int;
    final int notificationId = nextItem['notification_id'] as int;
    final String cardId = nextItem['card_id'] as String;
    final String tag = nextItem['tag'] as String;
    final String title = nextItem['title'] as String;
    final String body = nextItem['body'] as String;

    // 1. Remove background alert from plugin queue
    await _notificationsPlugin.cancel(id: notificationId);

    // 2. Schedule test alert to fire in 5 seconds
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

    final scheduledTime = tz.TZDateTime.now(tz.local).add(const Duration(seconds: 5));
    final testAlertId = DateTime.now().millisecondsSinceEpoch % 100000;

    try {
      await _notificationsPlugin.zonedSchedule(
        id: testAlertId,
        title: title,
        body: body,
        scheduledDate: scheduledTime,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: cardId,
      );
    } catch (e) {
      print("zonedSchedule failed: $e. Falling back to Timer + show()...");
    }

    // Fallback Timer to guarantee delivery after 5 seconds even if zonedSchedule is restricted by OS
    Timer(const Duration(seconds: 5), () async {
      try {
        await _notificationsPlugin.show(
          id: testAlertId,
          title: title,
          body: body,
          notificationDetails: notificationDetails,
          payload: cardId,
        );
      } catch (err) {
        print("Fallback show error: $err");
      }
    });

    // 3. Mark row as 'sent' in SQLite scheduled_notifications table (advances the pointer)
    await StorageService().markScheduledNotificationSent(rowId);

    // 4. Log to notifications_history table
    await StorageService().logNotification(cardId, title, body, scheduledTime);

    // 5. Update global rotation step pointer for UI NEXT tag sync
    int stepPointer = prefs.getInt('global_rotation_step_pointer') ?? 0;
    await prefs.setInt('global_rotation_step_pointer', stepPointer + 1);

    print("Next notification sent from SQLite queue (Row #$rowId | Tag #$tag | Card: $cardId). Firing in 5s!");
    return await StorageService().getCardById(cardId);
  }
}
