import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:mobile/services/sync_service.dart';

class ScannerView extends StatefulWidget {
  const ScannerView({Key? key}) : super(key: key);

  @override
  State<ScannerView> createState() => _ScannerViewState();
}

class _ScannerViewState extends State<ScannerView> {
  final MobileScannerController _controller = MobileScannerController();
  final TextEditingController _urlController = TextEditingController();
  bool _isProcessing = false;

  @override
  void dispose() {
    _controller.dispose();
    _urlController.dispose();
    super.dispose();
  }

  Future<void> _handleQrDetect(BarcodeCapture capture) async {
    if (_isProcessing) return;

    final List<Barcode> barcodes = capture.barcodes;
    if (barcodes.isEmpty) return;

    final String? rawValue = barcodes.first.rawValue;
    if (rawValue == null || rawValue.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    _controller.stop(); // Stop scanning while handshaking

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Scanned QR. Attempting handshake with PC...')),
    );

    // Call sync service to pair
    final bool success = await SyncService().pairWithQR(rawValue);

    if (mounted) {
      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Successfully Paired with PC!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true); // Return success
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Failed to pair. Make sure devices are on the same Wi-Fi.'), backgroundColor: Colors.red),
        );
        
        // Reset state and resume scanner
        setState(() {
          _isProcessing = false;
        });
        _controller.start();
      }
    }
  }

  Future<void> _handleManualConnect() async {
    final text = _urlController.text.trim();
    if (text.isEmpty) return;

    setState(() {
      _isProcessing = true;
    });

    final scaffoldMessenger = ScaffoldMessenger.of(context);
    scaffoldMessenger.showSnackBar(
      const SnackBar(content: Text('Attempting manual connection...')),
    );

    final success = await SyncService().connectWithManualUrl(text);

    if (mounted) {
      if (success) {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Successfully Connected to PC!'), backgroundColor: Colors.green),
        );
        Navigator.pop(context, true);
      } else {
        scaffoldMessenger.showSnackBar(
          const SnackBar(content: Text('Failed to connect. Check IP address and port.'), backgroundColor: Colors.red),
        );
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        title: const Text('Pair Mobile Device', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            color: Colors.white,
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                switch (state.torchState) {
                  case TorchState.on:
                    return const Icon(Icons.flash_on, color: Colors.yellow);
                  default:
                    return const Icon(Icons.flash_off, color: Colors.grey);
                }
              },
            ),
            iconSize: 25.0,
            onPressed: () => _controller.toggleTorch(),
          ),
          IconButton(
            color: Colors.white,
            icon: ValueListenableBuilder<MobileScannerState>(
              valueListenable: _controller,
              builder: (context, state, child) {
                switch (state.cameraDirection) {
                  case CameraFacing.front:
                    return const Icon(Icons.camera_front);
                  default:
                    return const Icon(Icons.camera_rear);
                }
              },
            ),
            iconSize: 25.0,
            onPressed: () => _controller.switchCamera(),
          ),
        ],
      ),
      body: Stack(
        children: [
          MobileScanner(
            controller: _controller,
            onDetect: _handleQrDetect,
          ),
          // Scanner Overlay Box
          Center(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(
                border: Border.all(color: Colors.cyan, width: 3),
                borderRadius: BorderRadius.circular(16),
                color: Colors.transparent,
              ),
            ),
          ),
          // Floating Manual IP Input Container at Bottom
          Positioned(
            left: 16,
            right: 16,
            bottom: 24,
            child: Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: const Color(0xFF1E293B),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.cyan, width: 2.5),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black54,
                    offset: Offset(4, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Text(
                    'Or Connect via IP / Server URL:',
                    style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 12),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: TextField(
                          controller: _urlController,
                          style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold),
                          decoration: InputDecoration(
                            hintText: 'e.g. 192.168.1.5:6769',
                            hintStyle: TextStyle(color: Colors.grey[500], fontSize: 12),
                            filled: true,
                            fillColor: Colors.black54,
                            isDense: true,
                            contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.grey),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(8),
                              borderSide: const BorderSide(color: Colors.cyan, width: 2),
                            ),
                          ),
                          onSubmitted: (_) => _handleManualConnect(),
                        ),
                      ),
                      const SizedBox(width: 8),
                      ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.cyan,
                          foregroundColor: Colors.black,
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                        onPressed: _handleManualConnect,
                        child: const Text('CONNECT', style: TextStyle(fontWeight: FontWeight.w900, fontSize: 12)),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
          if (_isProcessing)
            Container(
              color: Colors.black54,
              child: const Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CircularProgressIndicator(),
                    SizedBox(height: 16),
                    Text(
                      'Pairing in progress...',
                      style: TextStyle(color: Colors.white, fontSize: 16),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}
