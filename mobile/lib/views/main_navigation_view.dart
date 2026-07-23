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
  final GlobalKey<NotificationsHistoryViewState> _historyKey = GlobalKey<NotificationsHistoryViewState>();

  late final List<Widget> _pages;

  @override
  void initState() {
    super.initState();
    _pages = [
      NotificationsHistoryView(key: _historyKey),
      const HomeView(),
      const NotificationsView(),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final panelBg = isDark ? const Color(0xFF1E293B) : Colors.white;
    final borderColor = isDark ? const Color(0xFF38BDF8) : Colors.black;
    final shadowColor = isDark ? Colors.black45 : Colors.black;

    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _pages,
      ),
      bottomNavigationBar: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.only(left: 16.0, right: 16.0, bottom: 16.0, top: 4.0),
          child: Container(
            decoration: BoxDecoration(
              color: panelBg,
              borderRadius: BorderRadius.circular(20.0),
              border: Border.all(color: borderColor, width: 3.0),
              boxShadow: [
                BoxShadow(
                  color: shadowColor,
                  offset: const Offset(4, 4),
                  blurRadius: 0,
                ),
              ],
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16.0),
              child: BottomNavigationBar(
                currentIndex: _currentIndex,
                onTap: (index) {
                  if (index == 0) {
                    _historyKey.currentState?.refreshHistory();
                  }
                  setState(() {
                    _currentIndex = index;
                  });
                },
                backgroundColor: Colors.transparent,
                selectedItemColor: isDark ? const Color(0xFF38BDF8) : const Color(0xFF06B6D4),
                unselectedItemColor: isDark ? Colors.grey[400] : Colors.grey[600],
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
          ),
        ),
      ),
    );
  }
}
