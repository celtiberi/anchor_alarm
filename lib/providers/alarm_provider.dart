import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm_event.dart';
import '../models/position_update.dart';
import '../services/alarm_service.dart';
import '../services/notification_service.dart';
import '../services/background_alarm_service.dart';
import '../utils/logger_setup.dart';
import '../utils/gps_filtering.dart';
import 'anchor_provider.dart';
import 'gps_provider.dart';
import 'service_providers.dart';
import 'settings_provider.dart';
import 'pairing/pairing_providers.dart';

/// Provides active alarms state.
final activeAlarmsProvider =
    NotifierProvider.autoDispose<AlarmNotifier, List<AlarmEvent>>(() {
      return AlarmNotifier();
    });

/// Provides the monitoring state reactively.
/// This is derived from the alarm provider's internal monitoring state.
final alarmMonitoringStateProvider = Provider.autoDispose<bool>((ref) {
  return ref.read(activeAlarmsProvider.notifier).isMonitoring;
});

/// Notifier for alarm state management.
class AlarmNotifier extends Notifier<List<AlarmEvent>> {
  late final NotificationService _notificationService;
  late final BackgroundAlarmService _backgroundService;

  AlarmService get _alarmService {
    final settings = ref.read(settingsProvider);
    return AlarmService(settings: settings);
  }

  Timer? _checkTimer;
  bool _isMonitoring = false;
  bool _isPaused = false;
  DateTime?
  _lastPositionTime; // Track last position update time for GPS lost detection
  DateTime?
  _gpsLostWarningTime; // Track when GPS lost warning was first triggered
  DateTime? _gpsRestoredTime; // Track when GPS was last restored

  // Cached settings for performance - automatically updated when AppSettings change
  // Values from AppSettings: gpsLostThreshold, gpsCheckInterval, gpsHysteresisDelay, alarmAutoDismissThreshold
  Duration _gpsLostThreshold = const Duration(seconds: 30);
  Duration _gpsCheckInterval = const Duration(
    seconds: 15,
  ); // Check for GPS lost every 15 seconds
  Duration _gpsHysteresisDelay = const Duration(
    seconds: 5,
  ); // Hysteresis to prevent rapid on/off warnings
  Duration _alarmAutoDismissThreshold = const Duration(
    seconds: 120,
  ); // Auto-dismiss recent alarms within 2 minutes

  // Cached filtered results for performance
  List<AlarmEvent>? _cachedDriftAlarms;
  List<AlarmEvent>? _cachedGpsLostWarnings;
  List<AlarmEvent>? _lastState; // Track state changes

  List<AlarmEvent> get _driftAlarms {
    if (_lastState != state) {
      _invalidateCaches();
    }
    return _cachedDriftAlarms ??= state
        .where((a) => a.type == AlarmType.driftExceeded)
        .toList();
  }

  List<AlarmEvent> get _gpsLostWarnings {
    if (_lastState != state) {
      _invalidateCaches();
    }
    return _cachedGpsLostWarnings ??= state
        .where((a) => a.type == AlarmType.gpsLost)
        .toList();
  }


  void _invalidateCaches() {
    _lastState = List.from(state);
    _cachedDriftAlarms = null;
    _cachedGpsLostWarnings = null;
  }

