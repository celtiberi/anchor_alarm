import 'package:firebase_database/firebase_database.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import '../models/alarm_event.dart';
import '../models/pairing_session.dart';
import '../models/device_info.dart';
import '../utils/logger_setup.dart';
import '../firebase_options.dart';
import '../services/bandwidth_tracker.dart';

/// Repository for Firebase Realtime Database operations.
/// Migrated from Firestore to reduce costs and optimize for real-time sync.
class RealtimeDatabaseRepository {
  /// Cached database instance with persistence already configured.
  /// This ensures persistence is set only once, before any database operations.
  static FirebaseDatabase? _cachedInstance;

  /// Gets or creates a FirebaseDatabase instance with persistence enabled.
  /// Must be called before any other database operations.
  /// This is a static method to ensure persistence is set before any database access.
  static FirebaseDatabase _getDatabaseInstance() {
    if (_cachedInstance != null) {
      logger.i('🔧 Using cached FirebaseDatabase instance');
      return _cachedInstance!;
    }

    print('🔧🔧🔧 RTDB REPO: Creating FirebaseDatabase instance');
    print(
      '🔧🔧🔧 RTDB REPO: Available Firebase apps: ${Firebase.apps.length} total',
    );
    print(
      '🔧🔧🔧 RTDB REPO: Firebase apps: ${Firebase.apps.map((app) => '${app.name} (${app.options.projectId})').join(', ')}',
    );

    if (Firebase.apps.isEmpty) {
      throw StateError('No Firebase apps available - Firebase not initialized');
    }

    // Always use the app with the correct project ID
    final targetProjectId = DefaultFirebaseOptions.currentPlatform.projectId;
    final app = Firebase.apps.firstWhere(
      (app) => app.options.projectId == targetProjectId,
      orElse: () => throw StateError(
        'Firebase app with project ID $targetProjectId not found. Available apps: ${Firebase.apps.map((app) => app.options.projectId).join(', ')}',
      ),
    );

    print(
      '🔧🔧🔧 RTDB REPO: Using Firebase app: ${app.name} with projectId: ${app.options.projectId}',
    );
    print(
      '🔧🔧🔧 RTDB REPO: Target database URL: ${DefaultFirebaseOptions.currentPlatform.databaseURL}',
    );
    print('🔧🔧🔧 RTDB REPO: App database URL: ${app.options.databaseURL}');

    logger.i(
      '🔧 Using Firebase app: ${app.name} with projectId: ${app.options.projectId}',
    );
    logger.i(
      '🔧 Target database URL: ${DefaultFirebaseOptions.currentPlatform.databaseURL}',
    );
    logger.i('🔧 App database URL: ${app.options.databaseURL}');

    // Check for URL mismatch
    if (app.options.databaseURL !=
        DefaultFirebaseOptions.currentPlatform.databaseURL) {
      print(
        '⚠️⚠️⚠️ RTDB REPO WARNING: App database URL (${app.options.databaseURL}) does not match target URL (${DefaultFirebaseOptions.currentPlatform.databaseURL})',
      );
      logger.w(
        '⚠️ App database URL (${app.options.databaseURL}) does not match target URL (${DefaultFirebaseOptions.currentPlatform.databaseURL})',
      );
    }

    final instance = FirebaseDatabase.instanceFor(
      app: app,
      databaseURL: DefaultFirebaseOptions.currentPlatform.databaseURL,
    );

    print('🔧🔧🔧 RTDB REPO: FirebaseDatabase instance created successfully');
    logger.i('🔧 FirebaseDatabase instance created successfully');

    // Set persistence BEFORE creating any references or using the instance
    // These calls must happen before any other database operations
    try {
      instance.setPersistenceEnabled(true);
      instance.setPersistenceCacheSizeBytes(10000000); // 10MB
      logger.i('✅ Firebase persistence enabled (10MB cache)');
    } catch (e) {
      // If persistence is already set, that's fine - just log it
      logger.w('⚠️ Could not set persistence (may already be set): $e');
    }

    _cachedInstance = instance;
    return instance;
  }

  final DatabaseReference _db;
  final FirebaseDatabase _databaseInstance;
  final FirebaseAuth _auth;
  final BandwidthTracker? _bandwidthTracker;

