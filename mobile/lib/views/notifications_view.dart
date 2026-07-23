import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/models/flashcard.dart';
import 'package:mobile/services/notification_service.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/widgets/paper_background.dart';
import 'package:mobile/main.dart'; // To access themeNotifier

class NotificationsView extends StatefulWidget {
  const NotificationsView({super.key});

  @override
  State<NotificationsView> createState() => _NotificationsViewState();
}

class _NotificationsViewState extends State<NotificationsView> {
  final NotificationService _notificationService = NotificationService();
  int _frequencyHours = 3; // Default every 3 hours
  List<String> _shuffledTags = [];
  List<String> _completedTags = [];
  List<String> _fullyViewedTags = [];
  bool _isLoading = true;
  String _themeModeStr = 'light';

  @override
  void initState() {
    super.initState();
    _loadSettingsAndChecklist();
  }

  Future<void> _loadSettingsAndChecklist() async {
    // 1. Process background alerts progress first
    await _notificationService.updateNotificationProgress();

    // 2. Load settings from SharedPreferences
    final prefs = await SharedPreferences.getInstance();
    final cards = await StorageService().getAllCards();
    final countsRaw = prefs.getString('card_view_counts');
    Map<String, int> counts = {};
    if (countsRaw != null) {
      try {
        final Map<String, dynamic> decoded = jsonDecode(countsRaw);
        decoded.forEach((key, value) {
          if (value is int) {
            counts[key] = value;
          }
        });
      } catch (_) {}
    }

    final Set<String> fullyViewedTags = {};
    final Map<String, List<Flashcard>> cardsByTag = {};
    for (final card in cards) {
      for (final tag in card.tags) {
        cardsByTag.putIfAbsent(tag, () => []).add(card);
      }
    }
    cardsByTag.forEach((tag, tagCards) {
      if (tagCards.isNotEmpty && tagCards.every((c) => (counts[c.id] ?? 0) > 0)) {
        fullyViewedTags.add(tag);
      }
    });

    if (mounted) {
      setState(() {
        _frequencyHours = prefs.getInt('notification_frequency') ?? 3;
        _shuffledTags = prefs.getStringList('shuffled_hashtags') ?? [];
        _completedTags = prefs.getStringList('completed_hashtags') ?? [];
        _fullyViewedTags = fullyViewedTags.toList();
        _themeModeStr = prefs.getString('theme_mode') ?? 'light';
        _isLoading = false;
      });
    }
  }

  Future<void> _saveFrequency(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notification_frequency', hours);
    setState(() {
      _frequencyHours = hours;
    });
    // Reschedule in Notification Service
    await _notificationService.rescheduleReminders(hours);
    await _loadSettingsAndChecklist();
  }

  Future<void> _saveThemeMode(String mode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('theme_mode', mode);
    setState(() {
      _themeModeStr = mode;
    });
    
    // Dynamically update the Global ValueNotifier
    if (mode == 'dark') {
      themeNotifier.value = ThemeMode.dark;
    } else if (mode == 'system') {
      themeNotifier.value = ThemeMode.system;
    } else {
      themeNotifier.value = ThemeMode.light;
    }
  }

  Future<void> _toggleTagCompletion(String tag, bool isCompleted) async {
    final prefs = await SharedPreferences.getInstance();
    List<String> completed = prefs.getStringList('completed_hashtags') ?? [];
    List<String> shuffled = prefs.getStringList('shuffled_hashtags') ?? [];

    if (isCompleted) {
      if (!completed.contains(tag)) {
        completed.add(tag);
      }
    } else {
      completed.remove(tag);
    }

    if (completed.length >= shuffled.length && shuffled.isNotEmpty) {
      completed = [];
      shuffled.shuffle();
      await prefs.setStringList('shuffled_hashtags', shuffled);
    }

    await prefs.setStringList('completed_hashtags', completed);
    setState(() {
      _shuffledTags = shuffled;
      _completedTags = completed;
    });

    await _notificationService.rescheduleReminders(_frequencyHours);
    await _loadSettingsAndChecklist();
  }

