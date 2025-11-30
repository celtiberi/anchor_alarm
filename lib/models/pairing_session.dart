import 'device_info.dart';

/// Manages multi-device pairing for remote monitoring.
class PairingSession {
  final String token;
  /// Firebase Auth UID of the session owner (primary user)
  final String primaryUserId;
  final List<DeviceInfo> devices;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isActive;

  PairingSession({
    required this.token,
    required this.primaryUserId,
    required this.devices,
    required this.createdAt,
    required this.expiresAt,
    this.isActive = true,
  }) : assert(
          token.isNotEmpty,
          'Session token cannot be empty',
        ),
        assert(
          devices.isNotEmpty,
          'Session must have at least one device',
        ),
        assert(
          expiresAt.isAfter(createdAt),
          'Expiry time must be after creation time',
        ),
        assert(
          devices.any((d) => d.deviceId == primaryUserId && d.role == DeviceRole.primary),
          'Primary device must exist in devices list with primary role',
        );

  /// Creates PairingSession from RTDB map.
  factory PairingSession.fromMap(Map<String, dynamic> data, String token) {
    // Handle the devices map which comes as Map<Object?, Object?> from Firebase
    final rawDevices = data['devices'] as Map<Object?, Object?>;
    final devicesMap = rawDevices.map((key, value) => MapEntry(key.toString(), value));

    return PairingSession(
      token: token,
      primaryUserId: data['primaryUserId'] as String,
      devices: devicesMap.values
          .map((d) {
            final rawDevice = d as Map<Object?, Object?>;
            final deviceData = rawDevice.map((key, value) => MapEntry(key.toString(), value));
            return DeviceInfo.fromMap(deviceData);
          })
          .toList(),
      createdAt: DateTime.fromMillisecondsSinceEpoch((data['createdAt'] as int)),
      expiresAt: DateTime.fromMillisecondsSinceEpoch((data['expiresAt'] as int)),
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  /// Converts PairingSession to RTDB map data.
  Map<String, dynamic> toMap() {
    return {
      'primaryUserId': primaryUserId,
      'devices': {
        for (final device in devices) device.deviceId: device.toMap()
      },
      'createdAt': createdAt.millisecondsSinceEpoch,
      'expiresAt': expiresAt.millisecondsSinceEpoch,
      'isActive': isActive,
    };
  }

  /// Checks if session has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Creates a copy with updated fields.
  PairingSession copyWith({
    String? token,
    String? primaryUserId,
    List<DeviceInfo>? devices,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? isActive,
  }) {
    return PairingSession(
      token: token ?? this.token,
      primaryUserId: primaryUserId ?? this.primaryUserId,
      devices: devices ?? this.devices,
      createdAt: createdAt ?? this.createdAt,
      expiresAt: expiresAt ?? this.expiresAt,
      isActive: isActive ?? this.isActive,
    );
  }

  /// Adds a device to the session.
  /// If the device already exists, updates its joinedAt timestamp (allows re-joining).
  PairingSession addDevice(DeviceInfo device) {
    final existingDeviceIndex = devices.indexWhere((d) => d.deviceId == device.deviceId);
    
    if (existingDeviceIndex >= 0) {
      // Device already exists - update it with new joinedAt timestamp (re-joining)
      final updatedDevices = List<DeviceInfo>.from(devices);
      updatedDevices[existingDeviceIndex] = device;
      return PairingSession(
        token: token,
        primaryUserId: primaryUserId,
        devices: updatedDevices,
        createdAt: createdAt,
        expiresAt: expiresAt,
        isActive: isActive,
      );
    }
    
    // New device - add it
    return PairingSession(
      token: token,
      primaryUserId: primaryUserId,
      devices: [...devices, device],
      createdAt: createdAt,
      expiresAt: expiresAt,
      isActive: isActive,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PairingSession &&
        other.token == token &&
        other.primaryUserId == primaryUserId &&
        other.devices.length == devices.length &&
        other.createdAt == createdAt &&
        other.expiresAt == expiresAt &&
        other.isActive == isActive;
  }

  @override
  int get hashCode {
    return Object.hash(
      token,
      primaryUserId,
      devices.length,
      createdAt,
      expiresAt,
      isActive,
    );
  }

  @override
  String toString() {
    return 'PairingSession(token: $token, primaryUser: $primaryUserId, devices: ${devices.length}, active: $isActive, expiresAt: $expiresAt)';
  }
}

