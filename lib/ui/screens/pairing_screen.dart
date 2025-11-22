import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../providers/pairing_provider.dart';
import '../../providers/pairing_session_provider.dart';
import '../../models/pairing_session.dart';
import '../../models/device_info.dart';
import '../../utils/logger_setup.dart';
import 'pairing_scan_screen.dart';

/// Screen for pairing devices - shows QR code for primary device.
class PairingScreen extends ConsumerStatefulWidget {
  const PairingScreen({super.key});

  @override
  ConsumerState<PairingScreen> createState() => _PairingScreenState();
}

class _PairingScreenState extends ConsumerState<PairingScreen> {
  bool _isCreating = false;

  /// Converts Firebase session data Map to PairingSession object
  PairingSession _mapToPairingSession(Map<String, dynamic> data) {
    return PairingSession(
      token: data['token'] as String? ?? '',
      primaryDeviceId: data['primaryDeviceId'] as String? ?? '',
      devices: (data['devices'] as List<dynamic>? ?? [])
          .map((d) => DeviceInfo.fromFirestore(d as Map<String, dynamic>))
          .toList(),
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      expiresAt: (data['expiresAt'] as Timestamp?)?.toDate() ?? DateTime.now().add(const Duration(hours: 24)),
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(effectiveSessionProvider);
    final sessionData = sessionAsync.maybeWhen(
      data: (data) => data,
      orElse: () => <String, dynamic>{},
    );

    // Convert Map to PairingSession if we have data
    final PairingSession? session = sessionData.isNotEmpty ? _mapToPairingSession(sessionData) : null;

    final pairingNotifier = ref.read(pairingSessionProvider.notifier);
    final pairingState = ref.watch(pairingSessionStateProvider);
    final sessionNotifier = ref.read(pairingSessionStateProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Device Pairing'),
        actions: [
          IconButton(
            icon: const Icon(Icons.qr_code_scanner),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PairingScanScreen(),
                ),
              );
            },
            tooltip: 'Scan QR Code',
          ),
        ],
      ),
      body: session == null
          ? _buildCreateSessionView(pairingNotifier, sessionNotifier)
          : _buildSessionView(session, pairingNotifier, sessionNotifier),
    );
  }

  Widget _buildCreateSessionView(
    PairingSessionNotifier pairingNotifier,
    PairingSessionStateNotifier sessionNotifier,
  ) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(
              Icons.devices,
              size: 64,
              color: Colors.blue,
            ),
            const SizedBox(height: 24),
            const Text(
              'Share Monitoring',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Create a monitoring session to allow other devices to monitor your anchor position in real-time.',
              textAlign: TextAlign.center,
              style: TextStyle(fontSize: 16),
            ),
            const SizedBox(height: 32),
            ElevatedButton.icon(
              onPressed: _isCreating
                  ? null
                  : () async {
                      setState(() {
                        _isCreating = true;
                      });
                      try {
                        await sessionNotifier.startPrimarySession();
                      } catch (e, stackTrace) {
                        logger.e(
                          'Failed to create session',
                          error: e,
                          stackTrace: stackTrace,
                        );
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to create session: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      } finally {
                        if (mounted) {
                          setState(() {
                            _isCreating = false;
                          });
                        }
                      }
                    },
              icon: _isCreating
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.add),
              label: Text(_isCreating ? 'Creating...' : 'Create Session'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 32,
                  vertical: 16,
                ),
              ),
            ),
            const SizedBox(height: 24),
            TextButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PairingScanScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.qr_code_scanner),
              label: const Text('Join Existing Session'),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSessionView(
    PairingSession session,
    PairingSessionNotifier pairingNotifier,
    PairingSessionStateNotifier sessionNotifier,
  ) {
    // Generate deep link for QR code
    final deepLink = 'anchorapp://join?sessionId=${session.token}&token=${session.token}';
    return SingleChildScrollView(
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text(
              'Share this QR code with other devices',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 24),
            // QR Code
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  ),
                ],
              ),
              child: QrImageView(
                data: deepLink,
                version: QrVersions.auto,
                size: 300,
                backgroundColor: Colors.white,
              ),
            ),
            const SizedBox(height: 24),
            // Session Token (for manual entry)
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Session Token',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    SelectableText(
                      session.token,
                      style: const TextStyle(
                        fontFamily: 'monospace',
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: deepLink));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Deep link copied to clipboard'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy Link'),
                          ),
                        ),
                        Expanded(
                          child: TextButton.icon(
                            onPressed: () {
                              Clipboard.setData(ClipboardData(text: session.token));
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Token copied to clipboard'),
                                ),
                              );
                            },
                            icon: const Icon(Icons.copy),
                            label: const Text('Copy Token'),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 16),
            // Session Info
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16.0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Session Info',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    _buildInfoRow('Devices', '${session.devices.length}'),
                    _buildInfoRow(
                      'Expires',
                      _formatTimeRemaining(session.expiresAt),
                    ),
                    _buildInfoRow(
                      'Status',
                      session.isActive ? 'Active' : 'Inactive',
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 24),
            // End Session Button
            ElevatedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('End Session'),
                    content: const Text(
                      'Are you sure you want to end this pairing session?',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        child: const Text('End Session'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true) {
                  await sessionNotifier.endSession();
                }
              },
              icon: const Icon(Icons.close),
              label: const Text('End Session'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                foregroundColor: Colors.white,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  String _formatTimeRemaining(DateTime expiresAt) {
    final remaining = expiresAt.difference(DateTime.now());
    if (remaining.isNegative) {
      return 'Expired';
    }
    final hours = remaining.inHours;
    final minutes = remaining.inMinutes % 60;
    return '${hours}h ${minutes}m';
  }
}

