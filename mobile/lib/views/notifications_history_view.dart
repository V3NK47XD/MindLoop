import 'package:flutter/material.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/views/card_view.dart';
import 'package:mobile/widgets/paper_background.dart';

class NotificationsHistoryView extends StatefulWidget {
  const NotificationsHistoryView({super.key});

  @override
  State<NotificationsHistoryView> createState() => _NotificationsHistoryViewState();
}

class _NotificationsHistoryViewState extends State<NotificationsHistoryView> {
  List<Map<String, dynamic>> _history = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadHistory();
  }

  Future<void> _loadHistory() async {
    final data = await StorageService().getNotificationHistory();
    if (mounted) {
      setState(() {
        _history = data;
        _isLoading = false;
      });
    }
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111928),
        title: const Text('Clear History', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w900)),
        content: const Text('Are you sure you want to delete all notification logs?', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear All', style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await StorageService().clearNotificationHistory();
      _loadHistory();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Notification logs cleared.')),
        );
      }
    }
  }

  String _formatRelativeTime(String isoString) {
    try {
      final dateTime = DateTime.parse(isoString);
      final difference = DateTime.now().difference(dateTime);
      
      if (difference.isNegative) {
        return 'Just now';
      } else if (difference.inSeconds < 60) {
        return 'Just now';
      } else if (difference.inMinutes < 60) {
        return '${difference.inMinutes}m ago';
      } else if (difference.inHours < 24) {
        return '${difference.inHours}h ago';
      } else if (difference.inDays == 1) {
        return 'Yesterday';
      } else {
        return '${difference.inDays}d ago';
      }
    } catch (e) {
      return 'Recent';
    }
  }

  Future<void> _handleCardTap(String cardId) async {
    final card = await StorageService().getCardById(cardId);
    if (mounted) {
      if (card != null) {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (context) => CardView(card: card)),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Flashcard content not found in local library.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final panelBg = isDark ? const Color(0xFF111827) : Colors.white;
    final borderColor = isDark ? Colors.white : Colors.black;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Text(
          'REVIEW HISTORY',
          style: TextStyle(fontWeight: FontWeight.w900, fontSize: 18, color: textColor, letterSpacing: 1),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
        actions: [
          if (_history.isNotEmpty)
            IconButton(
              icon: Icon(Icons.delete_sweep_outlined, color: textColor),
              onPressed: _clearHistory,
              tooltip: 'Clear Log History',
            ),
        ],
      ),
      body: PaperBackground(
        isDark: isDark,
        child: _isLoading
            ? Center(child: CircularProgressIndicator(color: borderColor))
            : SafeArea(
                child: RefreshIndicator(
                  onRefresh: _loadHistory,
                  color: borderColor,
                  child: _history.isEmpty
                      ? ListView(
                          children: [
                            SizedBox(height: MediaQuery.of(context).size.height * 0.25),
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 40.0),
                              child: Container(
                                padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                                decoration: BoxDecoration(
                                  color: panelBg,
                                  border: Border.all(color: borderColor, width: 2.5),
                                  borderRadius: BorderRadius.circular(12),
                                  boxShadow: [
                                    BoxShadow(color: borderColor, offset: const Offset(4, 4)),
                                  ],
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.history_toggle_off_rounded, size: 48, color: textColor.withOpacity(0.5)),
                                    const SizedBox(height: 16),
                                    Text(
                                      'NO NOTIFICATIONS YET',
                                      style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textColor),
                                      textAlign: TextAlign.center,
                                    ),
                                    const SizedBox(height: 8),
                                    Text(
                                      'Fired rotational flashcards and test alerts will appear here in chronological order.',
                                      style: TextStyle(fontSize: 12, color: isDark ? Colors.grey[400] : Colors.grey[700], height: 1.4),
                                      textAlign: TextAlign.center,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(20),
                          itemCount: _history.length,
                          itemBuilder: (context, index) {
                            final item = _history[index];
                            final cardId = item['card_id'] as String? ?? '';
                            final title = item['title'] as String? ?? '';
                            final body = item['body'] as String? ?? '';
                            final timeStr = item['scheduled_time'] as String? ?? '';

                            return Padding(
                              padding: const EdgeInsets.only(bottom: 16.0),
                              child: InkWell(
                                onTap: () => _handleCardTap(cardId),
                                borderRadius: BorderRadius.circular(12),
                                child: Container(
                                  padding: const EdgeInsets.all(16),
                                  decoration: BoxDecoration(
                                    color: panelBg,
                                    border: Border.all(color: borderColor, width: 2.5),
                                    borderRadius: BorderRadius.circular(12),
                                    boxShadow: [
                                      BoxShadow(color: borderColor, offset: const Offset(4, 4)),
                                    ],
                                  ),
                                  child: Row(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Icon(
                                        Icons.notifications_outlined,
                                        color: isDark ? Colors.cyan : const Color(0xFF06B6D4),
                                        size: 24,
                                      ),
                                      const SizedBox(width: 14),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                                              children: [
                                                Expanded(
                                                  child: Text(
                                                    title,
                                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12, color: textColor),
                                                    maxLines: 1,
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                                Text(
                                                  _formatRelativeTime(timeStr),
                                                  style: const TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: Colors.grey),
                                                ),
                                              ],
                                            ),
                                            const SizedBox(height: 6),
                                            Text(
                                              body,
                                              style: TextStyle(
                                                fontSize: 13,
                                                fontWeight: FontWeight.w600,
                                                color: isDark ? Colors.grey[300] : Colors.grey[800],
                                              ),
                                              maxLines: 2,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
                ),
              ),
      ),
    );
  }
}
