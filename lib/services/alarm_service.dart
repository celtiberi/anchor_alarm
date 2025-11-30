import 'package:uuid/uuid.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anchor.dart';
import '../models/position_update.dart';
import '../models/alarm_event.dart';
import '../models/app_settings.dart';
import '../providers/settings_provider.dart';
import '../utils/distance_calculator.dart';
import '../utils/logger_setup.dart';

/// Provider for AlarmService instance with dependency injection.
/// Automatically disposes when no longer needed for memory efficiency.
final alarmServiceProvider = Provider.autoDispose<AlarmService>((ref) {
  final settings = ref.watch(settingsProvider);
  return AlarmService(settings: settings);
});

/// Service for detecting drift and triggering alarms.
///
/// Handles GPS accuracy filtering, sensitivity-based alarm triggering, and event creation.
/// Sensitivity range: 0.0 (full radius) to 1.0 (20% radius reduction).
///
/// Example usage:
/// ```dart
/// final service = AlarmService(settings: appSettings);
/// final distance = service.checkDrift(anchor, position);
/// if (distance != null && service.shouldTriggerAlarm(anchor, distance)) {
///   final alarm = service.createDriftAlarm(anchor, position, distance);
///   // Handle alarm...
/// }
/// ```
class AlarmService {
  final AppSettings settings;
  final Uuid _uuid = Uuid();

  AlarmService({required this.settings});

  /// Checks if the current position exceeds the anchor radius.
  ///
  /// Returns the distance from anchor in meters.
  /// Returns null if anchor is not set, position is invalid, or GPS accuracy is too poor.
  double? checkDrift(Anchor? anchor, PositionUpdate position) {
    if (anchor == null || !anchor.isActive) {
      return null;
    }

    // Check GPS accuracy - ignore positions that are too inaccurate
    if (position.accuracy == null ||
        position.accuracy! > settings.gpsAccuracyThreshold) {
      logger.d(
        'Ignoring position due to poor GPS accuracy: ${position.accuracy}m > ${settings.gpsAccuracyThreshold}m',
      );
      return null;
    }

    final distance = calculateDistance(
      anchor.latitude,
      anchor.longitude,
      position.latitude,
      position.longitude,
    );

    // Validate distance calculation results
    if (distance.isNaN || distance.isInfinite) {
      logger.w('Invalid distance calculated (NaN/Infinite), ignoring position');
      return null;
    }

    logger.d(
      'Calculated drift distance: ${distance.toStringAsFixed(1)}m from anchor (accuracy: ${position.accuracy}m)',
    );
    return distance;
  }

  /// Determines if an alarm should be triggered based on drift.
  ///
  /// Returns true if distance exceeds radius (accounting for sensitivity).
  /// Higher sensitivity = smaller effective radius (more sensitive to drift).
  ///
  /// Formula: effectiveRadius = anchor.radius * (1.0 - sensitivity * 0.2)
  /// Example: sensitivity 0.5 → effectiveRadius = radius * (1 - 0.5*0.2) = radius * 0.9
  bool shouldTriggerAlarm(Anchor anchor, double distanceFromAnchor) {
    // Apply sensitivity: higher sensitivity = smaller effective radius
    // sensitivity 0.0 = no filtering (use full radius), 1.0 = maximum filtering (reduce radius by 20%)
    const double maxSensitivityReduction =
        0.2; // Maximum 20% reduction in radius
    final sensitivityMultiplier =
        settings.alarmSensitivity.clamp(0.0, 1.0) * maxSensitivityReduction;
    final effectiveRadius = anchor.radius * (1.0 - sensitivityMultiplier);

    final shouldTrigger = distanceFromAnchor > effectiveRadius;

    if (shouldTrigger) {
      logger.w(
        '🚨 Alarm triggered: distance ${distanceFromAnchor.toStringAsFixed(1)}m > effective radius ${effectiveRadius.toStringAsFixed(1)}m (sensitivity: ${settings.alarmSensitivity})',
      );
    }

    return shouldTrigger;
  }

  /// Creates an alarm event for drift exceeded (severity: alarm).
  AlarmEvent createDriftAlarm(
    Anchor anchor,
    PositionUpdate position,
    double distanceFromAnchor,
  ) {
    return AlarmEvent(
      id: _generateAlarmId(),
      type: AlarmType.driftExceeded,
      severity: Severity.alarm,
      timestamp: position.timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      distanceFromAnchor: distanceFromAnchor,
    );
  }

  /// Creates a warning event for GPS lost (severity: warning).
  AlarmEvent createGpsLostWarning(
    PositionUpdate? lastPosition,
    Anchor? anchor,
  ) {
    // Calculate distance from anchor if both position and anchor are available
    double distanceFromAnchor = 0.0;
    if (lastPosition != null && anchor != null) {
      // Guard against invalid positions (e.g., default 0.0,0.0 coordinates)
      // Use small tolerance to avoid false positives for valid positions near equator/prime meridian
      const double tolerance = 0.0001; // ~10 meters tolerance
      if (lastPosition.latitude.abs() < tolerance &&
          lastPosition.longitude.abs() < tolerance) {
        distanceFromAnchor = 0.0; // Likely invalid default position
      } else {
        distanceFromAnchor = calculateDistance(
          anchor.latitude,
          anchor.longitude,
          lastPosition.latitude,
          lastPosition.longitude,
        );
      }
    }

    return AlarmEvent(
      id: _generateAlarmId(),
      type: AlarmType.gpsLost,
      severity: Severity.warning,
      timestamp: DateTime.now(),
      latitude: lastPosition?.latitude ?? 0.0,
      longitude: lastPosition?.longitude ?? 0.0,
      distanceFromAnchor: distanceFromAnchor,
    );
  }

  /// Creates a warning event for GPS inaccurate (severity: warning).
  AlarmEvent createGpsInaccurateWarning(
    PositionUpdate position,
    Anchor? anchor,
  ) {
    // Calculate distance from anchor if available
    double distanceFromAnchor = 0.0;
    if (anchor != null) {
      // Guard against invalid positions (e.g., default 0.0,0.0 coordinates)
      // Use small tolerance to avoid false positives for valid positions near equator/prime meridian
      const double tolerance = 0.0001; // ~10 meters tolerance
      if (position.latitude.abs() < tolerance &&
          position.longitude.abs() < tolerance) {
        distanceFromAnchor = 0.0; // Likely invalid default position
      } else {
        distanceFromAnchor = calculateDistance(
          anchor.latitude,
          anchor.longitude,
          position.latitude,
          position.longitude,
        );
      }
    }

    return AlarmEvent(
      id: _generateAlarmId(),
      type: AlarmType.gpsInaccurate,
      severity: Severity.warning,
      timestamp: position.timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      distanceFromAnchor: distanceFromAnchor,
    );
  }

  /// Checks if GPS should be considered "lost" based on time since last update.
  /// Useful for creating GPS lost warnings when no positions received for extended period.
  /// Returns true if no GPS updates received for more than 30 seconds.
  bool isGpsLost(Duration timeSinceLastUpdate) {
    return timeSinceLastUpdate >
        const Duration(seconds: 30); // 30 second timeout
  }

  /// Checks if a position has poor GPS accuracy that should trigger warnings.
  /// Returns true if position accuracy exceeds the configured threshold.
  bool isGpsInaccurate(PositionUpdate position) {
    return position.accuracy != null &&
        position.accuracy! > settings.gpsAccuracyThreshold;
  }

  /// Generates a unique alarm ID using UUID for guaranteed uniqueness.
  String _generateAlarmId() {
    return _uuid.v4();
  }
}
