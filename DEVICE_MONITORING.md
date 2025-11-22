# Design Document: Multi-Device Monitoring for Boat Anchor Alarm App

## Version: 1.0
## Date: November 20, 2025
## Author: Grok (xAI Assistant)
## Purpose: Outline architecture, implementation, and UX for read-only monitoring on secondary devices via QR code pairing, with primary as controller.

## 1. Overview
### 1.1 Problem
Enable secondary devices to monitor anchor, boat position, and alarms in real-time from primary. Secondaries read-only; pairing via QR scan.

### 1.2 Goals
- Seamless pairing: Scan QR to enter monitoring mode.
- Real-time sync: Data updates across devices.
- Security: Primary writes, secondaries read.
- Offline: Show last data.
- Support 5-10 secondaries.

### 1.3 Non-Goals
- User accounts.
- Bi-directional edits.
- Offline-only pairing.

### 1.4 Assumptions
- Devices have app and internet.
- Use Firebase for sync.

## 2. Architecture
### 2.1 Components
- Frontend: Flutter/Riverpod.
- Backend: Firebase Realtime Database.
- Pairing: QR with deep link.
- Sync: Primary pushes; secondaries stream.

### 2.2 Data Flow
1. Primary sets anchor, generates QR with session ID/token.
2. Secondary scans, parses link, auths, subscribes.
3. Primary updates Firebase on changes.
4. Firebase pushes to secondaries.
5. Primary revokes: Deletes session.

### 2.3 Data Model (Firebase)
- `/sessions/{sessionId}`: {anchor: {lat, lon, radius, isActive}, boatPosition: {lat, lon, speed?, accuracy?, timestamp}, alarms: [AlarmEvent], positionHistory: [{lat, lon, timestamp}] (last 500), primaryDeviceId, expiration}.

### 2.4 Packages
- firebase_core, cloud_firestore, firebase_auth.
- qr_flutter, uni_links/app_links, device_info_plus, uuid.

## 3. Pairing
### 3.1 Primary
- "Share Monitoring" button: Generate session, QR with `anchorapp://join?sessionId=...&token=...`.
- Modal: QR, instructions, refresh.

### 3.2 Secondary
- No join screen: Deep link launches/switches to monitoring.
- Parse link, auth, store session in Hive, enter read-only mode.
- Error: SnackBar, stay primary.

## 4. UI/UX
### 4.1 Primary
- MapScreen: Editable + Share button.

### 4.2 Secondary
- Auto-enter on scan: Read-only MapScreen (hide controls).
- Header: "Monitoring Session" + Disconnect (clears session).

### 4.3 Common
- Role provider (bool, Hive): Conditional rendering.

## 5. Implementation
### 5.1 Providers/Sync
- Primary: Write to Firebase on updates.
- Secondary: Override with Firebase streams.
- Throttle position writes.

### 5.2 Security
- Anon auth; rules: Write if auth.uid == primaryId.

### 5.3 Testing/Edges
- Unit/integration/e2e.
- Offline, expired session, multiples.

## 6. Risks/Mitigations
- Deep links: Test platforms.
- Costs: Throttle writes.
- Privacy: Consent on share.