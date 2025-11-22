import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pairing_session.dart';
import '../repositories/firestore_repository.dart';
import 'firestore_provider.dart';
import 'pairing_session_provider.dart';
import '../utils/logger_setup.dart';

/// Provides a stream of pairing session updates for secondary devices.
/// Used to detect when the primary device ends the session.
final secondarySessionMonitorProvider =
    StreamProvider<PairingSession?>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);
  
  if (!pairingState.isSecondary || pairingState.sessionToken == null) {
    // Not secondary or no session, return null
    yield null;
    return;
  }

  final firestore = ref.read(firestoreRepositoryProvider);
  yield* firestore
      .getSessionStream(pairingState.sessionToken!)
      .handleError((error) {
    logger.e('Error in secondary session monitor stream', error: error);
    return null;
  });
});

