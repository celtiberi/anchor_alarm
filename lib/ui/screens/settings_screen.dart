import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/settings_provider.dart';
import '../../models/app_settings.dart';

/// Settings screen for app configuration.
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider);
    final notifier = ref.read(settingsProvider.notifier);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
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
              min: 20,
              max: 100,
              divisions: 16,
              label: '${settings.defaultRadius.toStringAsFixed(0)} m',
              onChanged: (value) {
                notifier.setDefaultRadius(value);
              },
            ),
            trailing: Text('${settings.defaultRadius.toStringAsFixed(0)} m'),
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
}

