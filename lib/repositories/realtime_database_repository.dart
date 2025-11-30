import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/position_update.dart';
import '../models/alarm_event.dart';
import '../models/pairing_session.dart';
import '../models/device_info.dart';
import '../utils/logger_setup.dart';
import '../firebase_options.dart';

/// Repository for Firebase Realtime Database operations.
/// Migrated from Firestore to reduce costs and optimize for real-time sync.
class RealtimeDatabaseRepository {
  final DatabaseReference _db;
  final FirebaseDatabase _databaseInstance;
  final FirebaseAuth _auth;

  RealtimeDatabaseRepository({DatabaseReference? db, FirebaseAuth? auth})
    : _databaseInstance = FirebaseDatabase.instanceFor(
        // Explicitly specify the app and databaseURL
        app: Firebase.app(),
        databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
      ),
      _db =
          db ??
          FirebaseDatabase.instanceFor(
            // Do the same for the DatabaseReference's underlying instance
            app: Firebase.app(),
            databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
          ).ref(),
      _auth = auth ?? FirebaseAuth.instance {
    logger.i(
      'RealtimeDatabaseRepository created with ${auth != null ? "provided auth" : "default auth"}',
    );
    logger.i(
      'RTDB Database URL configured (from options): ${DefaultFirebaseOptions.currentPlatform.databaseURL}',
    );
    logger.i(
      'Database instance URL (_databaseInstance.databaseURL): ${_databaseInstance.databaseURL}',
    ); // Keep logging for diagnostic purposes
    logger.i('Database reference path (_db.path): ${_db.path}');
  }

  /// Initialize RTDB with offline persistence
  void init() {
    // Configure persistence on the database instance
    _databaseInstance.setPersistenceEnabled(true);
    _databaseInstance.setPersistenceCacheSizeBytes(10000000); // 10MB
    logger.i('RealtimeDatabase persistence enabled with 10MB cache');
    logger.i('Database instance URL: ${_databaseInstance.databaseURL}');
    logger.i('Firebase app databaseURL: ${Firebase.app().options.databaseURL}');
  }

  /// Helper to ensure authenticated state
  Future<void> ensureAuthenticated() async {
    if (_auth.currentUser != null) {
      logger.i('Already authenticated: ${_auth.currentUser!.uid}');
      return;
    }

    logger.w('No authenticated user, attempting anonymous sign-in...');
    try {
      final credential = await _auth.signInAnonymously();
      logger.i('Signed in anonymously: ${credential.user?.uid}');

      // Wait for token refresh and state sync
      await credential.user?.getIdToken(true); // Force token refresh
      await _auth.authStateChanges().firstWhere(
        (user) => user != null,
        orElse: () => throw StateError('Auth state sync failed'),
      );
      logger.i('Auth token refreshed and state confirmed');
    } catch (authError) {
      logger.e(
        'Failed to authenticate: ${authError.toString()}',
        error: authError,
      );
      if (authError is FirebaseAuthException) {
        logger.e(
          'Error code: ${authError.code}, Message: ${authError.message}',
        );
      }
      rethrow;
    }
  }

  /// Creates a new pairing session.
  Future<void> createSession(PairingSession session) async {
    await ensureAuthenticated();
    final userId = _auth.currentUser!.uid;

    // Set the primary device ID and update the first device to use the auth UID
    final primaryDevice = session.devices.first.copyWith(deviceId: userId);
    final updatedSession = session.copyWith(
      primaryUserId: userId,
      devices: [primaryDevice],
    );

    logger.i('🔥 RTDB WRITE: Creating session ${updatedSession.token}');
    logger.i(
      '🔥 RTDB DETAILS: primaryUserId=${updatedSession.primaryUserId}, token=${updatedSession.token}',
    );
    final writeStart = DateTime.now();
    try {
      await _db
          .child('sessions/${updatedSession.token}')
          .set(updatedSession.toMap());
      final writeDuration = DateTime.now().difference(writeStart);
      logger.i(
        '✅ RTDB WRITE SUCCESS: Session ${updatedSession.token} created in ${writeDuration.inMilliseconds}ms',
      );
    } catch (e) {
      logger.e(
        '❌ RTDB WRITE FAILED: Session creation failed after ${DateTime.now().difference(writeStart).inMilliseconds}ms',
        error: e,
      );
      rethrow;
    }
  }

