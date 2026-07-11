import 'dart:async';
import 'dart:math';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
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
    await _notificationsPlugin
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
  }

  // Schedule a batch of 7 future reminders (one for each interval step) containing random questions
  Future<void> rescheduleReminders(int frequencyHours) async {
    // A. Cancel all previously scheduled reminders
    await _notificationsPlugin.cancelAll();
    
    if (frequencyHours <= 0) {
      print("Reminders disabled (frequency set to 0).");
      return;
    }

    // B. Get all cards to pick from
    final cards = await StorageService().getAllCards();
    if (cards.isEmpty) {
      print("No cards available to schedule reminders.");
      return;
    }

    final random = Random();
    final androidDetails = const AndroidNotificationDetails(
      'mindloop_reminders',
      'MindLoop Reminders',
      channelDescription: 'Duolingo-style random flashcard question alerts',
      importance: Importance.max,
      priority: Priority.high,
      playSound: true,
    );
    final iosDetails = const DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    final notificationDetails = NotificationDetails(android: androidDetails, iOS: iosDetails);

    print("Scheduling next 7 reminders, every $frequencyHours hours...");
    
    // C. Schedule up to 7 items in the future
    for (int i = 1; i <= 7; i++) {
      // Select a random card
      final card = cards[random.nextInt(cards.length)];
      final scheduledTime = tz.TZDateTime.now(tz.local).add(Duration(hours: frequencyHours * i));

      await _notificationsPlugin.zonedSchedule(
        id: i,
        title: 'MindLoop Review!',
        body: card.question,
        scheduledDate: scheduledTime,
        notificationDetails: notificationDetails,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        payload: card.id,
      );
      print("Scheduled reminder #$i at $scheduledTime (Card: ${card.id})");
    }
  }

  // Helper to show an instant notification for testing
  Future<void> showTestNotification(String title, String body, String payload) async {
    const AndroidNotificationDetails androidDetails = AndroidNotificationDetails(
      'mindloop_test',
      'Test Channel',
      importance: Importance.max,
      priority: Priority.high,
    );
    const NotificationDetails details = NotificationDetails(android: androidDetails);
    await _notificationsPlugin.show(
      id: 999,
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }
}
