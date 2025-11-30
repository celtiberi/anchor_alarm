
/// Type of alarm event.
enum AlarmType {
  driftExceeded,
  gpsLost,
  gpsInaccurate,
}

/// Severity level for alarm events.
enum Severity {
  alarm,   // Critical - requires immediate attention (e.g., drift exceeded)
  warning, // Informational - user should be aware but not critical (e.g., GPS issues)
}

/// Records when an alarm is triggered (drift beyond radius).
class AlarmEvent {
  final String id;
  final AlarmType type;
  final Severity severity;
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double distanceFromAnchor;
  final bool acknowledged;
  final DateTime? acknowledgedAt;

  AlarmEvent({
    required this.id,
    required this.type,
    required this.severity,
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    required this.distanceFromAnchor,
    this.acknowledged = false,
    this.acknowledgedAt,
  }) : assert(
          id.isNotEmpty,
          'Alarm ID cannot be empty',
        ),
        assert(
          latitude >= -90 && latitude <= 90,
          'Latitude must be between -90 and 90, got $latitude',
        ),
        assert(
          longitude >= -180 && longitude <= 180,
          'Longitude must be between -180 and 180, got $longitude',
        ),
        assert(
          distanceFromAnchor >= 0,
          'Distance from anchor must be non-negative, got $distanceFromAnchor',
        );

  /// Creates AlarmEvent from RTDB map.
  /// Helper method to parse doubles that might be stored as different types in RTDB
  static double _parseDouble(dynamic value) {
    if (value is double) return value;
    if (value is int) return value.toDouble();
    if (value is String) return double.tryParse(value) ?? 0.0;
    return 0.0; // fallback
  }

  /// Helper method to parse timestamps that might be stored as different types in RTDB
  static int _parseTimestamp(dynamic value) {
    if (value is int) return value;
    if (value is double) return value.toInt();
    if (value is String) return int.tryParse(value) ?? 0;
    return 0; // fallback
  }

  factory AlarmEvent.fromMap(Map<String, dynamic> data, String alarmId) {
    return AlarmEvent(
      id: alarmId,
      type: AlarmType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => AlarmType.driftExceeded,
      ),
      severity: Severity.values.firstWhere(
        (e) => e.name == (data['severity'] as String? ?? 'alarm'),
        orElse: () => Severity.alarm,
      ),
      timestamp: DateTime.fromMillisecondsSinceEpoch(_parseTimestamp(data['timestamp'])),
      latitude: _parseDouble(data['latitude']),
      longitude: _parseDouble(data['longitude']),
      distanceFromAnchor: _parseDouble(data['distanceFromAnchor']),
      acknowledged: data['acknowledged'] as bool? ?? false,
      acknowledgedAt: data['acknowledgedAt'] != null
          ? DateTime.fromMillisecondsSinceEpoch((data['acknowledgedAt'] as int))
          : null,
    );
  }

  /// Converts AlarmEvent to RTDB map data.
  Map<String, dynamic> toMap() {
    return {
      'type': type.name,
      'severity': severity.name,
      'timestamp': timestamp.millisecondsSinceEpoch,
      'latitude': latitude,
      'longitude': longitude,
      'distanceFromAnchor': distanceFromAnchor,
      'acknowledged': acknowledged,
      if (acknowledgedAt != null)
        'acknowledgedAt': acknowledgedAt!.millisecondsSinceEpoch,
    };
  }

  /// Creates a copy with updated fields.
  AlarmEvent copyWith({
    String? id,
    AlarmType? type,
    Severity? severity,
    DateTime? timestamp,
    double? latitude,
    double? longitude,
    double? distanceFromAnchor,
    bool? acknowledged,
    DateTime? acknowledgedAt,
  }) {
    return AlarmEvent(
      id: id ?? this.id,
      type: type ?? this.type,
      severity: severity ?? this.severity,
      timestamp: timestamp ?? this.timestamp,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      distanceFromAnchor: distanceFromAnchor ?? this.distanceFromAnchor,
      acknowledged: acknowledged ?? this.acknowledged,
      acknowledgedAt: acknowledgedAt ?? this.acknowledgedAt,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AlarmEvent &&
        other.id == id &&
        other.type == type &&
        other.severity == severity &&
        other.timestamp == timestamp &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.distanceFromAnchor == distanceFromAnchor &&
        other.acknowledged == acknowledged &&
        other.acknowledgedAt == acknowledgedAt;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      type,
      severity,
      timestamp,
      latitude,
      longitude,
      distanceFromAnchor,
      acknowledged,
      acknowledgedAt,
    );
  }

  @override
  String toString() {
    return 'AlarmEvent(id: $id, type: $type, timestamp: $timestamp, distance: $distanceFromAnchor, acknowledged: $acknowledged)';
  }
}

