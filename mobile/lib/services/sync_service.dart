import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart'; // For ChangeNotifier
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile/models/flashcard.dart';
import 'package:mobile/services/storage_service.dart';
import 'package:crypto/crypto.dart';

class SyncService extends ChangeNotifier {
  static final SyncService _instance = SyncService._internal();
  factory SyncService() => _instance;
  SyncService._internal();

  final StorageService _storageService = StorageService();

  // Connection config saved in SharedPreferences
  String? _serverIp;
  int? _serverPort;
  String? _deviceId;
  String? _deviceName;
  bool _isSyncing = false;
  
  Timer? _pingTimer;
  bool _isPcReachable = false;
  int lastSyncedCount = 0;

  bool get isSyncing => _isSyncing;
  String? get serverIp => _serverIp;
  int? get serverPort => _serverPort;
  bool get isPcReachable => _isPcReachable;
  bool get isConnected => _serverIp != null && _serverPort != null && _isPcReachable;

  // Initialize service settings
  Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    _serverIp = prefs.getString('server_ip');
    _serverPort = prefs.getInt('server_port');
    _deviceId = prefs.getString('device_id');
    _deviceName = prefs.getString('device_name');

    if (_deviceId == null) {
      _deviceId = const Uuid().v4();
      await prefs.setString('device_id', _deviceId!);
    }
    if (_deviceName == null) {
      _deviceName = '${Platform.operatingSystem} Client';
      await prefs.setString('device_name', _deviceName!);
    }
    
