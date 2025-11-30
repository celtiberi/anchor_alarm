import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anchor.dart';
import '../models/position_update.dart';
import '../models/alarm_event.dart';
import '../models/position_history_point.dart';
import 'package:latlong2/latlong.dart';
import 'pairing_providers.dart';
import 'service_providers.dart';
import '../utils/logger_setup.dart';
import 'local_alarm_dismissal_provider.dart';

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

      if (!pairingState.isSecondary || pairingState.sessionToken == null) {
        yield {};
        return;
      }

      final realtimeDb = ref.read(realtimeDatabaseRepositoryProvider);
      yield* realtimeDb
          .getSessionDataStream(pairingState.sessionToken!)
          .handleError((error) {
            logger.e('Error in remote session data stream', error: error);
            return {};
          });
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
        data: (data) =>
            AsyncValue.data(data['monitoringActive'] as bool? ?? false),
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
final remoteAlarmProvider = StreamProvider.autoDispose<List<AlarmEvent>>((
  ref,
) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);
  final localDismissals = ref.watch(localAlarmDismissalProvider);

  if (!pairingState.isSecondary || pairingState.sessionToken == null) {
    yield [];
    return;
  }

  final realtimeDb = ref.read(realtimeDatabaseRepositoryProvider);
  yield* realtimeDb
      .getAlarmsStream(pairingState.sessionToken!)
      .map((alarms) {
        return alarms
            .where((alarm) => !localDismissals.contains(alarm.id))
            .toList();
      })
      .handleError((error) {
        logger.e('Error in remote alarms stream', error: error);
        return [];
      });
});
