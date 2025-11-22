import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm_event.dart';
import '../models/position_update.dart';
import '../models/anchor.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import '../services/background_alarm_service.dart';
import '../utils/logger_setup.dart';
import 'alarm_service_provider.dart';
import 'anchor_provider.dart';
import 'position_provider.dart';
import 'notification_service_provider.dart';
import 'settings_provider.dart';
import 'firestore_provider.dart';
import 'pairing_session_provider.dart';

/// Provides active alarms state.
final activeAlarmsProvider = NotifierProvider<AlarmNotifier, List<AlarmEvent>>(() {
  return AlarmNotifier();
});

/// Provides the monitoring state reactively.
/// This allows the UI to react to changes in monitoring status.
final alarmMonitoringStateProvider = NotifierProvider<AlarmMonitoringStateNotifier, bool>(() {
  return AlarmMonitoringStateNotifier();
});

/// Notifier that tracks whether alarm monitoring is active.
class AlarmMonitoringStateNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Initialize to false by default - monitoring should only be active when explicitly started
    return false;
  }

  /// Updates the monitoring state.
  void setMonitoring(bool isMonitoring) {
    state = isMonitoring;
  }
}

/// Notifier for alarm state management.
class AlarmNotifier extends Notifier<List<AlarmEvent>> {
  AlarmService get _alarmService => ref.read(alarmServiceProvider);
  NotificationService get _notificationService => ref.read(notificationServiceProvider);
  final BackgroundAlarmService _backgroundService = BackgroundAlarmService();
  Timer? _checkTimer;
  bool _isMonitoring = false;
  bool _isPaused = false;
  DateTime? _lastPositionTime; // Track last position update time for GPS lost detection
  DateTime? _gpsLostWarningTime; // Track when GPS lost warning was first triggered
  DateTime? _gpsRestoredTime; // Track when GPS was last restored

  // Constants for timing and thresholds
  static const Duration _gpsLostThreshold = Duration(seconds: 30);
  static const Duration _gpsCheckInterval = Duration(seconds: 15); // Check for GPS lost every 15 seconds
  static const Duration _gpsHysteresisDelay = Duration(seconds: 5); // Hysteresis to prevent rapid on/off

  // Cached filtered results for performance
  List<AlarmEvent>? _cachedDriftAlarms;
  List<AlarmEvent>? _cachedGpsLostWarnings;
  List<AlarmEvent>? _cachedGpsInaccurateWarnings;
  List<AlarmEvent>? _lastState; // Track state changes

  List<AlarmEvent> get _driftAlarms {
    if (_lastState != state) {
      _invalidateCaches();
    }
    return _cachedDriftAlarms ??= state.where((a) => a.type == AlarmType.driftExceeded).toList();
  }

  List<AlarmEvent> get _gpsLostWarnings {
    if (_lastState != state) {
      _invalidateCaches();
    }
    return _cachedGpsLostWarnings ??= state.where((a) => a.type == AlarmType.gpsLost).toList();
  }

  List<AlarmEvent> get _gpsInaccurateWarnings {
    if (_lastState != state) {
      _invalidateCaches();
    }
    return _cachedGpsInaccurateWarnings ??= state.where((a) => a.type == AlarmType.gpsInaccurate).toList();
  }

  void _invalidateCaches() {
    _lastState = List.from(state);
    _cachedDriftAlarms = null;
    _cachedGpsLostWarnings = null;
    _cachedGpsInaccurateWarnings = null;
  }

  @override
  List<AlarmEvent> build() {
    // Set up cleanup when provider is disposed
    ref.onDispose(() {
      logger.i('Alarm provider disposing, cleaning up resources...');
      _checkTimer?.cancel();
      _checkTimer = null;
      // Stop notifications when provider is disposed
      _notificationService.stopAlarm();
      // Stop background service
      _backgroundService.dispose();
      // Stop monitoring if active
      if (_isMonitoring) {
        _isMonitoring = false;
        ref.read(alarmMonitoringStateProvider.notifier).setMonitoring(false);
        logger.i('Monitoring stopped during provider disposal');
      }
    });
    
    // Listen to position updates to check alarm conditions immediately
    ref.listen<PositionUpdate?>(positionProvider, (previous, next) {
      if (next != null) {
        // Update last position time for GPS lost detection
        _lastPositionTime = next.timestamp;
        
        if (_isMonitoring && !_isPaused) {
          // Check GPS warnings first
          _checkGpsWarnings();
          // Check alarm conditions immediately when position updates
          _checkAlarmConditions();
        }
      }
    });
    
    // Don't auto-start monitoring - user must explicitly start it
    return [];
  }
  