  RealtimeDatabaseRepository({
    DatabaseReference? db,
    FirebaseAuth? auth,
    BandwidthTracker? bandwidthTracker,
  }) : _databaseInstance = _getDatabaseInstance(),
       _db = db ?? _getDatabaseInstance().ref(),
       _auth = auth ?? FirebaseAuth.instance,
       _bandwidthTracker = bandwidthTracker {
    logger.i(
      'RealtimeDatabaseRepository created with ${auth != null ? "provided auth" : "default auth"}',
    );
    logger.i(
      'RTDB Database URL configured (from options): ${DefaultFirebaseOptions.currentPlatform.databaseURL}',
    );
    logger.i(
      'Database instance URL (_databaseInstance.databaseURL): ${_databaseInstance.databaseURL}',
    ); // Keep logging for diagnostic purposes
    logger.i('Database instance app name: ${_databaseInstance.app.name}');
    logger.i(
      'All Firebase apps: ${Firebase.apps.map((app) => '${app.name}: ${app.options.databaseURL}').join(', ')}',
    );
    logger.i('Database reference path (_db.path): ${_db.path}');
  }

  /// Estimates the byte size of data being sent to Firebase.
  int _estimateDataSize(dynamic data) {
    if (data == null) return 0;

    // Convert to JSON string and get byte length (UTF-8 approximation)
    final jsonString = data.toString();
    return jsonString.length * 2; // Rough UTF-8 estimation
  }

