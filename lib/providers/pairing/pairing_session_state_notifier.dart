import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../repositories/realtime_database_repository.dart';
import '../../utils/logger_setup.dart' as state_logger;
import '../service_providers.dart';
import '../alarm_provider.dart';
import '../remote_data_providers.dart';
import 'pairing_providers.dart';

/// Notifier for pairing session state management.
class PairingSessionStateNotifier extends Notifier<PairingSessionState> {
  RealtimeDatabaseRepository get _realtimeDb =>
      ref.read(realtimeDatabaseRepositoryProvider);

  @override
  PairingSessionState build() {
    state_logger.logger.i(
      'PairingSessionStateNotifier build() called - loading state from storage',
    );

    // Load persisted session data from local storage
    final localStorage = ref.read(localStorageRepositoryProvider);
    final savedToken = localStorage.getMonitoringSessionToken();
    final savedRole = localStorage.getDeviceRole();

    PairingRole role =
        PairingRole.primary; // Default to primary (standalone device)
    if (savedRole != null) {
      role = PairingRole.values.firstWhere(
        (r) => r.name == savedRole,
        orElse: () => PairingRole.primary,
      );
    }

    // Check if saved session is expired and delete it if so
    if (savedToken != null) {
      Future.microtask(() async {
        try {
          if (!ref.mounted) return; // Check if still mounted before async operations
          final session = await _realtimeDb.getSession(savedToken);
          if (session != null && session.isExpired) {
            state_logger.logger.w(
              '⚠️ Saved session $savedToken is expired, deleting and clearing local state',
            );
            if (!ref.mounted) return;
            await _realtimeDb.deleteSession(savedToken);
            await localStorage.saveMonitoringSessionToken(null);
            await localStorage.saveDeviceRole(null);
            state_logger.logger.i('✅ Deleted expired session and cleared local state');
          }
        } catch (e) {
          state_logger.logger.e('Failed to delete expired session', error: e);
        }
      });
    }

    // Properly assign saved token based on role:
    // - If primary: token goes to localSessionToken
    // - If secondary: token goes to remoteSessionToken (shouldn't happen on restart, but handle gracefully)
    final initialState = PairingSessionState(
      role: role,
      localSessionToken: role == PairingRole.primary ? savedToken : null,
      remoteSessionToken: role == PairingRole.secondary ? savedToken : null,
    );

    state_logger.logger.i(
      'Loaded state from storage: role=${initialState.role}, localSessionToken=${initialState.localSessionToken}, remoteSessionToken=${initialState.remoteSessionToken}',
    );

    return initialState;
  }

