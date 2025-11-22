import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/pairing_provider.dart';
import '../../providers/pairing_session_provider.dart';
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
  DateTime? _lastScanTime;

  /// Validates if a string looks like a valid session token format.
  bool _isValidSessionTokenFormat(String token) {
    if (token.length != 32) {
      return false;
    }
    return RegExp(r'^[A-Z0-9]+$').hasMatch(token);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final pairingState = ref.watch(pairingSessionStateProvider);
    logger.i('PairingScanScreen: Building screen, pairingState.role=${pairingState.role}, isPrimary=${pairingState.isPrimary}, sessionToken=${pairingState.sessionToken}');

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

    // Prevent processing the same token multiple times rapidly
    final now = DateTime.now();
    if (_lastScanTime != null && now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
      return; // Too soon after last scan
    }
    _lastScanTime = now;

    final barcodes = capture.barcodes;
    if (barcodes.isEmpty) {
      return;
    }

    final barcode = barcodes.first;
    final rawValue = barcode.rawValue;
    if (rawValue == null) {
      return;
    }

    logger.i('QR Code scanned: $rawValue');

    // Early validation for obviously invalid codes
    if (rawValue.length < 10) {
      logger.d('Ignoring very short code: "$rawValue"');
      return;
    }

    // Parse deep link or token
    String? token;
    if (rawValue.startsWith('anchorapp://join')) {
      logger.i('Detected deep link format');
      // Parse deep link: anchorapp://join?sessionId=...&token=...
      final uri = Uri.parse(rawValue);
      token = uri.queryParameters['token'] ?? uri.queryParameters['sessionId'];
      logger.i('Extracted token from deep link: $token');
    } else {
      logger.i('Detected direct token format');
      // Direct token - only accept if it looks like a valid session token
      final trimmed = rawValue.trim();
      if (_isValidSessionTokenFormat(trimmed)) {
        token = trimmed;
        logger.i('Accepted direct token: $token');
      } else {
        logger.w('Rejected invalid token format: "$trimmed"');
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Invalid QR code - not a valid session token'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }
    }

    if (token == null || token.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Invalid QR code format'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    // Check if trying to join our own session
    final pairingState = ref.read(pairingSessionStateProvider);
    if (pairingState.sessionToken == token) {
      logger.w('Cannot join own session - device is already primary of session $token');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Cannot join your own session'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    _scannedToken = token;
    _joinSession(token);
  }

  void _joinSession(String token) async {
    setState(() {
      _isJoining = true;
    });

    try {
      final pairingNotifier = ref.read(pairingSessionStateProvider.notifier);
      await pairingNotifier.joinSecondarySession(token);
      
      logger.i('Successfully joined monitoring session: $token');
      
      if (mounted) {
        Navigator.of(context).popUntil((route) => route.isFirst); // Return to map screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully joined paired session!'),
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

