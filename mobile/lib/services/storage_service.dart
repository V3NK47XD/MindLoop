import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:sqflite/sqflite.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:mobile/models/flashcard.dart';

class StorageService {
  static final StorageService _instance = StorageService._internal();
  factory StorageService() => _instance;
  StorageService._internal();

  Database? _database;

  Future<Database> get database async {
    if (_database != null) return _database!;
    _database = await _initDatabase();
    return _database!;
  }

  Future<Database> _initDatabase() async {
    final dbPath = await getDatabasesPath();
    final path = join(dbPath, 'flashcards.db');

    return await openDatabase(
      path,
      version: 3,
      onCreate: (db, version) async {
        await db.execute('''
          CREATE TABLE cards (
            id TEXT PRIMARY KEY,
            question TEXT,
            created_at TEXT,
            tags TEXT,
            source_pdf TEXT,
            pdf_ref_line INTEGER,
            attachments TEXT,
            folder_path TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE notifications_history (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            card_id TEXT,
            title TEXT,
            body TEXT,
            scheduled_time TEXT
          )
        ''');
        await db.execute('''
          CREATE TABLE scheduled_notifications (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            notification_id INTEGER,
            card_id TEXT,
            tag TEXT,
            title TEXT,
            body TEXT,
            scheduled_time TEXT,
            slot_order INTEGER,
            status TEXT
          )
        ''');
      },
      onUpgrade: (db, oldVersion, newVersion) async {
        if (oldVersion < 2) {
          await db.execute('''
            CREATE TABLE notifications_history (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              card_id TEXT,
              title TEXT,
              body TEXT,
              scheduled_time TEXT
            )
          ''');
        }
        if (oldVersion < 3) {
          await db.execute('''
            CREATE TABLE scheduled_notifications (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              notification_id INTEGER,
              card_id TEXT,
              tag TEXT,
              title TEXT,
              body TEXT,
              scheduled_time TEXT,
              slot_order INTEGER,
              status TEXT
            )
          ''');
        }
      },
    );
  }

