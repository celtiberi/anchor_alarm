import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:riverpod/riverpod.dart';
import '../repositories/firestore_repository.dart';
import 'firestore_provider.dart';
import 'pairing_provider.dart';
import 'alarm_provider.dart';
import '../utils/logger_setup.dart';

// Re-export the pairing provider for convenience
export 'pairing_provider.dart';

/// Device role in pairing session.
enum PairingRole {
  primary,
  secondary,
  none,
}

/// Provides the current pairing session state and role.
final pairingSessionStateProvider =
    NotifierProvider<PairingSessionStateNotifier, PairingSessionState>(() {
  return PairingSessionStateNotifier();
});

/// State for pairing session.
class PairingSessionState {
  final PairingRole role;
  final String? sessionToken;
  final String? primaryDeviceId;

  PairingSessionState({
    required this.role,
    this.sessionToken,
    this.primaryDeviceId,
  });

  bool get isPrimary => role == PairingRole.primary;
  bool get isSecondary => role == PairingRole.secondary;
  bool get isPaired => role != PairingRole.none;

  PairingSessionState copyWith({
    PairingRole? role,
    String? sessionToken,
    String? primaryDeviceId,
  }) {
    return PairingSessionState(
      role: role ?? this.role,
      sessionToken: sessionToken ?? this.sessionToken,
      primaryDeviceId: primaryDeviceId ?? this.primaryDeviceId,
    );
  }
}

/// Notifier for pairing session state management.
class PairingSessionStateNotifier extends Notifier<PairingSessionState> {
  FirestoreRepository get _firestore => ref.read(firestoreRepositoryProvider);

  @override
  PairingSessionState build() {
    logger.i('PairingSessionStateNotifier build() called');
    // Return initial state - auto-create is handled by pairingSessionAutoCreateProvider
    return PairingSessionState(role: PairingRole.none);
  }



  /// Sets this device as primary and creates a pairing session.
  Future<String> startPrimarySession() async {
    try {
      final pairingProvider = ref.read(pairingSessionProvider.notifier);
      final deviceId = await pairingProvider.deviceId;  // Await to ensure loaded

      // Create pairing session
      final sessionProvider = ref.read(pairingSessionProvider.notifier);
      final session = await sessionProvider.createSession();

      state = PairingSessionState(
        role: PairingRole.primary,
        sessionToken: session.token,
        primaryDeviceId: deviceId,
      );

      logger.i('Started primary pairing session: ${session.token}');
      return session.token;
    } catch (e) {
      logger.e('Failed to start primary session', error: e);
      rethrow;
    }
  }

  /// Joins a pairing session as secondary device.
  Future<void> joinSecondarySession(String token) async {
    try {
      // If this device was previously primary of a different session, stop that session first
      if (state.isPrimary && state.sessionToken != null && state.sessionToken != token) {
        logger.i('Leaving previous primary session ${state.sessionToken} to join $token as secondary');
        // The monitoring sync provider will handle stopping monitoring when role changes
      }

      final sessionProvider = ref.read(pairingSessionProvider.notifier);
      await sessionProvider.joinSession(token);

      // Get session to find primary device ID
      final session = await _firestore.getSession(token);
      if (session == null) {
        throw StateError('Session not found after joining');
      }

      state = PairingSessionState(
        role: PairingRole.secondary,
        sessionToken: token,
        primaryDeviceId: session.primaryDeviceId,
      );

      logger.i('Joined secondary pairing session: $token');
    } catch (e) {
      logger.e('Failed to join secondary session', error: e);
      rethrow;
    }
  }

  /// Disconnects from pairing session.
  Future<void> disconnect() async {
    // Stop any active alarm monitoring when disconnecting
    try {
      final alarmNotifier = ref.read(activeAlarmsProvider.notifier);
      if (alarmNotifier.isMonitoring) {
        logger.i('Stopping alarm monitoring due to session disconnect');
        alarmNotifier.stopMonitoring();
      }
    } catch (e) {
      logger.w('Failed to stop alarm monitoring during disconnect: $e');
    }

    state = PairingSessionState(role: PairingRole.none);
    logger.i('Disconnected from pairing session');
  }

