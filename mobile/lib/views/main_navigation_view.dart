import 'package:flutter/material.dart';
import 'package:mobile/views/notifications_history_view.dart';
import 'package:mobile/views/home_view.dart';
import 'package:mobile/views/notifications_view.dart';

class MainNavigationView extends StatefulWidget {
  const MainNavigationView({super.key});

  @override
  State<MainNavigationView> createState() => _MainNavigationViewState();
}

class _MainNavigationViewState extends State<MainNavigationView> {
  int _currentIndex = 0;

  final List<Widget> _pages = const [
    NotificationsHistoryView(),
    HomeView(),
    NotificationsView(),
  ];

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark ? const Color(0xFF111827) : Colors.white;
    final borderColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: Container(
        decoration: BoxDecoration(
          color: panelBg,
          border: Border(
            top: BorderSide(color: borderColor, width: 3.0),
          ),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          backgroundColor: panelBg,
          selectedItemColor: isDark ? Colors.cyan : const Color(0xFF06B6D4),
          unselectedItemColor: isDark ? Colors.grey[500] : Colors.grey[600],
          selectedLabelStyle: const TextStyle(fontWeight: FontWeight.w900, fontSize: 11, letterSpacing: 0.5),
          unselectedLabelStyle: const TextStyle(fontWeight: FontWeight.w800, fontSize: 10, letterSpacing: 0.5),
          type: BottomNavigationBarType.fixed,
          elevation: 0,
          items: const [
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.history_toggle_off_rounded),
              ),
              label: 'HISTORY',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.swap_horizontal_circle_outlined),
              ),
              label: 'SYNC & LIBRARY',
            ),
            BottomNavigationBarItem(
              icon: Padding(
                padding: EdgeInsets.only(bottom: 4.0),
                child: Icon(Icons.settings_outlined),
              ),
              label: 'SETTINGS',
            ),
          ],
        ),
      ),
    );
  }
}