  /// Updates notification service based on current alarm state.
  void _updateNotificationServiceState() {
    // Since acknowledged alarms are immediately removed, any alarm in state is unacknowledged
    // If there are no alarms, stop notifications
    if (state.isEmpty) {
      _notificationService.stopAlarm();
    }
  }

  /// Starts monitoring for alarm conditions.
  /// Only works if there's an active anchor set.
  void startMonitoring() {
    // Check if we have an anchor before starting monitoring
    final anchor = ref.read(anchorProvider);
    if (anchor == null || !anchor.isActive) {
      logger.w('Cannot start monitoring: no active anchor set');
      return;
    }

    if (_isMonitoring) {
      logger.d('Monitoring already active, skipping start');
      return;
    }

    logger.i('Starting alarm monitoring for anchor at ${anchor.latitude}, ${anchor.longitude}');
    _isMonitoring = true;
    // Update reactive monitoring state
    ref.read(alarmMonitoringStateProvider.notifier).setMonitoring(true);

    try {
      // Initialize GPS status tracking
      final currentPosition = ref.read(positionProvider);
      if (currentPosition != null) {
        _lastPositionTime = currentPosition.timestamp;
      } else {
        _lastPositionTime = DateTime.now(); // GPS might be initializing
      }

      // Start background service for alarms when app is minimized
      _backgroundService.startMonitoring();

      // Check GPS status and alarm conditions immediately when starting monitoring
      _checkGpsWarnings();
      _checkAlarmConditions();

      // Periodic check for GPS lost detection (position updates handle alarm checking)
      _checkTimer?.cancel();
      _checkTimer = Timer.periodic(_gpsCheckInterval, (_) {
        if (_isMonitoring && !_isPaused) {
          // Only check GPS warnings - position updates handle immediate alarm checking
          _checkGpsWarnings();
        }
      });

      logger.i('Alarm monitoring started successfully');
    } catch (e, stackTrace) {
      logger.e('Failed to start monitoring', error: e, stackTrace: stackTrace);
      _isMonitoring = false;
      ref.read(alarmMonitoringStateProvider.notifier).setMonitoring(false);
      rethrow;
    }
  }

  /// Stops monitoring for alarm conditions.
  void stopMonitoring() {
    if (!_isMonitoring) {
      logger.d('Monitoring already stopped, skipping stop');
      return;
    }
    
    logger.i('Stopping alarm monitoring');
    _isMonitoring = false;
    _checkTimer?.cancel();
    _checkTimer = null;
    
    // Stop background service
    _backgroundService.stopMonitoring();
    // Update reactive monitoring state
    ref.read(alarmMonitoringStateProvider.notifier).setMonitoring(false);
    logger.i('Alarm monitoring stopped');
  }

  /// Returns whether monitoring is currently active.
  bool get isMonitoring => _isMonitoring;

  /// Temporarily pauses alarm checks without stopping monitoring.
  /// Useful when user is adjusting settings (e.g., radius).
  void pauseMonitoring() {
    _isPaused = true;
  }

  /// Resumes alarm checks if monitoring is active.
  /// Optionally checks alarm conditions immediately after resuming.
  void resumeMonitoring({bool checkImmediately = true}) {
    _isPaused = false;
    if (_isMonitoring && checkImmediately) {
      _checkAlarmConditions();
    }
  }

  /// Gets the last known position from the position provider.
  PositionUpdate? _getLastKnownPosition() {
    return ref.read(positionProvider);
  }