  String? get _activeTag {
    for (final tag in _shuffledTags) {
      if (!_completedTags.contains(tag)) {
        return tag;
      }
    }
    return _shuffledTags.isNotEmpty ? _shuffledTags.first : null;
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final panelBg = isDark ? const Color(0xFF111827) : Colors.white;
    final borderColor = isDark ? Colors.white : Colors.black;
    final shadowColor = isDark ? Colors.white.withOpacity(0.1) : Colors.black.withOpacity(0.15);

    final activeTag = _activeTag;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'STUDY REMINDERS',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: textColor, letterSpacing: 1),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
        iconTheme: IconThemeData(color: textColor),
      ),
      body: PaperBackground(
        isDark: isDark,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: borderColor))
            : SafeArea(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 20.0, vertical: 10.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Description Header Box
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: panelBg,
                          border: Border.all(color: borderColor, width: 2.5),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: borderColor, offset: const Offset(4, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'ROTATION SETTINGS',
                              style: TextStyle(color: textColor, fontSize: 15, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 6),
                            Text(
                              'Reminders cycle sequentially through flashcards grouped by matching hashtags. Tapping tags in the checklist below configures the active cycle.',
                              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700], fontSize: 12, height: 1.4),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Interval Selector & Theme Selector
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: panelBg,
                          border: Border.all(color: borderColor, width: 2.5),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: borderColor, offset: const Offset(4, 4)),
                          ],
                        ),
                        child: Column(
                          children: [
                            DropdownButtonFormField<int>(
                              value: _frequencyHours,
                              dropdownColor: panelBg,
                              decoration: InputDecoration(
                                labelText: 'NOTIFICATION INTERVAL',
                                labelStyle: TextStyle(color: textColor.withOpacity(0.6), fontWeight: FontWeight.w800, fontSize: 11),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: borderColor, width: 2.0),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: isDark ? Colors.cyan : const Color(0xFF06B6D4), width: 2.0),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
                              items: const [
                                DropdownMenuItem(value: 0, child: Text('MUTED / DISABLED')),
                                DropdownMenuItem(value: 1, child: Text('EVERY HOUR')),
                                DropdownMenuItem(value: 3, child: Text('EVERY 3 HOURS')),
                                DropdownMenuItem(value: 6, child: Text('EVERY 6 HOURS')),
                                DropdownMenuItem(value: 12, child: Text('EVERY 12 HOURS')),
                                DropdownMenuItem(value: 24, child: Text('EVERY 24 HOURS')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  _saveFrequency(val);
                                }
                              },
                            ),
                            const SizedBox(height: 20),
                            DropdownButtonFormField<String>(
                              value: _themeModeStr,
                              dropdownColor: panelBg,
                              decoration: InputDecoration(
                                labelText: 'NOTEBOOK THEME',
                                labelStyle: TextStyle(color: textColor.withOpacity(0.6), fontWeight: FontWeight.w800, fontSize: 11),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: borderColor, width: 2.0),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(color: isDark ? Colors.cyan : const Color(0xFF06B6D4), width: 2.0),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              style: TextStyle(color: textColor, fontWeight: FontWeight.w700),
                              items: const [
                                DropdownMenuItem(value: 'light', child: Text('LIGHT NOTEBOOK (DEFAULT)')),
                                DropdownMenuItem(value: 'dark', child: Text('GRAPHITE DARK NOTEBOOK')),
                                DropdownMenuItem(value: 'system', child: Text('SYSTEM DEFAULTS')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  _saveThemeMode(val);
                                }
                              },
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 20),

                      // Rotation Progress Checklist Card
                      if (_shuffledTags.isNotEmpty) ...[
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(18),
                          decoration: BoxDecoration(
                            color: panelBg,
                            border: Border.all(color: borderColor, width: 2.5),
                            borderRadius: BorderRadius.circular(12),
                            boxShadow: [
                              BoxShadow(color: borderColor, offset: const Offset(4, 4)),
                            ],
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(Icons.checklist_rtl_rounded, color: Colors.cyan, size: 22),
                                      const SizedBox(width: 8),
                                      Text(
                                        'ROTATION PROGRESS',
                                        style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textColor),
                                      ),
                                    ],
                                  ),
                                  Text(
                                    '${_shuffledTags.where((t) => _completedTags.contains(t)).length}/${_shuffledTags.length} DONE',
                                    style: TextStyle(color: textColor, fontSize: 12, fontWeight: FontWeight.w900),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 12),
                              ClipRRect(
                                borderRadius: BorderRadius.circular(4),
                                child: LinearProgressIndicator(
                                  value: _shuffledTags.isEmpty 
                                      ? 0 
                                      : _shuffledTags.where((t) => _completedTags.contains(t)).length / _shuffledTags.length,
                                  backgroundColor: isDark ? Colors.white12 : Colors.black12,
                                  valueColor: const AlwaysStoppedAnimation<Color>(Colors.green),
                                  minHeight: 8,
                                ),
                              ),
                              if (activeTag != null) ...[
                                const SizedBox(height: 14),
                                Container(
                                  width: double.infinity,
                                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                                  decoration: BoxDecoration(
                                    color: isDark ? Colors.cyan.withOpacity(0.15) : const Color(0xFF06B6D4).withOpacity(0.12),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: isDark ? Colors.cyan : const Color(0xFF06B6D4),
                                      width: 2.0,
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.notifications_active_rounded, color: Colors.cyan, size: 20),
                                      const SizedBox(width: 8),
                                      Text(
                                        'NEXT NOTIFICATION TAG:',
                                        style: TextStyle(
                                          color: textColor.withOpacity(0.7),
                                          fontSize: 11,
                                          fontWeight: FontWeight.w800,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                        decoration: BoxDecoration(
                                          color: isDark ? Colors.cyan : const Color(0xFF06B6D4),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          '#$activeTag',
                                          style: const TextStyle(
                                            color: Colors.black,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w900,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                              const SizedBox(height: 16),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _shuffledTags.map((tag) {
                                  final isCompleted = _completedTags.contains(tag);
                                  final isActive = tag == activeTag && !isCompleted;
                                  return InkWell(
                                    onTap: () => _toggleTagCompletion(tag, !isCompleted),
                                    borderRadius: BorderRadius.circular(4),
                                    child: AnimatedContainer(
                                      duration: const Duration(milliseconds: 150),
                                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                      decoration: BoxDecoration(
                                        color: isCompleted 
                                            ? Colors.green.withOpacity(0.15)
                                            : (isActive
                                                ? (isDark ? Colors.cyan.withOpacity(0.15) : const Color(0xFF06B6D4).withOpacity(0.15))
                                                : panelBg),
                                        borderRadius: BorderRadius.circular(4),
                                        border: Border.all(
                                          color: isCompleted 
                                              ? Colors.green 
                                              : (isActive ? (isDark ? Colors.cyan : const Color(0xFF06B6D4)) : borderColor),
                                          width: 2.0,
                                        ),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            isCompleted 
                                                ? Icons.check_box 
                                                : Icons.check_box_outline_blank,
                                            color: isCompleted 
                                                ? Colors.green 
                                                : (isActive ? Colors.cyan : textColor.withOpacity(0.6)),
                                            size: 16,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            '#$tag',
                                            style: TextStyle(
                                              color: isCompleted 
                                                  ? Colors.green 
                                                  : (isActive ? (isDark ? Colors.cyan : const Color(0xFF0891B2)) : textColor),
                                              fontSize: 12,
                                              fontWeight: FontWeight.w900,
                                              decoration: isCompleted ? TextDecoration.lineThrough : null,
                                            ),
                                          ),
                                          if (isActive) ...[
                                            const SizedBox(width: 4),
                                            Text(
                                              '(NEXT)',
                                              style: TextStyle(
                                                color: isDark ? Colors.cyan : const Color(0xFF0891B2),
                                                fontSize: 10,
                                                fontWeight: FontWeight.w900,
                                              ),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ),
                                  );
                                }).toList(),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 20),
                      ],

                      // Next Notification Action Card
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: panelBg,
                          border: Border.all(color: borderColor, width: 2.5),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(color: borderColor, offset: const Offset(4, 4)),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'NEXT NOTIFICATION TRIGGER',
                              style: TextStyle(color: textColor, fontSize: 14, fontWeight: FontWeight.w900),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Instantly triggers the next scheduled notification in the active rotation after a 5-second delay. Subsequent taps cycle through the remaining cards.',
                              style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700], fontSize: 11, height: 1.4),
                            ),
                            const SizedBox(height: 16),
                            SizedBox(
                              width: double.infinity,
                              height: 46,
                              child: ElevatedButton.icon(
                                icon: Icon(Icons.send_rounded, color: textColor),
                                label: Text(
                                  'SEND NEXT NOTIFICATION',
                                  style: TextStyle(color: textColor, fontWeight: FontWeight.w900, fontSize: 13),
                                ),
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: panelBg,
                                  elevation: 0,
                                  side: BorderSide(color: borderColor, width: 2.0),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () async {
                                  final card = await _notificationService.scheduleNextNotificationAfter5Seconds();
                                  if (card == null) {
                                    if (mounted) {
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        const SnackBar(content: Text('Please sync or create flashcards first.')),
                                      );
                                    }
                                    return;
                                  }
                                  if (mounted) {
                                    final tagLabel = card.tags.isNotEmpty ? '#${card.tags.first}' : '';
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text('Next notification ($tagLabel) scheduled! Firing in 5 seconds...'),
                                        duration: const Duration(seconds: 4),
                                      ),
                                    );
                                  }
                                },
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
