import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:mobile/models/flashcard.dart';
import 'package:mobile/services/storage_service.dart';

class SyncService {
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

  bool get isSyncing => _isSyncing;
  String? get serverIp => _serverIp;
  int? get serverPort => _serverPort;

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
  }

  // Set pairing configuration manually
  Future<void> _saveConnection(String ip, int port) async {
    final prefs = await SharedPreferences.getInstance();
    _serverIp = ip;
    _serverPort = port;
    await prefs.setString('server_ip', ip);
    await prefs.setInt('server_port', port);
  }

  // Disconnect / Clear pairing
  Future<void> disconnect() async {
    final prefs = await SharedPreferences.getInstance();
    _serverIp = null;
    _serverPort = null;
    await prefs.remove('server_ip');
    await prefs.remove('server_port');
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
      
      // Step B: If UDP fails, fall back to sweeping TCP IP list
      if (foundIp == null) {
        foundIp = await _sweepIpsForPairing(ips.cast<String>(), port, pairingCode);
      }

      if (foundIp != null) {
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

  // Iterate over IPs to pair
  Future<String?> _sweepIpsForPairing(List<String> ips, int port, String pairingCode) async {
    for (String ip in ips) {
      try {
        print("Sweeping connection target: http://$ip:$port/api/pairing/pair");
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
        ).timeout(const Duration(seconds: 1));

        if (response.statusCode == 200) {
          print("Handshake success with PC at $ip");
          return ip;
        }
      } catch (e) {
        // Timeout or unreachable IP, move to next
        continue;
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
        print("Sync queue has ${pendingHashes.length} cards to download.");

        for (String cardHash in pendingHashes.cast<String>()) {
          await _downloadAndImportCard(cardHash);
        }
      }
    } catch (e) {
      print("Sync cycle failed: $e");
    } finally {
      _isSyncing = false;
    }
  }

  // Download a single zip, unzip it, and insert into local library
  Future<void> _downloadAndImportCard(String cardHash) async {
    try {
      final downloadUrl = Uri.parse("http://$_serverIp:$_serverPort/api/sync/card/$cardHash/download");
      final response = await http.get(downloadUrl);

      if (response.statusCode == 200) {
        // Save bytes as temporary zip file
        final tempDir = await getTemporaryDirectory();
        final tempZipFile = File('${tempDir.path}/$cardHash.zip');
        await tempZipFile.writeAsBytes(response.bodyBytes);

        // Process and unzip
        await _storageService.importFlashcardFromZip(tempZipFile, cardHash);
        print("Successfully synced and unzipped card $cardHash");

        // Notify backend of completion
        final confirmUri = Uri.parse("http://$_serverIp:$_serverPort/api/sync/device/$_deviceId/complete/$cardHash");
        await http.post(confirmUri);
      } else {
        print("Failed to download card $cardHash (Status: ${response.statusCode})");
      }
    } catch (e) {
      print("Error downloading/extracting card $cardHash: $e");
    }
  }
}
