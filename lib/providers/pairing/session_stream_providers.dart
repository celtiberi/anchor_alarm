import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/pairing_session.dart';
import '../../utils/logger_setup.dart';
import '../service_providers.dart';
import 'pairing_providers.dart';

/// Stream provider for local session data.
final localSessionProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);
  if (pairingState.localSessionToken == null) {
    yield {};
    return;
  }
  final firestore = ref.watch(realtimeDatabaseRepositoryProvider);
  yield* firestore.getSessionDataStream(pairingState.localSessionToken!);
});

/// Stream provider for remote session data.
final remoteSessionProvider = StreamProvider<Map<String, dynamic>>((
  ref,
) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);
  if (pairingState.remoteSessionToken == null) {
    yield {};
    return;
  }
  final firestore = ref.watch(realtimeDatabaseRepositoryProvider);
  yield* firestore.getSessionDataStream(pairingState.remoteSessionToken!);
});

/// Stream provider for effective session data (remote ?? local).
final firestoreSessionProvider = StreamProvider<Map<String, dynamic>>((
  ref,
) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);
  final sessionToken = pairingState.sessionToken;
  if (sessionToken == null) {
    yield {};
    return;
  }
  final firestore = ref.watch(realtimeDatabaseRepositoryProvider);
  yield* firestore.getSessionDataStream(sessionToken);
});

/// Pairing session stream provider.
final pairingSessionStreamProvider = StreamProvider<PairingSession?>((
  ref,
) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (!pairingState.isPrimary || pairingState.sessionToken == null) {
    yield null;
    return;
  }

  final firestore = ref.read(realtimeDatabaseRepositoryProvider);
  yield* firestore
      .getSessionStream(pairingState.sessionToken!)
      .map((session) {
        // Check if primary device's session is expired
        if (session.isExpired) {
          logger.w(
            '⚠️ Primary device session ${session.token} is expired, deleting and clearing state',
          );
          // Delete expired session and clear local state
          Future.microtask(() async {
            try {
              if (!ref.mounted) return; // Check if still mounted before async operations
              await firestore.deleteSession(session.token);
              logger.i('✅ Deleted expired primary session: ${session.token}');

              if (!ref.mounted) return;
              // Clear local storage
              final localStorage = ref.read(localStorageRepositoryProvider);
              await localStorage.saveMonitoringSessionToken(null);
              await localStorage.saveDeviceRole(null);

              if (!ref.mounted) return;
              // Clear state
              final sessionNotifier = ref.read(pairingSessionStateProvider.notifier);
              await sessionNotifier.disconnect();
              logger.i('✅ Cleared state after deleting expired session');
            } catch (e) {
              logger.e('Failed to delete expired primary session and clear state', error: e);
            }
          });
          return null;
        }
        return session;
      })
      .handleError((
    error,
  ) {
    logger.e('Error in pairing session stream', error: error);

    // If session is corrupted, delete it
    if (error is StateError && error.message.contains('corrupted')) {
      logger.w('⚠️ Session is corrupted, deleting it and stopping sync');
      Future.microtask(() async {
        try {
          if (!ref.mounted) return; // Check if still mounted before async operations
          // Stop session sync service immediately
          ref.invalidate(pairingSyncProvider);
          logger.i('🛑 Stopped session sync service for corrupted session');

          final token = pairingState.sessionToken!;
          await firestore.deleteSession(token);
          logger.i('✅ Deleted corrupted session: $token');

          if (!ref.mounted) return;
          // Clear local storage
          final localStorage = ref.read(localStorageRepositoryProvider);
          await localStorage.saveMonitoringSessionToken(null);
          await localStorage.saveDeviceRole(null);

          if (!ref.mounted) return;
          // Clear state
          final sessionNotifier = ref.read(pairingSessionStateProvider.notifier);
          await sessionNotifier.disconnect();
          logger.i('✅ Cleared state after deleting corrupted session');
        } catch (e) {
          logger.e('Failed to delete corrupted session and clear state', error: e);
        }
      });
    }

    return null;
  });
});

