import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';
import 'dart:async';

import '../models/pairing_session.dart';
import '../models/device_info.dart';
import '../models/anchor.dart';
import '../models/position_update.dart';
import '../models/alarm_event.dart';
import '../services/pairing_service.dart';
import '../repositories/realtime_database_repository.dart';
import '../utils/logger_setup.dart';
import 'service_providers.dart';
import 'anchor_provider.dart';
import 'gps_provider.dart';
import 'alarm_provider.dart';

// Note: Assuming pairing_service_provider.dart and firestore_provider.dart are merged here.
// If other providers like session_sync_service_provider.dart exist, import them as needed.

/*

╔══════════════════════════════════════════════════════════════════════════════╗

║                           PAIRING SYSTEM ARCHITECTURE                        ║

╠══════════════════════════════════════════════════════════════════════════════╣

║                                                                              ║

║  CORE CONCEPTS:                                                              ║

║  ──────────────                                                              ║

║  • Every device always creates and maintains its own local Firebase session. ║

║    This session stores the device's own data.                                ║

║                                                                              ║

║  • When operating alone, the device is primary and uses its local session.   ║

║                                                                              ║

║  • In a pairing:                                                             ║

║    - The primary device shares its session via QR code.                      ║

║    - The secondary device joins the primary's session and uses it for data   ║

║      display, while still maintaining its own local session in the background║

║                                                                              ║

║  PAIRING FLOW:                                                               ║

║  ─────────────                                                               ║

║  1. Device A starts app:                                                     ║

║     - Auto-creates local session "A-session"                                 ║

║     - Sets role to primary                                                   ║

║     - Uses "A-session" as effective session                                  ║

║                                                                              ║

║  2. Device B starts app:                                                     ║

║     - Auto-creates local session "B-session"                                 ║

║     - Sets role to primary                                                   ║

║     - Uses "B-session" as effective session                                  ║

║                                                                              ║

║  3. Device B scans Device A's QR code ("A-session"):                         ║

║     - Device B becomes secondary                                             ║

║     - Keeps "B-session" as local                                             ║

║     - Sets remote to "A-session"                                             ║

║     - Uses "A-session" as effective session                                  ║

║                                                                              ║

║  SESSION TYPES:                                                              ║

║  ──────────────                                                              ║

║  • LOCAL SESSION: Session created by this device (always exists after start) ║

║    - Device owns and manages this session                                    ║

║    - localSessionToken always points to this device's session                ║

║    - Represented by localSessionProvider                                     ║

║                                                                              ║

║  • REMOTE SESSION: Session joined by scanning QR code (when secondary)       ║

║    - Device participates in someone else's session                           ║

║    - remoteSessionToken points to joined session (null when primary)         ║

║    - Represented by remoteSessionProvider                                    ║

║                                                                              ║

║  • EFFECTIVE SESSION: The session this device is currently using             ║

║    - remoteSessionToken when secondary, localSessionToken when primary       ║

║    - Represented by firestoreSessionProvider                                 ║

║                                                                              ║

║  ROLES:                                                                      ║

║  ──────                                                                      ║

║  • primary: Using own local session (default when not secondary)             ║

║  • secondary: Using remote session                                           ║

║                                                                              ║

║  FIRESTORE REPOSITORY:                                                       ║

║  ────────────────────                                                        ║

║  • realtimeDatabaseRepositoryProvider provides access to Firebase operations        ║

║  • All session providers use realtimeDb.getSessionDataStream(token)         ║

║  • Primary and secondary devices read from SAME Firebase document when paired║

║  • Session data includes: anchor, position, alarms, monitoring status        ║

║                                                                              ║

║  STATE MANAGEMENT:                                                           ║

║  ─────────────────                                                           ║

║  • pairingSessionStateProvider: Current role and session tokens              ║

║  • sessionToken (computed): Effective session = remote ?? local              ║

║  • Role determines behavior, but effective session always available if tokens║

║    exist                                                                     ║

║                                                                              ║

╚══════════════════════════════════════════════════════════════════════════════╝

*/

