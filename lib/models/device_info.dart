
/// Device role in a pairing session.
enum DeviceRole {
  primary,
  secondary,
}

/// Information about a device in a pairing session.
/// deviceId is the Firebase Auth UID of the user/device.
class DeviceInfo {
  /// Firebase Auth UID of the authenticated user
  final String deviceId;
  final DeviceRole role;
  final DateTime joinedAt;
  final DateTime? lastSeenAt;

  DeviceInfo({
    required this.deviceId,
    required this.role,
    required this.joinedAt,
    this.lastSeenAt,
  });

  /// Creates DeviceInfo from RTDB map.
  factory DeviceInfo.fromMap(Map<String, dynamic> data) {
    return DeviceInfo(
      deviceId: data['deviceId'] as String,
      role: DeviceRole.values.firstWhere(
        (e) => e.name == data['role'],
        orElse: () => DeviceRole.secondary,
      ),
      joinedAt: DateTime.fromMillisecondsSinceEpoch((data['joinedAt'] as int)),
      lastSeenAt: data['lastSeenAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((data['lastSeenAt'] as int))
          : null,
    );
  }

  /// Converts DeviceInfo to RTDB map.
  Map<String, dynamic> toMap() {
    return {
      'deviceId': deviceId,
      'role': role.name,
      'joinedAt': joinedAt.millisecondsSinceEpoch,
      if (lastSeenAt != null) 'lastSeenAt': lastSeenAt!.millisecondsSinceEpoch,
    };
  }

  /// Creates a copy with updated fields.
  DeviceInfo copyWith({
    String? deviceId,
    DeviceRole? role,
    DateTime? joinedAt,
    DateTime? lastSeenAt,
  }) {
    return DeviceInfo(
      deviceId: deviceId ?? this.deviceId,
      role: role ?? this.role,
      joinedAt: joinedAt ?? this.joinedAt,
      lastSeenAt: lastSeenAt ?? this.lastSeenAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is DeviceInfo &&
        other.deviceId == deviceId &&
        other.role == role &&
        other.joinedAt == joinedAt &&
        other.lastSeenAt == lastSeenAt;
  }

  @override
  int get hashCode {
    return Object.hash(deviceId, role, joinedAt, lastSeenAt);
  }

  @override
  String toString() {
    return 'DeviceInfo(deviceId: $deviceId, role: $role, joinedAt: $joinedAt, lastSeenAt: $lastSeenAt)';
  }
}

