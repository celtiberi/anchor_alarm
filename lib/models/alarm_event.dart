import 'package:cloud_firestore/cloud_firestore.dart';

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

  /// Creates AlarmEvent from Firestore document.
  factory AlarmEvent.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AlarmEvent(
      id: doc.id,
      type: AlarmType.values.firstWhere(
        (e) => e.name == data['type'],
        orElse: () => AlarmType.driftExceeded,
      ),
      severity: Severity.values.firstWhere(
        (e) => e.name == (data['severity'] as String? ?? 'alarm'),
        orElse: () => Severity.alarm,
      ),
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      latitude: data['latitude'] as double,
      longitude: data['longitude'] as double,
      distanceFromAnchor: data['distanceFromAnchor'] as double,
      acknowledged: data['acknowledged'] as bool? ?? false,
      acknowledgedAt: data['acknowledgedAt'] != null
          ? (data['acknowledgedAt'] as Timestamp).toDate()
          : null,
    );
  }

  /// Converts AlarmEvent to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'id': id,
      'type': type.name,
      'severity': severity.name,
      'timestamp': Timestamp.fromDate(timestamp),
      'latitude': latitude,
      'longitude': longitude,
      'distanceFromAnchor': distanceFromAnchor,
      'acknowledged': acknowledged,
      if (acknowledgedAt != null)
        'acknowledgedAt': Timestamp.fromDate(acknowledgedAt!),
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