  /// Helper to ensure authenticated state with forced token refresh
  Future<void> ensureAuthenticated() async {
    logger.i('🔐 AUTH CHECK: Starting ensureAuthenticated...');
    try {
      // Always force reload and token refresh to handle restart cases
      if (_auth.currentUser != null) {
        logger.i(
          '🔐 AUTH CHECK: Found existing user (${_auth.currentUser!.uid}), forcing reload and token refresh...',
        );
        await _auth.currentUser!.reload();
        await _auth.currentUser!.getIdToken(true);
        logger.i(
          '🔐 AUTH CHECK: Auth state reloaded and token refreshed: ${_auth.currentUser!.uid}',
        );
      } else {
        logger.w('🔐 AUTH CHECK: No current user, signing in anonymously...');
        final credential = await _auth.signInAnonymously();
        await credential.user?.getIdToken(true);
        logger.i(
          '🔐 AUTH CHECK: Signed in anonymously: ${credential.user?.uid}',
        );
      }

      // Wait for auth state confirmation
      await _auth.authStateChanges().firstWhere((user) => user != null);
      logger.i(
        '🔐 AUTH CHECK: Auth state confirmed - ready for database access',
      );
    } catch (authError) {
      logger.e('🔐 AUTH CHECK: Auth refresh failed', error: authError);
      // If token refresh fails, try signing out and signing back in
      try {
        logger.w('🔐 AUTH CHECK: Attempting auth reset...');
        await _auth.signOut();
        final credential = await _auth.signInAnonymously();
        await credential.user?.getIdToken(true);
        await _auth.authStateChanges().firstWhere((user) => user != null);
        logger.i(
          '🔐 AUTH CHECK: Auth reset successful: ${credential.user?.uid}',
        );
      } catch (resetError) {
        logger.e('🔐 AUTH CHECK: Auth reset also failed', error: resetError);
        rethrow;
      }
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

      try {
        return PairingSession.fromMap(data, token);
      } catch (e) {
        logger.e('Failed to parse session $token from database: $e');
        // Re-throw as a different error type that the cleanup can handle
        throw StateError('Session $token is corrupted: $e');
      }
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

  /// Removes a device from a session.
  Future<void> removeDeviceFromSession(String token, String deviceId) async {
    await ensureAuthenticated();
    logger.i('🔥 RTDB DELETE: Removing device $deviceId from session $token');

    final writeStart = DateTime.now();
    try {
      // Remove device from session's device list
      await _db.child('sessions/$token/devices/$deviceId').remove();
      final writeDuration = DateTime.now().difference(writeStart);
      logger.i(
        '✅ RTDB DELETE SUCCESS: Device $deviceId removed from session $token in ${writeDuration.inMilliseconds}ms',
      );
    } catch (e) {
      logger.e(
        '❌ RTDB DELETE FAILED: Failed to remove device $deviceId from session $token after ${DateTime.now().difference(writeStart).inMilliseconds}ms',
        error: e,
      );
      rethrow;
    }

    // Also remove the reverse lookup
    try {
      await _db.child('deviceSessions/$deviceId').remove();
      logger.i(
        '✅ RTDB DELETE SUCCESS: Device session lookup removed for $deviceId',
      );
    } catch (e) {
      logger.w(
        '⚠️ Failed to remove device session lookup for $deviceId',
        error: e,
      );
      // Don't rethrow - this is not critical
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
    final alarmData = alarm.toMap();
    final dataSize = _estimateDataSize(alarmData);

    final writeStart = DateTime.now();
    try {
      await _db
          .child('sessions/$sessionToken/alarms/${alarm.id}')
          .set(alarmData);
      final writeDuration = DateTime.now().difference(writeStart);

      // Record bandwidth usage
      _bandwidthTracker?.recordFirebaseDatabaseOperation(bytesSent: dataSize);

      logger.i(
        '✅ RTDB WRITE SUCCESS: Alarm ${alarm.id} created in $sessionToken in ${writeDuration.inMilliseconds}ms ($dataSize bytes)',
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
    logger.i(
      '📡 getSessionDataStream: Setting up stream for session $sessionToken',
    );
    final streamRef = _db.child('sessions/$sessionToken');
    logger.i(
      '📡 getSessionDataStream: Database reference path: ${streamRef.path}',
    );

    return streamRef.onValue.map((event) {
      logger.i(
        '📡 getSessionDataStream: Received event for session $sessionToken, exists=${event.snapshot.exists}',
      );

      if (!event.snapshot.exists) {
        logger.e(
          '📡 getSessionDataStream: Session $sessionToken not found in Firebase',
        );
        throw StateError('Session $sessionToken not found');
      }

      final rawData = event.snapshot.value as Map<Object?, Object?>;
      logger.i(
        '📡 getSessionDataStream: Raw data keys: ${rawData.keys.toList()}',
      );

      final convertedData = _convertToStringDynamicMap(rawData);
      logger.i(
        '📡 getSessionDataStream: Converted data keys: ${convertedData.keys.toList()}',
      );
      logger.i(
        '📡 getSessionDataStream: anchor=${convertedData['anchor']}, boatPosition=${convertedData['boatPosition']}, monitoringActive=${convertedData['monitoringActive']}',
      );

      return convertedData;
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

  /// Deletes expired and inactive sessions (cleanup).
  /// Tests basic connectivity to the Firebase Realtime Database
  Future<bool> testDatabaseConnectivity() async {
    try {
      logger.i('🔍 Testing database connectivity...');
      final rootSnapshot = await _db.get();
      logger.i(
        '🔍 Database connectivity test successful, exists: ${rootSnapshot.exists}',
      );
      return true;
    } on FirebaseException catch (e) {
      logger.e('🔍 Database connectivity test failed', error: e);
      logger.e('🔍 Error code: ${e.code}, message: ${e.message}');
      return false;
    } catch (e) {
      logger.e('🔍 Unexpected error during connectivity test', error: e);
      return false;
    }
  }

  /// Removes sessions that are:
  /// 1. Expired (past their expiresAt time)
  /// 2. Inactive (monitoringActive = false or missing) and older than 24 hours
  Future<void> deleteExpiredSessions() async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final twentyFourHoursAgo =
        now - (24 * 60 * 60 * 1000); // 24 hours in milliseconds

    logger.i(
      '🧹 Starting deleteExpiredSessions - checking database connectivity',
    );

    // First test basic connectivity
    final connectivityTest = await testDatabaseConnectivity();
    if (!connectivityTest) {
      logger.w(
        '🧹 Database connectivity test failed, skipping session cleanup',
      );
      return;
    }

    try {
      logger.i(
        '🧹 Attempting to read sessions from: ${_db.child('sessions').path}',
      );
      final sessionsSnapshot = await _db.child('sessions').get();
      logger.i(
        '🧹 Sessions read successful, exists: ${sessionsSnapshot.exists}',
      );
      if (!sessionsSnapshot.exists) {
        logger.i('🧹 No sessions found to clean up');
        return;
      }

      final rawSessions = sessionsSnapshot.value as Map<Object?, Object?>;
      final sessions = rawSessions.map(
        (key, value) => MapEntry(key.toString(), value),
      );
      final tokensToDelete = <String>[];

      for (final entry in sessions.entries) {
        try {
          // Skip if entry value is not a map (corrupted data)
          if (entry.value is! Map) {
            logger.w(
              '🗑️ Session ${entry.key} has invalid data type (not a Map), deleting',
            );
            tokensToDelete.add(entry.key);
            continue;
          }

          final rawSessionData = entry.value as Map<Object?, Object?>;
          final sessionData = rawSessionData.map(
            (key, value) => MapEntry(key.toString(), value),
          );

          final expiresAt = sessionData['expiresAt'];
          final createdAt = sessionData['createdAt'];
          final monitoringActive = sessionData['monitoringActive'] as bool?;
          final isActive = sessionData['isActive'] as bool? ?? true;

          // Check if session is missing required fields (corrupted)
          final devicesField = sessionData['devices'];
          final primaryUserIdField = sessionData['primaryUserId'];

          if (expiresAt == null ||
              createdAt == null ||
              devicesField == null ||
              primaryUserIdField == null) {
            logger.w(
              '🗑️ Session ${entry.key} is missing required fields '
              '(devices: ${devicesField != null}, primaryUserId: ${primaryUserIdField != null}, '
              'createdAt: ${createdAt != null}, expiresAt: ${expiresAt != null}), deleting',
            );
            tokensToDelete.add(entry.key);
            continue;
          }

          // Convert to int if needed
          final expiresAtMs = expiresAt is int
              ? expiresAt
              : (expiresAt as num?)?.toInt();
          final createdAtMs = createdAt is int
              ? createdAt
              : (createdAt as num?)?.toInt();

          if (expiresAtMs == null || createdAtMs == null) {
            logger.w(
              '🗑️ Session ${entry.key} has invalid timestamp types, deleting',
            );
            tokensToDelete.add(entry.key);
            continue;
          }

          // Check if session is expired
          if (expiresAtMs < now) {
            tokensToDelete.add(entry.key);
            logger.d(
              '🗑️ Session ${entry.key} is expired (expiresAt: $expiresAtMs, now: $now)',
            );
            continue;
          }

          // Check if session is inactive and older than 24 hours
          if (createdAtMs < twentyFourHoursAgo) {
            // Session is older than 24 hours
            final hasNoMonitoringData = monitoringActive != true;
            final isInactive = isActive != true;

            if (hasNoMonitoringData || isInactive) {
              tokensToDelete.add(entry.key);
              logger.d(
                '🗑️ Session ${entry.key} is inactive and older than 24 hours '
                '(createdAt: $createdAtMs, monitoringActive: $monitoringActive, isActive: $isActive)',
              );
            }
          }
        } catch (e) {
          // If we can't parse the session, it's corrupted - delete it
          logger.w(
            '🗑️ Session ${entry.key} is corrupted (error parsing: $e), deleting',
          );
          tokensToDelete.add(entry.key);
        }
      }

      // Delete expired/inactive sessions
      for (final token in tokensToDelete) {
        try {
          await _db.child('sessions/$token').remove();
          logger.i('🗑️ Deleted session: $token');
        } catch (e) {
          logger.w('Failed to delete session $token', error: e);
        }
      }

      logger.i(
        '✅ Cleanup complete: ${tokensToDelete.length} sessions removed '
        '(expired or inactive >24h)',
      );
    } catch (e) {
      logger.w('Could not delete expired/inactive sessions', error: e);

      // Provide more specific error information
      if (e.toString().contains('permission-denied')) {
        logger.e('🔐 PERMISSION ERROR: Cannot access sessions path');
        logger.e('🔐 Current user: ${getCurrentUserId() ?? "null"}');
        logger.e(
          '🔐 Database URL: ${DefaultFirebaseOptions.currentPlatform.databaseURL}',
        );
        logger.e(
          '🔐 Check Firebase Realtime Database rules and ensure user is authenticated',
        );
      }
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

      // Record bandwidth usage for auth operation (estimated ~1KB for request/response)
      _bandwidthTracker?.recordFirebaseAuthOperation(
        bytesSent: 512,
        bytesReceived: 512,
      );

      logger.i('✅ Signed in anonymously for RTDB access');
    } catch (e) {
      logger.e('❌ Failed to sign in anonymously', error: e);
      rethrow;
    }
  }
}
