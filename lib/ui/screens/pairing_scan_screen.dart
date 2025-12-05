import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../providers/pairing/pairing_providers.dart';
import '../../utils/logger_setup.dart';

/// Screen for scanning QR code to join a pairing session.
class PairingScanScreen extends ConsumerStatefulWidget {
  const PairingScanScreen({super.key});

  @override
  ConsumerState<PairingScanScreen> createState() => _PairingScanScreenState();
}

class _PairingScanScreenState extends ConsumerState<PairingScanScreen>
    with WidgetsBindingObserver {
  final MobileScannerController _controller = MobileScannerController(
    autoStart: false, // Don't start automatically to avoid blocking UI
  );
  bool _isJoining = false;
  String? _scannedToken;
  DateTime? _lastScanTime;
  bool _scannerStarted = false;
  bool _showConflictDialog = false; // Control dialog visibility
  bool _conflictDialogDismissed =
      false; // Prevent dialog from showing again once dismissed
  // Camera permission handling is now done by MobileScanner directly

  /// Validates if a string looks like a valid session token format.
  bool _isValidSessionTokenFormat(String token) {
    if (token.length != 32) {
      return false;
    }
    return RegExp(r'^[A-Z0-9]+$').hasMatch(token);
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Start scanner after frame renders to avoid blocking UI
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _startScanner();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);

    // Pause/resume scanner based on app lifecycle to prevent freezes
    if (state == AppLifecycleState.paused) {
      logger.i('Scanner: App paused, stopping scanner');
      _controller.stop();
      _scannerStarted = false;
    } else if (state == AppLifecycleState.resumed && !_scannerStarted) {
      logger.i('Scanner: App resumed, starting scanner');
      _startScanner();
    }
  }

  Future<void> _startScanner() async {
    try {
      await _controller.start();
      _scannerStarted = true;
      logger.i('Scanner started successfully');
    } catch (e) {
      logger.e('Failed to start scanner', error: e);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: const Text(
              'Failed to start camera. Please check permissions.',
            ),
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final pairingState = ref.watch(pairingSessionStateProvider);
    logger.i(
      'PairingScanScreen: Building screen, pairingState.role=${pairingState.role}, isPrimary=${pairingState.isPrimary}, sessionToken=${pairingState.sessionToken}',
    );

    // Check for session conflict - device already has an active session
    if (pairingState.isPrimary &&
        pairingState.sessionToken != null &&
        !_showConflictDialog &&
        !_conflictDialogDismissed) {
      _showConflictDialog = true;
    }

    // Let MobileScanner handle camera permissions directly
    // This ensures iOS shows the permission dialog and adds the toggle to Settings

    return Scaffold(
      appBar: AppBar(title: const Text('Scan QR Code')),
      body: Stack(
        children: [
          // Main scan interface
          Column(
            children: [
              // Scanner view
              Expanded(
                child: Stack(
                  children: [
                    MobileScanner(
                      controller: _controller,
                      onDetect: _onQRCodeDetected,
                      errorBuilder: (BuildContext context, MobileScannerException error) {
                        logger.e('MobileScanner error', error: error);
                        return Container(
                          color: Colors.black,
                          child: Center(
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                const Icon(
                                  Icons.camera_alt,
                                  size: 64,
                                  color: Colors.white70,
                                ),
                                const SizedBox(height: 16),
                                const Text(
                                  'Camera Access Required',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Text(
                                  error.toString().contains('permission')
                                      ? 'Camera permission is required to scan QR codes. Please go to Settings > Anchor Alarm and enable Camera.'
                                      : 'Unable to access camera. Please check your device settings.',
                                  style: const TextStyle(color: Colors.white70),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(height: 24),
                                ElevatedButton(
                                  onPressed: () {
                                    // Navigate back so user can try again or go to settings manually
                                    Navigator.of(context).pop();
                                  },
                                  child: const Text('Go Back'),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                    // Overlay with scanning area
                    CustomPaint(painter: QRScannerOverlay()),
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
          // Conflict dialog overlay
          if (_showConflictDialog &&
              pairingState.isPrimary &&
              pairingState.sessionToken != null)
            Container(
              color: Colors.black54,
              child: Center(
                child: AlertDialog(
                  title: const Text('Session Conflict'),
                  content: const Text(
                    'You already have an active session as the primary device. '
                    'To pair with another device, you must first cancel your current session.\n\n'
                    'What would you like to do?',
                  ),
                  actions: [
                    TextButton(
                      onPressed: () async {
                        logger.i(
                          '❌ Cancel Session button pressed - canceling session and staying on scan screen',
                        );

                        try {
                          // Cancel the current session
                          final sessionNotifier = ref.read(
                            pairingSessionStateProvider.notifier,
                          );
                          logger.i('🔄 Calling sessionNotifier.endSession()');
                          await sessionNotifier.endSession();
                          logger.i('✅ sessionNotifier.endSession() completed');

                          // Hide the dialog
                          _showConflictDialog = false;
                          _conflictDialogDismissed =
                              true; // Prevent showing again

                          // Stay on scan screen - user can manually navigate back
                          if (mounted) {
                            setState(() {});
                          }
                        } catch (e) {
                          logger.e('❌ Failed to cancel session', error: e);
                          // Hide dialog even on error
                          _showConflictDialog = false;
                          _conflictDialogDismissed = true;

                          if (mounted) {
                            setState(() {});
                          }
                        }
                      },
                      child: const Text('Cancel Session'),
                    ),
                    TextButton(
                      onPressed: () {
                        logger.i('🚪 Exit button pressed - going back without canceling session');
                        // Just hide the dialog and navigate back
                          _showConflictDialog = false;
                        _conflictDialogDismissed = true;
                          if (mounted) {
                            Navigator.of(context).pop();
                        }
                      },
                      child: const Text('Exit'),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _onQRCodeDetected(BarcodeCapture capture) {
    final detectStartTime = DateTime.now();
    logger.i('🕐 QR code detected at $detectStartTime');

    if (_isJoining || _scannedToken != null) {
      return; // Already processing
    }

    // Prevent processing the same token multiple times rapidly
    final now = DateTime.now();
    if (_lastScanTime != null &&
        now.difference(_lastScanTime!) < const Duration(seconds: 2)) {
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

    logger.i('🕐 Raw QR value received at ${DateTime.now()}: $rawValue');
    logger.i('🕐 QR barcode format: ${barcode.format}');
    logger.i('🕐 QR raw bytes length: ${barcode.rawBytes?.length ?? 0}');

    // Early validation for obviously invalid codes
    if (rawValue.length < 10) {
      logger.d('Ignoring very short code: "$rawValue"');
      return;
    }

    // Parse deep link or token
    String? token;
    if (rawValue.startsWith('anchorapp://join')) {
      logger.i('🔗 Detected deep link format');
      // Parse deep link: anchorapp://join?sessionId=...&token=...
      final uri = Uri.parse(rawValue);
      logger.i('🔗 Deep link URI: $uri');
      logger.i('🔗 Deep link query parameters: ${uri.queryParameters}');
      token = uri.queryParameters['token'] ?? uri.queryParameters['sessionId'];
      logger.i('🔗 Extracted token from deep link: "$token"');
    } else {
      logger.i('🎫 Detected direct token format');
      // Direct token - only accept if it looks like a valid session token
      final trimmed = rawValue.trim();
      logger.i('🎫 Trimmed token: "$trimmed"');
      if (_isValidSessionTokenFormat(trimmed)) {
        token = trimmed;
        logger.i('✅ Accepted direct token: "$token"');
      } else {
        logger.w('❌ Rejected invalid token format: "$trimmed"');
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

    // Check if trying to join our own active session
    final pairingState = ref.read(pairingSessionStateProvider);
    logger.i(
      '🔍 Checking for own session: isPrimary=${pairingState.isPrimary}, sessionToken=${pairingState.sessionToken}, scannedToken=$token',
    );
    if (pairingState.isPrimary && pairingState.sessionToken == token) {
      logger.w(
        'Cannot join own session - device is already primary of session $token',
      );
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
    logger.i('🕐 Starting session join at ${DateTime.now()} for token: $token');
    _joinSession(token);
  }

  void _joinSession(String token) async {
    final joinStartTime = DateTime.now();
    logger.i('🕐 TOKEN TRACE: _joinSession called with token: "$token"');
    logger.i(
      '🕐 TOKEN VALIDATION: Token length: ${token.length}, isValidFormat: ${_isValidSessionTokenFormat(token)}',
    );
    logger.i('🕐 Session join operation started at $joinStartTime');

    setState(() {
      _isJoining = true;
    });

    try {
      final pairingNotifier = ref.read(pairingSessionStateProvider.notifier);
      logger.i(
        '🕐 TOKEN TRACE: Calling pairingNotifier.joinSecondarySession("$token")',
      );
      await pairingNotifier.joinSecondarySession(token);

      final joinEndTime = DateTime.now();
      final joinDuration = joinEndTime.difference(joinStartTime);
      logger.i(
        '✅ Successfully joined session at $joinEndTime (duration: ${joinDuration.inSeconds}s): $token',
      );

      if (mounted) {
        Navigator.of(
          context,
        ).popUntil((route) => route.isFirst); // Return to map screen
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Successfully joined paired session!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e, stackTrace) {
      logger.e('Failed to join session', error: e, stackTrace: stackTrace);

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
                  const SnackBar(content: Text('Token must be 32 characters')),
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

    final clearPaint = Paint()..blendMode = BlendMode.clear;
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
      Offset(
        scanAreaLeft + scanAreaSize - cornerLength,
        scanAreaTop + scanAreaSize,
      ),
      cornerPaint,
    );
    canvas.drawLine(
      Offset(scanAreaLeft + scanAreaSize, scanAreaTop + scanAreaSize),
      Offset(
        scanAreaLeft + scanAreaSize,
        scanAreaTop + scanAreaSize - cornerLength,
      ),
      cornerPaint,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
