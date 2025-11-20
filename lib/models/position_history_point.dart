import 'package:latlong2/latlong.dart';

/// Represents a single position point in the history with timestamp.
class PositionHistoryPoint {
  final LatLng position;
  final DateTime timestamp;

  PositionHistoryPoint({
    required this.position,
    required this.timestamp,
  });
}

