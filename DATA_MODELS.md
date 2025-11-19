
1# Data Models Specification

This document defines the data models used throughout the Anchor Alarm app, including Dart classes and Firestore schemas.

## Anchor Model

**Purpose**: Represents the anchor point that the boat should stay within.

**Dart Class**:
```dart

  final String id;           // Unique identifier (UUID)
  final double latitude;     // Decimal degrees (-90 to 90)
  final double longitude;    // Decimal degrees (-180 to 180)
  final double radius;       // Meters (20-100 default, adjustable)
  final DateTime createdAt;  // When anchor was set
  final DateTime? updatedAt; // When anchor was last adjusted
  final bool isActive;       // Whether monitoring is active
}
```

**Firestore**: Not stored in Firestore (local-only for MVP). May be synced in future for multi-device anchor sharing.

**Validation**:
- `latitude`: -90.0 to 90.0
- `longitude`: -180.0 to 180.0
- `radius`: 20.0 to 100.0 meters (default: 50.0)
- `id`: Non-empty UUID v4

## Position Update

**Purpose**: Represents the current GPS position of the boat.

**Dart Class**:
```dart
class PositionUpdate {
  final DateTime timestamp;  // When position was recorded
  final double latitude;      // Decimal degrees
  final double longitude;     // Decimal degrees
  final double? speed;        // Meters per second (nullable)
  final double? accuracy;     // Meters (GPS accuracy, nullable)
  final double? altitude;     // Meters above sea level (nullable)
  final double? heading;      // Degrees (0-360, nullable)
}
```

**Firestore Collection**: `sessions/{sessionId}/positions`
- Document ID: Auto-generated timestamp-based
- Fields: All fields from Dart class
- Indexed: `timestamp` (descending) for recent positions query

**Validation**:
- `latitude`: -90.0 to 90.0
- `longitude`: -180.0 to 180.0
- `speed`: >= 0.0 (if provided)
- `accuracy`: >= 0.0 (if provided)
- `heading`: 0.0 to 360.0 (if provided)

## Alarm Event

**Purpose**: Records when an alarm is triggered (drift beyond radius).

**Dart Class**:
```dart
enum AlarmType {
  driftExceeded,    // Boat moved beyond anchor radius
  gpsLost,          // GPS signal lost
  gpsInaccurate,    // GPS accuracy too poor
}

class AlarmEvent {
  final String id;              // UUID
  final AlarmType type;         // Type of alarm
  final DateTime timestamp;     // When alarm occurred
  final double latitude;         // Position when alarm triggered
  final double longitude;        // Position when alarm triggered
  final double distanceFromAnchor; // Meters from anchor point
  final bool acknowledged;      // Whether user dismissed alarm
  final DateTime? acknowledgedAt; // When acknowledged (nullable)
}
```

**Firestore Collection**: `sessions/{sessionId}/alarms`
- Document ID: UUID
- Fields: All fields from Dart class
- Indexed: `timestamp` (descending), `acknowledged` (for unacknowledged alarms)

**Validation**:
- `distanceFromAnchor`: >= 0.0
- `latitude`, `longitude`: Valid coordinate ranges

## Pairing Session

**Purpose**: Manages multi-device pairing for remote monitoring.

**Dart Class**:
```dart
enum DeviceRole {
  primary,    // Device actively monitoring GPS
  secondary,  // Device receiving updates remotely
}

class DeviceInfo {
  final String deviceId;       // Unique device identifier
  final DeviceRole role;       // Primary or secondary
  final DateTime joinedAt;      // When device joined session
  final DateTime? lastSeenAt;   // Last position update received
}

class PairingSession {
  final String token;          // Unique session token (QR code)
  final String primaryDeviceId; // Device ID of primary device
  final List<DeviceInfo> devices; // All devices in session
  final DateTime createdAt;     // When session was created
  final DateTime expiresAt;     // Auto-expiry (24 hours default)
  final bool isActive;          // Whether session is active
}
```

**Firestore Collection**: `sessions`
- Document ID: `token` (session token)
- Fields: All fields from Dart class
- Indexed: `expiresAt` (for cleanup), `primaryDeviceId`

**Validation**:
- `token`: 32-character alphanumeric string
- `expiresAt`: Must be in future
- `devices`: Must contain at least one device (primary)
- `primaryDeviceId`: Must exist in `devices` list

## Settings Model

**Purpose**: User preferences and app configuration.

**Dart Class**:
```dart
enum UnitSystem {
  metric,    // Meters, kilometers
  imperial,  // Feet, miles
}

enum ThemeMode {
  light,
  dark,
  system,
}

class AppSettings {
  final UnitSystem unitSystem;      // Default: metric
  final ThemeMode themeMode;         // Default: system
  final double defaultRadius;       // Default: 50.0 meters
  final double alarmSensitivity;    // GPS noise filter (0.0-1.0, default: 0.5)
  final bool soundEnabled;           // Default: true
  final bool vibrationEnabled;       // Default: true
  final bool screenFlashEnabled;     // Default: true
}
```

**Storage**: Local only (Hive) - not synced across devices in MVP.

## Data Flow

1. **Primary Device**:
   - Collects GPS position → `PositionUpdate`
   - Calculates distance from `Anchor`
   - If distance > radius → Creates `AlarmEvent`
   - Pushes `PositionUpdate` and `AlarmEvent` to Firestore `sessions/{token}/positions` and `sessions/{token}/alarms`

2. **Secondary Device**:
   - Listens to Firestore `sessions/{token}/positions` (latest)
   - Listens to Firestore `sessions/{token}/alarms` (unacknowledged)
   - Displays remote position and alarm status

3. **Session Management**:
   - Primary creates `PairingSession` in Firestore
   - Secondary joins by scanning QR code (token)
   - Sessions auto-expire after 24 hours
   - Cleanup job removes expired sessions

## Notes

- All timestamps use UTC
- All coordinates use WGS84 (standard GPS)
- Distances calculated using Haversine formula
- Fail-fast: Invalid data should throw exceptions immediately, don't silently handle errors

