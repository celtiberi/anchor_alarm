import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm_event.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import 'alarm_service_provider.dart';
import 'anchor_provider.dart';
import 'position_provider.dart';
import 'notification_service_provider.dart';
import 'settings_provider.dart';

/// Provides active alarms state.
final activeAlarmsProvider = NotifierProvider<AlarmNotifier, List<AlarmEvent>>(() {
  return AlarmNotifier();
});

/// Notifier for alarm state management.
class AlarmNotifier extends Notifier<List<AlarmEvent>> {
  AlarmService get _alarmService => ref.read(alarmServiceProvider);
  NotificationService get _notificationService => ref.read(notificationServiceProvider);
  Timer? _checkTimer;
  bool _isMonitoring = false;

  @override
  List<AlarmEvent> build() {
    // Don't auto-start monitoring - user must explicitly start it
    return [];
  }

  /// Starts monitoring for alarm conditions.
  void startMonitoring() {
    if (_isMonitoring) {
      return; // Already monitoring
    }
    _isMonitoring = true;
    _checkTimer?.cancel();
    _checkTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      _checkAlarmConditions();
    });
  }

  /// Stops monitoring for alarm conditions.
  void stopMonitoring() {
    _isMonitoring = false;
    _checkTimer?.cancel();
    _checkTimer = null;
  }

  /// Returns whether monitoring is currently active.
  bool get isMonitoring => _isMonitoring;

  /// Checks if alarm conditions are met.
  void _checkAlarmConditions() async {
    final anchor = ref.read(anchorProvider);
    final position = ref.read(positionProvider);
    
    if (anchor == null || !anchor.isActive) {
      return;
    }

    // Check drift alarm (requires position)
    if (position != null) {
      final distance = _alarmService.checkDrift(anchor, position);
      if (distance != null && _alarmService.shouldTriggerAlarm(anchor, distance)) {
        final alarm = _alarmService.createDriftAlarm(anchor, position, distance);
        _addAlarm(alarm);
      }
    }
  }

  /// Adds an alarm to the list if not already present and triggers notification.
  void _addAlarm(AlarmEvent alarm) {
    if (state.any((a) => a.id == alarm.id)) {
      return; // Already exists
    }
    state = [...state, alarm];
    
    // Trigger notification
    final settings = ref.read(settingsProvider);
    _notificationService.triggerAlarm(alarm, settings);
  }

  /// Acknowledges an alarm and stops monitoring.
  void acknowledgeAlarm(String alarmId) {
    state = state.map((alarm) {
      if (alarm.id == alarmId && !alarm.acknowledged) {
        return alarm.copyWith(
          acknowledged: true,
          acknowledgedAt: DateTime.now(),
        );
      }
      return alarm;
    }).toList();
    
    // Stop monitoring when alarm is dismissed
    stopMonitoring();
  }

  /// Clears all acknowledged alarms.
  void clearAcknowledgedAlarms() {
    state = state.where((alarm) => !alarm.acknowledged).toList();
  }

  /// Clears all alarms.
  void clearAllAlarms() {
    state = [];
  }

  void dispose() {
    _checkTimer?.cancel();
  }
}