// RealtimeDatabaseRepository provider is now in service_providers.dart

final pairingServiceProvider = Provider<PairingService>((ref) {
  return PairingService();
});

// Device role in pairing session (from firestore_session_provider.dart).
enum PairingRole { primary, secondary }

// Provides the current pairing session model (from pairing_provider.dart).
final pairingSessionProvider =
    NotifierProvider<PairingSessionNotifier, PairingSession?>(() {
      return PairingSessionNotifier();
    });

// Notifier for managing the PairingSession model (create/join/end).
class PairingSessionNotifier extends Notifier<PairingSession?> {
  RealtimeDatabaseRepository get _realtimeDb =>
      ref.read(realtimeDatabaseRepositoryProvider);
  PairingService get _pairingService => ref.read(pairingServiceProvider);

  DateTime?
  _lastSessionCreationTime; // Prevent rapid duplicate session creation

  @override
  PairingSession? build() {
    logger.i('PairingSessionNotifier build() called');
    return null;
  }

  Future<String> createSession() async {
    // Prevent rapid duplicate session creation (within 5 seconds)
    final now = DateTime.now();
    if (_lastSessionCreationTime != null &&
        now.difference(_lastSessionCreationTime!).inSeconds < 5) {
      logger.w(
        'Blocking duplicate session creation attempt (too soon after previous creation)',
      );
      throw Exception('Session creation blocked - too frequent attempts');
    }

    logger.i('Creating new pairing session');

    // Log existing sessions count for debugging (keep this as it's useful)
    try {
      final sessionCount = await _realtimeDb.getSessionCount();
      logger.d('Existing sessions count: $sessionCount');
    } catch (e) {
      logger.w('Could not get session count', error: e);
    }

    // Check if we already have a session for this user (using Firebase Auth UID)
    final existingToken = await _realtimeDb.getExistingSessionToken();
    if (existingToken != null) {
      logger.i('Session already exists for current user: $existingToken');

      // Update local state with existing session instead of creating new one
      final existingSession = await _realtimeDb.getSession(existingToken);
      if (existingSession != null &&
          existingSession.isActive &&
          !existingSession.isExpired) {
        state = existingSession;
        logger.i('Using existing active session: $existingToken');

        // Update the creation timestamp to prevent immediate retries
        _lastSessionCreationTime = DateTime.now();
        return existingToken;
      } else {
        // Session exists but is inactive or expired - clean it up and create new one
        logger.w(
          'Found inactive/expired session reference, cleaning up: $existingToken (active: ${existingSession?.isActive}, expired: ${existingSession?.isExpired})',
        );
        try {
          await _realtimeDb.deleteSession(existingToken);
          await _realtimeDb.removeDeviceSession();
        } catch (e) {
          logger.w('Could not clean up stale session', error: e);
        }
      }
    }

    // Clean up any expired sessions before creating a new one
    try {
      await _realtimeDb.deleteExpiredSessions();
      logger.i('🧹 Cleaned up expired sessions before creating new session');
    } catch (e) {
      logger.w('Could not clean up expired sessions', error: e);
      // Continue anyway - this is not critical
    }

    final session = _pairingService.createSession();
    logger.i('Session created locally: ${session.token}');

    try {
      await _realtimeDb.createSession(session);
      logger.i('Session created and saved to Firebase: ${session.token}');
    } catch (e) {
      // Check if this is a quota exceeded error
      if (e.toString().contains('RESOURCE_EXHAUSTED') ||
          e.toString().contains('Quota exceeded')) {
        logger.w('Firebase quota exceeded - cannot create session remotely');
        throw Exception(
          'Firebase quota exceeded. Please check your Firebase Console billing/usage or wait for quota reset.',
        );
      } else {
        logger.w(
          'Failed to create session in Firebase (likely offline), operating in local-only mode',
          error: e,
        );
        // Continue with local-only mode for network errors
      }
    }

    // Always update local state regardless of Firebase success
    try {
      state = session;
      logger.i('Session state updated locally: ${session.token}');
    } catch (e) {
      logger.e('Failed to update local state', error: e);
      rethrow;
    }
    // Record successful session creation time
    _lastSessionCreationTime = DateTime.now();

    logger.i('🔥 Returning token: ${session.token}');
    return session.token;
  }

