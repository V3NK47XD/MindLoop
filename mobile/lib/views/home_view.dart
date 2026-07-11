import 'dart:math';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/models/flashcard.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:mobile/services/sync_service.dart';
import 'package:mobile/services/notification_service.dart';
import 'package:mobile/views/card_view.dart';
import 'package:mobile/views/scanner_view.dart';

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

  void _showSettingsBottomSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF111928),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setModalState) {
            return Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Study Reminders Settings',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white),
                  ),
                  const SizedBox(height: 8),
                  const Text(
                    'Configure how frequently MindLoop alerts you with random review questions.',
                    style: TextStyle(color: Colors.grey, fontSize: 13),
                  ),
                  const SizedBox(height: 20),
                  DropdownButtonFormField<int>(
                    value: _frequencyHours,
                    dropdownColor: const Color(0xFF111928),
                    decoration: InputDecoration(
                      labelText: 'Notification Frequency',
                      labelStyle: const TextStyle(color: Colors.grey),
                      enabledBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Colors.white.withOpacity(0.08)),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderSide: BorderSide(color: Theme.of(context).primaryColor),
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    style: const TextStyle(color: Colors.white),
                    items: const [
                      DropdownMenuItem(value: 0, child: Text('Disabled (Muted)')),
                      DropdownMenuItem(value: 1, child: Text('Every Hour')),
                      DropdownMenuItem(value: 3, child: Text('Every 3 Hours')),
                      DropdownMenuItem(value: 6, child: Text('Every 6 Hours')),
                      DropdownMenuItem(value: 12, child: Text('Every 12 Hours')),
                      DropdownMenuItem(value: 24, child: Text('Every 24 Hours')),
                    ],
                    onChanged: (val) {
                      if (val != null) {
                        setModalState(() {
                          _frequencyHours = val;
                        });
                        _saveFrequency(val);
                      }
                    },
                  ),
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      ElevatedButton.icon(
                        icon: const Icon(Icons.notifications_active),
                        label: const Text('Test Notification'),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.white.withOpacity(0.05),
                          foregroundColor: Colors.white,
                          side: BorderSide(color: Colors.white.withOpacity(0.1)),
                        ),
                        onPressed: () async {
                          if (_cards.isEmpty) {
                            ScaffoldMessenger.of(context).showSnackBar(
                              const SnackBar(content: Text('Please sync some cards first to run test.')),
                            );
                            return;
                          }
                          Navigator.pop(context);
                          final randomCard = _cards.first; // Get first card as test
                          await _notificationService.showTestNotification(
                            'MindLoop Review!',
                            randomCard.question,
                            randomCard.id,
                          );
                        },
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isPaired = _syncService.serverIp != null;

    return Scaffold(
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
            const Text('MindLoop', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
          ],
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _showSettingsBottomSheet,
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: _handleSync,
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
                  String statusTitle = 'Not Connected';
                  String statusDesc = 'Pair with PC QR code to sync cards';
                  
                  if (serverIp != null) {
                    if (isConnected) {
                      statusIcon = Icons.wifi_protected_setup;
                      statusColor = theme.primaryColor;
                      statusTitle = 'Connected to PC';
                      statusDesc = 'Server: $serverIp:${_syncService.serverPort}';
                    } else {
                      statusIcon = Icons.cloud_off_rounded;
                      statusColor = Colors.orangeAccent;
                      statusTitle = 'PC Offline';
                      statusDesc = 'Server unreachable. Check Wi-Fi or restart PC.';
                    }
                  }

                  return Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(
                      color: const Color(0xFF111928),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: statusColor.withOpacity(0.15)),
                      boxShadow: [
                        BoxShadow(
                          color: statusColor.withOpacity(0.02),
                          blurRadius: 10,
                          spreadRadius: 1,
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
                                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                              ),
                              const SizedBox(height: 2),
                              Text(
                                statusDesc,
                                style: const TextStyle(color: Colors.grey, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        if (serverIp != null) ...[
                          IconButton(
                            icon: Icon(Icons.sync, color: isConnected ? Colors.white : Colors.grey),
                            onPressed: isConnected ? _handleSync : null,
                            tooltip: 'Synchronize',
                          ),
                          IconButton(
                            icon: const Icon(Icons.link_off, color: Colors.redAccent),
                            onPressed: () async {
                              await _syncService.disconnect();
                              setState(() {});
                            },
                            tooltip: 'Disconnect',
                          ),
                        ] else ...[
                          ElevatedButton(
                            style: ElevatedButton.styleFrom(
                              backgroundColor: theme.primaryColor,
                              foregroundColor: Colors.white,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
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
                            child: const Text('Pair'),
                          ),
                        ],
                      ],
                    ),
                  );
                }
              ),
              const SizedBox(height: 20),

              // 2. Search & Tag Filters
              TextField(
                onChanged: (val) {
                  setState(() {
                    _searchQuery = val;
                  });
                  _refreshLibrary();
                },
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  hintText: 'Search flashcards...',
                  hintStyle: const TextStyle(color: Colors.grey),
                  prefixIcon: const Icon(Icons.search, color: Colors.grey),
                  filled: true,
                  fillColor: const Color(0xFF111928),
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  enabledBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white.withOpacity(0.06)),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderSide: BorderSide(color: theme.primaryColor),
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
              const SizedBox(height: 12),

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
                      return Padding(
                        padding: const EdgeInsets.only(right: 8.0),
                        child: FilterChip(
                          label: Text('#$tag'),
                          selected: isSelected,
                          selectedColor: theme.primaryColor.withOpacity(0.2),
                          checkmarkColor: theme.primaryColor,
                          backgroundColor: const Color(0xFF111928),
                          labelStyle: TextStyle(
                            color: isSelected ? theme.primaryColor : Colors.grey[400],
                            fontSize: 12,
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(20),
                            side: BorderSide(
                              color: isSelected ? theme.primaryColor : Colors.white.withOpacity(0.04),
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
                    ? const Center(child: CircularProgressIndicator())
                    : _cards.isEmpty
                        ? Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(Icons.layers_clear_outlined, size: 48, color: Colors.grey[700]),
                                const SizedBox(height: 12),
                                Text(
                                  _searchQuery.isNotEmpty || _selectedTags.isNotEmpty
                                      ? 'No matching flashcards'
                                      : 'No flashcards synced yet',
                                  style: TextStyle(color: Colors.grey[500]),
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
                                 margin: const EdgeInsets.only(bottom: 12),
                                 decoration: BoxDecoration(
                                   borderRadius: BorderRadius.circular(16),
                                   gradient: LinearGradient(
                                     colors: [
                                       const Color(0xFF111928),
                                       const Color(0xFF111928).withOpacity(0.85),
                                     ],
                                   ),
                                   border: Border.all(
                                     color: card.tags.isNotEmpty 
                                         ? _getTagColor(card.tags.first).withOpacity(0.12)
                                         : Colors.white.withOpacity(0.04),
                                   ),
                                   boxShadow: [
                                     BoxShadow(
                                       color: Colors.black.withOpacity(0.2),
                                       blurRadius: 8,
                                       offset: const Offset(0, 4),
                                     ),
                                   ],
                                 ),
                                 child: ListTile(
                                   contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                                   title: Text(
                                     card.question,
                                     style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
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
                                             Icon(Icons.description_outlined, size: 12, color: theme.colorScheme.secondary),
                                             const SizedBox(width: 4),
                                             Expanded(
                                               child: Text(
                                                 card.sourcePdf,
                                                 style: TextStyle(color: Colors.grey[400], fontSize: 11, fontWeight: FontWeight.w500),
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
                                                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                                 decoration: BoxDecoration(
                                                   color: col.withOpacity(0.1),
                                                   borderRadius: BorderRadius.circular(6),
                                                   border: Border.all(color: col.withOpacity(0.2), width: 0.5),
                                                 ),
                                                 child: Text(
                                                   '#$tag',
                                                   style: TextStyle(color: col, fontSize: 10, fontWeight: FontWeight.w600),
                                                 ),
                                               );
                                             }).toList(),
                                           ),
                                         ],
                                       ],
                                     ),
                                   ),
                                   trailing: const Icon(Icons.arrow_forward_ios, size: 14, color: Colors.grey),
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
    );
  }

  Color _getTagColor(String tag) {
    final hash = tag.hashCode;
    final colors = [
      Colors.pinkAccent,
      Colors.blueAccent,
      Colors.greenAccent,
      Colors.amberAccent,
      Colors.deepOrangeAccent,
      Colors.purpleAccent,
      Colors.cyanAccent,
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
