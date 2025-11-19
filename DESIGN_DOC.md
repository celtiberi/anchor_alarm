# Anchor Alarm App Design Document

## Introduction

This design document outlines the updated architecture and features for a cross-platform anchor alarm app targeted at sailors. The app provides reliable anchor monitoring with drift detection, alarms, and multi-device syncing, leveraging free hosting solutions to avoid subscriptions. Key updates include support for manual anchor position adjustment via finger drag (to correct for timing mismatches in anchor drops), deferral of advanced background power optimization, use of nautical-specific maps for water-based visualization, retention of logging primarily for debugging, and lightweight authentication for pairing (potentially none, given low privacy concerns for boat positions).

The app will be built using Flutter for Android and iOS compatibility, ensuring consistent UI and performance. Focus remains on an MVP with core monitoring and pairing, expandable later.

## Features

Features are categorized into core functionality, multi-device support, and enhancements. Design prioritizes sailor usability, such as intuitive drag-based adjustments and marine-focused visuals.

### Core Anchor Monitoring Features
- **Anchor Setup and Adjustment**: Users set an initial anchor point via current GPS location or manual input. Post-setup, allow easy repositioning by dragging the anchor marker on the map with a finger (e.g., long-press to enter edit mode, then drag to fine-tune). Include a confirmation prompt to lock the new position and recalculate the radius.
- **Drift Detection and Alarms**: Real-time GPS monitoring to detect drift beyond the set radius (adjustable via slider, 20-100 meters default). Triggers customizable alarms (audible, vibrations, screen flashes). Support for dynamic radius based on boat swing using device sensors.
- **Foreground Operation**: App operates in the foreground with basic GPS polling; advanced background modes for power efficiency are deferred to future features.
- **Visualization**: Interactive nautical map view using a marine-specific provider (e.g., flutter_map plugin with OpenSeaMap tiles for free, open-source nautical charts showing depths, buoys, and waterways; alternatives like Mapbox SDK with custom nautical styles or ArcGIS Maps SDK for detailed hydrographic data). Display anchor point, current position, drift path, and radius circle with zoom/pan gestures and overlay stats (distance, speed).
- **Event Logging (Debug-Focused)**: Basic logging of positions, alarms, and timestamps for debugging purposes. Accessible via a hidden developer menu; no user-facing history or exports in MVP.
- **Customization**: Settings for alarm sensitivity (to reduce GPS noise false positives), units (metric/imperial), and themes (day/night mode).

