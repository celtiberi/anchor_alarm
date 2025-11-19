import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/app_settings.dart';
import '../repositories/local_storage_repository.dart';
import 'local_storage_provider.dart';

/// Provides app settings state.
final settingsProvider = NotifierProvider<SettingsNotifier, AppSettings>(() {
  return SettingsNotifier();
});

/// Notifier for settings state management.
class SettingsNotifier extends Notifier<AppSettings> {
  LocalStorageRepository get _repository => ref.read(localStorageRepositoryProvider);

  @override
  AppSettings build() {
    final settings = _repository.getSettings();
    return settings;
  }

  /// Updates settings.
  Future<void> updateSettings(AppSettings newSettings) async {
    await _repository.saveSettings(newSettings);
    state = newSettings;
  }

  /// Updates unit system.
  Future<void> setUnitSystem(UnitSystem unitSystem) async {
    final updated = state.copyWith(unitSystem: unitSystem);
    await updateSettings(updated);
  }

  /// Updates theme mode.
  Future<void> setThemeMode(AppThemeMode themeMode) async {
    final updated = state.copyWith(themeMode: themeMode);
    await updateSettings(updated);
  }

  /// Updates default radius.
  Future<void> setDefaultRadius(double radius) async {
    final updated = state.copyWith(defaultRadius: radius);
    await updateSettings(updated);
  }

  /// Updates alarm sensitivity.
  Future<void> setAlarmSensitivity(double sensitivity) async {
    final updated = state.copyWith(alarmSensitivity: sensitivity);
    await updateSettings(updated);
  }

  /// Toggles sound enabled.
  Future<void> toggleSound() async {
    final updated = state.copyWith(soundEnabled: !state.soundEnabled);
    await updateSettings(updated);
  }

  /// Toggles vibration enabled.
  Future<void> toggleVibration() async {
    final updated = state.copyWith(vibrationEnabled: !state.vibrationEnabled);
    await updateSettings(updated);
  }
}