  /// Utility to wrap operations with authentication retry on permission-denied errors
  Future<T> withAuthRetry<T>(
    Future<T> Function() operation, {
    int maxRetries = 2,
  }) async {
    int attempts = 0;

    while (attempts <= maxRetries) {
      try {
        await ensureAuthenticated();
        return await operation();
      } catch (e) {
        attempts++;
        if (e is FirebaseException &&
            e.code == 'permission-denied' &&
            attempts <= maxRetries) {
          logger.w(
            'Permission denied - retrying after auth refresh (attempt $attempts/$maxRetries)',
          );
          await _auth.currentUser?.reload();
          await Future.delayed(const Duration(seconds: 2));
          // Continue to next iteration for retry
        } else {
          // Either not a permission-denied error, or we've exceeded max retries
          rethrow;
        }
      }
    }

    // This should never be reached, but just in case
    throw StateError('withAuthRetry exceeded maximum retries');
  }

  /// Checks if user has permission to access a session token (lightweight permission check).
  Future<bool> checkSessionAccess(String token) async {
    return await withAuthRetry(() async {
      logger.i('🔐 PERMISSION CHECK: Testing access to session $token');

      // Basic validation first
      if (token.length != 32 || !RegExp(r'^[A-Z0-9]+$').hasMatch(token)) {
        logger.i('🔐 PERMISSION CHECK: FAILED - Invalid token format');
        return false;
      }

      logger.i('🔐 PERMISSION CHECK: Authentication confirmed');

      // Try to access just the session metadata (shallow check)
      // Use a query that will fail fast if permissions are denied
      final testRef = _db.child('sessions/$token');
      logger.i(
        '🔐 PERMISSION CHECK: Attempting lightweight access to sessions/$token',
      );

      // Try to read the session directly to check permissions
      final testSnapshot = await testRef.get();

      logger.i('🔐 PERMISSION CHECK: SUCCESS - Can access session path');
      logger.i('🔐 PERMISSION CHECK: Session exists: ${testSnapshot.exists}');
      return true;
    });
  }

