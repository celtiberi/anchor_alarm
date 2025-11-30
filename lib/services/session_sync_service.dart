import 'dart:async';
import '../models/anchor.dart';
import '../models/position_update.dart';
import '../models/alarm_event.dart';
import '../models/app_settings.dart';
import '../repositories/realtime_database_repository.dart';
import '../utils/logger_setup.dart';

/// Service for syncing session data (anchor, position, alarms) from primary device to Firebase.
/// Secondary devices consume this data via Firebase streams for real-time monitoring.
class SessionSyncService {
  final RealtimeDatabaseRepository _realtimeDb;
  AppSettings _settings;
  StreamSubscription<PositionUpdate?>? _positionSubscription;
  StreamSubscription<Anchor?>? _anchorSubscription;
  StreamSubscription<List<AlarmEvent>>? _alarmsSubscription;
  Timer? _positionThrottleTimer;
  PositionUpdate? _pendingPosition;
  String? _currentSessionToken;

  SessionSyncService({
    RealtimeDatabaseRepository? realtimeDb,
    required AppSettings settings,
  }) : _realtimeDb = realtimeDb ?? RealtimeDatabaseRepository(),
       _settings = settings;

  /// Starts monitoring and syncing data to Firebase for a session.
  /// Only call this on the primary device.
  Future<void> startMonitoring({
    required String sessionToken,
    required Stream<Anchor?> anchorStream,
    required Stream<PositionUpdate?> positionStream,
    required Stream<List<AlarmEvent>> alarmsStream,
    Anchor? currentAnchor,
    PositionUpdate? currentPosition,
    List<AlarmEvent> currentAlarms = const [],
    bool forceRestart = false,
  }) async {
    if (_currentSessionToken == sessionToken && !forceRestart) {
      logger.w('Monitoring already active for session: $_currentSessionToken');
      return;
    }

    if (_currentSessionToken != null && forceRestart) {
      logger.i('Force restarting monitoring for session: $sessionToken');
      await stopMonitoringAsync();
    }

    _currentSessionToken = sessionToken;
    logger.i('Starting monitoring service for session: $sessionToken');

    // Mark monitoring as active in Firebase
    logger.i(
      '📡 Setting monitoringActive=true in Firebase for session: $sessionToken',
    );
    await _realtimeDb.updateSessionData(sessionToken, {
      'monitoringActive': true,
    });
    logger.i(
      '✅ Successfully set monitoringActive=true in Firebase for session: $sessionToken',
    );

    // Immediately sync current states that may have been set before monitoring started
    await _syncCurrentStates(
      sessionToken,
      currentAnchor,
      currentPosition,
      currentAlarms,
    );

    // Subscribe to anchor changes
    _anchorSubscription = anchorStream.listen(
      (anchor) async {
        logger.i('🎣 Anchor stream received: anchor = $anchor');
        if (anchor == null) {
          logger.i('🎣 Anchor stream: Setting anchor to null in Firebase');
          await updateSessionAnchor(sessionToken, null);
        } else {
          logger.i(
            '🎣 Anchor stream: Setting anchor in Firebase - lat=${anchor.latitude}, lon=${anchor.longitude}, radius=${anchor.radius}',
          );
          await updateSessionAnchor(sessionToken, anchor);
        }
      },
      onError: (error) {
        logger.e('❌ Error in anchor stream', error: error);
      },
    );

    // Listen to position updates
    _positionSubscription = positionStream.listen(
      (position) {
        if (position != null) {
          logger.i(
            '📍 Position stream received: lat=${position.latitude}, lon=${position.longitude}',
          );
          _pendingPosition = position;
          _schedulePositionUpdate(sessionToken);
        } else {
          logger.d('📍 Position stream received null - no position to send');
        }
      },
      onError: (error) {
        logger.e('Error in position stream', error: error);
      },
    );

    // Subscribe to alarms
    _alarmsSubscription = alarmsStream.listen(
      (alarms) async {
        // Find the active (unacknowledged) alarm—assuming only one
        AlarmEvent? activeAlarm;
        try {
          activeAlarm = alarms.firstWhere((alarm) => !alarm.acknowledged);
        } catch (e) {
          // No unacknowledged alarms found
          activeAlarm = null;
        }

        if (activeAlarm != null) {
          try {
            await _realtimeDb.createAlarm(sessionToken, activeAlarm);
            logger.d('✅ Synced active alarm ${activeAlarm.id} to Firebase');
          } catch (e) {
            logger.e(
              '❌ Failed to sync active alarm ${activeAlarm.id} to Firebase',
              error: e,
            );
          }
        } else {
          // Clear alarm in Firebase if none active
          await _realtimeDb.updateSessionData(sessionToken, {'alarm': null});
          logger.d('No active alarm—cleared in Firebase');
        }
      },
      onError: (error) {
        logger.e('Error in alarms stream', error: error);
      },
    );
  }