    await checkPcConnection();
    if (_isPcReachable) {
      triggerSyncCycle();
    }
    startPingTimer();
  }

  // Start periodic pings to verify if PC server is alive
  void startPingTimer() {
    _pingTimer?.cancel();
    _pingTimer = Timer.periodic(const Duration(seconds: 4), (timer) async {
      await checkPcConnection();
    });
  }

  // Verification request to server
  Future<void> checkPcConnection() async {
    if (_serverIp == null || _serverPort == null) {
      if (_isPcReachable) {
        _isPcReachable = false;
        notifyListeners();
      }
      return;
    }
    try {
      final uri = Uri.parse("http://$_serverIp:$_serverPort/api/pairing/heartbeat/$_deviceId");
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "device_name": _deviceName ?? "Flutter Client",
          "client_ip": "127.0.0.1",
        }),
      ).timeout(const Duration(seconds: 1));
      
      final reachable = (response.statusCode == 200);
      if (_isPcReachable != reachable) {
        _isPcReachable = reachable;
        notifyListeners();
        if (reachable) {
          triggerSyncCycle();
        }
      }
    } catch (_) {
      if (_isPcReachable) {
        _isPcReachable = false;
        notifyListeners();
      }
    }
  }

  // Set pairing configuration manually
  Future<void> _saveConnection(String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    _serverIp = ip;
    _serverPort = port;
    await prefs.setString('server_ip', ip);
    await prefs.setInt('server_port', port);
    await checkPcConnection();
    notifyListeners();
  }

  // Disconnect / Clear pairing
  Future<void> disconnect() async {
    if (_serverIp != null && _serverPort != null && _deviceId != null) {
      try {
        final uri = Uri.parse("http://$_serverIp:$_serverPort/api/pairing/disconnect/$_deviceId");
        await http.post(uri).timeout(const Duration(seconds: 1));
      } catch (e) {
        // ignore
      }
    }
    final prefs = await SharedPreferences.getInstance();
    _serverIp = null;
    _serverPort = null;
    _isPcReachable = false;
    await prefs.remove('server_ip');
    await prefs.remove('server_port');
    notifyListeners();
  }

  @override
  void dispose() {
    _pingTimer?.cancel();
    super.dispose();
  }

  // 1. Discovery & Pairing Flow
  Future<bool> pairWithQR(String qrRawPayload) async {
    try {
      final Map<String, dynamic> data = jsonDecode(qrRawPayload);
      final String pairingCode = data['pairing_code'];
      final int port = data['port'];
      final List<dynamic> ips = data['ips'];

      // Step A: Attempt UDP Broadcast discovery
      String? foundIp = await _discoverServerViaUdp(pairingCode, port);
      bool paired = false;
      
      if (foundIp != null) {
        paired = await _runPairingHandshake(foundIp, port, pairingCode);
      }
      
      // Step B: If UDP fails or handshake fails, fall back to sweeping TCP IP list
      if (!paired) {
        foundIp = await _sweepIpsForPairing(ips.cast<String>(), port, pairingCode);
        paired = (foundIp != null);
      }

      if (paired && foundIp != null) {
        await _saveConnection(foundIp, port);
        // Sync libraries immediately upon successful pairing
        triggerSyncCycle();
        return true;
      }
    } catch (e) {
      print("Pairing error: $e");
    }
    return false;
  }

  // Send UDP Broadcast to discover the PC
  Future<String?> _discoverServerViaUdp(String pairingCode, int port) async {
    try {
      final socket = await RawDatagramSocket.bind(InternetAddress.anyIPv4, 0);
      socket.broadcastEnabled = true;
      
      final Map<String, dynamic> discoverMsg = {
        "action": "discover",
        "pairing_code": pairingCode
      };
      final List<int> payload = utf8.encode(jsonEncode(discoverMsg));
      
      // Broadcast to 255.255.255.255 on specified port
      socket.send(payload, InternetAddress("255.255.255.255"), port);
      print("Sent UDP discovery broadcast to port $port");

      final Completer<String?> completer = Completer();
      
      // Setup a timeout for listening
      Timer(const Duration(seconds: 2), () {
        if (!completer.isCompleted) {
          socket.close();
          completer.complete(null);
        }
      });

      socket.listen((RawSocketEvent event) {
        if (event == RawSocketEvent.read) {
          final datagram = socket.receive();
          if (datagram != null) {
            try {
              final resp = jsonDecode(utf8.decode(datagram.data));
              if (resp['action'] == 'discover_reply' && resp['status'] == 'ok') {
                final pcIp = datagram.address.address;
                print("UDP Discovery Reply received from PC: $pcIp");
                socket.close();
                completer.complete(pcIp);
              }
            } catch (e) {
              // Ignore parse errors from foreign packets
            }
          }
        }
      });

      return await completer.future;
    } catch (e) {
      print("UDP Broadcast exception: $e");
      return null;
    }
  }

  // Run the HTTP pairing handshake to register with the PC
  Future<bool> _runPairingHandshake(String ip, int port, String pairingCode) async {
    try {
      final uri = Uri.parse("http://$ip:$port/api/pairing/pair");
      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "pairing_code": pairingCode,
          "device_id": _deviceId,
          "device_name": _deviceName,
          "client_ip": "127.0.0.1" // Will be overwritten by FastAPI client host address
        }),
      ).timeout(const Duration(seconds: 2));

      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Manual IP / Connection URL Connection Method
  Future<bool> connectWithManualUrl(String urlOrIp) async {
    try {
      String raw = urlOrIp.trim();
      if (raw.isEmpty) return false;

      if (!raw.startsWith('http://') && !raw.startsWith('https://')) {
        raw = 'http://$raw';
      }

      final uri = Uri.parse(raw);
      final host = uri.host;
      final port = uri.hasPort ? uri.port : 6769;

      if (host.isEmpty) return false;

      print("Attempting manual connection to $host:$port");

      final paired = await _runPairingHandshake(host, port, "manual");
      final heartbeat = await _tryHeartbeatDirect(host, port);

      if (paired || heartbeat) {
        await _saveConnection(host, port);
        triggerSyncCycle();
        return true;
      }
    } catch (e) {
      print("Manual URL connection error: $e");
    }
    return false;
  }

  Future<bool> _tryHeartbeatDirect(String host, int port) async {
    try {
      final uri = Uri.parse("http://$host:$port/api/pairing/heartbeat/$_deviceId");
      final response = await http.post(
        uri,
        headers: {"Content-Type": "application/json"},
        body: jsonEncode({
          "device_name": _deviceName ?? "Flutter Client",
          "client_ip": "127.0.0.1",
        }),
      ).timeout(const Duration(seconds: 2));
      return response.statusCode == 200;
    } catch (e) {
      return false;
    }
  }

  // Iterate over IPs to pair
  Future<String?> _sweepIpsForPairing(List<String> ips, int port, String pairingCode) async {
    for (String ip in ips) {
      print("Sweeping connection target: http://$ip:$port/api/pairing/pair");
      final success = await _runPairingHandshake(ip, port, pairingCode);
      if (success) {
        print("Handshake success with PC at $ip");
        return ip;
      }
    }
    return null;
  }

  // 2. Main Sync Cycle
  Future<void> triggerSyncCycle() async {
    if (_isSyncing) return;
    if (_serverIp == null || _serverPort == null) return;

    _isSyncing = true;
    print("Starting sync cycle with PC http://$_serverIp:$_serverPort");

    try {
      // Step A: Upload mobile library hashes
      final localCards = await _storageService.getAllCards();
      final localHashes = localCards.map((c) => c.id).toList();

      final libUri = Uri.parse("http://$_serverIp:$_serverPort/api/sync/device/$_deviceId/library");
      await http.post(
        libUri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({"card_hashes": localHashes}),
      );

      // Step B: Get pending sync transfers
      final pendingUri = Uri.parse("http://$_serverIp:$_serverPort/api/sync/device/$_deviceId/pending");
      final pendingResp = await http.get(pendingUri);
      
      if (pendingResp.statusCode == 200) {
        final Map<String, dynamic> data = jsonDecode(pendingResp.body);
        final List<dynamic> pendingHashes = data['pending_hashes'] ?? [];
        lastSyncedCount = pendingHashes.length;
        print("Sync queue has ${pendingHashes.length} cards to download.");

        for (String cardHash in pendingHashes.cast<String>()) {
          await _downloadAndImportCard(cardHash);
        }
      }
    } catch (e) {
      print("Sync cycle failed: $e");
    } finally {
      _isSyncing = false;
      notifyListeners();
    }
  }

  // Download a single zip, unzip it, and insert into local library
  Future<void> _downloadAndImportCard(String cardHash) async {
    try {
      final downloadUrl = Uri.parse("http://$_serverIp:$_serverPort/api/sync/card/$cardHash/download");
      final response = await http.get(downloadUrl);

      if (response.statusCode == 200) {
        final bytes = response.bodyBytes;
        // Compute SHA256 checksum of the downloaded file bytes
        final checksum = sha256.convert(bytes).toString();

        // Save bytes as temporary zip file
        final tempDir = await getTemporaryDirectory();
        final tempZipFile = File('${tempDir.path}/$cardHash.zip');
        await tempZipFile.writeAsBytes(bytes);

        // Process and unzip
        await _storageService.importFlashcardFromZip(tempZipFile, cardHash);
        print("Successfully synced and unzipped card $cardHash");

        // Notify backend of completion with checksum for file integrity verification
        final confirmUri = Uri.parse("http://$_serverIp:$_serverPort/api/sync/device/$_deviceId/complete/$cardHash?checksum=$checksum");
        final confirmResp = await http.post(confirmUri);
        if (confirmResp.statusCode != 200) {
          throw Exception("Integrity verification failed on PC server: ${confirmResp.body}");
        }
      } else {
        print("Failed to download card $cardHash (Status: ${response.statusCode})");
      }
    } catch (e) {
      print("Error downloading/extracting card $cardHash: $e");
    }
  }
}
