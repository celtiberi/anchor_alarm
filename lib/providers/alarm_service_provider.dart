import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/alarm_service.dart';
import 'settings_provider.dart';

/// Provides alarm service instance.
final alarmServiceProvider = Provider<AlarmService>((ref) {
  final settings = ref.watch(settingsProvider);
  return AlarmService(settings: settings);
});

