import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/position_update.dart';
import '../models/anchor.dart';
import '../models/alarm_event.dart';
import 'position_provider.dart';
import 'anchor_provider.dart';
import 'alarm_provider.dart';
import 'remote_position_provider.dart';
import 'remote_anchor_provider.dart';
import 'remote_alarm_provider.dart';
import 'remote_monitoring_status_provider.dart';
import 'pairing_session_provider.dart';

/// Effective position provider that selects the appropriate data source based on device role.
/// Primary devices: use local GPS position
/// Secondary devices: use remote position from Firebase
/// Not paired: use local GPS position
final effectivePositionProvider = Provider<AsyncValue<PositionUpdate?>>((ref) {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (pairingState.isSecondary && pairingState.sessionToken != null) {
    // Secondary device: use remote position from Firebase
    return ref.watch(remotePositionProvider);
  } else {
    // Primary device or not paired: use local position
    return AsyncValue.data(ref.watch(positionProvider));
  }
});

/// Provider that extracts the current position value from effectivePositionProvider.
/// This is useful for listening to position changes.
final currentPositionProvider = Provider<PositionUpdate?>((ref) {
  final asyncValue = ref.watch(effectivePositionProvider);
  return asyncValue.maybeWhen(
    data: (data) => data,
    orElse: () => null,
  );
});

/// Provider that extracts the current anchor value from effectiveAnchorProvider.
/// This is useful for listening to anchor changes.
final currentAnchorProvider = Provider<Anchor?>((ref) {
  final asyncValue = ref.watch(effectiveAnchorProvider);
  return asyncValue.maybeWhen(
    data: (data) => data,
    orElse: () => null,
  );
});

/// Effective anchor provider that selects the appropriate data source based on device role.
/// Primary devices: use local anchor data
/// Secondary devices: use remote anchor from Firebase
/// Not paired: use local anchor data
final effectiveAnchorProvider = Provider<AsyncValue<Anchor?>>((ref) {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (pairingState.isSecondary && pairingState.sessionToken != null) {
    // Secondary device: use remote anchor from Firebase
    return ref.watch(remoteAnchorProvider);
  } else {
    // Primary device or not paired: use local anchor
    return AsyncValue.data(ref.watch(anchorProvider));
  }
});

/// Effective alarm provider that selects the appropriate data source based on device role.
/// Primary devices: use local alarm management
/// Secondary devices: use remote alarms from Firebase
/// Not paired: use local alarms
final effectiveAlarmProvider = Provider<AsyncValue<List<AlarmEvent>>>((ref) {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (pairingState.isSecondary && pairingState.sessionToken != null) {
    // Secondary device: use remote alarms from Firebase
    return ref.watch(remoteAlarmProvider);
  } else {
    // Primary device or not paired: use local alarms
    return AsyncValue.data(ref.watch(activeAlarmsProvider) ?? <AlarmEvent>[]);
  }
});

/// Effective monitoring status provider that selects the appropriate source based on device role.
/// Primary devices: use local monitoring status
/// Secondary devices: use remote monitoring status from Firebase
/// Not paired: false (not monitoring)
final effectiveMonitoringStatusProvider = Provider<AsyncValue<bool>>((ref) {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (pairingState.isSecondary && pairingState.sessionToken != null) {
    // Secondary device: use remote monitoring status from Firebase
    return ref.watch(remoteMonitoringStatusProvider);
  } else {
    // Primary device or not paired: use local monitoring status
    return AsyncValue.data(ref.watch(activeAlarmsProvider.notifier).isMonitoring);
  }
});