  /// Checks for GPS warnings (GPS lost or inaccurate).
  /// This method respects the pause state and won't check if paused.
  void _checkGpsWarnings() {
    if (_isPaused) {
      return; // Don't check warnings while paused
    }

    // Batch provider reads for better performance
    final position = ref.read(positionProvider);
    final settings = ref.read(settingsProvider);
    final now = DateTime.now();
    
    // Check for GPS lost warning with hysteresis (no position update in last threshold period)
    final gpsLost = _lastPositionTime == null || now.difference(_lastPositionTime!) > _gpsLostThreshold;

    if (gpsLost) {
      // GPS is lost - create warning if we haven't recently warned or if enough time has passed
      final shouldWarn = _gpsLostWarningTime == null ||
                        now.difference(_gpsLostWarningTime!) > _gpsHysteresisDelay;

      if (shouldWarn && _gpsLostWarnings.isEmpty) {
        // Use last known position for GPS lost warning (more reliable than current potentially null position)
        final lastKnownPosition = position ?? _getLastKnownPosition();
        final warning = _alarmService.createGpsLostWarning(lastKnownPosition);
        _addWarning(warning);
        _gpsLostWarningTime = now;
        _gpsRestoredTime = null; // Reset restored time
      }
    } else {
      // GPS is active - clear warnings with hysteresis to prevent flickering
      final shouldClear = _gpsRestoredTime == null ||
                         now.difference(_gpsRestoredTime!) > _gpsHysteresisDelay;

      if (shouldClear && _gpsLostWarnings.isNotEmpty) {
        for (final warning in _gpsLostWarnings) {
          _dismissWarning(warning.id);
        }
        _gpsRestoredTime = now;
        _gpsLostWarningTime = null; // Reset warning time
      }
    }
    
    // Check for GPS inaccurate warning (if position exists but accuracy is poor)
    if (position != null && position.accuracy != null) {
      if (position.accuracy! > settings.gpsAccuracyThreshold) {
        if (_gpsInaccurateWarnings.isEmpty) {
          final warning = _alarmService.createGpsInaccurateWarning(position);
          _addWarning(warning);
        } else {
          // Update all existing inaccurate warnings more efficiently
          final newState = List<AlarmEvent>.from(state);
          bool updatedAny = false;

          for (final warning in _gpsInaccurateWarnings) {
            final existingIndex = newState.indexWhere((a) => a.id == warning.id);
            if (existingIndex >= 0) {
              newState[existingIndex] = newState[existingIndex].copyWith(
                timestamp: position.timestamp,
                latitude: position.latitude,
                longitude: position.longitude,
              );
              updatedAny = true;
            }
          }

          if (updatedAny) {
            state = newState;
          }
        }
      } else {
        // GPS accuracy is good, remove inaccurate warnings
        for (final warning in _gpsInaccurateWarnings) {
          _dismissWarning(warning.id);
        }
      }
    }
  }

  /// Checks if alarm conditions are met (drift exceeded).
  /// This method respects the pause state and won't check if paused.
  void _checkAlarmConditions() async {
    if (_isPaused) {
      return; // Don't check alarms while paused
    }

    // Batch provider reads for better performance
    final anchor = ref.read(anchorProvider);
    final position = ref.read(positionProvider);
    
    if (anchor == null || !anchor.isActive) {
      return;
    }

    // Check drift alarm (requires position)
    if (position != null) {
      final distance = _alarmService.checkDrift(anchor, position);
      
      // First, check if boat is back in radius - auto-dismiss recent drift alarms
      if (distance != null && distance <= anchor.radius) {
        if (_driftAlarms.isNotEmpty) {
          // Auto-dismiss drift alarms that are recent (within last 2 minutes)
          // This prevents dismissing old alarms that might still be relevant
          final now = DateTime.now();
          final recentThreshold = Duration(minutes: 2);

          for (final alarm in _driftAlarms) {
            if (now.difference(alarm.timestamp) <= recentThreshold) {
              _dismissAlarm(alarm.id, stopMonitoring: false);
            }
          }
        }
      }
      
      // Then check if alarm should trigger
      if (distance != null && _alarmService.shouldTriggerAlarm(anchor, distance)) {
        // Only create a new alarm if one doesn't already exist
        if (_driftAlarms.isEmpty) {
          final alarm = _alarmService.createDriftAlarm(anchor, position, distance);
          _addAlarm(alarm);
        }
        // If alarm already exists, update its distance and timestamp (but don't re-trigger notification)
        else {
          final existingIndex = state.indexWhere((a) => a.id == _driftAlarms.first.id);
          if (existingIndex >= 0) {
            final updatedAlarm = state[existingIndex].copyWith(
              distanceFromAnchor: distance,
              timestamp: position.timestamp,
              latitude: position.latitude,
              longitude: position.longitude,
            );
            final newState = List<AlarmEvent>.from(state);
            newState[existingIndex] = updatedAlarm;
            state = newState;
          }
        }
      }
    }
  }

