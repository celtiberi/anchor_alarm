import 'package:geolocator/geolocator.dart';
import '../models/position_update.dart';

/// Service for GPS location tracking and position updates.
class GpsService {
  /// Gets the current position.
  /// 
  /// Throws [Exception] if GPS is unavailable or permission denied.
  Future<PositionUpdate> getCurrentPosition() async {
    final position = await Geolocator.getCurrentPosition(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.high,
      ),
    );

    // Normalize heading: -1.0 or invalid values mean "not available", so use null
    // Note: position.heading is non-nullable in geolocator, but -1.0 means "not available"
    double? heading = (position.heading >= 0 && position.heading <= 360) 
        ? position.heading 
        : null;
    
    return PositionUpdate(
      timestamp: DateTime.now(),
      latitude: position.latitude,
      longitude: position.longitude,
      speed: position.speed >= 0 ? position.speed : null,
      accuracy: position.accuracy >= 0 ? position.accuracy : null,
      altitude: position.altitude,
      heading: heading,
    );
  }

  /// Starts listening to position updates.
  /// 
  /// Returns a stream of position updates.
  /// Throws [Exception] if GPS is unavailable or permission denied.
  Stream<PositionUpdate> getPositionStream({
    Duration interval = const Duration(seconds: 15),
    LocationAccuracy accuracy = LocationAccuracy.high,
  }) {
    return Geolocator.getPositionStream(
      locationSettings: LocationSettings(
        accuracy: accuracy,
        distanceFilter: 0, // Update on any movement
        timeLimit: interval,
      ),
    ).map((position) {
      // Normalize heading: -1.0 or invalid values mean "not available", so use null
      // Note: position.heading is non-nullable in geolocator, but -1.0 means "not available"
      double? heading = (position.heading >= 0 && position.heading <= 360) 
          ? position.heading 
          : null;
      
      return PositionUpdate(
        timestamp: DateTime.now(),
        latitude: position.latitude,
        longitude: position.longitude,
        speed: position.speed >= 0 ? position.speed : null,
        accuracy: position.accuracy >= 0 ? position.accuracy : null,
        altitude: position.altitude,
        heading: heading,
      );
    });
  }

  /// Checks if location services are enabled.
  Future<bool> isLocationServiceEnabled() async {
    return await Geolocator.isLocationServiceEnabled();
  }

  /// Checks if location permissions are granted.
  Future<bool> hasPermission() async {
    final status = await Geolocator.checkPermission();
    return status == LocationPermission.always ||
        status == LocationPermission.whileInUse;
  }

  /// Requests location permissions.
  /// 
  /// Returns true if permission granted, false otherwise.
  Future<bool> requestPermission() async {
    // First check if location services are enabled
    final isEnabled = await isLocationServiceEnabled();
    if (!isEnabled) {
      throw StateError('Location services are disabled. Please enable them in System Settings > Privacy & Security > Location Services.');
    }
    
    LocationPermission permission = await Geolocator.checkPermission();
    
    // On macOS, if permission is denied, we need to request it
    // The system will show a dialog if Info.plist and entitlements are correct
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
    }

    return permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;
  }
}