  Future<void> joinSession(String token) async {
    logger.i(
      '🔐 TOKEN TRACE: PairingSessionNotifier.joinSession called with token: "$token"',
    );
    logger.i(
      '🔐 TOKEN VALIDATION: Validating token format: "$token" (length: ${token.length})',
    );

    if (!_pairingService.isValidTokenFormat(token)) {
      logger.e(
        '🔐 TOKEN VALIDATION FAILED: Token validation failed for: "$token"',
      );
      throw ArgumentError('Invalid session token format');
    }

    logger.i('🔐 TOKEN VALIDATION PASSED: Token format is valid');

    try {
      // FIRST: Check permissions before attempting data access
      logger.i(
        '🔐 PERMISSION PRE-CHECK: Testing access to session "$token" before full retrieval',
      );
      final hasAccess = await _realtimeDb.checkSessionAccess(token);

      if (!hasAccess) {
        logger.e(
          '🔐 PERMISSION PRE-CHECK FAILED: No access to session "$token"',
        );
        throw FirebaseException(
          code: 'permission-denied',
          message: 'Permission denied: Cannot access session $token',
          plugin: 'firebase_database',
        );
      }

      logger.i(
        '🔐 PERMISSION PRE-CHECK PASSED: Access confirmed, proceeding to retrieve session data',
      );
      logger.i(
        '🔐 TOKEN TRACE: Calling _realtimeDb.getSession("$token") - FIRST DATABASE ACCESS',
      );
      final session = await _realtimeDb.getSession(
        token,
      ); // Authentication handled here
      if (session == null) throw StateError('Session not found');
      if (session.isExpired) throw StateError('Session has expired');
      if (!session.isActive) throw StateError('Session is not active');

      final userId = _realtimeDb.getCurrentUserId()!;
      final deviceInfo = DeviceInfo(
        deviceId: userId, // Use Firebase Auth UID
        role: DeviceRole.secondary,
        joinedAt: DateTime.now(),
      );
      await _realtimeDb.addDeviceToSession(token, deviceInfo);

      state = await _realtimeDb.getSession(token);
      logger.i('Joined session: $token');
    } catch (e) {
      logger.e('Failed to join session', error: e);
      rethrow;
    }
  }

  Future<void> endSession() async {
    if (state == null) return;

    try {
      final updatedSession = state!.copyWith(isActive: false);
      await _realtimeDb.updateSession(updatedSession);
      state = null;
      logger.i('Session ended successfully');
    } catch (e) {
      logger.e(
        'Failed to end session in Firebase, but clearing local state',
        error: e,
      );
      // Even if Firebase update fails, clear the local state to prevent the app from being stuck
      state = null;
    }
  }
}

// Provides the current pairing session state and role (from firestore_session_provider.dart).
final pairingSessionStateProvider =
    NotifierProvider<PairingSessionStateNotifier, PairingSessionState>(() {
      return PairingSessionStateNotifier();
    });

// State for pairing session.
class PairingSessionState {
  final PairingRole role;
  final String? localSessionToken;
  final String? remoteSessionToken;
  final String? primaryUserId;

  PairingSessionState({
    required this.role,
    this.localSessionToken,
    this.remoteSessionToken,
    this.primaryUserId,
  });

  String? get sessionToken {
    final token = remoteSessionToken ?? localSessionToken;
    logger.i(
      '🔍 sessionToken getter called: remoteSessionToken=$remoteSessionToken, localSessionToken=$localSessionToken, returning=$token',
    );
    logger.i(
      '📋 Full state in getter: role=$role, localSessionToken=$localSessionToken, remoteSessionToken=$remoteSessionToken',
    );
    return token;
  }

