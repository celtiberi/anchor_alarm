# API Contracts

This document defines the Firestore database structure and API contracts for the Anchor Alarm app.

## Firestore Collections

### `sessions` Collection

**Purpose**: Stores pairing session information for multi-device monitoring.

**Document ID**: Session token (32-character alphanumeric)

**Document Structure**:
```typescript
{
  token: string,                    // Session token (same as document ID)
  primaryDeviceId: string,          // Device ID of primary monitoring device
  devices: Array<{
    deviceId: string,                // Unique device identifier
    role: "primary" | "secondary",  // Device role
    joinedAt: Timestamp,            // When device joined
    lastSeenAt: Timestamp | null,   // Last update from device
  }>,
  createdAt: Timestamp,             // Session creation time
  expiresAt: Timestamp,             // Auto-expiry (24 hours from creation)
  isActive: boolean,                // Whether session is active
}
```

**Indexes**:
- `expiresAt` (ascending) - For cleanup queries
- `primaryDeviceId` (ascending) - For device lookup

**Security Rules** (Firestore):
- Read: Anyone with session token (no auth required per design doc)
- Write: Primary device only (validated by deviceId match)

**Operations**:
- **Create**: Primary device creates session on pairing start
- **Read**: Secondary devices read to join session
- **Update**: Primary device updates `devices` array when secondaries join
- **Delete**: Auto-delete after `expiresAt` (via Cloud Function or client cleanup)

---

### `sessions/{sessionId}/positions` Subcollection

**Purpose**: Stores position updates from primary device.

**Document ID**: Auto-generated (timestamp-based recommended)

**Document Structure**:
```typescript
{
  timestamp: Timestamp,              // When position was recorded
  latitude: number,                 // Decimal degrees (-90 to 90)
  longitude: number,                // Decimal degrees (-180 to 180)
  speed: number | null,             // Meters per second
  accuracy: number | null,          // GPS accuracy in meters
  altitude: number | null,          // Meters above sea level
  heading: number | null,           // Degrees (0-360)
}
```

**Indexes**:
- `timestamp` (descending) - For latest position queries

**Security Rules**:
- Read: Anyone with session access
- Write: Primary device only

**Operations**:
- **Create**: Primary device pushes position every 15-60 seconds
- **Read**: Secondary devices listen to latest position (limit 1, order by timestamp desc)
- **Update**: Not used
- **Delete**: Auto-delete old positions (keep last 100 or 24 hours)

**Query Pattern**:
```dart
// Get latest position
final positionsRef = FirebaseFirestore.instance
    .collection('sessions')
    .doc(sessionToken)
    .collection('positions')
    .orderBy('timestamp', descending: true)
    .limit(1);

// Listen to latest position
positionsRef.snapshots().listen((snapshot) {
  if (snapshot.docs.isNotEmpty) {
    final position = PositionUpdate.fromFirestore(snapshot.docs.first);
    // Update UI
  }
});
```

---

### `sessions/{sessionId}/alarms` Subcollection

**Purpose**: Stores alarm events (drift detected, GPS issues).

**Document ID**: UUID

**Document Structure**:
```typescript
{
  id: string,                       // UUID (same as document ID)
  type: "driftExceeded" | "gpsLost" | "gpsInaccurate",
  timestamp: Timestamp,             // When alarm occurred
  latitude: number,                  // Position when alarm triggered
  longitude: number,                // Position when alarm triggered
  distanceFromAnchor: number,       // Meters from anchor point
  acknowledged: boolean,            // Whether user dismissed
  acknowledgedAt: Timestamp | null, // When acknowledged
}
```

**Indexes**:
- `timestamp` (descending) - For recent alarms
- `acknowledged` (ascending) + `timestamp` (descending) - For unacknowledged alarms query

**Security Rules**:
- Read: Anyone with session access
- Write: Primary device creates, any device can acknowledge

**Operations**:
- **Create**: Primary device creates when alarm condition detected
- **Read**: Secondary devices listen to unacknowledged alarms
- **Update**: Any device can set `acknowledged: true`
- **Delete**: Not used (keep for history in MVP)