  /// Gets a pairing session by token.
  Future<PairingSession?> getSession(String token) async {
    return await withAuthRetry(() async {
      // Log detailed information about the data access attempt
      logger.i(
        '🔍 FIRST DATA ACCESS ATTEMPT - Secondary device joining session',
      );
      logger.i('🔍 TOKEN VALIDATION: Token received: "$token"');
      logger.i('🔍 TOKEN VALIDATION: Token length: ${token.length}');
      logger.i(
        '🔍 TOKEN VALIDATION: Token is uppercase alphanumeric: ${RegExp(r'^[A-Z0-9]+$').hasMatch(token)}',
      );
      logger.i(
        '🔍 TOKEN VALIDATION: Token is exactly 32 chars: ${token.length == 32}',
      );

      logger.i(
        '🔍 Database URL: ${DefaultFirebaseOptions.currentPlatform.databaseURL}',
      );
      logger.i('🔍 Target path: sessions/$token');
      logger.i(
        '🔍 Full Firebase URL: ${DefaultFirebaseOptions.currentPlatform.databaseURL}/sessions/$token.json',
      );
      logger.i('🔍 Auth current user: ${_auth.currentUser}');
      logger.i('🔍 Auth UID: ${_auth.currentUser?.uid}');
      logger.i('🔍 Auth isAnonymous: ${_auth.currentUser?.isAnonymous}');
      logger.i('🔍 Firebase app name: ${_auth.app.name}');
      logger.i(
        '🔍 Expected permission check: auth != null (rules allow read: true for all sessions)',
      );

      // Final token validation before database access
      if (token.length != 32 || !RegExp(r'^[A-Z0-9]+$').hasMatch(token)) {
        logger.e(
          '🔍 TOKEN VALIDATION FAILED: Invalid token format before database access',
        );
        throw ArgumentError(
          'Invalid session token format: must be 32 uppercase alphanumeric characters',
        );
      }
      logger.i(
        '🔍 TOKEN VALIDATION CONFIRMED: Token format is valid for database access',
      );

      // PRE-ACCESS PERMISSION CHECK
      logger.i('🔍 Running pre-access permission check...');
      final hasAccess = await checkSessionAccess(token);
      if (!hasAccess) {
        logger.e(
          '🔍 PERMISSION CHECK FAILED: No access to session $token before data retrieval',
        );
        throw FirebaseException(
          code: 'permission-denied',
          message: 'Permission denied: Cannot access session $token',
          plugin: 'firebase_database',
        );
      }
      logger.i(
        '🔍 PERMISSION CHECK PASSED: Access confirmed for session $token',
      );

      logger.i('🔍 Authentication confirmed - UID: ${_auth.currentUser?.uid}');

      logger.i(
        '🔍 Executing database query: _db.child(\'sessions/$token\').get()',
      );
      final requestStartTime = DateTime.now();
      final snapshot = await _db.child('sessions/$token').get();
      final requestDuration = DateTime.now().difference(requestStartTime);

      logger.i(
        '🔍 Database query completed in ${requestDuration.inMilliseconds}ms',
      );
      logger.i('🔍 Snapshot exists: ${snapshot.exists}');
      logger.i('🔍 Snapshot path: ${snapshot.ref.path}');
      logger.i('🔍 Snapshot key: ${snapshot.key}');

      if (!snapshot.exists) {
        logger.w(
          '🔍 Session $token does not exist - this will cause permission-denied if rules require session to exist',
        );
        return null;
      }

      logger.i('🔍 Session exists! Processing data...');
      final rawData = snapshot.value as Map<Object?, Object?>;
      logger.i('🔍 Raw data keys: ${rawData.keys.toList()}');
      logger.i(
        '🔍 Raw data sample: ${rawData.length > 5 ? '{...${rawData.length} fields...}' : rawData}',
      );

      final data = rawData.map((key, value) => MapEntry(key.toString(), value));
      final session = PairingSession.fromMap(data, token);

      logger.i(
        '🔍 Successfully parsed session: ${session.token}, primaryUserId: ${session.primaryUserId}',
      );
      return session;
    });
  }

  /// Checks if a session already exists for the current user.
  Future<String?> getExistingSessionToken() async {
    final userId = _auth.currentUser!.uid;
    logger.i('🔍 Checking for existing session for user: $userId');
    try {
      // RTDB doesn't support queries, so we need to check via a reverse lookup
      final sessionSnapshot = await _db.child('deviceSessions/$userId').get();
      if (sessionSnapshot.exists) {
        final token = sessionSnapshot.value as String;
        logger.i('✅ Found existing session for user $userId: $token');
        return token;
      }
      logger.i('ℹ️ No existing session found for user: $userId');
      return null;
    } catch (e) {
      logger.w('Could not check for existing sessions', error: e);
      return null;
    }
  }

  /// Gets count of all sessions for debugging purposes.
  Future<int> getSessionCount() async {
    try {
      final snapshot = await _db.child('sessions').get();
      if (!snapshot.exists) return 0;
      final rawSessions = snapshot.value as Map<Object?, Object?>;
      final sessions = rawSessions.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      return sessions.length;
    } catch (e) {
      logger.w('Could not get session count', error: e);
      return -1;
    }
  }

  /// Stream of pairing session updates (for real-time device list).
  Stream<PairingSession> getSessionStream(String token) {
    // Ensure authentication before streaming
    if (_auth.currentUser == null) {
      logger.w(
        'No authenticated user for session stream, attempting sign-in...',
      );
      // Note: This is async but we can't await in a stream constructor
      // The caller should ensure authentication before calling this
    }

    return _db.child('sessions/$token').onValue.map((event) {
      if (!event.snapshot.exists) {
        throw StateError('Session $token not found');
      }
      final rawData = event.snapshot.value as Map<Object?, Object?>;
      final data = rawData.map((key, value) => MapEntry(key.toString(), value));
      return PairingSession.fromMap(data, token);
    });
  }