  bool get isPrimary => role == PairingRole.primary;
  bool get isSecondary => role == PairingRole.secondary;
  bool get isPaired => isSecondary;

  PairingSessionState copyWith({
    PairingRole? role,
    String? localSessionToken,
    String? remoteSessionToken,
    String? primaryUserId,
    bool clearLocalSessionToken = false,
    bool clearRemoteSessionToken = false,
    bool clearPrimaryUserId = false,
  }) {
    return PairingSessionState(
      role: role ?? this.role,
      localSessionToken: clearLocalSessionToken
          ? null
          : (localSessionToken ?? this.localSessionToken),
      remoteSessionToken: clearRemoteSessionToken
          ? null
          : (remoteSessionToken ?? this.remoteSessionToken),
      primaryUserId: clearPrimaryUserId
          ? null
          : (primaryUserId ?? this.primaryUserId),
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PairingSessionState &&
        other.role == role &&
        other.localSessionToken == localSessionToken &&
        other.remoteSessionToken == remoteSessionToken &&
        other.primaryUserId == primaryUserId;
  }

  @override
  int get hashCode {
    return Object.hash(
      role,
      localSessionToken,
      remoteSessionToken,
      primaryUserId,
    );
  }

  @override
  String toString() {
    return 'PairingSessionState(role: $role, localSessionToken: $localSessionToken, remoteSessionToken: $remoteSessionToken, primaryUserId: $primaryUserId)';
  }
}

// Notifier for pairing session state management.
class PairingSessionStateNotifier extends Notifier<PairingSessionState> {
  RealtimeDatabaseRepository get _realtimeDb =>
      ref.read(realtimeDatabaseRepositoryProvider);
  bool _postFrameCallbackAdded = false;

  @override
  PairingSessionState build() {
    logger.i(
      'PairingSessionStateNotifier build() called - loading state from storage',
    );

    // Load persisted session data from local storage
    final localStorage = ref.read(localStorageRepositoryProvider);
    final savedToken = localStorage.getMonitoringSessionToken();
    final savedRole = localStorage.getDeviceRole();

    PairingRole role =
        PairingRole.secondary; // Default to secondary (can join sessions)
    if (savedRole != null) {
      role = PairingRole.values.firstWhere(
        (r) => r.name == savedRole,
        orElse: () => PairingRole.secondary,
      );
    }

    final initialState = PairingSessionState(
      role: role,
      localSessionToken: savedToken,
    );

    logger.i(
      'Loaded state from storage: role=${initialState.role}, localSessionToken=${initialState.localSessionToken}',
    );

    // Add a post-frame callback only once to ensure the provider is fully initialized before any auto-create logic runs
    if (!_postFrameCallbackAdded) {
      _postFrameCallbackAdded = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        logger.i(
          'PairingSessionStateNotifier: Post-frame callback - provider should be fully initialized now',
        );
      });
    }