  /// Stops monitoring and syncing.
  void stopMonitoring({String? sessionToken}) {
    logger.i('🛑 Stopping monitoring service (sessionToken: $sessionToken)');

    // Use provided session token or fall back to current session token
    final tokenToUse = sessionToken ?? _currentSessionToken;

    // Mark monitoring as inactive in Firebase
    if (tokenToUse != null) {
      logger.i(
        '📡 Setting monitoringActive=false in Firebase for session: $tokenToUse',
      );
      _realtimeDb
          .updateSessionData(tokenToUse, {'monitoringActive': false})
          .then((_) {
            logger.i(
              '✅ Successfully set monitoringActive=false in Firebase for session: $tokenToUse',
            );
          })
          .catchError((error) {
            logger.e(
              '❌ Failed to update monitoring status to inactive for session: $tokenToUse',
              error: error,
            );
          });
    } else {
      logger.w('⚠️ No session token available when stopping monitoring');
    }
    _anchorSubscription?.cancel();
    _anchorSubscription = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _alarmsSubscription?.cancel();
    _alarmsSubscription = null;
    _positionThrottleTimer?.cancel();
    _positionThrottleTimer = null;
    _pendingPosition = null;
    _currentSessionToken = null;
  }

  /// Asynchronous version of stopMonitoring that waits for Firebase operations to complete.
  Future<void> stopMonitoringAsync({String? sessionToken}) async {
    logger.i(
      '🛑 Stopping monitoring service asynchronously (sessionToken: $sessionToken)',
    );

    // Use provided session token or fall back to current session token
    final tokenToUse = sessionToken ?? _currentSessionToken;

    // Mark monitoring as inactive in Firebase and wait for completion
    if (tokenToUse != null) {
      logger.i(
        '📡 Setting monitoringActive=false in Firebase for session: $tokenToUse',
      );
      try {
        await _realtimeDb.updateSessionData(tokenToUse, {
          'monitoringActive': false,
        });
        logger.i(
          '✅ Successfully set monitoringActive=false in Firebase for session: $tokenToUse',
        );
      } catch (error) {
        logger.e(
          '❌ Failed to update monitoring status to inactive for session: $tokenToUse',
          error: error,
        );
        // Continue with cleanup even if Firebase update fails
      }
    } else {
      logger.w('⚠️ No session token available when stopping monitoring');
    }

    // Cancel subscriptions and clean up
    _anchorSubscription?.cancel();
    _anchorSubscription = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _alarmsSubscription?.cancel();
    _alarmsSubscription = null;
    _positionThrottleTimer?.cancel();
    _positionThrottleTimer = null;
    _pendingPosition = null;
    _currentSessionToken = null;
  }

  /// Updates settings at runtime (e.g., when user changes intervals).
  /// This allows dynamic adjustment of sync rates without restarting monitoring.
  void updateSettings(AppSettings newSettings) {
    logger.i('🔄 Updating SessionSyncService settings');

    // Update internal settings reference
    _settings = newSettings;

    logger.i(
      'Updated position interval to ${_settings.positionUpdateInterval}s',
    );

    // If monitoring is active, reschedule timers with new intervals
    if (_currentSessionToken != null) {
      logger.i('📅 Rescheduling timers with updated intervals');

      // Reschedule position throttle timer if it exists
      if (_positionThrottleTimer?.isActive == true) {
        _positionThrottleTimer?.cancel();
        if (_pendingPosition != null) {
          _schedulePositionUpdate(_currentSessionToken!);
        }
      }
    }
  }

  /// Immediately sync current states when monitoring starts.
  Future<void> _syncCurrentStates(
    String sessionToken,
    Anchor? currentAnchor,
    PositionUpdate? currentPosition,
    List<AlarmEvent> currentAlarms,
  ) async {
    logger.i('🔄 Syncing current states on monitoring start');

    // Sync current anchor if it exists
    if (currentAnchor != null) {
      logger.i(
        '🔄 Syncing existing anchor: lat=${currentAnchor.latitude}, lon=${currentAnchor.longitude}',
      );
      await updateSessionAnchor(sessionToken, currentAnchor);
    } else {
      logger.i('🔄 No current anchor to sync');
    }

    // Sync current position if it exists
    if (currentPosition != null) {
      logger.i(
        '🔄 Syncing existing position: lat=${currentPosition.latitude}, lon=${currentPosition.longitude}',
      );
      await _syncPositionUpdate(sessionToken, currentPosition);
    } else {
      logger.i('🔄 No current position to sync');
    }

    // Sync current active alarms
    final activeAlarms = currentAlarms
        .where((alarm) => !alarm.acknowledged)
        .toList();
    if (activeAlarms.isNotEmpty) {
      logger.i('🔄 Syncing ${activeAlarms.length} existing active alarms');
      for (final alarm in activeAlarms) {
        try {
          await _realtimeDb.createAlarm(sessionToken, alarm);
          logger.d('✅ Synced existing alarm ${alarm.id}');
        } catch (e) {
          logger.e('❌ Failed to sync existing alarm ${alarm.id}', error: e);
        }
      }
    } else {
      // Clear any stale alarms in Firebase
      await _realtimeDb.updateSessionData(sessionToken, {'alarm': null});
      logger.i('🔄 Cleared alarms in Firebase (none active locally)');
    }
  }

