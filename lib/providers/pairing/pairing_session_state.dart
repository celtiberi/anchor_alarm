import 'package:flutter/foundation.dart';
import 'package:meta/meta.dart';

import '../../utils/logger_setup.dart';
import 'pairing_role.dart';

/// State for pairing session.
@immutable
class PairingSessionState {
  final PairingRole role;
  final String? localSessionToken;
  final String? remoteSessionToken;
  final String? primaryUserId;

  const PairingSessionState({
    required this.role,
    this.localSessionToken,
    this.remoteSessionToken,
    this.primaryUserId,
  });

  String? get sessionToken {
    final token = remoteSessionToken ?? localSessionToken;
    if (kDebugMode) {
      logger.i(
        '🔍 sessionToken getter called: remoteSessionToken=$remoteSessionToken, localSessionToken=$localSessionToken, returning=$token',
      );
      logger.i(
        '📋 Full state in getter: role=$role, localSessionToken=$localSessionToken, remoteSessionToken=$remoteSessionToken',
      );
    }
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

