import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents the current GPS position of the boat.
class PositionUpdate {
  final DateTime timestamp;
  final double latitude;
  final double longitude;
  final double? speed;
  final double? accuracy;
  final double? altitude;
  final double? heading;

  const PositionUpdate({
    required this.timestamp,
    required this.latitude,
    required this.longitude,
    this.speed,
    this.accuracy,
    this.altitude,
    this.heading,
  }) : assert(
          latitude >= -90 && latitude <= 90,
          'Latitude must be between -90 and 90, got $latitude',
        ),
        assert(
          longitude >= -180 && longitude <= 180,
          'Longitude must be between -180 and 180, got $longitude',
        ),
        assert(
          speed == null || speed >= 0,
          'Speed must be non-negative, got $speed',
        ),
        assert(
          accuracy == null || accuracy >= 0,
          'Accuracy must be non-negative, got $accuracy',
        ),
        assert(
          heading == null || (heading >= 0 && heading <= 360),
          'Heading must be between 0 and 360, got $heading',
        );

  /// Creates PositionUpdate from Firestore document.
  factory PositionUpdate.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return PositionUpdate(
      timestamp: (data['timestamp'] as Timestamp).toDate(),
      latitude: data['latitude'] as double,
      longitude: data['longitude'] as double,
      speed: data['speed'] as double?,
      accuracy: data['accuracy'] as double?,
      altitude: data['altitude'] as double?,
      heading: data['heading'] as double?,
    );
  }

  /// Converts PositionUpdate to Firestore document data.
  Map<String, dynamic> toFirestore() {
    return {
      'timestamp': Timestamp.fromDate(timestamp),
      'latitude': latitude,
      'longitude': longitude,
      if (speed != null) 'speed': speed,
      if (accuracy != null) 'accuracy': accuracy,
      if (altitude != null) 'altitude': altitude,
      if (heading != null) 'heading': heading,
    };
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is PositionUpdate &&
        other.timestamp == timestamp &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.speed == speed &&
        other.accuracy == accuracy &&
        other.altitude == altitude &&
        other.heading == heading;
  }

  @override
  int get hashCode {
    return Object.hash(
      timestamp,
      latitude,
      longitude,
      speed,
      accuracy,
      altitude,
      heading,
    );
  }

  @override
  String toString() {
    return 'PositionUpdate(timestamp: $timestamp, lat: $latitude, lon: $longitude, speed: $speed, accuracy: $accuracy)';
  }
}

