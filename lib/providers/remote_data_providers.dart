import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anchor.dart';
import '../models/position_update.dart';
import '../models/alarm_event.dart';
import '../models/position_history_point.dart';
import 'package:latlong2/latlong.dart';
import 'pairing/pairing_providers.dart';
import 'service_providers.dart';
import '../utils/logger_setup.dart';
import 'local_alarm_dismissal_provider.dart';
import 'settings_provider.dart';

/// Helper method to parse timestamps that might be stored as different types in RTDB
int _parseTimestamp(dynamic value) {
  if (value is int) return value;
  if (value is double) return value.toInt();
  if (value is String) return int.tryParse(value) ?? 0;
  return 0; // fallback
}

/// Helper method to parse doubles that might be stored as different types in RTDB
double _parseDouble(dynamic value) {
  if (value is double) return value;
  if (value is int) return value.toDouble();
  if (value is String) return double.tryParse(value) ?? 0.0;
  return 0.0; // fallback
}

// Central remote session data stream (fetches once for all derived providers)
final remoteSessionDataProvider =
    StreamProvider.autoDispose<Map<String, dynamic>>((ref) async* {
      final pairingState = ref.watch(pairingSessionStateProvider);

      logger.i(
        '📡 Remote session data provider: role=${pairingState.role}, isSecondary=${pairingState.isSecondary}, sessionToken=${pairingState.sessionToken}',
      );

      if (!pairingState.isSecondary || pairingState.sessionToken == null) {
        logger.d('📡 Remote session data: Not secondary or no session token, yielding empty');
        yield {};
        return;
      }

      logger.i(
        '📡 Remote session data: Starting stream for session ${pairingState.sessionToken}',
      );
      final realtimeDb = ref.read(realtimeDatabaseRepositoryProvider);
      
      try {
      yield* realtimeDb
          .getSessionDataStream(pairingState.sessionToken!)
            .map((data) {
              logger.i(
                '📡 Remote session data: Received update - keys=${data.keys.toList()}, data=$data',
              );
              logger.i(
                '📡 Remote session data: anchor=${data['anchor']}, boatPosition=${data['boatPosition']}, monitoringActive=${data['monitoringActive']}',
              );
              return data;
            })
            .handleError((error, stackTrace) {
              logger.e(
                'Error in remote session data stream',
                error: error,
                stackTrace: stackTrace,
              );
              
              // Auto-disconnect if session not found or corrupted
              if (error is StateError &&
                  (error.message.contains('not found') || error.message.contains('corrupted'))) {
                logger.w('⚠️ Session ${error.message.contains('not found') ? 'not found' : 'corrupted'} - auto-disconnecting secondary device');

                if (error.message.contains('corrupted')) {
                  // Stop session sync service immediately
                  ref.invalidate(pairingSyncProvider);
                  logger.i('🛑 Stopped session sync service for corrupted session');

                  // Delete corrupted session
                  Future.microtask(() async {
                    try {
                      await realtimeDb.deleteSession(pairingState.sessionToken!);
                      logger.i('✅ Deleted corrupted session: ${pairingState.sessionToken}');
                    } catch (e) {
                      logger.e('Failed to delete corrupted session', error: e);
                    }
                  });
                }

                // Use Future.microtask to avoid circular dependency
                Future.microtask(() async {
                  try {
                    final sessionNotifier = ref.read(pairingSessionStateProvider.notifier);
                    await sessionNotifier.disconnect();
                    logger.i('✅ Auto-disconnected from ${error.message.contains('not found') ? 'missing' : 'corrupted'} session');
                  } catch (e) {
                    logger.e('Failed to auto-disconnect', error: e);
                  }
                });
              }
              
            return {};
          });
      } catch (e, stackTrace) {
        logger.e(
          'Failed to start remote session data stream',
          error: e,
          stackTrace: stackTrace,
        );
        yield {};
      }
    });

// Remote anchor provider (derived from central stream)
final remoteAnchorProvider = Provider.autoDispose<AsyncValue<Anchor?>>((ref) {
  return ref
      .watch(remoteSessionDataProvider)
      .when(
        data: (data) {
          final anchorData = data['anchor'] as Map<String, dynamic>?;
          logger.d(
            '🔍 Remote anchor provider: data keys = ${data.keys.toList()}',
          );
          logger.d('🔍 Remote anchor provider: anchorData = $anchorData');

          if (anchorData == null) {
            logger.d('🔍 Remote anchor provider: No anchor data found');
            return const AsyncValue.data(null);
          }

          try {
            final anchor = Anchor(
              id: 'remote_anchor',
              latitude: _parseDouble(anchorData['lat']),
              longitude: _parseDouble(anchorData['lon']),
              radius: _parseDouble(anchorData['radius']),
              createdAt: DateTime.fromMillisecondsSinceEpoch(
                _parseTimestamp(
                  anchorData['createdAt'] ??
                      DateTime.now().millisecondsSinceEpoch,
                ),
              ),
              isActive: anchorData['isActive'] as bool? ?? true,
            );
            logger.i(
              '✅ Remote anchor provider: Successfully parsed anchor - lat=${anchor.latitude}, lon=${anchor.longitude}, radius=${anchor.radius}',
            );
            return AsyncValue.data(anchor);
          } catch (e) {
            logger.e(
              '❌ Remote anchor provider: Failed to parse remote anchor',
              error: e,
            );
            return AsyncValue.data(null);
          }
        },
        error: (error, stack) => AsyncValue.error(error, stack),
        loading: () => const AsyncValue.loading(),
      );
});