  /// Updates a pairing session.
  Future<void> updateSession(PairingSession session) async {
    // Validate session data before updating
    if (session.primaryUserId.isEmpty) {
      logger.e('❌ Cannot update session: primaryUserId is empty');
      throw StateError('Session has invalid primaryUserId');
    }

    // Check that all device IDs are valid
    for (final device in session.devices) {
      if (device.deviceId.isEmpty) {
        logger.e('❌ Cannot update session: device has empty deviceId');
        throw StateError('Session has device with invalid deviceId');
      }
    }

    logger.i('🔥 RTDB WRITE: Updating session ${session.token}');
    logger.i(
      '🔥 RTDB DETAILS: primaryUserId=${session.primaryUserId}, deviceCount=${session.devices.length}',
    );
    final writeStart = DateTime.now();
    try {
      await _db.child('sessions/${session.token}').update(session.toMap());
      final writeDuration = DateTime.now().difference(writeStart);
      logger.i(
        '✅ RTDB WRITE SUCCESS: Session ${session.token} updated in ${writeDuration.inMilliseconds}ms',
      );
    } catch (e) {
      logger.e(
        '❌ RTDB WRITE FAILED: Session update failed after ${DateTime.now().difference(writeStart).inMilliseconds}ms',
        error: e,
      );
      rethrow;
    }
  }

  /// Adds a device to a session.
  Future<void> addDeviceToSession(String token, DeviceInfo device) async {
    await ensureAuthenticated();
    logger.i(
      '🔥 RTDB WRITE: Adding device ${device.deviceId} to session $token',
    );

    // Write directly to the devices sub-path to avoid permission issues
    final writeStart = DateTime.now();
    try {
      await _db
          .child('sessions/$token/devices/${device.deviceId}')
          .set(device.toMap());
      final writeDuration = DateTime.now().difference(writeStart);
      logger.i(
        '✅ RTDB WRITE SUCCESS: Device ${device.deviceId} added to session $token in ${writeDuration.inMilliseconds}ms',
      );
    } catch (e) {
      logger.e(
        '❌ RTDB WRITE FAILED: Failed to add device ${device.deviceId} to session $token after ${DateTime.now().difference(writeStart).inMilliseconds}ms',
        error: e,
      );
      rethrow;
    }

    // Also update the reverse lookup for the device using its UID
    try {
      await _db.child('deviceSessions/${device.deviceId}').set(token);
      logger.i(
        '✅ RTDB WRITE SUCCESS: Device session lookup updated for ${device.deviceId}',
      );
    } catch (e) {
      logger.w(
        '⚠️ Failed to update device session lookup for ${device.deviceId}',
        error: e,
      );
      // Don't rethrow - this is not critical
    }
  }

  /// Stream of position updates (latest position only).
  Stream<PositionUpdate> getPositionStream(String sessionToken) {
    return _db.child('sessions/$sessionToken/latestPosition').onValue.map((
      event,
    ) {
      if (!event.snapshot.exists) {
        throw StateError('No position found in session $sessionToken');
      }
      final rawData = event.snapshot.value as Map<Object?, Object?>;
      final data = rawData.map((key, value) => MapEntry(key.toString(), value));
      return PositionUpdate.fromMap(data);
    });
  }

  /// Pushes a position update to RTDB (overwrites latestPosition).
  Future<void> pushPosition(
    String sessionToken,
    PositionUpdate position,
  ) async {
    logger.i('🔥 RTDB WRITE: Pushing position update to session $sessionToken');
    logger.i(
      '🔥 RTDB DETAILS: lat=${position.latitude.toStringAsFixed(6)}, lng=${position.longitude.toStringAsFixed(6)}, accuracy=${position.accuracy?.toStringAsFixed(1)}m',
    );
    final writeStart = DateTime.now();
    try {
      await _db
          .child('sessions/$sessionToken/latestPosition')
          .set(position.toMap());
      final writeDuration = DateTime.now().difference(writeStart);
      logger.i(
        '✅ RTDB WRITE SUCCESS: Position pushed to $sessionToken in ${writeDuration.inMilliseconds}ms',
      );
    } catch (e) {
      logger.e(
        '❌ RTDB WRITE FAILED: Position push failed after ${DateTime.now().difference(writeStart).inMilliseconds}ms',
        error: e,
      );
      rethrow;
    }
  }

