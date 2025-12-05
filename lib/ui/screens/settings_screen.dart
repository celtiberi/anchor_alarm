import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/settings_provider.dart';
import '../../providers/pairing/pairing_providers.dart';
import '../../providers/secondary_session_monitor_provider.dart';
import '../../providers/secondary_auto_disconnect_provider.dart';
import '../../providers/anchor_provider.dart';
import '../../providers/service_providers.dart';
import '../../models/device_info.dart';
import '../../models/app_settings.dart';
import '../../utils/distance_formatter.dart';
import '../../utils/logger_setup.dart';
import 'pairing_scan_screen.dart';

/// Settings screen for app configuration.
class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);
    final pairingState = ref.watch(
      pairingSessionStateProvider,
    ); // Device pairing/session state
    final sessionNotifier = ref.read(
      pairingSessionStateProvider.notifier,
    ); // For device roles/sessions
    final pairingDataNotifier = ref.read(
      pairingSessionProvider.notifier,
    ); // For pairing session data

    logger.i(
      '🔄 SettingsScreen build() called - pairingState: role=${pairingState.role}, localSessionToken=${pairingState.localSessionToken}, remoteSessionToken=${pairingState.remoteSessionToken}, sessionToken=${pairingState.sessionToken}',
    );
    logger.i(
      '🔄 SettingsScreen build() - state hash: ${pairingState.hashCode}',
    );
    logger.i(
      '🔄 SettingsScreen build() - should QR code show? sessionToken != null: ${pairingState.sessionToken != null}',
    );
    logger.i(
      '📊 State object details: hash=${pairingState.hashCode}, runtimeType=${pairingState.runtimeType}',
    );

    // Add a listener to track state changes
    ref.listen<PairingSessionState>(pairingSessionStateProvider, (
      previous,
      next,
    ) {
      logger.i('🎧 SettingsScreen listener: STATE CHANGED!');
      logger.i(
        '🎧 Previous: role=${previous?.role}, localSessionToken=${previous?.localSessionToken}, remoteSessionToken=${previous?.remoteSessionToken}, sessionToken=${previous?.sessionToken}',
      );
      logger.i(
        '🎧 Next: role=${next.role}, localSessionToken=${next.localSessionToken}, remoteSessionToken=${next.remoteSessionToken}, sessionToken=${next.sessionToken}',
      );
      logger.i('🎧 Are they equal? ${previous == next}');
      logger.i(
        '🎧 Hash codes: prev=${previous?.hashCode}, next=${next.hashCode}',
      );
      logger.i('🎧 SettingsScreen should rebuild now!');
    });

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          // Pairing QR Code Section (only for primary devices)
          if (!pairingState.isSecondary) ...[
            _buildPairingQRCodeSection(
              context,
              ref,
              pairingState,
              pairingDataNotifier,
              sessionNotifier,
            ),
          ],
          // Check if secondary device's session is still active
          if (pairingState.isSecondary) ...[
            _buildSecondarySessionStatusSection(
              context,
              ref,
              pairingState,
              sessionNotifier,
            ),
            const Divider(),
          ],
          // Pair with another device (always show for non-secondary devices)
          if (!pairingState.isSecondary) ...[
            _buildPairWithDeviceSection(
              context,
              pairingState,
              pairingDataNotifier,
              sessionNotifier,
            ),
            const Divider(),
          ],
          // Unit System
          ListTile(
            title: const Text('Unit System'),
            subtitle: Text(
              settings.unitSystem == UnitSystem.metric
                  ? 'Metric (meters, kilometers)'
                  : 'Imperial (feet, miles)',
            ),
            trailing: Switch(
              value: settings.unitSystem == UnitSystem.metric,
              onChanged: (value) {
                notifier.setUnitSystem(
                  value ? UnitSystem.metric : UnitSystem.imperial,
                );
              },
            ),
          ),
          const Divider(),
          // Debug: Current Anchor State
          Consumer(
            builder: (context, ref, child) {
              final anchor = ref.watch(anchorProvider);
              final pairingState = ref.watch(pairingSessionStateProvider);
              return ListTile(
                title: const Text('Debug: Anchor State'),
                subtitle: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Anchor: ${anchor != null ? 'Set (${anchor.latitude.toStringAsFixed(4)}, ${anchor.longitude.toStringAsFixed(4)})' : 'Not set'}',
                    ),
                    Text('Role: ${pairingState.role}'),
                    Text(
                      'Session Token: ${pairingState.sessionToken ?? 'None'}',
                    ),
                  ],
                ),
                trailing: ElevatedButton(
                  onPressed: () async {
                    // Manual anchor sync test
                    final sessionToken = pairingState.sessionToken;
                    if (sessionToken != null && anchor != null) {
                      try {
                        final sessionSyncService = ref.read(
                          sessionSyncServiceProvider,
                        );
                        await sessionSyncService.updateSessionAnchor(
                          sessionToken,
                          anchor,
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Manual anchor sync attempted'),
                          ),
                        );
                      } catch (e) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('Manual anchor sync failed: $e'),
                          ),
                        );
                      }
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('No session token or anchor to sync'),
                        ),
                      );
                    }
                  },
                  child: const Text('Test Sync'),
                ),
              );
            },
          ),
          const Divider(),

          // Theme Mode
          ListTile(
            title: const Text('Theme'),
            subtitle: Text(_getThemeModeText(settings.themeMode)),
            trailing: PopupMenuButton<AppThemeMode>(
              onSelected: (mode) => notifier.setThemeMode(mode),
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: AppThemeMode.light,
                  child: Text('Light'),
                ),
                const PopupMenuItem(
                  value: AppThemeMode.dark,
                  child: Text('Dark'),
                ),
                const PopupMenuItem(
                  value: AppThemeMode.system,
                  child: Text('System'),
                ),
              ],
              child: const Icon(Icons.arrow_drop_down),
            ),
          ),
          const Divider(),

          // Default Radius
          ListTile(
            title: const Text('Default Anchor Radius'),
            subtitle: Slider(
              value: settings.defaultRadius,
              min: 1,
              max: 100,
              divisions: 99,
              label: formatDistanceInt(
                settings.defaultRadius,
                settings.unitSystem,
              ),
              onChanged: (value) {
                notifier.setDefaultRadius(value);
              },
            ),
            trailing: Text(
              formatDistanceInt(settings.defaultRadius, settings.unitSystem),
            ),
          ),
          const Divider(),

          // Alarm Sensitivity
          ListTile(
            title: const Text('Alarm Sensitivity'),
            subtitle: Text(
              'Higher sensitivity reduces false alarms from GPS noise',
            ),
            trailing: SizedBox(
              width: 100,
              child: Slider(
                value: settings.alarmSensitivity,
                min: 0,
                max: 1,
                divisions: 10,
                label: settings.alarmSensitivity.toStringAsFixed(1),
                onChanged: (value) {
                  notifier.setAlarmSensitivity(value);
                },
              ),
            ),
          ),
          const Divider(),

          // Sound
          ListTile(
            title: const Text('Sound Alerts'),
            subtitle: const Text('Play sound when alarm triggers'),
            trailing: Switch(
              value: settings.soundEnabled,
              onChanged: (_) => notifier.toggleSound(),
            ),
          ),
          const Divider(),

          // Vibration
          ListTile(
            title: const Text('Vibration Alerts'),
            subtitle: const Text('Vibrate when alarm triggers'),
            trailing: Switch(
              value: settings.vibrationEnabled,
              onChanged: (_) => notifier.toggleVibration(),
            ),
          ),
          const Divider(),

          // Firebase Write Intervals
          ListTile(
            title: const Text('Position Update Interval'),
            subtitle: Text(
              'How often GPS position is sent to Firebase (${settings.positionUpdateInterval}s)',
            ),
            trailing: SizedBox(
              width: 120,
              child: Slider(
                value: settings.positionUpdateInterval.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '${settings.positionUpdateInterval}s',
                onChanged: (value) {
                  notifier.setPositionUpdateInterval(value.toInt());
                },
              ),
            ),
          ),
          const Divider(),

          ListTile(
            title: const Text('Position History Batch Interval'),
            subtitle: Text(
              'How often position history is batched to Firebase (${settings.positionHistoryBatchInterval}s)',
            ),
            trailing: SizedBox(
              width: 120,
              child: Slider(
                value: settings.positionHistoryBatchInterval.toDouble(),
                min: 1,
                max: 30,
                divisions: 29,
                label: '${settings.positionHistoryBatchInterval}s',
                onChanged: (value) {
                  notifier.setPositionHistoryBatchInterval(value.toInt());
                },
              ),
            ),
          ),
          const Divider(),
        ],
      ),
    );
  }

  String _getThemeModeText(AppThemeMode mode) {
    switch (mode) {
      case AppThemeMode.light:
        return 'Light';
      case AppThemeMode.dark:
        return 'Dark';
      case AppThemeMode.system:
        return 'System Default';
    }
  }

  Widget _buildPairingQRCodeSection(
    BuildContext context,
    WidgetRef ref,
    PairingSessionState pairingState,
    PairingSessionNotifier pairingNotifier,
    PairingSessionStateNotifier sessionNotifier,
  ) {
    logger.i(
      'Settings: Building QR section - pairingState: role=${pairingState.role}, localSessionToken=${pairingState.localSessionToken}, remoteSessionToken=${pairingState.remoteSessionToken}',
    );
    logger.i(
      'Settings: QR section - sessionToken: ${pairingState.sessionToken}',
    );
    logger.i(
      'Settings: QR section - deepLink will be: ${pairingState.sessionToken != null ? 'anchorapp://join?sessionId=${pairingState.sessionToken}&token=${pairingState.sessionToken}' : 'null'}',
    );

    // Get session token - force a call to the getter to trigger logging
    final sessionTokenFromGetter = pairingState.sessionToken;
    logger.i('Settings: sessionToken from getter: $sessionTokenFromGetter');

    // Get session token
    String? sessionToken = pairingState.sessionToken;
    String? deepLink;

    // Get paired devices info if we have an active session
    List<DeviceInfo> secondaryDevices = [];
    if (sessionToken != null && pairingState.isPrimary) {
      final pairingSessionAsync = ref.watch(pairingSessionStreamProvider);
      final pairingSession = pairingSessionAsync.value;
      if (pairingSession != null && pairingSession.isActive) {
        secondaryDevices = pairingSession.devices
            .where((d) => d.role == DeviceRole.secondary)
            .toList();
      }
    }

    if (sessionToken != null) {
      deepLink = 'anchorapp://join?sessionId=$sessionToken&token=$sessionToken';
      logger.i('Settings: Generated deep link for session: $sessionToken');
      logger.i('Settings: QR code data: $deepLink');
      logger.i('Settings: Session token length: ${sessionToken.length}');
    } else {
      logger.i('Settings: No session token available, showing create button');
    }

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Share Pairing',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (deepLink != null) ...[
              const Text(
                'Scan this QR code with another device to pair for anchor monitoring. The other device will automatically connect and show your boat\'s position, anchor location, and any alarms.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade300),
                ),
                child: Center(
                  child: QrImageView(
                    data: deepLink,
                    version: QrVersions.auto,
                    size: 200,
                    backgroundColor: Colors.white,
                  ),
                ),
              ),
              const SizedBox(height: 16),
              // Show paired devices info if any exist
              if (secondaryDevices.isNotEmpty) ...[
                const Divider(),
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Icon(Icons.devices, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      '${secondaryDevices.length} device${secondaryDevices.length == 1 ? '' : 's'} paired',
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                ...secondaryDevices.map(
                  (device) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 4),
                    child: Row(
                      children: [
                        Icon(
                          Icons.phone_android,
                          size: 16,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            'Device ${device.deviceId.substring(0, 8)}...',
                            style: const TextStyle(fontSize: 14),
                          ),
                        ),
                        Text(
                          'Joined ${_formatTime(device.joinedAt)}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Theme.of(
                              context,
                            ).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                OutlinedButton.icon(
                  onPressed: () async {
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (context) => AlertDialog(
                        title: const Text('Disable Pairing'),
                        content: const Text(
                          'This will end the pairing session, disconnect all paired devices, and invalidate the current QR code. A new QR code will need to be generated to pair devices again. Are you sure?',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context, false),
                            child: const Text('Cancel'),
                          ),
                          TextButton(
                            onPressed: () => Navigator.pop(context, true),
                            style: TextButton.styleFrom(
                              foregroundColor: Colors.red,
                            ),
                            child: const Text('Disable Pairing'),
                          ),
                        ],
                      ),
                    );

                    if (confirmed == true && context.mounted) {
                      try {
                        await sessionNotifier.endSession();
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text(
                                'Pairing disabled. All devices disconnected.',
                              ),
                              backgroundColor: Colors.green,
                            ),
                          );
                        }
                      } catch (e) {
                        if (context.mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to disable pairing: $e'),
                              backgroundColor: Colors.red,
                            ),
                          );
                        }
                      }
                    }
                  },
                  icon: const Icon(Icons.link_off),
                  label: const Text('Disable Pairing'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ],
              SizedBox(height: secondaryDevices.isNotEmpty ? 12 : 16),
              OutlinedButton.icon(
                onPressed: () async {
                  try {
                    // Clear the current session
                    await sessionNotifier.disconnect();
                    setState(() {}); // Refresh UI
                  } catch (e) {
                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to clear session: $e'),
                          backgroundColor: Theme.of(context).colorScheme.error,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.refresh),
                label: const Text('Generate New Session'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ] else ...[
              const Text(
                'Create a pairing session to allow other devices to monitor your anchor alarm. The QR code will appear here once created.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              ElevatedButton.icon(
                onPressed: () async {
                  try {
                    logger.i(
                      '🚀 Settings: Create Pairing Session button pressed',
                    );
                    logger.i(
                      '📊 Pre-session creation state: pairingState.sessionToken=${pairingState.sessionToken}',
                    );

                    final token = await sessionNotifier.startPrimarySession();

                    logger.i(
                      '✅ Settings: Session creation method returned token: $token',
                    );
                    logger.i(
                      '🔄 Settings: State should have updated automatically via Riverpod',
                    );
                    logger.i('🎯 Settings: Session creation flow complete');
                  } catch (e) {
                    logger.e('❌ Settings: Failed to create session', error: e);

                    String errorMessage;
                    if (e.toString().contains('quota exceeded') ||
                        e.toString().contains('Quota exceeded')) {
                      errorMessage =
                          'Firebase quota exceeded. Please check your Firebase Console billing/usage or wait for quota reset.';
                    } else {
                      errorMessage = 'Failed to create session: $e';
                    }

                    if (mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text(errorMessage),
                          backgroundColor: Theme.of(context).colorScheme.error,
                          duration: const Duration(
                            seconds: 8,
                          ), // Longer duration for quota messages
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.qr_code),
                label: const Text('Create Pairing Session'),
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPairWithDeviceSection(
    BuildContext context,
    PairingSessionState pairingState,
    PairingSessionNotifier pairingNotifier,
    PairingSessionStateNotifier sessionNotifier,
  ) {
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.qr_code_scanner, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Pair with Another Device',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Scan the QR code from the primary device to monitor its anchor alarm in real-time. The QR code can be found in Settings on the primary device.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            ElevatedButton.icon(
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (context) => const PairingScanScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.camera_alt),
              label: const Text('Scan QR Code'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSecondarySessionStatusSection(
    BuildContext context,
    WidgetRef ref,
    PairingSessionState pairingState,
    PairingSessionStateNotifier sessionNotifier,
  ) {
    // Check session status for secondary devices
    final sessionAsync = ref.watch(secondarySessionMonitorProvider);
    final session = sessionAsync.value;

    // Auto-disconnect provider handles disconnection automatically
    // Just watch it to ensure it's active
    ref.watch(secondaryAutoDisconnectProvider);

    // If session is inactive or doesn't exist, show informational message
    // (auto-disconnect will handle clearing the state)
    if (session == null || !session.isActive) {
      return Card(
        margin: const EdgeInsets.all(16),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  const Icon(Icons.link_off, color: Colors.orange, size: 24),
                  const SizedBox(width: 8),
                  const Text(
                    'Pairing Disconnected',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'The pairing session has been ended by the primary device or no longer exists. Returning to primary mode...',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // Session is active - show status
    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.visibility, color: Colors.green, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Pairing Active',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'You are paired with the primary device. You can view the anchor position and receive alarm alerts, but cannot control the anchor.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            OutlinedButton.icon(
              onPressed: () async {
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: const Text('Disconnect from Session'),
                    content: const Text(
                      'This will disconnect you from the pairing session. You will no longer receive updates from the primary device.',
                    ),
                    actions: [
                      TextButton(
                        onPressed: () => Navigator.pop(context, false),
                        child: const Text('Cancel'),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context, true),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
                        child: const Text('Disconnect'),
                      ),
                    ],
                  ),
                );

                if (confirmed == true && context.mounted) {
                  try {
                    await sessionNotifier.disconnect();
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text('Disconnected from paired session.'),
                          backgroundColor: Colors.green,
                        ),
                      );
                    }
                  } catch (e) {
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to disconnect: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                }
              },
              icon: const Icon(Icons.link_off),
              label: const Text('Disconnect'),
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.red,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  String _formatTime(DateTime time) {
    final now = DateTime.now();
    final diff = now.difference(time);

    if (diff.inMinutes < 1) {
      return 'just now';
    } else if (diff.inHours < 1) {
      return '${diff.inMinutes}m ago';
    } else if (diff.inDays < 1) {
      return '${diff.inHours}h ago';
    } else {
      return '${diff.inDays}d ago';
    }
  }
}
