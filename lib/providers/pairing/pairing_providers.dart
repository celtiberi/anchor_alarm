import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/pairing_session.dart';
import '../../services/pairing_service.dart';
import 'pairing_session_notifier.dart';
import 'pairing_session_state.dart';
import 'pairing_session_state_notifier.dart';
import 'pairing_sync_notifier.dart';

// Export types for use in UI and other files
export 'pairing_role.dart';
export 'pairing_session_state.dart';
export 'pairing_session_notifier.dart';
export 'pairing_session_state_notifier.dart';
export 'session_stream_providers.dart';

/// Service provider for PairingService.
final pairingServiceProvider = Provider<PairingService>((ref) {
  return PairingService();
});

/// Provides the current pairing session model.
final pairingSessionProvider =
    NotifierProvider<PairingSessionNotifier, PairingSession?>(() {
  return PairingSessionNotifier();
});

/// Provides the current pairing session state and role.
final pairingSessionStateProvider =
    NotifierProvider<PairingSessionStateNotifier, PairingSessionState>(() {
  return PairingSessionStateNotifier();
});

/// Pairing sync provider.
final pairingSyncProvider = NotifierProvider<PairingSyncNotifier, void>(() {
  return PairingSyncNotifier();
});