// Remote position provider (derived from central stream)
final remotePositionProvider =
    Provider.autoDispose<AsyncValue<PositionUpdate?>>((ref) {
      return ref
          .watch(remoteSessionDataProvider)
          .when(
            data: (data) {
              final positionData =
                  data['boatPosition'] as Map<String, dynamic>?;
              if (positionData == null) return const AsyncValue.data(null);

              try {
                final position = PositionUpdate(
                  timestamp: DateTime.fromMillisecondsSinceEpoch(
                    _parseTimestamp(positionData['timestamp']),
                  ),
                  latitude: _parseDouble(positionData['lat']),
                  longitude: _parseDouble(positionData['lon']),
                  speed: positionData['speed'] != null
                      ? _parseDouble(positionData['speed'])
                      : null,
                  accuracy: positionData['accuracy'] != null
                      ? _parseDouble(positionData['accuracy'])
                      : null,
                );
                return AsyncValue.data(position);
              } catch (e) {
                logger.e('Failed to parse remote position', error: e);
                return const AsyncValue.data(null);
              }
            },
            error: (error, stack) => AsyncValue.error(error, stack),
            loading: () => const AsyncValue.loading(),
          );
    });

// Remote monitoring status provider (derived from central stream)
final remoteMonitoringStatusProvider = Provider.autoDispose<AsyncValue<bool>>((
  ref,
) {
  return ref
      .watch(remoteSessionDataProvider)
      .when(
        data: (data) {
          final monitoringActive = data['monitoringActive'] as bool? ?? false;
          logger.d(
            '📊 Remote monitoring status: data keys=${data.keys.toList()}, monitoringActive=$monitoringActive',
          );
          return AsyncValue.data(monitoringActive);
        },
        error: (error, stack) => AsyncValue.error(error, stack),
        loading: () => const AsyncValue.loading(),
      );
});

// Local position history provider for secondary devices
// Builds history from streamed position updates instead of RTDB
final secondaryPositionHistoryProvider =
    NotifierProvider<
      SecondaryPositionHistoryNotifier,
      List<PositionHistoryPoint>
    >(() {
      return SecondaryPositionHistoryNotifier();
    });

class SecondaryPositionHistoryNotifier
    extends Notifier<List<PositionHistoryPoint>> {
  @override
  List<PositionHistoryPoint> build() {
    final pairingState = ref.watch(pairingSessionStateProvider);

    // Only build history on secondary devices
    if (!pairingState.isSecondary) {
      return [];
    }

    // Listen to position updates and build local history
    ref.listen<AsyncValue<PositionUpdate?>>(remotePositionProvider, (
      previous,
      next,
    ) {
      final position = next.value;
      if (position != null) {
        addPosition(position);
      }
    });

    return [];
  }

  void addPosition(PositionUpdate position) {
    final historyPoint = PositionHistoryPoint(
      position: LatLng(position.latitude, position.longitude),
      timestamp: position.timestamp,
    );

    // Keep only last 500 points to prevent memory issues
    final newHistory = [...state, historyPoint];
    if (newHistory.length > 500) {
      state = newHistory.sublist(newHistory.length - 500);
    } else {
      state = newHistory;
    }
  }

  void clearHistory() {
    state = [];
  }
}

// Remote alarms provider (separate stream for alarms)
final remoteAlarmProvider = StreamProvider<List<AlarmEvent>>((
  ref,
) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);
  final localDismissals = ref.watch(localAlarmDismissalProvider);

  if (!pairingState.isSecondary || pairingState.sessionToken == null) {
    yield [];
    return;
  }

  final realtimeDb = ref.read(realtimeDatabaseRepositoryProvider);
  logger.i('🔄 Secondary device starting remote alarm stream for session: ${pairingState.sessionToken}');

  yield* realtimeDb
      .getAlarmsStream(pairingState.sessionToken!)
      .map((alarms) {
        final filteredAlarms = alarms
            .where((alarm) => !localDismissals.contains(alarm.id))
            .toList();
        logger.i('📡 Remote alarms update: ${alarms.length} total, ${filteredAlarms.length} after filtering, local dismissals: ${localDismissals.length}');
        logger.d('📡 Alarm IDs in stream: ${alarms.map((a) => a.id).toList()}');
        logger.d('📡 Filtered alarm IDs: ${filteredAlarms.map((a) => a.id).toList()}');
        return filteredAlarms;
      })
      .handleError((error) {
        logger.e('Error in remote alarms stream', error: error);
        return [];
      });
});

/// Provider that tracks previously seen alarm IDs for secondary devices.
/// Used to detect when alarms are cleared remotely.

/// Provider that handles alarm notifications for secondary devices.
/// Listens to remote alarms and triggers local notifications when alarms are present.
/// This is a simplified approach that triggers notifications for all active alarms
/// rather than trying to track "new" vs "existing" alarms, since notification
/// services are typically idempotent.
final secondaryAlarmNotificationProvider = Provider.autoDispose<void>((ref) {
  final pairingState = ref.watch(pairingSessionStateProvider);
  final alarmsAsync = ref.watch(remoteAlarmProvider);
  final settings = ref.watch(settingsProvider);

  // Only handle notifications for secondary devices
  if (!pairingState.isSecondary) {
    return;
  }

  final alarms = alarmsAsync.value ?? [];
  final notificationService = ref.read(notificationServiceProvider);

  if (alarms.isNotEmpty) {
    // Trigger notifications for all active alarms
    // The notification service should handle duplicates gracefully
    for (final alarm in alarms) {
      logger.i('📢 Secondary device triggering notification for remote alarm: ${alarm.type} (${alarm.id})');
      try {
        notificationService.triggerAlarm(alarm, settings);
      } catch (e) {
        logger.e('Failed to trigger notification for remote alarm ${alarm.id}', error: e);
      }
    }
  } else {
    // No active alarms - stop any ongoing notifications
    logger.i('🔕 Stopping alarm notifications - no active remote alarms');
    notificationService.stopAlarm();
  }
});

