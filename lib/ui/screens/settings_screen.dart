import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../providers/settings_provider.dart';
import '../../providers/pairing_session_provider.dart';
import '../../providers/pairing_provider.dart';
import '../../providers/pairing_session_stream_provider.dart';
import '../../providers/secondary_session_monitor_provider.dart';
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
    final pairingState = ref.watch(pairingSessionStateProvider); // Device pairing/session state
    final sessionNotifier = ref.read(pairingSessionStateProvider.notifier); // For device roles/sessions
    final pairingDataNotifier = ref.read(pairingSessionProvider.notifier); // For pairing session data

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
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
            const Divider(),
            // Pairing status section (show connected devices and disable button)
            _buildPairingStatusSection(context, ref, pairingState, sessionNotifier),
            const Divider(),
          ],
          // Check if secondary device's session is still active
          if (pairingState.isSecondary) ...[
            _buildSecondarySessionStatusSection(context, ref, pairingState, sessionNotifier),
            const Divider(),
          ],
          // Pair with another device (always show for non-secondary devices)
          if (!pairingState.isSecondary) ...[
            _buildPairWithDeviceSection(context, pairingState, pairingDataNotifier, sessionNotifier),
            const Divider(),
          ],
          // Unit System
          ListTile(
            title: const Text('Unit System'),
            subtitle: Text(settings.unitSystem == UnitSystem.metric
                ? 'Metric (meters, kilometers)'
                : 'Imperial (feet, miles)'),
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
              label: formatDistanceInt(settings.defaultRadius, settings.unitSystem),
              onChanged: (value) {
                notifier.setDefaultRadius(value);
              },
            ),
            trailing: Text(formatDistanceInt(settings.defaultRadius, settings.unitSystem)),
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
    // Get or create session token
    String? sessionToken = pairingState.sessionToken;
    String? deepLink;

    if (sessionToken != null) {
      deepLink = 'anchorapp://join?sessionId=$sessionToken&token=$sessionToken';
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            const Text(
              'Scan this QR code with another device to pair for anchor monitoring. The other device will automatically connect and show your boat\'s position, anchor location, and any alarms.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
            const SizedBox(height: 16),
            if (deepLink != null) ...[
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
            ] else ...[
              // Session is being auto-created, show loading indicator
              const Padding(
                padding: EdgeInsets.all(16),
                child: Center(
                  child: Column(
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 12),
                      Text(
                        'Creating new pairing session...',
                        style: TextStyle(fontSize: 14, color: Colors.grey),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPairWithDeviceSection(BuildContext context, PairingSessionState pairingState, PairingSessionNotifier pairingNotifier, PairingSessionStateNotifier sessionNotifier) {
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
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
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

  Widget _buildPairingStatusSection(
    BuildContext context,
    WidgetRef ref,
    PairingSessionState pairingState,
    PairingSessionStateNotifier sessionNotifier,
  ) {
    // Only show for primary devices
    if (!pairingState.isPrimary) {
      return const SizedBox.shrink();
    }

    // Use stream provider for real-time updates
    final pairingSessionAsync = ref.watch(pairingSessionStreamProvider);
    final pairingSession = pairingSessionAsync.value;

    // Hide if no session or session is inactive
    if (pairingSession == null || !pairingSession.isActive) {
      return const SizedBox.shrink();
    }

    final secondaryDevices = pairingSession.devices
        .where((d) => d.role == DeviceRole.secondary)
        .toList();

    return Card(
      margin: const EdgeInsets.all(16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.devices, size: 24),
                const SizedBox(width: 8),
                const Text(
                  'Paired Devices',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (secondaryDevices.isEmpty) ...[
              const Text(
                'Pairing is disabled. Create a new pairing session above to generate a QR code for other devices.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
            ] else ...[
              Text(
                '${secondaryDevices.length} device${secondaryDevices.length == 1 ? '' : 's'} paired in this session:',
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              ...secondaryDevices.map((device) => Padding(
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
                            color: Theme.of(context).colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  )),
            ],
            // Only show disable button when there are actually devices to disconnect
            if (secondaryDevices.isNotEmpty) ...[
              const SizedBox(height: 16),
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
                          child: const Text('Disable Pairing'),
                          style: TextButton.styleFrom(
                            foregroundColor: Colors.red,
                          ),
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
                            content: Text('Pairing disabled. All devices disconnected.'),
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

    // If session is inactive or doesn't exist, show disconnect option
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text(
                'The pairing session has been ended by the primary device. You are no longer monitoring the anchor alarm.',
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              const SizedBox(height: 16),
              OutlinedButton.icon(
                onPressed: () async {
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
                },
                icon: const Icon(Icons.close),
                label: const Text('Close'),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
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
                    style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
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
                        child: const Text('Disconnect'),
                        style: TextButton.styleFrom(
                          foregroundColor: Colors.red,
                        ),
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

