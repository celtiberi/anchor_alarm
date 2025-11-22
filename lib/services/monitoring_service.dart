import 'dart:async';
import '../models/anchor.dart';
import '../models/position_update.dart';
import '../models/alarm_event.dart';
import '../models/position_history_point.dart';
import '../repositories/firestore_repository.dart';
import '../utils/logger_setup.dart';

/// Service for syncing anchor, position, and alarms to Firebase for multi-device monitoring.
class MonitoringService {
  final FirestoreRepository _firestore;
  StreamSubscription<PositionUpdate?>? _positionSubscription;
  StreamSubscription<Anchor?>? _anchorSubscription;
  Timer? _positionThrottleTimer;
  PositionUpdate? _pendingPosition;
  String? _currentSessionToken;

  MonitoringService({FirestoreRepository? firestore})
      : _firestore = firestore ?? FirestoreRepository();

  /// Starts monitoring and syncing data to Firebase for a session.
  /// Only call this on the primary device.
  Future<void> startMonitoring({
    required String sessionToken,
    required Stream<Anchor?> anchorStream,
    required Stream<PositionUpdate?> positionStream,
    required Stream<List<AlarmEvent>> alarmsStream,
    required Stream<List<PositionHistoryPoint>> positionHistoryStream,
  }) async {
    if (_currentSessionToken != null) {
      logger.w('Monitoring already active for session: $_currentSessionToken');
      return;
    }

    _currentSessionToken = sessionToken;
    logger.i('Starting monitoring service for session: $sessionToken');

    // Mark monitoring as active in Firebase
    logger.i('📡 Setting monitoringActive=true in Firebase for session: $sessionToken');
    await _firestore.updateSessionData(sessionToken, {
      'monitoringActive': true,
    });
    logger.i('✅ Successfully set monitoringActive=true in Firebase for session: $sessionToken');

    // Subscribe to anchor changes
    _anchorSubscription = anchorStream.listen(
      (anchor) async {
        if (anchor == null) {
          await _updateSessionAnchor(sessionToken, null);
        } else {
          await _updateSessionAnchor(sessionToken, anchor);
        }
      },
      onError: (error) {
        logger.e('Error in anchor stream', error: error);
      },
    );

    // Listen to position updates
    _positionSubscription = positionStream.listen(
      (position) {
        if (position != null) {
          logger.i('📍 Position stream received: lat=${position.latitude}, lon=${position.longitude}');
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
    alarmsStream.listen(
      (alarms) async {
        for (final alarm in alarms) {
          // Only sync unacknowledged alarms to Firebase
          if (!alarm.acknowledged) {
            await _firestore.createAlarm(sessionToken, alarm);
          }
        }
      },
      onError: (error) {
        logger.e('Error in alarms stream', error: error);
      },
    );

    // Subscribe to position history (last 500 points)
    positionHistoryStream.listen(
      (history) async {
        await _updateSessionPositionHistory(sessionToken, history);
      },
      onError: (error) {
        logger.e('Error in position history stream', error: error);
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
      logger.i('📡 Setting monitoringActive=false in Firebase for session: $tokenToUse');
      _firestore.updateSessionData(tokenToUse, {
        'monitoringActive': false,
      }).then((_) {
        logger.i('✅ Successfully set monitoringActive=false in Firebase for session: $tokenToUse');
      }).catchError((error) {
        logger.e('❌ Failed to update monitoring status to inactive for session: $tokenToUse', error: error);
      });
    } else {
      logger.w('⚠️ No session token available when stopping monitoring');
    }
    _anchorSubscription?.cancel();
    _anchorSubscription = null;
    _positionSubscription?.cancel();
    _positionSubscription = null;
    _positionThrottleTimer?.cancel();
    _positionThrottleTimer = null;
    _pendingPosition = null;
    _currentSessionToken = null;
  }

  /// Updates anchor in session document.
  Future<void> _updateSessionAnchor(String sessionToken, Anchor? anchor) async {
    try {
      if (anchor == null) {
        await _firestore.updateSessionData(sessionToken, {
          'anchor': null,
        });
      } else {
        await _firestore.updateSessionData(sessionToken, {
          'anchor': {
            'lat': anchor.latitude,
            'lon': anchor.longitude,
            'radius': anchor.radius,
            'isActive': anchor.isActive,
          },
        });
      }
    } catch (e) {
      logger.e('Failed to update session anchor', error: e);
    }
  }

  /// Schedules a position update (throttled to avoid too many writes).
  void _schedulePositionUpdate(String sessionToken) {
    _positionThrottleTimer?.cancel();
    _positionThrottleTimer = Timer(const Duration(seconds: 2), () async {
      if (_pendingPosition != null) {
        try {
          logger.i('🔄 Sending position update to Firebase: lat=${_pendingPosition!.latitude}, lon=${_pendingPosition!.longitude}');
          await _firestore.pushPosition(sessionToken, _pendingPosition!);
          logger.d('✅ Position pushed to history');

          final positionData = {
            'lat': _pendingPosition!.latitude,
            'lon': _pendingPosition!.longitude,
            'speed': _pendingPosition!.speed,
            'accuracy': _pendingPosition!.accuracy,
            'timestamp': _pendingPosition!.timestamp.toIso8601String(),
          };

          logger.d('📝 Updating session document with boatPosition: $positionData');

          await _firestore.updateSessionData(sessionToken, {
            'boatPosition': positionData,
          });
          logger.i('✅ Successfully sent position update to Firebase for session: $sessionToken');
          _pendingPosition = null;
        } catch (e) {
          logger.e('❌ Failed to send position update to Firebase for session $sessionToken', error: e);
          _pendingPosition = null; // Clear on error too
        }
      } else {
        logger.d('⚠️ No pending position to send');
      }
    });
  }

  /// Updates position history in session document using atomic array operations.
  Future<void> _updateSessionPositionHistory(
    String sessionToken,
    List<PositionHistoryPoint> history,
  ) async {
    try {
      // Only append new points that aren't already in history
      // For simplicity, we'll just keep the last N points by replacing the array
      // In a production app, you'd track what's already been sent to avoid duplicates
      final limitedHistory = history.length > 500
          ? history.sublist(history.length - 500)
          : history;

      await _firestore.updateSessionData(sessionToken, {
        'positionHistory': limitedHistory
            .map((p) => {
                  'lat': p.position.latitude,
                  'lon': p.position.longitude,
                  'timestamp': p.timestamp.toIso8601String(),
                })
            .toList(),
      });
    } catch (e) {
      logger.e('Failed to update session position history', error: e);
    }
  }
}

