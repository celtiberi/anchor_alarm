import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:firebase_core/firebase_core.dart';

import '../../models/pairing_session.dart';
import '../../models/device_info.dart';
import '../../services/pairing_service.dart';
import '../../repositories/realtime_database_repository.dart';
import '../../utils/logger_setup.dart';
import '../service_providers.dart';
import 'pairing_providers.dart';

/// Notifier for managing the PairingSession model (create/join/end).
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

