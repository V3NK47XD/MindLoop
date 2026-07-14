import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/models/flashcard.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/sync_service.dart';
import 'package:mobile/services/notification_service.dart';
import 'package:mobile/views/card_view.dart';
import 'package:mobile/views/home_view.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier<ThemeMode>(ThemeMode.light);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize DB and Network services
  final syncService = SyncService();
  await syncService.init();

  // 2. Initialize Notification reminders
  final notificationService = NotificationService();
  await notificationService.init();

  // 3. Load Saved Theme settings
  final prefs = await SharedPreferences.getInstance();
  final themeStr = prefs.getString('theme_mode') ?? 'light';
  if (themeStr == 'dark') {
    themeNotifier.value = ThemeMode.dark;
  } else if (themeStr == 'system') {
    themeNotifier.value = ThemeMode.system;
  } else {
    themeNotifier.value = ThemeMode.light;
  }

  runApp(const MindLoopApp());

  // 4. Listen for notification clicks to Deep Link to CardView
  notificationService.selectNotificationStream.listen((String cardHash) async {
    print("Notification click caught! Deep-linking to card hash: $cardHash");
    final card = await StorageService().getCardById(cardHash);
    if (card != null) {
      navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (context) => CardView(card: card),
        ),
      );
    } else {
      print("Card with hash $cardHash not found in local DB.");
    }
  });
}

class MindLoopApp extends StatelessWidget {
  const MindLoopApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, currentThemeMode, child) {
        return MaterialApp(
          title: 'MindLoop',
          navigatorKey: navigatorKey,
          debugShowCheckedModeBanner: false,
          themeMode: currentThemeMode,
          theme: ThemeData(
            brightness: Brightness.light,
            primaryColor: const Color(0xFF06B6D4), // Cyan
            scaffoldBackgroundColor: const Color(0xFFFCFBF7),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
            ),
          ),
          darkTheme: ThemeData(
            brightness: Brightness.dark,
            primaryColor: const Color(0xFF06B6D4), // Cyan
            scaffoldBackgroundColor: const Color(0xFF0B0F19),
            appBarTheme: const AppBarTheme(
              backgroundColor: Colors.transparent,
              elevation: 0,
              centerTitle: true,
            ),
          ),
          home: const HomeView(),
        );
      },
    );
  }
}
