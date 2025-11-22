import 'package:cloud_firestore/cloud_firestore.dart';
import 'device_info.dart';

/// Manages multi-device pairing for remote monitoring.
class PairingSession {
  final String token;
  final String primaryDeviceId;
  final List<DeviceInfo> devices;
  final DateTime createdAt;
  final DateTime expiresAt;
  final bool isActive;

  PairingSession({
    required this.token,
    required this.primaryDeviceId,
    required this.devices,
    required this.createdAt,
    required this.expiresAt,
    this.isActive = true,
  }) : assert(
          token.isNotEmpty,
          'Session token cannot be empty',
        ),
        assert(
          primaryDeviceId.isNotEmpty,
          'Primary device ID cannot be empty',
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
          devices.any((d) => d.deviceId == primaryDeviceId && d.role == DeviceRole.primary),
          'Primary device must exist in devices list with primary role',
        );

  /// Creates PairingSession from Firestore document.
  factory PairingSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PairingSession(
      token: doc.id,
      primaryDeviceId: data['primaryDeviceId'] as String,
      devices: (data['devices'] as List<dynamic>)
          .map((d) => DeviceInfo.fromFirestore(d as Map<String, dynamic>))
          .toList(),
      createdAt: (data['createdAt'] as Timestamp).toDate(),
      expiresAt: (data['expiresAt'] as Timestamp).toDate(),
      isActive: data['isActive'] as bool? ?? true,
    );
  }

  /// Converts PairingSession to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'token': token,
      'primaryDeviceId': primaryDeviceId,
      'devices': devices.map((d) => d.toFirestore()).toList(),
      'createdAt': Timestamp.fromDate(createdAt),
      'expiresAt': Timestamp.fromDate(expiresAt),
      'isActive': isActive,
    };
  }

  /// Checks if session has expired.
  bool get isExpired => DateTime.now().isAfter(expiresAt);

  /// Creates a copy with updated fields.
  PairingSession copyWith({
    String? token,
    String? primaryDeviceId,
    List<DeviceInfo>? devices,
    DateTime? createdAt,
    DateTime? expiresAt,
    bool? isActive,
  }) {
    return PairingSession(
      token: token ?? this.token,
      primaryDeviceId: primaryDeviceId ?? this.primaryDeviceId,
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
        primaryDeviceId: primaryDeviceId,
        devices: updatedDevices,
        createdAt: createdAt,
        expiresAt: expiresAt,
        isActive: isActive,
      );
    }
    
    // New device - add it
    return PairingSession(
      token: token,
      primaryDeviceId: primaryDeviceId,
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
        other.primaryDeviceId == primaryDeviceId &&
        other.devices.length == devices.length &&
        other.createdAt == createdAt &&
        other.expiresAt == expiresAt &&
        other.isActive == isActive;
  }

  @override
  int get hashCode {
    return Object.hash(
      token,
      primaryDeviceId,
      devices.length,
      createdAt,
      expiresAt,
      isActive,
    );
  }

  @override
  String toString() {
    return 'PairingSession(token: $token, primaryDevice: $primaryDeviceId, devices: ${devices.length}, active: $isActive, expiresAt: $expiresAt)';
  }
}