### Multi-Device Monitoring Features
- **Device Pairing**: QR code-based setup where the primary device generates a scannable QR with a unique session token. Secondary devices scan to link for data sharing. Keep authentication lightweight—use simple, temporary tokens without full user accounts; consider skipping formal auth entirely if privacy risks are minimal (e.g., positions aren't sensitive), relying on QR obscurity for access control.
- **Remote Monitoring**: Secondary devices receive live boat position, alarm status, and basic updates. Includes remote alarm acknowledgment and bidirectional notifications.
- **Sync and Notifications**: Primary pushes data to server (e.g., every 15-60 seconds). Use push notifications for alarms. Support unlimited devices per session (no arbitrary cap, as scalability via free-tier backend should handle typical sailor use cases without issue).
- **Offline Handling**: Primary maintains local monitoring if offline, queuing data for sync on reconnection. Secondary shows last-known status with timestamp.
- **Session Management**: Sessions auto-expire (e.g., 24 hours) or manually end. Minimal privacy controls, as data sensitivity is low.

### Additional/Enhancement Features
- **Integrations**: Weather API pulls (e.g., OpenWeatherMap) for wind/tide alerts. Optional smartwatch notifications via Flutter plugins.
- **Safety Tools**: SOS location sharing via SMS/email.
- **Monetization and Accessibility**: Free core with in-app purchases for premiums. Accessibility support (e.g., voice alerts, high-contrast).
- **User Onboarding**: Tutorial covering permissions, quick anchoring, and drag adjustment demo.

Prioritization: MVP focuses on core monitoring with draggable anchors, nautical visuals, and basic pairing. Enhancements like power optimization added later.

## Architecture

Architecture uses a client-server model for scalability and low cost. Flutter manages client-side; backend handles sync with free-tier services.

### High-Level Overview
- **Client-Server Model**: Flutter apps handle local monitoring/UI; backend relays for multi-device.
- **Data Flow**: Primary collects GPS → Local processing for alarms → Push to backend if paired → Backend notifies secondaries.
- **Modularity**: Clean architecture with layers for UI, logic, data.
- **Scalability**: Free-tier start; easy migration if needed.

### Client-Side Architecture (Flutter)
- **Framework**: Flutter/Dart with state management (e.g., Provider) for reactive updates like position drags.
- **Key Components**:
  - **UI Layer**: Screens for map view (with draggable anchor widget), settings, pairing. Use gestures for drag (e.g., GestureDetector for long-press/drag events).
  - **Business Logic Layer**: Services for GPS handling (geolocator plugin), alarm logic, drag repositioning (update anchor coords on gesture end).
  - **Data Layer**: Repositories for local storage (Hive for debug logs) and API interactions.
- **Background Tasks**: Deferred; focus on foreground GPS for MVP.
- **Integrations**: flutter_map or mapbox_gl for nautical maps (e.g., tile provider URL: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png' overlaid on base map); qr_flutter for pairing; firebase_messaging for notifications; permission_handler for GPS.
- **Testing**: Unit tests for drag logic/drift calc; widget tests for UI; integration for flows like pairing.

### Dependencies / Packages
The following Dart/Flutter packages are recommended based on their popularity, performance, and suitability for the app's features in 2025. These are sourced from pub.dev and community recommendations for reliability and active maintenance.

- **geolocator**: For GPS location tracking, permission handling, and real-time position updates. It's cross-platform, accurate, and supports foreground monitoring.
- **flutter_map**: For interactive nautical maps with custom tile providers (e.g., OpenSeaMap for marine charts). It's lightweight, open-source, and ideal for overlaying depths/buoys without relying on Google Maps.
- **qr_flutter**: For QR code generation on the primary device. Simple and efficient for creating pairing codes.
- **mobile_scanner**: For QR code scanning on secondary devices. High-performance, supports real-time scanning, and works across platforms.
- **riverpod**: For state management, handling reactive updates like position changes and session states. Modern, type-safe, and preferred for scalable apps in 2025.
- **hive**: For local storage of debug logs and offline data queuing. Fast, NoSQL, and lightweight for key-value or object storage.
- **logger**: For debugging logs. Simple, colorful console output for tracking events like alarms and positions.
- **permission_handler**: For managing GPS, notification, and other permissions across Android/iOS. Unified API for requests and checks.
- **firebase_core, cloud_firestore, firebase_auth, firebase_messaging**: For Firebase integration—core setup, realtime database for sync, lightweight auth (tokens), and push notifications. Essential for multi-device features.
- **dio**: For HTTP API calls (e.g., weather integrations). Advanced networking with interceptors, better than basic http for robustness.
- **flutter_local_notifications**: For local alarms and foreground notifications, complementing Firebase for cross-platform alerts.

These packages can be added via `flutter pub add <package_name>` and should be imported as needed in the code. Prioritize minimal dependencies for the MVP to keep the app lightweight.

### Server-Side Architecture
- **Backend Service**: Firebase (free tier) for realtime DB/functions. Alternatives: Supabase or Vercel-hosted Node.js.
- **Components**:
  - **Authentication**: Lightweight—generate simple session tokens via QR; no mandatory user auth, but tokens prevent casual access.
  - **Database**: Firestore for sessions, positions, alarms. Schema: Sessions (token, devices, expiry), Positions (timestamp, lat/long).
  - **API**: Functions for data push/pull; WebSockets for sync.
  - **Notifications**: FCM for alerts.
- **Deployment**: Serverless; monitor free limits.

### Data Models
- **Anchor Model**: { id, lat, long, radius, adjustable: true }
- **Position Update**: { timestamp, lat, long, speed, accuracy }
- **Alarm Event**: { type, timestamp, position }
- **Pairing Session**: { token, primaryId, secondaryIds, expiry }

### Security and Privacy
- **Encryption**: HTTPS for APIs; minimal data collection given low sensitivity.
- **Compliance**: Basic location privacy; delete expired sessions.
- **Authentication**: Token-only; evaluate no-auth option post-MVP.

### Non-Functional Requirements
- **Performance**: Foreground GPS intervals (10-30 seconds); nautical map rendering optimized for marine use.
- **Reliability**: Handle offline gracefully; debug logs for error tracking.
- **Compatibility**: Android 8+, iOS 13+; test on devices for drag gestures and maps.
- **Accessibility**: Large targets for touch; voice feedback.

This updated design incorporates user feedback for practical sailing needs, maintaining a lean, free-focused approach with Flutter's efficiency.