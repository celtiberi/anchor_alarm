import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'dart:io';
import '../models/pairing_session.dart';
import '../models/device_info.dart';
import '../services/pairing_service.dart';
import '../repositories/firestore_repository.dart';
import 'firestore_provider.dart';
import 'pairing_service_provider.dart';
import '../utils/logger_setup.dart';

/// Provides the current pairing session state.
final pairingSessionProvider =
    NotifierProvider<PairingSessionNotifier, PairingSession?>(() {
  return PairingSessionNotifier();
});

/// Notifier for pairing session state management.
class PairingSessionNotifier extends Notifier<PairingSession?> {
  FirestoreRepository get _firestore => ref.read(firestoreRepositoryProvider);
  PairingService get _pairingService => ref.read(pairingServiceProvider);
  String? _deviceId;

  @override
  PairingSession? build() {
    _loadDeviceId();
    return null;
  }

  /// Loads or generates device ID.
  Future<void> _loadDeviceId() async {
    if (_deviceId != null) {
      return;
    }

    try {
      final deviceInfo = DeviceInfoPlugin();
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        _deviceId = androidInfo.id;
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        _deviceId = iosInfo.identifierForVendor;
      } else {
        _deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
      }
      logger.i('Device ID: $_deviceId');
    } catch (e) {
      logger.e('Failed to get device ID', error: e);
      _deviceId = 'unknown_${DateTime.now().millisecondsSinceEpoch}';
    }
  }

  /// Creates a new pairing session as primary device.
  Future<PairingSession> createSession() async {
    await _loadDeviceId();
    
    final session = _pairingService.createSession(_deviceId!);
    
    try {
      await _firestore.createSession(session);
      state = session;
      logger.i('Pairing session created and saved: ${session.token}');
      return session;
    } catch (e) {
      logger.e('Failed to create session in Firestore', error: e);
      throw StateError('Failed to create pairing session: $e');
    }
  }

  /// Joins an existing session as secondary device.
  Future<void> joinSession(String token) async {
    await _loadDeviceId();
    
    if (!_pairingService.isValidTokenFormat(token)) {
      throw ArgumentError('Invalid session token format');
    }

    try {
      final session = await _firestore.getSession(token);
      if (session == null) {
        throw StateError('Session not found');
      }

      if (session.isExpired) {
        throw StateError('Session has expired');
      }

      if (!session.isActive) {
        throw StateError('Session is not active');
      }

      // Add this device to the session
      final deviceInfo = DeviceInfo(
        deviceId: _deviceId!,
        role: DeviceRole.secondary,
        joinedAt: DateTime.now(),
      );

      await _firestore.addDeviceToSession(token, deviceInfo);
      
      // Reload session
      final updatedSession = await _firestore.getSession(token);
      state = updatedSession;
      
      logger.i('Joined session: $token');
    } catch (e) {
      logger.e('Failed to join session', error: e);
      rethrow;
    }
  }

  /// Ends the current session.
  Future<void> endSession() async {
    if (state == null) {
      return;
    }

    try {
      final updatedSession = state!.copyWith(isActive: false);
      await _firestore.updateSession(updatedSession);
      state = null;
      logger.i('Session ended');
    } catch (e) {
      logger.e('Failed to end session', error: e);
    }
  }

  /// Gets device ID.
  String? get deviceId => _deviceId;
}

