import 'dart:math';

/// Calculates the distance between two coordinates using the Haversine formula.
/// 
/// Returns distance in meters.
/// Throws [ArgumentError] if coordinates are invalid.
double calculateDistance(
  double lat1,
  double lon1,
  double lat2,
  double lon2,
) {
  if (lat1 < -90 || lat1 > 90) {
    throw ArgumentError('Latitude 1 must be between -90 and 90, got $lat1');
  }
  if (lat2 < -90 || lat2 > 90) {
    throw ArgumentError('Latitude 2 must be between -90 and 90, got $lat2');
  }
  if (lon1 < -180 || lon1 > 180) {
    throw ArgumentError('Longitude 1 must be between -180 and 180, got $lon1');
  }
  if (lon2 < -180 || lon2 > 180) {
    throw ArgumentError('Longitude 2 must be between -180 and 180, got $lon2');
  }

  const double earthRadiusMeters = 6371000; // Earth's radius in meters

  final double dLat = _toRadians(lat2 - lat1);
  final double dLon = _toRadians(lon2 - lon1);

  final double a = sin(dLat / 2) * sin(dLat / 2) +
      cos(_toRadians(lat1)) *
          cos(_toRadians(lat2)) *
          sin(dLon / 2) *
          sin(dLon / 2);

  final double c = 2 * atan2(sqrt(a), sqrt(1 - a));

  return earthRadiusMeters * c;
}

/// Converts degrees to radians.
double _toRadians(double degrees) {
  return degrees * (pi / 180);
}