  @override
  List<AlarmEvent> build() {
    // Initialize services
    _notificationService = ref.read(notificationServiceProvider);
    _backgroundService = BackgroundAlarmService();

    // Set initial settings on background service
    final initialSettings = ref.read(settingsProvider);
    _backgroundService.updateSettings(initialSettings);

    // Set up GPS monitoring coordination
    final gpsNotifier = ref.read(gpsProvider.notifier);
    gpsNotifier.onMonitoringStateChanged = (bool isForegroundActive) {
      if (isForegroundActive) {
        // Foreground GPS started - stop background GPS if it's running and we have an anchor
        logger.i('🛰️ Foreground GPS started - stopping background GPS to prevent conflicts');
        if (_isMonitoring && !_isPaused) {
          _backgroundService.stopMonitoring();
        }
      } else {
        // Foreground GPS stopped - restart background GPS if we should be monitoring
        logger.i('🛰️ Foreground GPS stopped - restarting background GPS if monitoring active');
        if (_isMonitoring && !_isPaused) {
          final anchor = ref.read(anchorProvider);
          if (anchor != null) {
            _backgroundService.startMonitoring(anchor);
          }
        }
      }
    };

    // Listen to settings changes and update cached durations
    ref.listen(settingsProvider, (previous, newSettings) {
      logger.i('Settings updated, refreshing cached durations');
      _gpsLostThreshold = Duration(seconds: newSettings.gpsLostThreshold);
      _gpsCheckInterval = Duration(seconds: newSettings.gpsCheckInterval);
      _gpsHysteresisDelay = Duration(seconds: newSettings.gpsHysteresisDelay);
      _alarmAutoDismissThreshold = Duration(
        seconds: newSettings.alarmAutoDismissThreshold,
      );

      // Update background service settings
      _backgroundService.updateSettings(newSettings);

      // Restart timer if interval changed and monitoring is active
      if (_isMonitoring && _checkTimer != null) {
        logger.i('Restarting GPS check timer due to interval change');
        _checkTimer!.cancel();
        _checkTimer = Timer.periodic(_gpsCheckInterval, (_) {
          if (_isMonitoring && !_isPaused) {
            _checkGpsWarnings();
          }
        });
      }
    });

    // Set initial cached values from current settings
    final settings = ref.read(settingsProvider);
    _gpsLostThreshold = Duration(seconds: settings.gpsLostThreshold);
    _gpsCheckInterval = Duration(seconds: settings.gpsCheckInterval);
    _gpsHysteresisDelay = Duration(seconds: settings.gpsHysteresisDelay);
    _alarmAutoDismissThreshold = Duration(
      seconds: settings.alarmAutoDismissThreshold,
    );

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

    logger.i(
      'Starting alarm monitoring for anchor at ${anchor.latitude}, ${anchor.longitude}',
    );
    _isMonitoring = true;
    // Update reactive monitoring state

    try {
      // Initialize GPS status tracking
      final currentPosition = ref.read(positionProvider);
      if (currentPosition != null) {
        _lastPositionTime = currentPosition.timestamp;
      } else {
        // Don't set _lastPositionTime to now - let it remain null initially
        // This prevents immediate GPS lost warnings when GPS is still initializing
        _lastPositionTime = null;
      }

      // Start background service for alarms when app is minimized
      // But don't start if foreground GPS is already active (to prevent conflicts)
      final isForegroundGpsActive = ref.read(gpsProvider.notifier).isMonitoring;
      if (!isForegroundGpsActive) {
        logger.i('🛰️ Starting background GPS - no foreground GPS conflict');
      _backgroundService.startMonitoring(anchor);
      } else {
        logger.i('🛰️ Skipping background GPS start - foreground GPS already active');
      }

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
      rethrow;
    }
  }