  Future<String> startPrimarySession() async {
    state_logger.logger.i('Starting primary session');

    try {
      final pairingNotifier = ref.read(pairingSessionProvider.notifier);

      String token;
      if (state.localSessionToken == null) {
        state_logger.logger.i('Creating new session');
        token = await pairingNotifier.createSession();
        state_logger.logger.i('Session created with token: $token');
      } else {
        // Check if the existing session is still active
        final existingSession = await _realtimeDb.getSession(
          state.localSessionToken!,
        );
        if (existingSession != null &&
            existingSession.isActive &&
            !existingSession.isExpired) {
          token = state.localSessionToken!;
          state_logger.logger.i('Using existing active session token: $token');
        } else {
          state_logger.logger.i(
            'Existing session is inactive/expired, deleting and creating new session',
          );
          // Delete expired/inactive session
          if (existingSession != null) {
            try {
              await _realtimeDb.deleteSession(state.localSessionToken!);
              state_logger.logger.i('✅ Deleted expired/inactive session: ${state.localSessionToken}');
            } catch (e) {
              state_logger.logger.w('Could not delete expired session', error: e);
            }
          }
          token = await pairingNotifier.createSession();
          state_logger.logger.i('New session created with token: $token');
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

      // Persist to local storage
      final localStorage = ref.read(localStorageRepositoryProvider);
      await localStorage.saveMonitoringSessionToken(token);
      await localStorage.saveDeviceRole(PairingRole.primary.name);
      state_logger.logger.i('Persisted primary session to local storage: $token');

      state_logger.logger.i('Primary session started successfully with token: $token');
      return token;
    } catch (e) {
      state_logger.logger.e('Failed to start primary mode', error: e);
      rethrow;
    }
  }

  Future<void> joinSecondarySession(String token) async {
    try {
      // Secondary devices should NOT create primary sessions
      // This logic was incorrect and causing multiple session creation
      state_logger.logger.i(
        '🎯 TOKEN TRACE: joinSecondarySession called with token: "$token"',
      );
      state_logger.logger.i('🎯 TOKEN VALIDATION: Token length: ${token.length}');

      final pairingNotifier = ref.read(pairingSessionProvider.notifier);
      state_logger.logger.i('🎯 TOKEN TRACE: Calling pairingNotifier.joinSession("$token")');
      await pairingNotifier.joinSession(token);

      final session = await _realtimeDb.getSession(token);
      if (session == null) throw StateError('Session not found after joining');

      state_logger.logger.i('🎯 About to update state to secondary');
      state_logger.logger.i('🎯 Current state before update: role=${state.role}, sessionToken=${state.sessionToken}');

      // Update state directly
      state = state.copyWith(
        role: PairingRole.secondary,
        clearLocalSessionToken: true,
        remoteSessionToken: token,
        primaryUserId: session.primaryUserId,
      );

      state_logger.logger.i('🎯 State updated directly: role=${state.role}, sessionToken=${state.sessionToken}');
      state_logger.logger.i('🎯 Persisting to local storage');
      await _persistSecondarySession(token);
      state_logger.logger.i('🎯 Invalidating providers');
      _invalidateSessionProviders();

      state_logger.logger.i(
        'Joined as secondary: remote $token (local cleared), primaryUserId: ${session.primaryUserId}',
      );
      state_logger.logger.i(
        '🎯 FINAL STATE: role=${state.role}, sessionToken=${state.sessionToken}, isSecondary=${state.isSecondary}',
      );
    } catch (e) {
      state_logger.logger.e('Failed to join as secondary', error: e);
      rethrow;
    }
  }

  Future<void> disconnect() async {
    if (state.isPrimary) {
      state_logger.logger.i('Disconnect called on primary; no action needed');
      return;
    }

    try {
      await _stopMonitoringServices();
      await _removeDeviceFromFirebase();
      await _clearLocalSessionData();
      await _updateStateToPrimary();
      _invalidateSessionProviders();

      state_logger.logger.i(
        '🔌 DISCONNECT: Completed disconnect (cleared all session data from storage and state, now unpaired primary device)',
      );
    } catch (e) {
      state_logger.logger.e('Failed to disconnect', error: e);
      rethrow;
    }
  }

  Future<void> endSession() async {
    state_logger.logger.i('🏁 PairingSessionStateNotifier.endSession() called');
    if (!state.isPrimary) {
      state_logger.logger.e('❌ Cannot end session: device is not primary');
      throw StateError('Only primary device can end session');
    }

    try {
      state_logger.logger.i('🔄 Starting session end process');
      final pairingNotifier = ref.read(pairingSessionProvider.notifier);
      await pairingNotifier.endSession();
      await _stopMonitoringServices();
      await _clearLocalSessionData();
      await _updateStateToPrimary();
      state_logger.logger.i('✅ Session ended successfully');
    } catch (e) {
      state_logger.logger.e('Failed to end session', error: e);
      rethrow;
    }
  }

  /// Sync offline session data to Firebase when connectivity returns
  /// Note: Sessions are created on-demand, so this primarily handles edge cases
  /// where a session was created offline and needs to be synced to Firebase
  Future<void> syncOfflineData() async {
    try {
      state_logger.logger.d('Syncing offline session data to Firebase');
      state_logger.logger.d(
        'Current state: role=${state.role}, localSessionToken=${state.localSessionToken}, remoteSessionToken=${state.remoteSessionToken}',
      );

      // Only sync if we have a local session (primary device with active session)
      if (state.isPrimary && state.localSessionToken != null) {
        // The session was created locally, now try to sync it to Firebase
        final pairingNotifier = ref.read(pairingSessionProvider.notifier);
        try {
          await pairingNotifier.createSession();
          state_logger.logger.i('✅ Offline session data synced successfully');
        } catch (e) {
          state_logger.logger.w('🔄 Failed to sync session to Firebase', error: e);
        }
      } else {
        state_logger.logger.i(
          '🔄 No local session to sync (role=${state.role}, localToken=${state.localSessionToken != null ? "exists" : "null"})',
        );
      }
    } catch (e) {
      state_logger.logger.w('Failed to sync offline session data', error: e);
      // Data will remain local until next sync attempt
    }
  }


  Future<void> _persistSecondarySession(String token) async {
    // Persist to local storage
    final localStorage = ref.read(localStorageRepositoryProvider);
    await localStorage.saveMonitoringSessionToken(token);
    await localStorage.saveDeviceRole(PairingRole.secondary.name);
    state_logger.logger.i('Persisted secondary session to local storage: $token');
  }

  Future<void> _stopMonitoringServices() async {
    // Stop alarm monitoring if active
    try {
      final alarmNotifier = ref.read(activeAlarmsProvider.notifier);
      if (alarmNotifier.isMonitoring) {
        state_logger.logger.i('Stopping alarm monitoring');
        alarmNotifier.stopMonitoring();
      }
    } catch (e) {
      state_logger.logger.w('Failed to stop alarm monitoring: $e');
    }

    // Stop session sync monitoring if active
    try {
      await ref
          .read(sessionSyncServiceProvider)
          .stopMonitoringAsync(sessionToken: state.sessionToken);
      state_logger.logger.i('Stopped session sync monitoring');
    } catch (e) {
      state_logger.logger.w('Failed to stop session sync monitoring: $e');
    }
  }

  Future<void> _removeDeviceFromFirebase() async {
    // Remove this device from the Firebase session
    final sessionToken = state.remoteSessionToken;
    if (sessionToken != null) {
      try {
        final userId = _realtimeDb.getCurrentUserId();
        if (userId != null) {
          await _realtimeDb.removeDeviceFromSession(sessionToken, userId);
          state_logger.logger.i('Removed device from Firebase session');
        }
      } catch (e) {
        state_logger.logger.w('Failed to remove device from Firebase session', error: e);
        // Continue with disconnect even if Firebase removal fails
      }
    }
  }

  Future<void> _clearLocalSessionData() async {
    // Clear session data from local storage
    final localStorage = ref.read(localStorageRepositoryProvider);
    await localStorage.saveMonitoringSessionToken(null);
    await localStorage.saveDeviceRole(null);
    state_logger.logger.i('Cleared local session data');
  }

  Future<void> _updateStateToPrimary() async {
    final oldState = state;
    state = state.copyWith(
      role: PairingRole.primary,
      clearLocalSessionToken: true,
      clearRemoteSessionToken: true,
      clearPrimaryUserId: true,
    );
    state_logger.logger.i(
      'Updated state to primary: ${oldState.role} -> ${state.role}, token: ${oldState.sessionToken} -> ${state.sessionToken}',
    );
  }

  void _invalidateSessionProviders() {
    // Invalidate all session-related providers to clear any stale data
    // Note: remoteSessionDataProvider is autoDispose and watches pairingSessionStateProvider,
    // so it will automatically rebuild when state changes - no need to invalidate it
    ref.invalidate(pairingSessionProvider);
    ref.invalidate(pairingSessionStreamProvider);
    ref.invalidate(localSessionProvider);

    // Only invalidate remoteAlarmProvider since it's not autoDispose
    // remoteSessionDataProvider will automatically rebuild when pairingSessionStateProvider changes
    Future.microtask(() {
      try {
        if (!ref.mounted) return; // Check if still mounted before invalidation
        ref.invalidate(remoteAlarmProvider); // Separate alarm stream (not autoDispose)
      } catch (e) {
        // Provider may have been disposed, ignore
        state_logger.logger.d('Could not invalidate remote alarm provider (may be disposed): $e');
      }
    });
    // Note: remoteSessionDataProvider, remoteAnchorProvider, remotePositionProvider, etc.
    // are autoDispose and will rebuild automatically when pairingSessionStateProvider changes
  }
}







