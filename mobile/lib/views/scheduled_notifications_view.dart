import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/notification_service.dart';
import 'package:mobile/widgets/paper_background.dart';

class ScheduledNotificationsView extends StatefulWidget {
  const ScheduledNotificationsView({super.key});

  @override
  State<ScheduledNotificationsView> createState() => _ScheduledNotificationsViewState();
}

class _ScheduledNotificationsViewState extends State<ScheduledNotificationsView> {
  List<Map<String, dynamic>> _scheduledList = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadScheduledList();
  }

  Future<void> _loadScheduledList() async {
    await NotificationService().updateNotificationProgress();
    final list = await StorageService().getScheduledNotifications();
    if (mounted) {
      setState(() {
        _scheduledList = list;
        _isLoading = false;
      });
    }
  }

  Future<void> _regenerateSchedule() async {
    setState(() => _isLoading = true);
    final prefs = await SharedPreferences.getInstance();
    final frequencyHours = prefs.getInt('notification_frequency') ?? 3;
    await NotificationService().rescheduleReminders(frequencyHours > 0 ? frequencyHours : 3);
    await _loadScheduledList();
  }

  String _formatTime(String isoString) {
    try {
      final dt = DateTime.parse(isoString).toLocal();
      final year = dt.year;
      final month = dt.month.toString().padLeft(2, '0');
      final day = dt.day.toString().padLeft(2, '0');
      final hour = dt.hour.toString().padLeft(2, '0');
      final min = dt.minute.toString().padLeft(2, '0');
      return '$year-$month-$day $hour:$min';
    } catch (_) {
      return isoString;
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final panelBg = isDark ? const Color(0xFF111827) : Colors.white;
    final borderColor = isDark ? Colors.white : Colors.black;

    final pendingCount = _scheduledList.where((i) => i['status'] == 'pending').length;
    final sentCount = _scheduledList.where((i) => i['status'] == 'sent').length;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'SCHEDULED QUEUE',
          style: TextStyle(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: textColor,
            letterSpacing: 1,
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
        iconTheme: IconThemeData(color: textColor),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Refresh Queue',
            onPressed: () {
              setState(() => _isLoading = true);
              _loadScheduledList();
            },
          ),
        ],
      ),
      body: PaperBackground(
        isDark: isDark,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: borderColor))
            : SafeArea(
                child: Column(
                  children: [
                    // Summary Header Card
                    Container(
                      margin: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 10.0),
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
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                'ROTATION QUEUE',
                                style: TextStyle(
                                  color: textColor,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              Row(
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: isDark ? Colors.cyan.withOpacity(0.2) : Colors.cyan.withOpacity(0.3),
                                      border: Border.all(color: isDark ? Colors.cyan : const Color(0xFF06B6D4)),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$pendingCount PENDING',
                                      style: TextStyle(
                                        color: isDark ? Colors.cyan : const Color(0xFF0891B2),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 6),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                                    decoration: BoxDecoration(
                                      color: Colors.green.withOpacity(0.15),
                                      border: Border.all(color: Colors.green),
                                      borderRadius: BorderRadius.circular(4),
                                    ),
                                    child: Text(
                                      '$sentCount SENT',
                                      style: const TextStyle(
                                        color: Colors.green,
                                        fontSize: 11,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'Stored persistently in SQLite scheduled_notifications table. The pointer automatically advances as notifications trigger or are sent via "Send Next Notification".',
                            style: TextStyle(
                              color: isDark ? Colors.grey[400] : Colors.grey[700],
                              fontSize: 11,
                              height: 1.4,
                            ),
                          ),
                          const SizedBox(height: 12),
                          SizedBox(
                            width: double.infinity,
                            height: 38,
                            child: ElevatedButton.icon(
                              icon: const Icon(Icons.autorenew_rounded, size: 18),
                              label: const Text(
                                'RE-GENERATE FULL SCHEDULE',
                                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12),
                              ),
                              style: ElevatedButton.styleFrom(
                                backgroundColor: panelBg,
                                foregroundColor: textColor,
                                elevation: 0,
                                side: BorderSide(color: borderColor, width: 2.0),
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                              ),
                              onPressed: _regenerateSchedule,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // List of Scheduled Notifications
                    Expanded(
                      child: _scheduledList.isEmpty
                          ? Center(
                              child: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.event_note_rounded, size: 48, color: textColor.withOpacity(0.4)),
                                  const SizedBox(height: 12),
                                  Text(
                                    'No scheduled notifications in database.',
                                    style: TextStyle(
                                      color: textColor.withOpacity(0.6),
                                      fontWeight: FontWeight.w800,
                                      fontSize: 13,
                                    ),
                                  ),
                                ],
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
                              itemCount: _scheduledList.length,
                              itemBuilder: (context, index) {
                                final item = _scheduledList[index];
                                final isPending = item['status'] == 'pending';
                                final slotOrder = item['slot_order'] ?? (index + 1);
                                final tag = item['tag'] ?? '';
                                final title = item['title'] ?? '';
                                final body = item['body'] ?? '';
                                final scheduledTime = _formatTime(item['scheduled_time'] ?? '');

                                return Container(
                                  margin: const EdgeInsets.only(bottom: 10.0),
                                  padding: const EdgeInsets.all(14.0),
                                  decoration: BoxDecoration(
                                    color: panelBg,
                                    border: Border.all(
                                      color: isPending
                                          ? (isDark ? Colors.cyan : const Color(0xFF06B6D4))
                                          : (isDark ? Colors.white24 : Colors.black26),
                                      width: isPending ? 2.0 : 1.5,
                                    ),
                                    borderRadius: BorderRadius.circular(10),
                                    boxShadow: [
                                      BoxShadow(
                                        color: isPending ? borderColor.withOpacity(0.2) : Colors.transparent,
                                        offset: const Offset(2, 2),
                                      ),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      // Slot index badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                                        decoration: BoxDecoration(
                                          color: isPending
                                              ? (isDark ? Colors.cyan : const Color(0xFF06B6D4))
                                              : Colors.grey.withOpacity(0.3),
                                          borderRadius: BorderRadius.circular(6),
                                        ),
                                        child: Text(
                                          '#$slotOrder',
                                          style: TextStyle(
                                            color: isPending ? Colors.black : textColor,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 12,
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 12),

                                      // Main info
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Container(
                                                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                                  decoration: BoxDecoration(
                                                    color: isDark ? Colors.cyan.withOpacity(0.2) : const Color(0xFF06B6D4).withOpacity(0.2),
                                                    borderRadius: BorderRadius.circular(4),
                                                  ),
                                                  child: Text(
                                                    '#$tag',
                                                    style: TextStyle(
                                                      color: isDark ? Colors.cyan : const Color(0xFF0891B2),
                                                      fontWeight: FontWeight.w900,
                                                      fontSize: 11,
                                                    ),
                                                  ),
                                                ),
                                                const SizedBox(width: 8),
                                                Expanded(
                                                  child: Text(
                                                    scheduledTime,
                                                    style: TextStyle(
                                                      color: textColor.withOpacity(0.6),
                                                      fontSize: 11,
                                                      fontWeight: FontWeight.w700,
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              body,
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                              style: TextStyle(
                                                color: textColor,
                                                fontWeight: FontWeight.w800,
                                                fontSize: 13,
                                                decoration: isPending ? null : TextDecoration.lineThrough,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),

                                      const SizedBox(width: 8),

                                      // Status badge
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                        decoration: BoxDecoration(
                                          color: isPending
                                              ? (isDark ? Colors.cyan.withOpacity(0.15) : const Color(0xFF06B6D4).withOpacity(0.15))
                                              : Colors.green.withOpacity(0.15),
                                          border: Border.all(
                                            color: isPending
                                                ? (isDark ? Colors.cyan : const Color(0xFF06B6D4))
                                                : Colors.green,
                                            width: 1.5,
                                          ),
                                          borderRadius: BorderRadius.circular(4),
                                        ),
                                        child: Text(
                                          isPending ? 'PENDING' : 'SENT',
                                          style: TextStyle(
                                            color: isPending
                                                ? (isDark ? Colors.cyan : const Color(0xFF0891B2))
                                                : Colors.green,
                                            fontWeight: FontWeight.w900,
                                            fontSize: 10,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}