**Query Pattern**:
```dart
// Get unacknowledged alarms
final alarmsRef = FirebaseFirestore.instance
    .collection('sessions')
    .doc(sessionToken)
    .collection('alarms')
    .where('acknowledged', isEqualTo: false)
    .orderBy('timestamp', descending: true);

// Acknowledge alarm
await alarmsRef.doc(alarmId).update({
  'acknowledged': true,
  'acknowledgedAt': FieldValue.serverTimestamp(),
});
```

---

## Data Flow

### Primary Device Flow

1. **Start Monitoring**:
   - User sets anchor point (local only)
   - Start GPS polling (every 15 seconds)
   - If pairing active, create/update session in Firestore

2. **Position Update**:
   - Get GPS position → `PositionUpdate`
   - Calculate distance from anchor
   - If distance > radius → Create `AlarmEvent` in Firestore
   - Push `PositionUpdate` to Firestore `sessions/{token}/positions`

3. **Alarm Trigger**:
   - Create alarm document in `sessions/{token}/alarms`
   - Trigger local notification
   - Send FCM push to secondary devices

### Secondary Device Flow

1. **Join Session**:
   - Scan QR code → Get session token
   - Read `sessions/{token}` document
   - Add device to `devices` array (primary device updates)

2. **Monitor Position**:
   - Listen to `sessions/{token}/positions` (latest only)
   - Display remote boat position on map
   - Show distance from anchor (if anchor shared in future)

3. **Monitor Alarms**:
   - Listen to `sessions/{token}/alarms` (unacknowledged)
   - Display alarm notifications
   - Allow remote acknowledgment

---

## Firebase Cloud Messaging (FCM)

### Message Types

1. **Alarm Notification**:
```json
{
  "notification": {
    "title": "Anchor Alarm",
    "body": "Boat has drifted beyond safe radius"
  },
  "data": {
    "type": "alarm",
    "alarmId": "uuid",
    "sessionToken": "token",
    "alarmType": "driftExceeded"
  }
}
```

2. **Position Update** (optional, for background):
```json
{
  "data": {
    "type": "position",
    "sessionToken": "token",
    "latitude": "37.7749",
    "longitude": "-122.4194"
  }
}
```

### FCM Topics
- Per-session topic: `session_{token}` (all devices in session subscribe)

---

## Error Handling

### Firestore Errors
- **Permission Denied**: Fail fast - throw exception, don't retry silently
- **Network Error**: Queue for retry, but fail if offline too long
- **Invalid Data**: Validate before writing, throw `ArgumentError` on invalid data

### Retry Strategy
- **Position Updates**: Retry up to 3 times, then queue for later
- **Alarm Events**: Always persist (critical), retry indefinitely
- **Session Updates**: Fail fast if can't update (user should retry manually)

---

## Offline Support

### Primary Device
- Continue local monitoring if offline
- Queue position updates in Hive
- Sync when connection restored
- Alarms still trigger locally

### Secondary Device
- Show "Last seen: {timestamp}" if offline
- Display cached last position
- Queue alarm acknowledgments

---

## Data Retention

- **Sessions**: Auto-delete after `expiresAt` (24 hours)
- **Positions**: Keep last 100 positions or 24 hours (whichever is smaller)
- **Alarms**: Keep all unacknowledged, keep acknowledged for 7 days

---

## Security Considerations

### Token Generation
- Generate 32-character alphanumeric tokens
- Use cryptographically secure random: `Random.secure()`
- Tokens are single-use for session creation

### Access Control
- No user authentication required (per design doc)
- Access controlled by token knowledge (QR code)
- Consider rate limiting on session creation (prevent abuse)

### Data Privacy
- Location data is sensitive but low-privacy per design doc
- Sessions auto-expire (24 hours)
- No PII stored (device IDs are anonymous)

---

## Migration Notes

- All timestamps use Firestore `Timestamp` (not Dart `DateTime` directly)
- Use `FieldValue.serverTimestamp()` for server-side timestamps
- Coordinate precision: Use `double` (sufficient for GPS accuracy)
- Distances: Always in meters (convert for display based on user preference)

