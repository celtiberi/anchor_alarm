import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'pairing/pairing_providers.dart';
import 'secondary_session_monitor_provider.dart';
import '../utils/logger_setup.dart';

/// Automatically disconnects secondary devices when their session becomes inactive or missing.
/// This provider watches the session monitor and triggers disconnect when needed.
final secondaryAutoDisconnectProvider = Provider.autoDispose<void>((ref) {
  final pairingState = ref.watch(pairingSessionStateProvider);
  final sessionAsync = ref.watch(secondarySessionMonitorProvider);

  // Only act if we're secondary
  if (pairingState.isSecondary) {
    final session = sessionAsync.value;

    // If session monitor is still loading, don't disconnect
    if (sessionAsync.isLoading) {
      logger.d('🔄 Session monitor is loading, not auto-disconnecting');
      return;
    }

    // Only disconnect if session is confirmed null or inactive
    if (session == null || !session.isActive) {
      logger.i('🔄 Auto-disconnecting: session is null or inactive');

      // Use Future.microtask to avoid circular dependency
      Future.microtask(() async {
        try {
          // Double-check we're still secondary before disconnecting
          final currentState = ref.read(pairingSessionStateProvider);
          if (currentState.isSecondary) {
            final sessionNotifier = ref.read(pairingSessionStateProvider.notifier);
            await sessionNotifier.disconnect();
            logger.i('✅ Auto-disconnected from inactive/missing session');
          }
        } catch (e) {
          logger.e('Failed to auto-disconnect', error: e);
        }
      });
    }
  }
});