    return initialState;
  }

  Future<String> startPrimarySession() async {
    logger.i('Starting primary session');

    try {
      final pairingNotifier = ref.read(pairingSessionProvider.notifier);

      String token;
      if (state.localSessionToken == null) {
        logger.i('Creating new session');
        token = await pairingNotifier.createSession();
        logger.i('Session created with token: $token');
      } else {
        // Check if the existing session is still active
        final existingSession = await _realtimeDb.getSession(
          state.localSessionToken!,
        );
        if (existingSession != null &&
            existingSession.isActive &&
            !existingSession.isExpired) {
          token = state.localSessionToken!;
          logger.i('Using existing active session token: $token');
        } else {
          logger.i(
            'Existing session is inactive/expired, creating new session',
          );
          token = await pairingNotifier.createSession();
          logger.i('New session created with token: $token');
        }
      }

      // Get the current user's Firebase Auth UID
      final user = _realtimeDb.getCurrentUser();
      if (user == null) {
        throw StateError('User not authenticated');
      }

      // Update state to primary mode with the session token
      state = state.copyWith(
        role: PairingRole.primary,
        localSessionToken: token,
        remoteSessionToken: null,
        primaryUserId: user.uid,
      );

      logger.i('Primary session started successfully with token: $token');
      return token;
    } catch (e) {
      logger.e('Failed to start primary mode', error: e);
      rethrow;
    }
  }

  Future<void> joinSecondarySession(String token) async {
    try {
      // Secondary devices should NOT create primary sessions
      // This logic was incorrect and causing multiple session creation
      logger.i(
        '🎯 TOKEN TRACE: joinSecondarySession called with token: "$token"',
      );
      logger.i('🎯 TOKEN VALIDATION: Token length: ${token.length}');

      final pairingNotifier = ref.read(pairingSessionProvider.notifier);
      logger.i('🎯 TOKEN TRACE: Calling pairingNotifier.joinSession("$token")');
      await pairingNotifier.joinSession(token);

      final session = await _realtimeDb.getSession(token);
      if (session == null) throw StateError('Session not found after joining');

      state = state.copyWith(
        role: PairingRole.secondary,
        remoteSessionToken: token,
        primaryUserId: session.primaryUserId,
      );

      logger.i(
        'Joined as secondary: remote $token (local: ${state.localSessionToken}), primaryUserId: ${session.primaryUserId}',
      );
    } catch (e) {
      logger.e('Failed to join as secondary', error: e);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (state.isPrimary) {
      logger.i('Disconnect called on primary; no action needed');
      return;
    }

    try {
      final alarmNotifier = ref.read(activeAlarmsProvider.notifier);
      if (alarmNotifier.isMonitoring) {
        logger.i('Stopping alarm monitoring due to disconnect');
        alarmNotifier.stopMonitoring();
      }
    } catch (e) {
      logger.w('Failed to stop alarm monitoring during disconnect: $e');
    }

    // Stop session sync monitoring if active
    try {
      await ref
          .read(sessionSyncServiceProvider)
          .stopMonitoringAsync(sessionToken: state.sessionToken);
      logger.i('Stopped session sync monitoring during disconnect');
    } catch (e) {
      logger.w('Failed to stop session sync monitoring during disconnect: $e');
    }

    state = state.copyWith(
      role: PairingRole.primary,
      remoteSessionToken: null,
      primaryUserId: null,
    );

    // Invalidate remote data providers to clear any stale data
    ref.invalidate(remoteSessionProvider);
    ref.invalidate(firestoreSessionProvider);

    logger.i(
      'Disconnected from pairing (switched to primary with local session: ${state.localSessionToken})',
    );
  }

  Future<void> endSession() async {
    logger.i('🏁 PairingSessionStateNotifier.endSession() called');
    if (!state.isPrimary) {
      logger.e('❌ Cannot end session: device is not primary');
      throw StateError('Only primary device can end session');
    }

    try {
      logger.i('🔄 Starting session end process');
      final pairingNotifier = ref.read(pairingSessionProvider.notifier);
      await pairingNotifier.endSession();

      try {
        final alarmNotifier = ref.read(activeAlarmsProvider.notifier);
        if (alarmNotifier.isMonitoring) {
          logger.i('Stopping alarm monitoring due to session end');
          alarmNotifier.stopMonitoring();
        }
      } catch (e) {
        logger.w('Failed to stop alarm monitoring during session end: $e');
      }

      // Stop session sync monitoring
      try {
        await ref
            .read(sessionSyncServiceProvider)
            .stopMonitoringAsync(sessionToken: state.sessionToken);
        logger.i('Stopped session sync monitoring during session end');
      } catch (e) {
        logger.w(
          'Failed to stop session sync monitoring during session end: $e',
        );
      }

      // Clear session data from local storage
      final localStorage = ref.read(localStorageRepositoryProvider);
      await localStorage.saveMonitoringSessionToken(null);
      await localStorage.saveDeviceRole(null);

      final oldState = state;
      final newState = state.copyWith(
        role: PairingRole
            .primary, // Back to primary mode since we're not secondary to anyone
        clearLocalSessionToken: true,
        clearRemoteSessionToken: true,
        clearPrimaryUserId: true,
      );
      logger.i('🔄 About to update state with clear flags');
      logger.i(
        '🔄 Old state: role=${oldState.role}, localToken=${oldState.localSessionToken}, remoteToken=${oldState.remoteSessionToken}, sessionToken=${oldState.sessionToken}',
      );
      logger.i(
        '🔄 New state: role=${newState.role}, localToken=${newState.localSessionToken}, remoteToken=${newState.remoteSessionToken}, sessionToken=${newState.sessionToken}',
      );
      logger.i('🔄 Are states equal? ${oldState == newState}');
      logger.i(
        '🔄 Hash codes: old=${oldState.hashCode}, new=${newState.hashCode}',
      );

      state = newState;

      logger.i('Ended session and cleared local storage');
      logger.i(
        '🔄 State transition: ${oldState.role} -> ${state.role}, token: ${oldState.sessionToken} -> ${state.sessionToken}',
      );
      logger.i('✅ Session ended successfully');
    } catch (e) {
      logger.e('Failed to end session', error: e);
      rethrow;
    }
  }

  /// Sync offline session data to Firebase when connectivity returns
  Future<void> syncOfflineData() async {
    try {
      logger.d('Syncing offline session data to Firebase');
      logger.d(
        'Current state: role=${state.role}, localSessionToken=${state.localSessionToken}, remoteSessionToken=${state.remoteSessionToken}',
      );

      // Only sync if we have a local session that was created manually
      if (state.localSessionToken != null) {
        // The session was created locally, now try to sync it to Firebase
        final pairingNotifier = ref.read(pairingSessionProvider.notifier);
        try {
          await pairingNotifier.createSession();
          logger.i('✅ Offline session data synced successfully');
        } catch (e) {
          logger.w('🔄 Failed to sync session to Firebase', error: e);
        }
      } else {
        logger.i(
          '🔄 No local session to sync (sessions are now created manually in settings)',
        );
      }
    } catch (e) {
      logger.w('Failed to sync offline session data', error: e);
      // Data will remain local until next sync attempt
    }
  }
}

