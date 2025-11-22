import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pairing_session_provider.dart';
import 'firestore_provider.dart';
import '../repositories/firestore_repository.dart';
import '../utils/logger_setup.dart';

/// Provides monitoring status that syncs from Firebase for secondary devices.
/// For primary devices, this is not used (they use local monitoring status).
final remoteMonitoringStatusProvider = StreamProvider<bool>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (!pairingState.isPaired || pairingState.isPrimary || pairingState.sessionToken == null) {
    // Not paired, not secondary, or no session - monitoring status not available
    yield false;
    return;
  }

  // Secondary device: read monitoring status from Firebase
  final firestore = ref.read(firestoreRepositoryProvider);
  logger.i('📡 Secondary device listening for monitoring status from session: ${pairingState.sessionToken}');

  yield* firestore
      .getSessionDataStream(pairingState.sessionToken!)
      .map((sessionData) {
        if (sessionData == null) {
          logger.i('📭 Session data is null for session: ${pairingState.sessionToken}');
          return false;
        }
        final monitoringActive = sessionData['monitoringActive'] as bool? ?? false;
        logger.i('📊 Remote monitoring status for session ${pairingState.sessionToken}: $monitoringActive (sessionData keys: ${sessionData.keys.toList()})');
        return monitoringActive;
      })
      .handleError((error) {
        logger.e('Error in remote monitoring status stream for session ${pairingState.sessionToken}', error: error);
        return false;
      });
});
