import 'dart:math';
import '../models/pairing_session.dart';
import '../models/device_info.dart';
import '../utils/logger_setup.dart';

/// Service for generating and managing pairing sessions.
class PairingService {
  /// Generates a unique session token.
  String generateSessionToken() {
    final random = Random.secure();
    const chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    final token = StringBuffer();
    
    for (int i = 0; i < 32; i++) {
      token.write(chars[random.nextInt(chars.length)]);
    }
    
    final tokenString = token.toString();
    logger.i('Generated session token: $tokenString');
    return tokenString;
  }

  /// Creates a new pairing session.
  /// Note: primaryUserId will be set to the Firebase Auth UID by the repository
  PairingSession createSession() {
    final token = generateSessionToken();
    final now = DateTime.now();
    final expiresAt = now.add(const Duration(hours: 24));

    final session = PairingSession(
      token: token,
      primaryUserId: '', // Will be overridden by repository with auth UID
      devices: [
        DeviceInfo(
          deviceId: '', // Will be overridden by repository with auth UID
          role: DeviceRole.primary,
          joinedAt: now,
        ),
      ],
      createdAt: now,
      expiresAt: expiresAt,
      isActive: true,
    );

    logger.i('Created pairing session: $token');
    return session;
  }

  /// Validates a session token format.
  bool isValidTokenFormat(String token) {
    if (token.length != 32) {
      return false;
    }
    return RegExp(r'^[A-Z0-9]+$').hasMatch(token);
  }
}

