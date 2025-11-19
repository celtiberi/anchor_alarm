import 'package:cloud_firestore/cloud_firestore.dart';

/// Device role in a pairing session.
enum DeviceRole {
  primary,
  secondary,
}

/// Information about a device in a pairing session.
class DeviceInfo {
  final String deviceId;
  final DeviceRole role;
  final DateTime joinedAt;
  final DateTime? lastSeenAt;

  DeviceInfo({
    required this.deviceId,
    required this.role,
    required this.joinedAt,
    this.lastSeenAt,
  }) : assert(deviceId.isNotEmpty, 'Device ID cannot be empty');

  /// Creates DeviceInfo from Firestore map.
  factory DeviceInfo.fromFirestore(Map<String, dynamic> data) {
    return DeviceInfo(
      deviceId: data['deviceId'] as String,
      role: DeviceRole.values.firstWhere(
        (e) => e.name == data['role'],
        orElse: () => DeviceRole.secondary,
      ),
      joinedAt: (data['joinedAt'] as Timestamp).toDate(),
      lastSeenAt: data['lastSeenAt'] != null
          ? (data['lastSeenAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Converts DeviceInfo to Firestore map.
  Map<String, dynamic> toFirestore() {
    return {
      'deviceId': deviceId,
      'role': role.name,
      'joinedAt': Timestamp.fromDate(joinedAt),
      if (lastSeenAt != null) 'lastSeenAt': Timestamp.fromDate(lastSeenAt!),
    };
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