  /// Stream of active alarms for a session.
  Stream<List<AlarmEvent>> getAlarmsStream(String sessionToken) {
    return _db.child('sessions/$sessionToken/alarms').onValue.map((event) {
      if (!event.snapshot.exists) {
        return <AlarmEvent>[];
      }

      final rawAlarmsMap = event.snapshot.value as Map<Object?, Object?>;
      final alarmsMap = rawAlarmsMap.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final alarms = alarmsMap.entries.map((entry) {
        final rawAlarmData = entry.value as Map<Object?, Object?>;
        final alarmData = rawAlarmData.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        return AlarmEvent.fromMap(alarmData, entry.key);
      }).toList();

      // Sort by timestamp (most recent first)
      alarms.sort((a, b) => b.timestamp.compareTo(a.timestamp));
      return alarms;
    });
  }

  /// Creates an alarm event in RTDB.
  Future<void> createAlarm(String sessionToken, AlarmEvent alarm) async {
    logger.i(
      '🔥 RTDB WRITE: Creating alarm ${alarm.id} in session $sessionToken',
    );
    logger.i(
      '🔥 RTDB DETAILS: type=${alarm.type}, severity=${alarm.severity}, distance=${alarm.distanceFromAnchor.toStringAsFixed(1)}m',
    );
    final writeStart = DateTime.now();
    try {
      await _db
          .child('sessions/$sessionToken/alarms/${alarm.id}')
          .set(alarm.toMap());
      final writeDuration = DateTime.now().difference(writeStart);
      logger.i(
        '✅ RTDB WRITE SUCCESS: Alarm ${alarm.id} created in $sessionToken in ${writeDuration.inMilliseconds}ms',
      );
    } catch (e) {
      logger.e(
        '❌ RTDB WRITE FAILED: Alarm creation failed after ${DateTime.now().difference(writeStart).inMilliseconds}ms',
        error: e,
      );
      rethrow;
    }
  }

  /// Acknowledges an alarm (removes it from RTDB).
  Future<void> acknowledgeAlarm(String sessionToken, String alarmId) async {
    logger.i(
      '🔥 RTDB DELETE: Acknowledging alarm $alarmId in session $sessionToken',
    );
    final writeStart = DateTime.now();
    try {
      await _db.child('sessions/$sessionToken/alarms/$alarmId').remove();
      final writeDuration = DateTime.now().difference(writeStart);
      logger.i(
        '✅ RTDB DELETE SUCCESS: Alarm $alarmId acknowledged in $sessionToken in ${writeDuration.inMilliseconds}ms',
      );
    } catch (e) {
      logger.e(
        '❌ RTDB DELETE FAILED: Alarm acknowledgment failed after ${DateTime.now().difference(writeStart).inMilliseconds}ms',
        error: e,
      );
      rethrow;
    }
  }

  /// Updates session data (anchor, boatPosition, etc.) for monitoring.
  Future<void> updateSessionData(
    String sessionToken,
    Map<String, dynamic> data,
  ) async {
    await ensureAuthenticated();
    logger.i('🔧 Updating session $sessionToken with data: $data');
    try {
      await _db.child('sessions/$sessionToken').update(data);
      logger.i('✅ Successfully updated session $sessionToken');
    } catch (e) {
      logger.e(
        '❌ Failed to update session $sessionToken with data $data',
        error: e,
      );
      rethrow;
    }
  }

