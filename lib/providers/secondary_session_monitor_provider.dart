import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/pairing_session.dart';
import 'pairing/pairing_providers.dart';
import 'service_providers.dart';
import '../utils/logger_setup.dart';

/// Provides a stream of pairing session updates for secondary devices.
/// Used to detect when the primary device ends the session.
final secondarySessionMonitorProvider =
    StreamProvider.autoDispose<PairingSession?>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);
  
  if (!pairingState.isSecondary || pairingState.sessionToken == null) {
    // Not secondary or no session, return null
    yield null;
    return;
  }

  final realtimeDb = ref.read(realtimeDatabaseRepositoryProvider);
  yield* realtimeDb
      .getSessionStream(pairingState.sessionToken!)
      .map((session) {
        // Check if session is expired
        if (session.isExpired) {
          logger.w(
            '⚠️ Session ${session.token} is expired, deleting and disconnecting',
          );
          // Delete expired session and disconnect
          Future.microtask(() async {
            try {
              await realtimeDb.deleteSession(session.token);
              logger.i('✅ Deleted expired session: ${session.token}');
              final sessionNotifier = ref.read(pairingSessionStateProvider.notifier);
              await sessionNotifier.disconnect();
              logger.i('✅ Auto-disconnected from expired session');
            } catch (e) {
              logger.e('Failed to delete expired session and disconnect', error: e);
            }
          });
          return null;
        }
        return session;
      })
      .handleError((error) {
    logger.e('Error in secondary session monitor stream', error: error);

    // Auto-disconnect if session not found or corrupted
    if (error is StateError &&
        (error.message.contains('not found') || error.message.contains('corrupted'))) {
      logger.w('⚠️ Session ${error.message.contains('not found') ? 'not found' : 'corrupted'} in monitor - auto-disconnecting secondary device');

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
          logger.i('✅ Auto-disconnected from ${error.message.contains('not found') ? 'missing' : 'corrupted'} session (via monitor)');
        } catch (e) {
          logger.e('Failed to auto-disconnect from monitor', error: e);
        }
      });
    }

    return null;
  });
});

