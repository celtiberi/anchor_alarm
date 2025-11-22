import 'package:cloud_firestore/cloud_firestore.dart';
import '../models/position_update.dart';
import '../models/alarm_event.dart';
import '../models/pairing_session.dart';
import '../models/device_info.dart';
import '../utils/logger_setup.dart';

/// Repository for Firestore operations.
class FirestoreRepository {
  final FirebaseFirestore _firestore;

  FirestoreRepository({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

  /// Creates a new pairing session.
  Future<void> createSession(PairingSession session) async {
    await _firestore
        .collection('sessions')
        .doc(session.token)
        .set(session.toFirestore());
  }

  /// Gets a pairing session by token.
  Future<PairingSession?> getSession(String token) async {
    final doc = await _firestore.collection('sessions').doc(token).get();
    if (!doc.exists) {
      return null;
    }
    return PairingSession.fromFirestore(doc);
  }

  /// Stream of pairing session updates (for real-time device list).
  Stream<PairingSession> getSessionStream(String token) {
    return _firestore
        .collection('sessions')
        .doc(token)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        throw StateError('Session $token not found');
      }
      return PairingSession.fromFirestore(snapshot);
    });
  }

  /// Updates a pairing session.
  Future<void> updateSession(PairingSession session) async {
    await _firestore
        .collection('sessions')
        .doc(session.token)
        .update(session.toFirestore());
  }

  /// Adds a device to a session.
  Future<void> addDeviceToSession(String token, DeviceInfo device) async {
    final session = await getSession(token);
    if (session == null) {
      throw StateError('Session $token not found');
    }
    final updatedSession = session.addDevice(device);
    await updateSession(updatedSession);
  }

  /// Stream of position updates for a session.
  Stream<PositionUpdate> getPositionStream(String sessionToken) {
    return _firestore
        .collection('sessions')
        .doc(sessionToken)
        .collection('positions')
        .orderBy('timestamp', descending: true)
        .limit(1)
        .snapshots()
        .map((snapshot) {
      if (snapshot.docs.isEmpty) {
        throw StateError('No positions found in session');
      }
      return PositionUpdate.fromFirestore(snapshot.docs.first);
    });
  }

  /// Pushes a position update to Firestore.
  Future<void> pushPosition(String sessionToken, PositionUpdate position) async {
    await _firestore
        .collection('sessions')
        .doc(sessionToken)
        .collection('positions')
        .add(position.toFirestore());
  }

  /// Stream of active alarms for a session (acknowledged alarms are deleted).
  Stream<List<AlarmEvent>> getAlarmsStream(String sessionToken) {
    return _firestore
        .collection('sessions')
        .doc(sessionToken)
        .collection('alarms')
        .snapshots()
        .map((snapshot) {
      // Sort in memory instead of requiring a Firestore index
      final alarms = snapshot.docs
          .map((doc) => AlarmEvent.fromFirestore(doc))
          .toList();
      alarms.sort((a, b) => b.timestamp.compareTo(a.timestamp)); // Most recent first
      return alarms;
    });
  }

  /// Creates an alarm event in Firestore.
  Future<void> createAlarm(String sessionToken, AlarmEvent alarm) async {
    await _firestore
        .collection('sessions')
        .doc(sessionToken)
        .collection('alarms')
        .doc(alarm.id)
        .set(alarm.toFirestore());
  }

  /// Acknowledges an alarm.
  Future<void> acknowledgeAlarm(String sessionToken, String alarmId) async {
    await _firestore
        .collection('sessions')
        .doc(sessionToken)
        .collection('alarms')
        .doc(alarmId)
        .delete();
  }

  /// Updates session data (anchor, boatPosition, etc.) for monitoring.
  Future<void> updateSessionData(String sessionToken, Map<String, dynamic> data) async {
    logger.d('🔧 Updating session $sessionToken with data: $data');
    try {
      await _firestore
          .collection('sessions')
          .doc(sessionToken)
          .update(data);
      logger.d('✅ Successfully updated session $sessionToken');
    } catch (e) {
      logger.e('❌ Failed to update session $sessionToken with data $data', error: e);
      rethrow;
    }
  }

  /// Gets session data for monitoring (anchor, boatPosition, alarms, positionHistory).
  Future<Map<String, dynamic>?> getSessionData(String sessionToken) async {
    final doc = await _firestore.collection('sessions').doc(sessionToken).get();
    if (!doc.exists) {
      return null;
    }
    return doc.data();
  }

  /// Stream of session data for monitoring (for secondary devices).
  Stream<Map<String, dynamic>> getSessionDataStream(String sessionToken) {
    return _firestore
        .collection('sessions')
        .doc(sessionToken)
        .snapshots()
        .map((snapshot) {
      if (!snapshot.exists) {
        throw StateError('Session $sessionToken not found');
      }
      return snapshot.data()!;
    });
  }

  /// Deletes expired sessions (cleanup).
  Future<void> deleteExpiredSessions() async {
    final now = Timestamp.now();
    final query = await _firestore
        .collection('sessions')
        .where('expiresAt', isLessThan: now)
        .get();

    final batch = _firestore.batch();
    for (final doc in query.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();
  }
}

