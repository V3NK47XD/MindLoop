import 'package:flutter/material';
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
    setState(() => _isLoading = true);
    
    // Fetch all cards and tags from local database
    final cards = await _storageService.searchCards(_searchQuery, filterTags: _selectedTags);
    final tags = await _storageService.getAllTags();

    if (mounted) {
      setState(() {
        _cards = cards;
        _allTags = tags;
        _isLoading = false;
      });
    }
  }

  Future<void> _handleSync() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(const SnackBar(content: Text('Starting Sync...')));
    
    await _syncService.triggerSyncCycle();
    
    // Reschedule notifications using the newly downloaded cards
    await _notificationService.rescheduleReminders(_frequencyHours);
    
    await _refreshLibrary();
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Sync Complete!'), backgroundColor: Colors.green),
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
      backgroundColor: const Color(0xFF0B0F19),
      appBar: AppBar(
        title: const Text('MindLoop', style: TextStyle(fontWeight: FontWeight.w800, fontSize: 22)),
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
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(18),
                decoration: BoxDecoration(
                  color: const Color(0xFF111928),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.white.withOpacity(0.06)),
                ),
                child: Row(
                  children: [
                    Icon(
                      isPaired ? Icons.wifi_protected_setup : Icons.signal_wifi_off_outlined,
                      color: isPaired ? theme.primaryColor : Colors.grey,
                      size: 28,
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            isPaired ? 'Connected to PC' : 'Not Connected',
                            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Colors.white),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            isPaired
                                ? 'Server: ${_syncService.serverIp}:${_syncService.serverPort}'
                                : 'Pair with PC QR code to sync cards',
                            style: const TextStyle(color: Colors.grey, fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    if (isPaired) ...[
                      IconButton(
                        icon: const Icon(Icons.sync, color: Colors.white),
                        onPressed: _handleSync,
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
                              return Card(
                                color: const Color(0xFF111928),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                  side: BorderSide(color: Colors.white.withOpacity(0.04)),
                                ),
                                margin: const EdgeInsets.only(bottom: 10),
                                child: ListTile(
                                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                                  title: Text(
                                    card.question,
                                    style: const TextStyle(fontWeight: FontWeight.w600, color: Colors.white),
                                    maxLines: 2,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  subtitle: Padding(
                                    padding: const EdgeInsets.only(top: 8.0),
                                    child: Row(
                                      children: [
                                        Icon(Icons.description, size: 12, color: theme.primaryColor),
                                        const SizedBox(width: 4),
                                        Expanded(
                                          child: Text(
                                            card.sourcePdf,
                                            style: TextStyle(color: Colors.grey[500], fontSize: 11),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
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
}
