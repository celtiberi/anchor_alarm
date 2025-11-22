import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pairing_session.dart';
import '../repositories/firestore_repository.dart';
import 'firestore_provider.dart';
import 'pairing_session_provider.dart';
import '../utils/logger_setup.dart';

/// Provides a stream of pairing session updates for real-time device list.
final pairingSessionStreamProvider =
    StreamProvider<PairingSession?>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (!pairingState.isPrimary || pairingState.sessionToken == null) {
    // Not primary or no session, return null
    yield null;
    return;
  }

  final firestore = ref.read(firestoreRepositoryProvider);
  yield* firestore
      .getSessionStream(pairingState.sessionToken!)
      .handleError((error) {
    logger.e('Error in pairing session stream', error: error);
    return null;
  });
});