  /// Adds an alarm to the list if not already present and triggers notification.
  /// Only triggers loud notifications (sound/vibration) for alarms, not warnings.
  void _addAlarm(AlarmEvent alarm) {
    // Atomic check and update to prevent race conditions
    final existingIndex = state.indexWhere((a) => a.id == alarm.id);
    if (existingIndex >= 0) {
      return; // Already exists
    }
    state = [...state, alarm];

    // Only trigger loud notifications for alarms (not warnings)
    if (alarm.severity == Severity.alarm) {
      final settings = ref.read(settingsProvider);
      _notificationService.triggerAlarm(alarm, settings);
    }
  }

  /// Adds a warning to the list if not already present.
  /// Warnings don't trigger loud notifications, only silent notifications.
  void _addWarning(AlarmEvent warning) {
    // Atomic check and update to prevent race conditions
    final existingIndex = state.indexWhere((a) => a.id == warning.id);
    if (existingIndex >= 0) {
      return; // Already exists
    }
    state = [...state, warning];

    // Warnings don't trigger loud notifications - they're informational only
    // UI will show them as SnackBars instead of banners
  }

  /// Acknowledges an alarm (for manual dismiss - stops monitoring for alarms only).
  Future<void> acknowledgeAlarm(String alarmId) async {
    AlarmEvent? alarm;
    try {
      alarm = state.firstWhere((a) => a.id == alarmId);
    } catch (e) {
      logger.w('Attempted to acknowledge non-existent alarm: $alarmId');
      return; // Already dismissed or doesn't exist
    }

    // Sync dismissal to Firebase first (for paired devices)
    final pairingState = ref.read(pairingSessionStateProvider);
    if (pairingState.isPrimary && pairingState.sessionToken != null) {
      try {
        final firestore = ref.read(firestoreRepositoryProvider);
        await firestore.acknowledgeAlarm(pairingState.sessionToken!, alarmId);
        logger.i('Synced alarm dismissal to Firebase: $alarmId');
      } catch (e) {
        logger.e('Failed to sync alarm dismissal to Firebase', error: e);
        // Continue with local dismissal even if Firebase sync fails
      }
    }

    // Only stop monitoring for alarms (not warnings)
    _dismissAlarm(alarmId, stopMonitoring: alarm.severity == Severity.alarm);
  }
  
  /// Internal method to dismiss an alarm.
  /// Removes the alarm from state immediately - no need to keep acknowledged alarms.
  /// For warnings, monitoring continues. For alarms, monitoring stops if requested.
  void _dismissAlarm(String alarmId, {required bool stopMonitoring}) {
    // Remove the alarm from state immediately
    state = state.where((alarm) => alarm.id != alarmId).toList();
    
    // Update notification service - stop if no alarms remain
    _updateNotificationServiceState();
    
    // Only stop monitoring if explicitly requested (manual dismiss of alarm)
    if (stopMonitoring) {
      this.stopMonitoring();
    }
  }
  
  /// Dismisses a warning (doesn't stop monitoring).
  void _dismissWarning(String warningId) {
    // Remove warning from state immediately
    state = state.where((alarm) => alarm.id != warningId).toList();
    // No need to update notification service - warnings don't trigger loud notifications

    // Note: UI is responsible for cleaning up _shownWarningIds when dismissing via SnackBar
  }

  /// Clears all acknowledged alarms.
  /// Note: Acknowledged alarms are now removed immediately, so this is mainly for cleanup.
  void clearAcknowledgedAlarms() {
    // Since acknowledged alarms are removed immediately, this just ensures state is clean
    state = [];
    _updateNotificationServiceState();
  }

  /// Clears all alarms.
  void clearAllAlarms() {
    state = [];
    _updateNotificationServiceState();
  }

}

