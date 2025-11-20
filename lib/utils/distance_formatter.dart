import '../models/app_settings.dart';

/// Utility functions for formatting distances, speeds, and other measurements
/// based on the user's unit system preference.

/// Converts meters to feet.
double metersToFeet(double meters) {
  return meters * 3.28084;
}

/// Converts feet to meters.
double feetToMeters(double feet) {
  return feet / 3.28084;
}

/// Formats a distance value (in meters) as a string with appropriate unit.
/// 
/// Example:
/// - formatDistance(50.0, UnitSystem.metric) -> "50.0 m"
/// - formatDistance(50.0, UnitSystem.imperial) -> "164.0 ft"
String formatDistance(double meters, UnitSystem unitSystem) {
  if (unitSystem == UnitSystem.imperial) {
    final feet = metersToFeet(meters);
    return '${feet.toStringAsFixed(1)} ft';
  } else {
    return '${meters.toStringAsFixed(1)} m';
  }
}

/// Formats a distance value (in meters) as a string with appropriate unit,
/// using integer precision (no decimals).
/// 
/// Example:
/// - formatDistanceInt(50.0, UnitSystem.metric) -> "50 m"
/// - formatDistanceInt(50.0, UnitSystem.imperial) -> "164 ft"
String formatDistanceInt(double meters, UnitSystem unitSystem) {
  if (unitSystem == UnitSystem.imperial) {
    final feet = metersToFeet(meters);
    return '${feet.toInt()} ft';
  } else {
    return '${meters.toInt()} m';
  }
}

/// Formats a speed value (in meters per second) as a string in knots.
/// Speed is always displayed in knots (nautical miles per hour) regardless of unit system.
/// 
/// Example:
/// - formatSpeed(5.0, UnitSystem.metric) -> "9.7 kn"
/// - formatSpeed(5.0, UnitSystem.imperial) -> "9.7 kn"
String formatSpeed(double metersPerSecond, UnitSystem unitSystem) {
  final knots = metersPerSecond * 1.94384; // m/s to knots
  return '${knots.toStringAsFixed(1)} kn';
}

/// Formats an accuracy value (in meters) as a string with appropriate unit.
/// 
/// Example:
/// - formatAccuracy(5.0, UnitSystem.metric) -> "5.0 m"
/// - formatAccuracy(5.0, UnitSystem.imperial) -> "16.4 ft"
String formatAccuracy(double meters, UnitSystem unitSystem) {
  return formatDistance(meters, unitSystem);
}