  /// Gets session data for monitoring (anchor, boatPosition, alarms, positionHistory).
  Future<Map<String, dynamic>?> getSessionData(String sessionToken) async {
    try {
      final snapshot = await _db.child('sessions/$sessionToken').get();
      if (!snapshot.exists) {
        return null;
      }
      final rawData = snapshot.value as Map<Object?, Object?>;
      return rawData.map((key, value) => MapEntry(key.toString(), value));
    } catch (e) {
      logger.e('❌ Failed to get session data for $sessionToken', error: e);
      return null;
    }
  }

  /// Helper method to recursively convert Map<Object?, Object?> to Map<String, dynamic>
  Map<String, dynamic> _convertToStringDynamicMap(
    Map<Object?, Object?> rawData,
  ) {
    try {
      return rawData.map((key, value) {
        final stringKey = key.toString();
        if (value is Map<Object?, Object?>) {
          return MapEntry(stringKey, _convertToStringDynamicMap(value));
        } else if (value is List<Object?>) {
          final convertedList = value.map((item) {
            if (item is Map<Object?, Object?>) {
              return _convertToStringDynamicMap(item);
            }
            return item;
          }).toList();
          return MapEntry(stringKey, convertedList);
        } else {
          return MapEntry(stringKey, value);
        }
      });
    } catch (e) {
      logger.e('Failed to convert RTDB map data', error: e);
      // Return empty map as fallback to prevent app crashes
      return {};
    }
  }

  /// Stream of session data for monitoring (for secondary devices).
  Stream<Map<String, dynamic>> getSessionDataStream(String sessionToken) {
    return _db.child('sessions/$sessionToken').onValue.map((event) {
      if (!event.snapshot.exists) {
        throw StateError('Session $sessionToken not found');
      }
      final rawData = event.snapshot.value as Map<Object?, Object?>;
      return _convertToStringDynamicMap(rawData);
    });
  }

  /// Removes the device session reference for the current user.
  Future<void> removeDeviceSession() async {
    final userId = _auth.currentUser!.uid;
    try {
      await _db.child('deviceSessions/$userId').remove();
      logger.i('🗑️ Removed device session reference for user: $userId');
    } catch (e) {
      logger.w('Could not remove device session reference', error: e);
    }
  }

  /// Deletes a specific session by token.
  Future<void> deleteSession(String token) async {
    try {
      await _db.child('sessions/$token').remove();
      logger.i('🗑️ Deleted session: $token');
    } catch (e) {
      logger.w('Could not delete session $token', error: e);
      rethrow;
    }
  }

  /// Deletes expired sessions (cleanup).
  Future<void> deleteExpiredSessions() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      final sessionsSnapshot = await _db.child('sessions').get();
      if (!sessionsSnapshot.exists) return;

      final rawSessions = sessionsSnapshot.value as Map<Object?, Object?>;
      final sessions = rawSessions.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final expiredTokens = <String>[];

      for (final entry in sessions.entries) {
        final rawSessionData = entry.value as Map<Object?, Object?>;
        final sessionData = rawSessionData.map(
          (key, value) => MapEntry(key.toString(), value),
        );
        final expiresAt = sessionData['expiresAt'] as int;
        if (expiresAt < now) {
          expiredTokens.add(entry.key);
        }
      }

      // Delete expired sessions
      for (final token in expiredTokens) {
        await _db.child('sessions/$token').remove();
        logger.i('🗑️ Deleted expired session: $token');
      }

      logger.i(
        '✅ Cleanup complete: ${expiredTokens.length} expired sessions removed',
      );
    } catch (e) {
      logger.w('Could not delete expired sessions', error: e);
    }
  }

  /// Get current user ID (for security rules)
  User? getCurrentUser() {
    return _auth.currentUser;
  }

  String? getCurrentUserId() {
    return _auth.currentUser?.uid;
  }

  /// Sign in anonymously (required for RTDB access)
  Future<void> signInAnonymously() async {
    try {
      await _auth.signInAnonymously();
      logger.i('✅ Signed in anonymously for RTDB access');
    } catch (e) {
      logger.e('❌ Failed to sign in anonymously', error: e);
      rethrow;
    }
  }
}