// Stream providers for sessions (from firestore_session_provider.dart).
final localSessionProvider = StreamProvider<Map<String, dynamic>>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);
  if (pairingState.localSessionToken == null) {
    yield {};
    return;
  }
  final firestore = ref.watch(realtimeDatabaseRepositoryProvider);
  yield* firestore.getSessionDataStream(pairingState.localSessionToken!);
});

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

// Pairing session stream provider (from pairing_session_stream_provider.dart).
final pairingSessionStreamProvider = StreamProvider<PairingSession?>((
  ref,
) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (!pairingState.isPrimary || pairingState.sessionToken == null) {
    yield null;
    return;
  }

  final firestore = ref.read(realtimeDatabaseRepositoryProvider);
  yield* firestore.getSessionStream(pairingState.sessionToken!).handleError((
    error,
  ) {
    logger.e('Error in pairing session stream', error: error);
    return null;
  });
});

// Pairing sync provider (from pairing_sync_provider.dart).
final pairingSyncProvider = NotifierProvider<PairingSyncNotifier, void>(() {
  return PairingSyncNotifier();
});

class PairingSyncNotifier extends Notifier<void> {
  @override
  void build() {
    logger.i('PairingSyncNotifier initialized');

    // Check current state and start monitoring if appropriate
    final currentState = ref.read(pairingSessionStateProvider);
    logger.i(
      'PairingSyncNotifier: Checking current state - role=${currentState.role}, sessionToken=${currentState.sessionToken}',
    );
    if (currentState.isPrimary && currentState.sessionToken != null) {
      logger.i(
        'PairingSyncNotifier: Device is already primary with session token, starting monitoring sync',
      );
      try {
        _startMonitoringSync(currentState.sessionToken!);
      } catch (e) {
        logger.e(
          'Failed to start monitoring sync for existing session',
          error: e,
        );
      }
    }

    // Add error boundary for the entire listener
    try {
      ref.listen<PairingSessionState>(
        pairingSessionStateProvider,
        (previous, next) {
          try {
            _handlePairingStateChange(previous, next);
          } catch (e) {
            logger.e('Error handling pairing state change', error: e);
          }
        },
        // Handle errors in the stream itself
        onError: (error, stackTrace) {
          logger.e(
            'Error in pairing session state stream',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
    } catch (e) {
      logger.e('Failed to set up pairing state listener', error: e);
    }
  }

  void _handlePairingStateChange(
    PairingSessionState? previous,
    PairingSessionState next,
  ) {
    logger.i('🔗 Pairing state changed: ${previous?.role} -> ${next.role}');

    if (next.isPrimary &&
        next.sessionToken != null &&
        (previous == null ||
            !previous.isPrimary ||
            previous.sessionToken != next.sessionToken ||
            (previous.sessionToken == null && next.sessionToken != null))) {
      logger.i(
        '🚀 Starting monitoring sync for primary device with token: ${next.sessionToken}',
      );
      try {
        _startMonitoringSync(next.sessionToken!);
      } catch (e) {
        logger.e('Failed to start monitoring sync', error: e);
      }
    } else if (!next.isPrimary && previous?.isPrimary == true) {
      logger.i('🛑 Stopping monitoring service - leaving primary mode');
      Future.microtask(() async {
        try {
          await ref
              .read(sessionSyncServiceProvider)
              .stopMonitoringAsync(sessionToken: previous?.sessionToken);
          logger.i('✅ Monitoring service stopped successfully');
        } catch (e) {
          logger.e('Error stopping monitoring service', error: e);
        }
      });
    } else {
      logger.d('ℹ️ No action needed for pairing state change');
    }
  }

  void _startMonitoringSync(String sessionToken) {
    final sessionSyncService = ref.read(sessionSyncServiceProvider);

    // Create reactive streams that emit when providers change
    final anchorController = StreamController<Anchor?>.broadcast();
    final positionController = StreamController<PositionUpdate?>.broadcast();
    final alarmsController = StreamController<List<AlarmEvent>>.broadcast();

    // Listen to provider changes and emit to streams with error handling
    try {
      ref.listen<Anchor?>(anchorProvider, (previous, next) {
        try {
          anchorController.add(next);
        } catch (e) {
          logger.e('Error adding anchor to stream', error: e);
        }
      }, fireImmediately: true);

      ref.listen<PositionUpdate?>(positionProvider, (previous, next) {
        try {
          positionController.add(next);
        } catch (e) {
          logger.e('Error adding position to stream', error: e);
        }
      }, fireImmediately: true);

      ref.listen<List<AlarmEvent>>(activeAlarmsProvider, (previous, next) {
        try {
          alarmsController.add(next);
        } catch (e) {
          logger.e('Error adding alarms to stream', error: e);
        }
      }, fireImmediately: true);
    } catch (e) {
      logger.e('Error setting up provider listeners', error: e);
      // Clean up on setup failure
      anchorController.close();
      positionController.close();
      alarmsController.close();
      return;
    }

    try {
      sessionSyncService.startMonitoring(
        sessionToken: sessionToken,
        anchorStream: anchorController.stream.distinct(),
        positionStream: positionController.stream.distinct(),
        alarmsStream: alarmsController.stream.distinct(),
        currentAnchor: ref.read(anchorProvider),
        currentPosition: ref.read(positionProvider),
        currentAlarms: ref.read(activeAlarmsProvider),
      );
      logger.i(
        'Successfully started monitoring sync for session: $sessionToken',
      );
    } catch (e) {
      logger.e('Failed to start monitoring sync', error: e);
      // Clean up on failure
      anchorController.close();
      positionController.close();
      alarmsController.close();
      return;
    }

    // Clean up controllers when monitoring stops
    ref.onDispose(() {
      logger.d('Cleaning up monitoring stream controllers');
      anchorController.close();
      positionController.close();
      alarmsController.close();
    });
  }
}