  // Save/Insert a flashcard into SQLite index
  Future<void> saveFlashcard(Flashcard card) async {
    final db = await database;
    await db.insert(
      'cards',
      card.toMap(),
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
  }

  // Retrieve all flashcards
  Future<List<Flashcard>> getAllCards() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'cards',
      orderBy: 'created_at DESC',
    );
    return List.generate(maps.length, (i) => Flashcard.fromMap(maps[i]));
  }

  // Search flashcards by title, tags, or content
  Future<List<Flashcard>> searchCards(String query, {List<String>? filterTags}) async {
    final db = await database;
    
    // We fetch all cards and filter or query directly using SQL
    String sql = "SELECT * FROM cards WHERE 1=1";
    List<dynamic> args = [];
    
    if (query.isNotEmpty) {
      sql += " AND (question LIKE ?)";
      args.add('%$query%');
    }
    
    final List<Map<String, dynamic>> maps = await db.rawQuery(sql, args);
    List<Flashcard> cards = List.generate(maps.length, (i) => Flashcard.fromMap(maps[i]));
    
    // Manual tags intersection check
    if (filterTags != null && filterTags.isNotEmpty) {
      cards = cards.where((card) {
        return filterTags.every((t) => card.tags.contains(t));
      }).toList();
    }
    
    return cards;
  }

  // Retrieve all unique tags in the database
  Future<List<String>> getAllTags() async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query('cards', columns: ['tags']);
    final Set<String> tagSet = {};
    for (var row in maps) {
      final String tagsStr = row['tags'] as String? ?? '';
      if (tagsStr.isNotEmpty) {
        tagSet.addAll(tagsStr.split(','));
      }
    }
    return tagSet.toList()..sort();
  }

  // Get a card by its ID
  Future<Flashcard?> getCardById(String id) async {
    final db = await database;
    final List<Map<String, dynamic>> maps = await db.query(
      'cards',
      where: 'id = ?',
      whereArgs: [id],
    );
    if (maps.isEmpty) return null;
    return Flashcard.fromMap(maps.first);
  }

  // Read content.md from a flashcard directory
  Future<String> getCardMarkdownContent(Flashcard card) async {
    final file = File(join(card.folderPath, 'content.md'));
    if (await file.exists()) {
      return await file.readAsString();
    }
    return '';
  }

  // Package a local card into a .flash ZIP archive for uploading to PC
  Future<File?> createZipFromLocalCard(Flashcard card) async {
    try {
      final appDir = await getTemporaryDirectory();
      final zipFilePath = join(appDir.path, '${card.id}.flash');
      final zipFile = File(zipFilePath);
      if (await zipFile.exists()) {
        await zipFile.delete();
      }

      final archive = Archive();

      // Write metadata.json
      final metadata = {
        "id": card.id,
        "question": card.question,
        "created_at": card.createdAt,
        "tags": card.tags,
        "source_pdf": card.sourcePdf,
        "pdf_ref_line": card.pdfRefLine,
        "attachments": card.attachments,
      };
      final metadataBytes = utf8.encode(jsonEncode(metadata));
      archive.addFile(ArchiveFile('metadata.json', metadataBytes.length, metadataBytes));

      // Write content.md
      final contentStr = await getCardMarkdownContent(card);
      final contentBytes = utf8.encode(contentStr);
      archive.addFile(ArchiveFile('content.md', contentBytes.length, contentBytes));

      // Write asset files inside assets/
      final folder = Directory(card.folderPath);
      if (await folder.exists()) {
        await for (final entity in folder.list(recursive: true)) {
          if (entity is File) {
            final fname = basename(entity.path);
            if (fname != 'metadata.json' && fname != 'content.md') {
              final bytes = await entity.readAsBytes();
              archive.addFile(ArchiveFile('assets/$fname', bytes.length, bytes));
            }
          }
        }
      }

      final zipData = ZipEncoder().encode(archive);
      if (zipData != null) {
        await zipFile.writeAsBytes(zipData);
        return zipFile;
      }
    } catch (e) {
      print("Failed to create zip for card ${card.id}: $e");
    }
    return null;
  }

  // Delete a card and its folder from disk
  Future<void> deleteCard(String id) async {
    final db = await database;
    
    final card = await getCardById(id);
    if (card != null) {
      // Remove files from disk
      final dir = Directory(card.folderPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
      }
    }
    
    // Remove from database
    await db.delete(
      'cards',
      where: 'id = ?',
      whereArgs: [id],
    );

    // Remove pending scheduled notifications for deleted card
    await db.delete(
      'scheduled_notifications',
      where: 'card_id = ? AND status = ?',
      whereArgs: [id, 'pending'],
    );

    // Remove view count record if exists
    try {
      final prefs = await SharedPreferences.getInstance();
      final countsRaw = prefs.getString('card_view_counts');
      if (countsRaw != null) {
        final Map<String, dynamic> counts = jsonDecode(countsRaw);
        if (counts.containsKey(id)) {
          counts.remove(id);
          await prefs.setString('card_view_counts', jsonEncode(counts));
        }
      }
    } catch (_) {}
  }

  // Save downloaded .flash zip, unzip it, parse metadata, write SQLite index
  Future<Flashcard> importFlashcardFromZip(File zipFile, String cardHash) async {
    final appDir = await getApplicationDocumentsDirectory();
    final targetDir = Directory(join(appDir.path, 'flashcards', cardHash));
    
    // Clean target directory if exists
    if (await targetDir.exists()) {
      await targetDir.delete(recursive: true);
    }
    await targetDir.create(recursive: true);

    // Decode and Extract ZIP
    final bytes = await zipFile.readAsBytes();
    final archive = ZipDecoder().decodeBytes(bytes);

    for (final file in archive) {
      final filename = file.name;
      if (file.isFile) {
        final data = file.content as List<int>;
        final outFile = File(join(targetDir.path, filename));
        await outFile.parent.create(recursive: true);
        await outFile.writeAsBytes(data);
      } else {
        await Directory(join(targetDir.path, filename)).create(recursive: true);
      }
    }

    // Read metadata.json inside the folder
    final metadataFile = File(join(targetDir.path, 'metadata.json'));
    if (!await metadataFile.exists()) {
      throw FileSystemException("metadata.json not found inside flashcard archive", metadataFile.path);
    }

    final metadataStr = await metadataFile.readAsString();
    final Map<String, dynamic> metadataJson = jsonDecode(metadataStr);

    // Instantiate and save SQLite
    final flashcard = Flashcard.fromJson(metadataJson, targetDir.path);
    await saveFlashcard(flashcard);

    // Clean up temporary zip file
    try {
      if (await zipFile.exists()) {
        await zipFile.delete();
      }
    } catch (e) {
      // Ignore cleanup error
    }

    return flashcard;
  }

  // Log a notification in the history
  Future<void> logNotification(String cardId, String title, String body, DateTime scheduledTime) async {
    final db = await database;
    await db.insert(
      'notifications_history',
      {
        'card_id': cardId,
        'title': title,
        'body': body,
        'scheduled_time': scheduledTime.toUtc().toIso8601String(),
      },
    );
  }

  // Get notification history (where scheduled_time <= now)
  Future<List<Map<String, dynamic>>> getNotificationHistory() async {
    final db = await database;
    final nowStr = DateTime.now().toUtc().toIso8601String();
    return await db.query(
      'notifications_history',
      where: 'scheduled_time <= ?',
      whereArgs: [nowStr],
      orderBy: 'scheduled_time DESC',
    );
  }
  
  // Clear notification history
  Future<void> clearNotificationHistory() async {
    final db = await database;
    await db.delete('notifications_history');
  }

  // Clear future notifications from history
  Future<void> clearFutureNotifications() async {
    final db = await database;
    final nowStr = DateTime.now().toUtc().toIso8601String();
    await db.delete(
      'notifications_history',
      where: 'scheduled_time > ?',
      whereArgs: [nowStr],
    );
  }

  // --- SCHEDULED NOTIFICATIONS TABLE METHODS ---

  // Insert a new batch of scheduled notifications
  Future<void> saveScheduledNotificationsBatch(List<Map<String, dynamic>> slots) async {
    final db = await database;
    final batch = db.batch();
    for (final slot in slots) {
      batch.insert('scheduled_notifications', slot);
    }
    await batch.commit(noResult: true);
  }

  // Clear scheduled notifications (if clearSent is false, preserves sent history)
  Future<void> clearScheduledNotifications({bool clearSent = false}) async {
    final db = await database;
    if (clearSent) {
      await db.delete('scheduled_notifications');
    } else {
      await db.delete(
        'scheduled_notifications',
        where: 'status = ?',
        whereArgs: ['pending'],
      );
    }
  }

  // Get all scheduled notifications (optionally filter pending only)
  Future<List<Map<String, dynamic>>> getScheduledNotifications({bool pendingOnly = false}) async {
    final db = await database;
    if (pendingOnly) {
      return await db.query(
        'scheduled_notifications',
        where: 'status = ?',
        whereArgs: ['pending'],
        orderBy: 'slot_order ASC',
      );
    }
    return await db.query(
      'scheduled_notifications',
      orderBy: 'slot_order ASC',
    );
  }

  // Get the single next pending scheduled notification (pointer item)
  Future<Map<String, dynamic>?> getNextPendingScheduledNotification() async {
    final db = await database;
    final results = await db.query(
      'scheduled_notifications',
      where: 'status = ?',
      whereArgs: ['pending'],
      orderBy: 'slot_order ASC',
      limit: 1,
    );
    if (results.isEmpty) return null;
    return results.first;
  }

  // Mark a specific scheduled notification as 'sent'
  Future<void> markScheduledNotificationSent(int id) async {
    final db = await database;
    await db.update(
      'scheduled_notifications',
      {'status': 'sent'},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  // Count remaining pending scheduled notifications
  Future<int> getPendingScheduledNotificationsCount() async {
    final db = await database;
    final result = await db.rawQuery(
      "SELECT COUNT(*) as count FROM scheduled_notifications WHERE status = 'pending'"
    );
    return Sqflite.firstIntValue(result) ?? 0;
  }

  // Mark all pending scheduled notifications for a tag as 'sent'
  Future<void> markScheduledNotificationsForTagSent(String tag) async {
    final db = await database;
    await db.rawUpdate(
      "UPDATE scheduled_notifications SET status = 'sent' WHERE LOWER(TRIM(tag)) = LOWER(TRIM(?)) AND status = 'pending'",
      [tag],
    );
  }

  // Reset sent scheduled notifications for a tag back to 'pending'
  Future<void> markScheduledNotificationsForTagPending(String tag) async {
    final db = await database;
    await db.rawUpdate(
      "UPDATE scheduled_notifications SET status = 'pending' WHERE LOWER(TRIM(tag)) = LOWER(TRIM(?))",
      [tag],
    );
  }
}
