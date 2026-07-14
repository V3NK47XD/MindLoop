import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/models/flashcard.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/sync_service.dart';
import 'package:mobile/services/notification_service.dart';
import 'package:mobile/views/card_view.dart';
import 'package:mobile/views/scanner_view.dart';
import 'package:mobile/views/notifications_view.dart';

import 'package:mobile/widgets/paper_background.dart';

class HomeView extends StatefulWidget {
  const HomeView({Key? key}) : super(key: key);

  @override
  State<HomeView> createState() => _HomeViewState();
}

class _HomeViewState extends State<HomeView> {
  final StorageService _storageService = StorageService();
  final SyncService _syncService = SyncService();
  final NotificationService _notificationService = NotificationService();

  List<Flashcard> _cards = [];
  List<String> _allTags = [];
  List<String> _selectedTags = [];
  String _searchQuery = '';
  int _frequencyHours = 3; // Default every 3 hours
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _refreshLibrary();
    _syncService.addListener(_onSyncServiceChange);
  }

  @override
  void dispose() {
    _syncService.removeListener(_onSyncServiceChange);
    super.dispose();
  }

  void _onSyncServiceChange() {
    if (mounted) {
      _refreshLibrary();
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _frequencyHours = prefs.getInt('notification_frequency') ?? 3;
    });
  }

  Future<void> _saveFrequency(int hours) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notification_frequency', hours);
    setState(() {
      _frequencyHours = hours;
    });
    // Reschedule in Notification Service
    await _notificationService.rescheduleReminders(hours);
  }

  Future<void> _refreshLibrary() async {
    if (!mounted) return;
    setState(() => _isLoading = true);
    
    // Fetch all cards matching tags
    final cards = await _storageService.searchCards('', filterTags: _selectedTags);
    final tags = await _storageService.getAllTags();

    // Apply BM25 search ranking
    List<Flashcard> finalCards = cards;
    if (_searchQuery.trim().isNotEmpty) {
      finalCards = BM25Searcher.search(cards, _searchQuery);
    }

    if (mounted) {
      setState(() {
        _cards = finalCards;
        _allTags = tags;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSync() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: const Text('Starting Sync...'),
        backgroundColor: Colors.indigo[700],
      ),
    );
    
    await _syncService.triggerSyncCycle();
    
    // Reschedule notifications using the newly downloaded cards
    await _notificationService.rescheduleReminders(_frequencyHours);
    
    await _refreshLibrary();
    
    final count = _syncService.lastSyncedCount;
    scaffoldMessenger.showSnackBar(
      SnackBar(
        content: Text(count > 0 
          ? 'Sync Complete! Received $count new flashcard(s).' 
          : 'Sync Complete! Library is up to date.'),
        backgroundColor: Colors.green,
      ),
    );
  }

  Future<void> _handleDeleteCard(String id) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF111928),
        title: const Text('Delete Flashcard', style: TextStyle(color: Colors.white)),
        content: const Text('Are you sure you want to delete this card from the phone?', style: TextStyle(color: Colors.grey)),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await _storageService.deleteCard(id);
      // Reschedule reminders since card pool changed
      await _notificationService.rescheduleReminders(_frequencyHours);
      _refreshLibrary();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final textColor = isDark ? Colors.white : Colors.black;
    final panelBg = isDark ? const Color(0xFF111827) : Colors.white;
    final borderColor = isDark ? Colors.white : Colors.black;
    final isPaired = _syncService.serverIp != null;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        title: Row(
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(6),
              child: Image.asset(
                'assets/icon.png',
                height: 32,
                width: 32,
                fit: BoxFit.cover,
              ),
            ),
            const SizedBox(width: 12),
            Text('MINDLOOP', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 22, color: textColor)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: textColor,
        actions: [
          IconButton(
            icon: Icon(Icons.notifications_active_outlined, color: textColor),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(builder: (context) => const NotificationsView()),
              );
            },
          ),
        ],
      ),
      body: PaperBackground(
        isDark: isDark,
        child: SafeArea(
          child: RefreshIndicator(
            onRefresh: _handleSync,
            color: borderColor,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // 1. Connection Status Card
                  Builder(
                    builder: (context) {
                      final serverIp = _syncService.serverIp;
                      final isConnected = _syncService.isConnected;
                      
                      IconData statusIcon = Icons.signal_wifi_off_outlined;
                      Color statusColor = Colors.grey;
                      String statusTitle = 'NOT CONNECTED';
                      String statusDesc = 'Pair with PC QR code to sync cards';
                      
                      if (serverIp != null) {
                        if (isConnected) {
                          statusIcon = Icons.wifi_protected_setup;
                          statusColor = Colors.cyan;
                          statusTitle = 'CONNECTED TO PC';
                          statusDesc = 'Server: $serverIp:${_syncService.serverPort}';
                        } else {
                          statusIcon = Icons.cloud_off_rounded;
                          statusColor = Colors.amber; // Yellow
                          statusTitle = 'PC OFFLINE';
                          statusDesc = 'Server unreachable. Check Wi-Fi or restart PC.';
                        }
                      }

                      return Container(
                        width: double.infinity,
                        padding: const EdgeInsets.all(18),
                        decoration: BoxDecoration(
                          color: panelBg,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: borderColor, width: 2.5),
                          boxShadow: [
                            BoxShadow(
                              color: borderColor,
                              offset: const Offset(4, 4),
                            ),
                          ],
                        ),
                        child: Row(
                          children: [
                            Icon(
                              statusIcon,
                              color: statusColor,
                              size: 28,
                            ),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    statusTitle,
                                    style: TextStyle(fontWeight: FontWeight.w900, fontSize: 14, color: textColor),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    statusDesc,
                                    style: TextStyle(color: isDark ? Colors.grey[400] : Colors.grey[700], fontSize: 11, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            if (serverIp != null) ...[
                              IconButton(
                                icon: Icon(Icons.sync, color: isConnected ? textColor : Colors.grey),
                                onPressed: isConnected ? _handleSync : null,
                                tooltip: 'Synchronize',
                              ),
                              IconButton(
                                icon: const Icon(Icons.link_off, color: Colors.red),
                                onPressed: () async {
                                  await _syncService.disconnect();
                                  setState(() {});
                                },
                                tooltip: 'Disconnect',
                              ),
                            ] else ...[
                              ElevatedButton(
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: Colors.cyan,
                                  foregroundColor: Colors.black,
                                  elevation: 0,
                                  side: BorderSide(color: borderColor, width: 2.0),
                                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                                ),
                                onPressed: () async {
                                  final success = await Navigator.push(
                                    context,
                                    MaterialPageRoute(builder: (context) => const ScannerView()),
                                  );
                                  if (success == true) {
                                    setState(() {});
                                  }
                                },
                                child: const Text('PAIR', style: TextStyle(fontWeight: FontWeight.w900)),
                              ),
                            ],
                          ],
                        ),
                      );
                    }
                  ),
                  const SizedBox(height: 20),

                  // 2. Search Field
                  Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: borderColor,
                          offset: const Offset(3, 3),
                        ),
                      ],
                    ),
                    child: TextField(
                      onChanged: (val) {
                        setState(() {
                          _searchQuery = val;
                        });
                        _refreshLibrary();
                      },
                      style: TextStyle(color: textColor, fontWeight: FontWeight.bold),
                      decoration: InputDecoration(
                        hintText: 'Search flashcards...',
                        hintStyle: TextStyle(color: textColor.withOpacity(0.5)),
                        prefixIcon: Icon(Icons.search, color: textColor),
                        filled: true,
                        fillColor: panelBg,
                        contentPadding: const EdgeInsets.symmetric(vertical: 0),
                        enabledBorder: OutlineInputBorder(
                          borderSide: BorderSide(color: borderColor, width: 2.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderSide: const BorderSide(color: Colors.cyan, width: 2.5),
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // 3. Tags Chips
                  if (_allTags.isNotEmpty) ...[
                    SizedBox(
                      height: 35,
                      child: ListView.builder(
                        scrollDirection: Axis.horizontal,
                        itemCount: _allTags.length,
                        itemBuilder: (context, idx) {
                          final tag = _allTags[idx];
                          final isSelected = _selectedTags.contains(tag);
                          final tagCol = _getTagColor(tag);
                          
                          return Padding(
                            padding: const EdgeInsets.only(right: 8.0),
                            child: FilterChip(
                              label: Text('#$tag'),
                              selected: isSelected,
                              selectedColor: tagCol.withOpacity(0.2),
                              checkmarkColor: tagCol,
                              backgroundColor: panelBg,
                              labelStyle: TextStyle(
                                color: tagCol,
                                fontSize: 11,
                                fontWeight: FontWeight.w900,
                              ),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(6),
                                side: BorderSide(
                                  color: isSelected ? tagCol : borderColor,
                                  width: 2.0,
                                ),
                              ),
                              onSelected: (selected) {
                                setState(() {
                                  if (selected) {
                                    _selectedTags.add(tag);
                                  } else {
                                    _selectedTags.remove(tag);
                                  }
                                });
                                _refreshLibrary();
                              },
                            ),
                          );
                        },
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // 4. Cards list
                  Expanded(
                    child: _isLoading
                        ? Center(child: CircularProgressIndicator(color: borderColor))
                        : _cards.isEmpty
                            ? Center(
                                child: Column(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.layers_clear_outlined, size: 48, color: textColor.withOpacity(0.4)),
                                    const SizedBox(height: 12),
                                    Text(
                                      _searchQuery.isNotEmpty || _selectedTags.isNotEmpty
                                          ? 'No matching flashcards'
                                          : 'No flashcards synced yet',
                                      style: TextStyle(color: textColor.withOpacity(0.5), fontWeight: FontWeight.bold),
                                    ),
                                  ],
                                ),
                              )
                            : ListView.builder(
                                physics: const AlwaysScrollableScrollPhysics(),
                                itemCount: _cards.length,
                                itemBuilder: (context, idx) {
                                  final card = _cards[idx];
                                  return Container(
                                    margin: const EdgeInsets.only(bottom: 14),
                                    decoration: BoxDecoration(
                                      color: panelBg,
                                      borderRadius: BorderRadius.circular(12),
                                      border: Border.all(
                                        color: borderColor,
                                        width: 2.5,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: borderColor,
                                          offset: const Offset(3, 3),
                                        ),
                                      ],
                                    ),
                                    child: ListTile(
                                      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                      title: Text(
                                        card.question,
                                        style: TextStyle(fontWeight: FontWeight.w900, color: textColor),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      subtitle: Padding(
                                        padding: const EdgeInsets.only(top: 8.0),
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Row(
                                              children: [
                                                Icon(Icons.description_outlined, size: 12, color: textColor.withOpacity(0.6)),
                                                const SizedBox(width: 4),
                                                Expanded(
                                                  child: Text(
                                                    card.sourcePdf,
                                                    style: TextStyle(color: textColor.withOpacity(0.6), fontSize: 11, fontWeight: FontWeight.bold),
                                                    overflow: TextOverflow.ellipsis,
                                                  ),
                                                ),
                                              ],
                                            ),
                                            if (card.tags.isNotEmpty) ...[
                                              const SizedBox(height: 8),
                                              Wrap(
                                                spacing: 6,
                                                runSpacing: 4,
                                                children: card.tags.take(3).map((tag) {
                                                  final col = _getTagColor(tag);
                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: col.withOpacity(0.15),
                                                      borderRadius: BorderRadius.circular(4),
                                                      border: Border.all(color: col, width: 2.0),
                                                    ),
                                                    child: Text(
                                                      '#$tag',
                                                      style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.w900),
                                                    ),
                                                  );
                                                }).toList(),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ),
                                      trailing: Icon(Icons.arrow_forward_ios, size: 14, color: textColor),
                                      onTap: () {
                                        Navigator.push(
                                          context,
                                          MaterialPageRoute(builder: (context) => CardView(card: card)),
                                        );
                                      },
                                      onLongPress: () => _handleDeleteCard(card.id),
                                    ),
                                  );
                                },
                              ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Color _getTagColor(String tag) {
    final hash = tag.hashCode;
    final colors = [
      Colors.cyan,
      Colors.amber, // Yellow
      Colors.green,
      Colors.redAccent,
    ];
    return colors[hash.abs() % colors.length];
  }
}

class BM25Searcher {
  static List<Flashcard> search(List<Flashcard> documents, String query, {double k1 = 1.2, double b = 0.75}) {
    if (query.trim().isEmpty) return documents;

    List<String> tokenize(String text) {
      return text.toLowerCase()
          .replaceAll(RegExp(r'[^\w\s]'), '')
          .split(RegExp(r'\s+'))
          .where((token) => token.isNotEmpty)
          .toList();
    }

    final queryTerms = tokenize(query);
    if (queryTerms.isEmpty) return documents;

    final N = documents.length;

    final List<Map<String, dynamic>> docsData = documents.map((doc) {
      final textToSearch = "${doc.question} ${doc.tags.join(' ')} ${doc.sourcePdf}";
      final tokens = tokenize(textToSearch);
      final Map<String, int> tf = {};
      for (var token in tokens) {
        tf[token] = (tf[token] ?? 0) + 1;
      }
      return {
        "doc": doc,
        "length": tokens.length,
        "tf": tf
      };
    }).toList();

    final double avgdl = docsData.fold<double>(0.0, (sum, d) => sum + d["length"]) / N;

    final Map<String, int> df = {};
    for (var term in queryTerms) {
      df[term] = docsData.where((d) => (d["tf"] as Map<String, int>)[term] != null && (d["tf"] as Map<String, int>)[term]! > 0).length;
    }

    final Map<String, double> idf = {};
    for (var term in queryTerms) {
      final n = df[term] ?? 0;
      idf[term] = log(((N - n + 0.5) / (n + 0.5)) + 1.0);
    }

    final List<Map<String, dynamic>> scoredDocs = docsData.map((d) {
      double score = 0.0;
      final tfMap = d["tf"] as Map<String, int>;
      for (var term in queryTerms) {
        final f = tfMap[term] ?? 0;
        if (f > 0) {
          final idfVal = idf[term] ?? 0.0;
          final numerator = f * (k1 + 1.0);
          final denominator = f + k1 * (1.0 - b + b * (d["length"] / avgdl));
          score += idfVal * (numerator / denominator);
        }
      }
      return {
        "doc": d["doc"] as Flashcard,
        "score": score
      };
    }).toList();

    final filtered = scoredDocs.where((item) => item["score"] > 0.0).toList();
    filtered.sort((a, b) => (b["score"] as double).compareTo(a["score"] as double));

    return filtered.map((item) => item["doc"] as Flashcard).toList();
  }
}
