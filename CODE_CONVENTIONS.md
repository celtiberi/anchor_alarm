# Code Conventions

This document outlines coding patterns, conventions, and best practices for the Anchor Alarm app.

## Architecture Principles

### Clean Architecture Layers

1. **UI Layer** (`lib/ui/`)
   - Screens: `lib/ui/screens/`
   - Widgets: `lib/ui/widgets/`
   - No business logic, only presentation
   - Consumes Riverpod providers for state

2. **Business Logic Layer** (`lib/services/`)
   - GPS service, alarm service, pairing service
   - Pure Dart, no Flutter dependencies
   - Testable in isolation

3. **Data Layer** (`lib/repositories/`)
   - Firestore repository, local storage repository
   - Abstracts data sources
   - Handles serialization/deserialization

4. **Models** (`lib/models/`)
   - Data classes with validation
   - Immutable (use `final` fields)
   - Include `fromJson`/`toJson` for Firestore

5. **Providers** (`lib/providers/`)
   - Riverpod providers for state management
   - Naming: `{feature}Provider`, `{feature}Notifier`

## State Management (Riverpod)

### Provider Naming
- State providers: `{name}Provider` (e.g., `anchorProvider`)
- Notifiers: `{name}Notifier` (e.g., `anchorNotifier`)
- Future providers: `{name}FutureProvider`
- Stream providers: `{name}StreamProvider`

### Provider Structure
```dart
// State provider for simple values
final anchorProvider = StateProvider<Anchor?>((ref) => null);

// Notifier for complex state
final anchorNotifierProvider = StateNotifierProvider<AnchorNotifier, AnchorState>(
  (ref) => AnchorNotifier(ref.read(gpsServiceProvider)),
);

// Future provider for async data
final sessionFutureProvider = FutureProvider<PairingSession?>((ref) async {
  final repo = ref.read(sessionRepositoryProvider);
  return repo.getActiveSession();
});
```

### Provider Location
- Keep providers close to the feature they serve
- Shared providers in `lib/providers/`
- Feature-specific providers can live in feature folders

## Error Handling

### Fail-Fast Principle
**CRITICAL**: Do not handle errors gracefully. Fail immediately with clear error messages.

```dart
// ✅ GOOD: Fail fast with clear error
void setAnchor(double lat, double lon) {
  if (lat < -90 || lat > 90) {
    throw ArgumentError('Latitude must be between -90 and 90, got $lat');
  }
  if (lon < -180 || lon > 180) {
    throw ArgumentError('Longitude must be between -180 and 180, got $lon');
  }
  // ... proceed
}

// ❌ BAD: Silent error handling
void setAnchor(double lat, double lon) {
  if (lat < -90 || lat > 90) {
    return; // Silent failure - BAD!
  }
  // ...
}
```

### Exception Types
- Use `ArgumentError` for invalid parameters
- Use `StateError` for invalid state transitions
- Use `UnimplementedError` for not-yet-implemented features
- Let platform errors (GPS, network) bubble up - don't catch and hide

### Logging
- Use `logger` package for debug logs
- Log errors with stack traces: `logger.e('Error message', error, stackTrace)`
- Don't log sensitive data (tokens, positions are OK per design doc)

## Naming Conventions

### Files
- Snake_case: `anchor_service.dart`, `position_update.dart`
- One class per file (except related classes)
- File name matches primary class name

### Classes
- PascalCase: `AnchorService`, `PositionUpdate`, `AlarmNotifier`
- Descriptive names: `GpsLocationService` not `GpsService` (if there are multiple GPS services)

### Variables/Functions
- camelCase: `currentPosition`, `calculateDistance()`
- Boolean: `isActive`, `hasPermission`, `canMonitor`
- Private: `_privateField`, `_privateMethod()`

### Constants
- `SCREAMING_SNAKE_CASE`: `DEFAULT_RADIUS`, `MAX_RADIUS`
- Or `static const` in classes: `static const double defaultRadius = 50.0;`

## Code Organization

### Imports
- Group imports: Flutter, packages, relative
- Sort alphabetically within groups
- Prefer explicit imports over `export` files

```dart
// Flutter
import 'package:flutter/material.dart';

// Packages
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:geolocator/geolocator.dart';

// Relative
import '../models/anchor.dart';
import '../services/gps_service.dart';
```

### File Structure
```dart
// 1. Imports
// 2. Constants (if any)
// 3. Class definition
// 4. Public methods
// 5. Private methods
```

## Testing

### Unit Tests
- Test business logic in isolation
- Mock dependencies (GPS, Firestore)
- Test edge cases and error conditions

### Widget Tests
- Test UI components
- Use `WidgetTester` for interactions
- Test state changes

### Integration Tests
- Test full user flows (pairing, alarm triggering)
- Use real services where possible

## Documentation

### Code Comments
- Explain **why**, not **what** (code should be self-documenting)
- Document public APIs
- Use Dart doc comments for public classes/methods

```dart
/// Calculates the distance between two coordinates using Haversine formula.
/// 
/// Returns distance in meters.
/// Throws [ArgumentError] if coordinates are invalid.
double calculateDistance(double lat1, double lon1, double lat2, double lon2) {
  // ...
}
```

## Dependencies

### Adding Dependencies
- Check if existing package can be used
- Prefer well-maintained packages (pub.dev score, recent updates)
- Keep dependencies minimal for MVP

### Version Constraints
- Use `^` for minor updates: `^2.6.1`
- Pin major versions if breaking changes are common
- Update dependencies regularly

## Platform-Specific Code

### Conditional Imports
```dart
// lib/services/platform_service.dart
import 'platform_service_stub.dart'
    if (dart.library.io) 'platform_service_io.dart'
    if (dart.library.html) 'platform_service_web.dart';
```

### Platform Checks
```dart
import 'dart:io';

if (Platform.isAndroid) {
  // Android-specific code
} else if (Platform.isIOS) {
  // iOS-specific code
}
```

## Performance

### GPS Polling
- Default interval: 15 seconds (configurable)
- Don't poll faster than 10 seconds (battery drain)
- Stop polling when app is backgrounded (MVP: foreground only)

### Map Rendering
- Use `flutter_map` efficiently
- Limit visible markers/polylines
- Debounce map updates if needed

### State Updates
- Use `ref.read()` for one-time access
- Use `ref.watch()` for reactive updates
- Avoid unnecessary rebuilds

## Security

### Sensitive Data
- Don't log tokens or session IDs in production
- Use HTTPS for all API calls
- Validate all user inputs

### Permissions
- Request permissions explicitly
- Handle denial gracefully (show message, don't crash)
- Check permissions before operations