  /// Async version of startMonitoring that properly awaits background service initialization.
  /// Use this when you need to ensure monitoring is fully started before continuing.
  Future<void> startMonitoringAsync() async {
    // Check if we have an anchor before starting monitoring
    final anchor = ref.read(anchorProvider);
    if (anchor == null || !anchor.isActive) {
      logger.w('Cannot start monitoring: no active anchor set');
      throw StateError('No active anchor set');
    }

    if (_isMonitoring) {
      logger.d('Monitoring already active, skipping start');
      return;
    }

    logger.i(
      'Starting alarm monitoring (async) for anchor at ${anchor.latitude}, ${anchor.longitude}',
    );

    // Reset GPS filters when starting monitoring to ensure clean state
    GpsFiltering.resetFilters();
    logger.d('🛰️ GPS filters reset for new monitoring session');

    _isMonitoring = true;

    try {
      // Initialize GPS status tracking
      final currentPosition = ref.read(positionProvider);
      if (currentPosition != null) {
        _lastPositionTime = currentPosition.timestamp;
      } else {
        _lastPositionTime = null;
      }

      // Start background service for alarms when app is minimized
      // Always await the background service start to ensure it's fully initialized
      final isForegroundGpsActive = ref.read(gpsProvider.notifier).isMonitoring;
      if (!isForegroundGpsActive) {
        logger.i('🛰️ Starting background GPS - no foreground GPS conflict');
        await _backgroundService.startMonitoring(anchor);
      } else {
        logger.i('🛰️ Skipping background GPS start - foreground GPS already active');
      }

      // Check GPS status and alarm conditions immediately when starting monitoring
      _checkGpsWarnings();
      _checkAlarmConditions();

      // Periodic check for GPS lost detection (position updates handle alarm checking)
      _checkTimer?.cancel();
      _checkTimer = Timer.periodic(_gpsCheckInterval, (_) {
        if (_isMonitoring && !_isPaused) {
          _checkGpsWarnings();
        }
      });

      logger.i('Alarm monitoring started successfully (async)');
    } catch (e, stackTrace) {
      logger.e('Failed to start monitoring (async)', error: e, stackTrace: stackTrace);
      _isMonitoring = false;
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

    // Batch all provider reads at the start for consistency and performance
    final position = ref.read(positionProvider);
    final anchor = ref.read(anchorProvider);
    final now = DateTime.now();

    // Check for GPS lost warning with hysteresis (no position update in last threshold period)
    final gpsLost =
        _lastPositionTime == null ||
        now.difference(_lastPositionTime!) > _gpsLostThreshold;

    if (gpsLost) {
      // GPS is lost - create warning if we haven't recently warned or if enough time has passed
      final shouldWarn =
          _gpsLostWarningTime == null ||
          now.difference(_gpsLostWarningTime!) > _gpsHysteresisDelay;

      if (shouldWarn && _gpsLostWarnings.isEmpty) {
        // Use last known position for GPS lost warning (more reliable than current potentially null position)
        final lastKnownPosition = position ?? _getLastKnownPosition();
        final warning = _alarmService.createGpsLostWarning(
          lastKnownPosition,
          anchor,
        );
        _addWarning(warning);
        _gpsLostWarningTime = now;
        _gpsRestoredTime = null; // Reset restored time
      }
    } else {
      // GPS is active - clear warnings with hysteresis to prevent flickering
      final shouldClear =
          _gpsRestoredTime == null ||
          now.difference(_gpsRestoredTime!) > _gpsHysteresisDelay;

      if (shouldClear && _gpsLostWarnings.isNotEmpty) {
        for (final warning in _gpsLostWarnings) {
          _dismissWarning(warning.id);
        }
        _gpsRestoredTime = now;
        _gpsLostWarningTime = null; // Reset warning time
      }
    }

  }

  /// Checks if alarm conditions are met (drift exceeded).
  /// This method respects the pause state and won't check if paused.
  void _checkAlarmConditions() {
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
      // Use distance hysteresis (90% of radius) to prevent flapping at the edge
      const double hysteresisFactor = 0.9; // Dismiss when within 90% of radius
      final hysteresisRadius = anchor.radius * hysteresisFactor;

      if (distance != null && distance <= hysteresisRadius) {
        if (_driftAlarms.isNotEmpty) {
          // Auto-dismiss drift alarms that are recent (within configured threshold)
          // This prevents dismissing old alarms that might still be relevant
          final now = DateTime.now();

          for (final alarm in _driftAlarms) {
            if (now.difference(alarm.timestamp) <= _alarmAutoDismissThreshold) {
              logger.i(
                'Auto-dismissing drift alarm (distance ${distance.toStringAsFixed(1)}m < hysteresis radius ${hysteresisRadius.toStringAsFixed(1)}m)',
              );
              // Use autoDismissAlarm which syncs to Firebase and keeps monitoring active
              autoDismissAlarm(alarm.id);
            }
          }
        }
      }

      // Then check if alarm should trigger
      if (distance != null &&
          _alarmService.shouldTriggerAlarm(anchor, distance)) {
        // Only create a new alarm if one doesn't already exist
        if (_driftAlarms.isEmpty) {
          final alarm = _alarmService.createDriftAlarm(
            anchor,
            position,
            distance,
          );
          _addAlarm(alarm);
        }
        // If alarm already exists, update its distance and timestamp (but don't re-trigger notification)
        else {
          final existingIndex = state.indexWhere(
            (a) => a.id == _driftAlarms.first.id,
          );
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

    logger.i('Adding alarm: ${alarm.type} (${alarm.severity})');
    state = [...state, alarm];

    // Only trigger loud notifications for alarms (not warnings)
    if (alarm.severity == Severity.alarm) {
      final settings = ref.read(settingsProvider);
      _notificationService.triggerAlarm(alarm, settings);
    }
  }

  /// Adds a warning to the list, ensuring only one warning per type exists.
  /// Warnings don't trigger loud notifications, only silent notifications.
  void _addWarning(AlarmEvent warning) {
    // Check if a warning of this type already exists
    final existingIndex = state.indexWhere(
      (a) => a.type == warning.type && a.severity == Severity.warning,
    );
    if (existingIndex >= 0) {
      // Replace existing warning of same type with updated one
      logger.d('Updating existing ${warning.type} warning');
      final newState = List<AlarmEvent>.from(state);
      newState[existingIndex] = warning;
      state = newState;
      return;
    }

    logger.i('Adding warning: ${warning.type} (${warning.severity})');
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

    logger.i('🔔 Acknowledging alarm: $alarmId (severity: ${alarm.severity})');

    // Sync dismissal to Firebase first (for paired devices)
    final pairingState = ref.read(pairingSessionStateProvider);
    if (pairingState.isPrimary && pairingState.sessionToken != null) {
      try {
        final realtimeDb = ref.read(realtimeDatabaseRepositoryProvider);
        await realtimeDb.acknowledgeAlarm(pairingState.sessionToken!, alarmId);
        logger.i('✅ Synced alarm dismissal to Firebase: $alarmId for session ${pairingState.sessionToken}');
      } catch (e) {
        logger.e('❌ Failed to sync alarm dismissal to Firebase - NOT dismissing locally', error: e);
        // Don't dismiss locally if Firebase sync fails - this ensures secondary devices stay in sync
        return;
      }
    } else {
      logger.i('ℹ️ Not syncing to Firebase - not primary device or no session');
    }

    // Only stop monitoring for alarms (not warnings)
    _dismissAlarm(alarmId, stopMonitoring: alarm.severity == Severity.alarm);
  }

  /// Auto-dismisses an alarm (for automatic dismissal when returning to safe zone - keeps monitoring).
  Future<void> autoDismissAlarm(String alarmId) async {
    AlarmEvent? alarm;
    try {
      alarm = state.firstWhere((a) => a.id == alarmId);
    } catch (e) {
      logger.w('Attempted to auto-dismiss non-existent alarm: $alarmId');
      return; // Already dismissed or doesn't exist
    }

    logger.i('🔄 Auto-dismissing alarm: $alarmId (severity: ${alarm.severity})');

    // Sync dismissal to Firebase first (for paired devices)
    final pairingState = ref.read(pairingSessionStateProvider);
    if (pairingState.isPrimary && pairingState.sessionToken != null) {
      try {
        final realtimeDb = ref.read(realtimeDatabaseRepositoryProvider);
        await realtimeDb.acknowledgeAlarm(pairingState.sessionToken!, alarmId);
        logger.i('✅ Synced auto-dismissal to Firebase: $alarmId for session ${pairingState.sessionToken}');
      } catch (e) {
        logger.e('❌ Failed to sync auto-dismissal to Firebase - NOT dismissing locally', error: e);
        // Don't dismiss locally if Firebase sync fails - this ensures secondary devices stay in sync
        return;
      }
    } else {
      logger.i('ℹ️ Not syncing to Firebase - not primary device or no session');
    }

    // Auto-dismissal keeps monitoring active (don't stop monitoring)
    _dismissAlarm(alarmId, stopMonitoring: false);
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

  /// Clears all acknowledged alarms, keeping active alarms and warnings.
  void clearAcknowledgedAlarms() {
    state = state.where((alarm) => !alarm.acknowledged).toList();
    _updateNotificationServiceState();
  }

  /// Clears all alarms.
  void clearAllAlarms() {
    state = [];
    _updateNotificationServiceState();
  }

  /// Syncs background alarm events from local storage (called on app resume).
  /// This ensures alarms triggered in the background are reflected in the foreground UI.
  Future<void> syncBackgroundAlarmEvents() async {
    try {
      final backgroundEvents = ref
          .read(localStorageRepositoryProvider)
          .getBackgroundAlarmEvents();

      if (backgroundEvents.isNotEmpty) {
        logger.i(
          'Syncing ${backgroundEvents.length} background alarm events to foreground',
        );

        // Add background events to current state (avoiding duplicates)
        final currentIds = state.map((alarm) => alarm.id).toSet();
        final newEvents = backgroundEvents
            .where((alarm) => !currentIds.contains(alarm.id))
            .toList();

        if (newEvents.isNotEmpty) {
          state = [...state, ...newEvents];
          logger.i('Added ${newEvents.length} new background alarm events');
        }

        // Clear the background events since they've been synced
        await ref
            .read(localStorageRepositoryProvider)
            .clearBackgroundAlarmEvents();
      }
    } catch (e) {
      logger.e('Error syncing background alarm events', error: e);
    }
  }
}
