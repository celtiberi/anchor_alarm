import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/alarm_event.dart';
import 'pairing_session_provider.dart';
import 'firestore_provider.dart';
import 'local_alarm_dismissal_provider.dart';
import '../repositories/firestore_repository.dart';
import '../utils/logger_setup.dart';

/// Provides alarm data from Firebase for secondary devices.
/// Acknowledged alarms are deleted from Firebase, so no filtering needed.
/// This provider ONLY handles reading from Firebase - does not provide local data.
/// Use effectiveAlarmProvider to get the appropriate data source based on device role.
final remoteAlarmProvider = StreamProvider<List<AlarmEvent>>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);
  final localDismissals = ref.watch(localAlarmDismissalProvider);

  if (!pairingState.isPaired) {
    // Not paired, return empty list
    yield [];
    return;
  }

  if (pairingState.isSecondary && pairingState.sessionToken != null) {
    // Secondary device: read alarms from Firebase and filter out locally dismissed ones
    final firestore = ref.read(firestoreRepositoryProvider);
    yield* firestore
        .getAlarmsStream(pairingState.sessionToken!)
        .map((alarms) {
      // Filter out locally dismissed alarms
      return alarms
          .where((alarm) => !localDismissals.contains(alarm.id))
          .toList();
    })
        .handleError((error) {
      logger.e('Error in remote alarms stream', error: error);
      return <AlarmEvent>[];
    });
  } else {
    // Primary device: alarms are handled by activeAlarmsProvider
    // This provider is mainly for secondary devices
    yield [];
  }
});

