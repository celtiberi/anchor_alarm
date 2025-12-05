import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/pairing/pairing_providers.dart';
import '../../models/pairing_session.dart';
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

  @override
  Widget build(BuildContext context) {
    final sessionAsync = ref.watch(pairingSessionProvider);
    final pairingNotifier = ref.read(pairingSessionProvider.notifier);
    final sessionNotifier = ref.read(pairingSessionStateProvider.notifier);

    return sessionAsync == null
        ? _buildCreateSessionView(pairingNotifier, sessionNotifier)
        : _buildSessionView(sessionAsync, pairingNotifier, sessionNotifier);
  }

  Widget _buildCreateSessionView(
    PairingSessionNotifier pairingNotifier,
    PairingSessionStateNotifier sessionNotifier,
  ) {
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
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.devices, size: 64, color: Colors.blue),
              const SizedBox(height: 24),
              const Text(
                'Share Monitoring',
                style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold),
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
      ),
    );
  }

  Widget _buildSessionView(
    PairingSession session,
    PairingSessionNotifier pairingNotifier,
    PairingSessionStateNotifier sessionNotifier,
  ) {
    return Scaffold(
      appBar: AppBar(title: const Text('Device Pairing')),
      body: Center(child: Text('Session: ${session.token}')),
    );
  }
}
