import 'package:flutter/material';
import 'package:mobile/models/flashcard.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/sync_service.dart';
import 'package:mobile/services/notification_service.dart';
import 'package:mobile/views/card_view.dart';
import 'package:mobile/views/home_view.dart';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // 1. Initialize DB and Network services
  final syncService = SyncService();
  await syncService.init();

  // 2. Initialize Notification reminders
  final notificationService = NotificationService();
  await notificationService.init();

  runApp(const MindLoopApp());

  // 3. Listen for notification clicks to Deep Link to CardView
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
    return MaterialApp(
      title: 'MindLoop',
      navigatorKey: navigatorKey,
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        primaryColor: const Color(0xFF6366F1), // Premium Indigo
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFF6366F1),
          secondary: Color(0xFFEC4899), // Premium Pink
          surface: Color(0xFF111928),
        ),
        scaffoldBackgroundColor: const Color(0xFF0B0F19), // Clean Dark
        appBarTheme: const AppBarTheme(
          backgroundColor: Colors.transparent,
          elevation: 0,
          centerTitle: true,
        ),
      ),
      home: const HomeView(),
    );
  }
}