  /// Ends the pairing session (primary device only).
  Future<void> endSession() async {
    if (!state.isPrimary) {
      throw StateError('Only primary device can end session');
    }

    try {
      final sessionProvider = ref.read(pairingSessionProvider.notifier);
      await sessionProvider.endSession();

      // Stop any active alarm monitoring when ending session
      try {
        final alarmNotifier = ref.read(activeAlarmsProvider.notifier);
        if (alarmNotifier.isMonitoring) {
          logger.i('Stopping alarm monitoring due to session end');
          alarmNotifier.stopMonitoring();
        }
      } catch (e) {
        logger.w('Failed to stop alarm monitoring during session end: $e');
      }

      state = PairingSessionState(role: PairingRole.none);
      logger.i('Ended pairing session');
    } catch (e) {
      logger.e('Failed to end session', error: e);
      rethrow;
    }
  }
}

/// Provider that handles auto-creation of pairing sessions when device ID becomes available.
/// This is separate from the main notifier to avoid rebuilding the session state.
final pairingSessionAutoCreateProvider = Provider<void>((ref) {
  // Listen to pairing session state
  final pairingState = ref.watch(pairingSessionStateProvider);

  // Only auto-create if we don't have a session
  if (pairingState.role == PairingRole.none) {
    final pairingProvider = ref.read(pairingSessionProvider.notifier);

    // Use async to wait for deviceId
    Future<void> autoCreate() async {
      try {
        final deviceId = await pairingProvider.deviceId;  // Now awaits loading
        if (deviceId.isNotEmpty) {
          logger.i('Auto-creating pairing session for device: $deviceId');
          ref.read(pairingSessionStateProvider.notifier).startPrimarySession();
        } else {
          logger.w('Device ID is empty; skipping auto-create');
        }
      } catch (e) {
        logger.e('Failed to auto-create pairing session', error: e);
      }
    }

    autoCreate();  // Fire-and-forget; the provider will re-evaluate if needed
  }
});

/// Provider for local session data (used by primary devices).
/// This manages the session that this device created and owns.
final localSessionProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);

  // Only provide data for primary devices with a session token
  if (!pairingState.isPrimary || pairingState.sessionToken == null) {
    yield {};
    return;
  }

  // For primary devices, get the session data from Firebase
  final firestore = ref.watch(firestoreRepositoryProvider);
  yield* firestore.getSessionDataStream(pairingState.sessionToken!);
});

/// Provider for remote session data (used by secondary devices).
/// This reads session data from Firebase for sessions this device joined.
final remoteSessionProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);

  // Only provide data for secondary devices with a session token
  if (!pairingState.isSecondary || pairingState.sessionToken == null) {
    yield {};
    return;
  }

  // For secondary devices, get the session data from Firebase
  final firestore = ref.watch(firestoreRepositoryProvider);
  yield* firestore.getSessionDataStream(pairingState.sessionToken!);
});

/// Effective session provider that switches between local and remote based on device role.
/// This is the main provider used throughout the app for session data.
final effectiveSessionProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (pairingState.isPrimary && pairingState.sessionToken != null) {
    // Primary device: yield data from local session provider
    final firestore = ref.watch(firestoreRepositoryProvider);
    yield* firestore.getSessionDataStream(pairingState.sessionToken!);
  } else if (pairingState.isSecondary && pairingState.sessionToken != null) {
    // Secondary device: yield data from remote session provider
    final firestore = ref.watch(firestoreRepositoryProvider);
    yield* firestore.getSessionDataStream(pairingState.sessionToken!);
  } else {
    // No session: empty data
    yield {};
  }
});

