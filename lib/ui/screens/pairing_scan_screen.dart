import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/pairing_provider.dart';
import '../../utils/logger_setup.dart';

/// Screen for scanning QR code to join a pairing session.
class PairingScanScreen extends ConsumerStatefulWidget {
  const PairingScanScreen({super.key});

  @override
  ConsumerState<PairingScanScreen> createState() => _PairingScanScreenState();
}

class _PairingScanScreenState extends ConsumerState<PairingScanScreen> {
  final MobileScannerController _controller = MobileScannerController();
  bool _isJoining = false;
  String? _scannedToken;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Scan QR Code'),
      ),
      body: Column(
        children: [
          // Scanner view
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: _onQRCodeDetected,
                ),
                // Overlay with scanning area
                CustomPaint(
                  painter: QRScannerOverlay(),
                ),
              ],
            ),
          ),
          // Instructions
          Container(
            padding: const EdgeInsets.all(16),
            color: Colors.black87,
            child: Column(
              children: [
                const Text(
                  'Point camera at QR code',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 8),
                const Text(
                  'The QR code should be displayed on the primary device',
                  style: TextStyle(color: Colors.white70),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                // Manual entry option
                TextButton.icon(
                  onPressed: () => _showManualEntryDialog(),
                  icon: const Icon(Icons.keyboard, color: Colors.white),
                  label: const Text(
                    'Enter Token Manually',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  void _onQRCodeDetected(BarcodeCapture capture) {
    if (_isJoining || _scannedToken != null) {
      return; // Already processing
    }

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) {
      return;
    }

    final barcode = barcodes.first;
    final rawValue = barcode.rawValue;
    if (rawValue == null) {
      return;
    }

    final token = rawValue.trim();
    _scannedToken = token;
    _joinSession(token);
  }

  void _joinSession(String token) async {
    setState(() {
      _isJoining = true;
    });

    try {
      final notifier = ref.read(pairingSessionProvider.notifier);
      await notifier.joinSession(token);
      
      logger.i('Successfully joined session: $token');
      
      if (mounted) {
        Navigator.of(context).pop(); // Return to pairing screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully joined pairing session!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      logger.e(
        'Failed to join session',
        error: e,
        stackTrace: stackTrace,
      );
      
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to join session: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
        
        // Reset to allow retry
        setState(() {
          _isJoining = false;
          _scannedToken = null;
        });
      }
    }
  }

  void _showManualEntryDialog() {
    final tokenController = TextEditingController();
    
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Enter Session Token'),
        content: TextField(
          controller: tokenController,
          decoration: const InputDecoration(
            labelText: 'Token',
            hintText: 'Enter 32-character token',
            border: OutlineInputBorder(),
          ),
          maxLength: 32,
          textCapitalization: TextCapitalization.characters,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () {
              final token = tokenController.text.trim().toUpperCase();
              if (token.length == 32) {
                Navigator.pop(context);
                _joinSession(token);
              } else {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Token must be 32 characters'),
                  ),
                );
              }
            },
            child: const Text('Join'),
          ),
        ],
      ),
    );
  }
}

/// Custom painter for QR scanner overlay.
class QRScannerOverlay extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.black.withValues(alpha: 0.5)
      ..style = PaintingStyle.fill;

    // Draw darkened background
    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, size.height), paint);

    // Clear scanning area (center square)
    final scanAreaSize = size.width * 0.7;
    final scanAreaLeft = (size.width - scanAreaSize) / 2;
    final scanAreaTop = (size.height - scanAreaSize) / 2;
    final scanArea = Rect.fromLTWH(
      scanAreaLeft,
      scanAreaTop,
      scanAreaSize,
      scanAreaSize,
    );

    final clearPaint = Paint()
      ..blendMode = BlendMode.clear;
    canvas.drawRect(scanArea, clearPaint);

    // Draw corner brackets
    final cornerLength = 30.0;
    final cornerWidth = 4.0;
    final cornerPaint = Paint()
      ..color = Colors.white
      ..strokeWidth = cornerWidth
      ..style = PaintingStyle.stroke;

    // Top-left
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop),
      Offset(scanAreaLeft + cornerLength, scanAreaTop),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop),
      Offset(scanAreaLeft, scanAreaTop + cornerLength),
      cornerPaint,
    );

    // Top-right
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop),
      Offset(scanAreaLeft + scanAreaSize - cornerLength, scanAreaTop),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop),
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + cornerLength),
      cornerPaint,
    );

    // Bottom-left
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop + scanAreaSize),
      Offset(scanAreaLeft + cornerLength, scanAreaTop + scanAreaSize),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft, scanAreaTop + scanAreaSize),
      Offset(scanAreaLeft, scanAreaTop + scanAreaSize - cornerLength),
      cornerPaint,
    );

    // Bottom-right
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + scanAreaSize),
      Offset(scanAreaLeft + scanAreaSize - cornerLength, scanAreaTop + scanAreaSize),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + scanAreaSize),
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + scanAreaSize - cornerLength),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