  /// Sync a position update immediately (non-throttled version for initial sync).
  Future<void> _syncPositionUpdate(
    String sessionToken,
    PositionUpdate position,
  ) async {
    try {
      logger.i(
        '🔄 Sending position update to Firebase: lat=${position.latitude}, lon=${position.longitude}',
      );
      await _realtimeDb.pushPosition(sessionToken, position);
      logger.d('✅ Position pushed to history');

      final positionData = {
        'lat': position.latitude,
        'lon': position.longitude,
        'speed': position.speed,
        'accuracy': position.accuracy,
        'timestamp': position.timestamp.toIso8601String(),
      };

      logger.d('📝 Updating session document with boatPosition: $positionData');
      await _realtimeDb.updateSessionData(sessionToken, {
        'boatPosition': positionData,
      });
      logger.i(
        '✅ Successfully sent position update to Firebase for session: $sessionToken',
      );
    } catch (e) {
      logger.e(
        '❌ Failed to send position update to Firebase for session $sessionToken',
        error: e,
      );
    }
  }

  /// Updates anchor in session document.
  Future<void> updateSessionAnchor(String sessionToken, Anchor? anchor) async {
    try {
      if (anchor == null) {
        logger.i(
          '🔧 Updating session anchor to null for session: $sessionToken',
        );
        await _realtimeDb.updateSessionData(sessionToken, {'anchor': null});
        logger.i(
          '✅ Successfully set anchor to null in Firebase for session: $sessionToken',
        );
      } else {
        final anchorData = {
          'lat': anchor.latitude,
          'lon': anchor.longitude,
          'radius': anchor.radius,
          'isActive': anchor.isActive,
          'createdAt': anchor.createdAt.millisecondsSinceEpoch,
        };
        logger.i(
          '🔧 Updating session anchor for session: $sessionToken with data: $anchorData',
        );
        await _realtimeDb.updateSessionData(sessionToken, {
          'anchor': anchorData,
        });
        logger.i(
          '✅ Successfully updated anchor in Firebase for session: $sessionToken',
        );
      }
    } catch (e) {
      logger.e('❌ Failed to update session anchor', error: e);
    }
  }

  /// Schedules a position update (throttled to avoid too many writes).
  void _schedulePositionUpdate(String sessionToken) {
    _positionThrottleTimer?.cancel();

    // Clamp interval to minimum 5 seconds to prevent spam
    final clampedInterval = _settings.positionUpdateInterval < 5
        ? 5
        : _settings.positionUpdateInterval;

    logger.d('⏱️ Throttling position update for ${clampedInterval}s');
    _positionThrottleTimer = Timer(Duration(seconds: clampedInterval), () async {
      if (_pendingPosition != null) {
        try {
          logger.i(
            '🔄 Sending position update to Firebase: lat=${_pendingPosition!.latitude}, lon=${_pendingPosition!.longitude}',
          );
          await _realtimeDb.pushPosition(sessionToken, _pendingPosition!);
          logger.d('✅ Position pushed to history');

          final positionData = {
            'lat': _pendingPosition!.latitude,
            'lon': _pendingPosition!.longitude,
            'speed': _pendingPosition!.speed,
            'accuracy': _pendingPosition!.accuracy,
            'timestamp': _pendingPosition!.timestamp.toIso8601String(),
          };

          logger.d(
            '📝 Updating session document with boatPosition: $positionData',
          );

          await _realtimeDb.updateSessionData(sessionToken, {
            'boatPosition': positionData,
          });
          logger.i(
            '✅ Successfully sent position update to Firebase for session: $sessionToken',
          );
          _pendingPosition = null;
        } catch (e) {
          logger.e(
            '❌ Failed to send position update to Firebase for session $sessionToken',
            error: e,
          );
          _pendingPosition = null; // Clear on error too
        }
      } else {
        logger.d('⚠️ No pending position to send');
      }
    });
  }
}
