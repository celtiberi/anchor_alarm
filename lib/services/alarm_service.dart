import '../models/anchor.dart';
import '../models/position_update.dart';
import '../models/alarm_event.dart';
import '../models/app_settings.dart';
import '../utils/distance_calculator.dart';

/// Service for detecting drift and triggering alarms.
class AlarmService {
  final AppSettings settings;

  AlarmService({required this.settings});

  /// Checks if the current position exceeds the anchor radius.
  /// 
  /// Returns the distance from anchor in meters.
  /// Returns null if anchor is not set or position is invalid.
  double? checkDrift(Anchor? anchor, PositionUpdate position) {
    if (anchor == null || !anchor.isActive) {
      return null;
    }

    final distance = calculateDistance(
      anchor.latitude,
      anchor.longitude,
      position.latitude,
      position.longitude,
    );

    return distance;
  }

  /// Determines if an alarm should be triggered based on drift.
  /// 
  /// Returns true if distance exceeds radius (accounting for sensitivity).
  bool shouldTriggerAlarm(Anchor anchor, double distanceFromAnchor) {
    // Apply sensitivity: higher sensitivity = smaller effective radius
    // sensitivity 0.0 = no filtering, 1.0 = maximum filtering
    final effectiveRadius = anchor.radius * (1.0 - settings.alarmSensitivity * 0.2);
    
    return distanceFromAnchor > effectiveRadius;
  }

  /// Creates an alarm event for drift exceeded.
  AlarmEvent createDriftAlarm(
    Anchor anchor,
    PositionUpdate position,
    double distanceFromAnchor,
  ) {
    return AlarmEvent(
      id: _generateAlarmId(),
      type: AlarmType.driftExceeded,
      timestamp: position.timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      distanceFromAnchor: distanceFromAnchor,
    );
  }

  /// Creates an alarm event for GPS lost.
  AlarmEvent createGpsLostAlarm(PositionUpdate? lastPosition) {
    return AlarmEvent(
      id: _generateAlarmId(),
      type: AlarmType.gpsLost,
      timestamp: DateTime.now(),
      latitude: lastPosition?.latitude ?? 0.0,
      longitude: lastPosition?.longitude ?? 0.0,
      distanceFromAnchor: 0.0,
    );
  }

  /// Creates an alarm event for GPS inaccurate.
  AlarmEvent createGpsInaccurateAlarm(
    PositionUpdate position,
    double minRequiredAccuracy,
  ) {
    return AlarmEvent(
      id: _generateAlarmId(),
      type: AlarmType.gpsInaccurate,
      timestamp: position.timestamp,
      latitude: position.latitude,
      longitude: position.longitude,
      distanceFromAnchor: 0.0,
    );
  }

  /// Generates a unique alarm ID.
  String _generateAlarmId() {
    return DateTime.now().millisecondsSinceEpoch.toString();
  }
}

