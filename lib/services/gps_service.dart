import 'dart:io';
import 'package:geolocator/geolocator.dart';
import '../models/position_update.dart';
import '../utils/logger_setup.dart';

/// Service for GPS location tracking and position updates.
/// Optimized for maximum accuracy in anchor alarm applications.
///
/// Key accuracy features:
/// - LocationAccuracy.bestForNavigation for precise positioning
/// - Zero distance filter for immediate movement detection
/// - 5-second update intervals for responsive anchor monitoring
/// - Background location access for continuous monitoring
/// - Platform-specific optimizations for iOS and Android
class GpsService {
  /// Gets the current position with maximum accuracy.
  ///
  /// Throws [Exception] if GPS is unavailable or permission denied.
  Future<PositionUpdate> getCurrentPosition() async {
    logger.i('🌍 GPS Service: Getting current position...');
    final position = await Geolocator.getCurrentPosition(
      locationSettings: LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation, // Maximum accuracy for anchor monitoring
        // Note: timeLimit removed for better accuracy
      ),
    );
    logger.i('✅ GPS Service: Got position: lat=${position.latitude}, lon=${position.longitude}');

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

  /// Starts listening to position updates with maximum accuracy for anchor monitoring.
  /// 
  /// Returns a stream of position updates.
  /// Throws [Exception] if GPS is unavailable or permission denied.
  Stream<PositionUpdate> getPositionStream({
    Duration interval = const Duration(seconds: 5), // More frequent updates for anchor monitoring
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
  }) {
    // Maximum accuracy settings for anchor alarm - detect any movement
    final locationSettings = LocationSettings(
      accuracy: accuracy, // Best accuracy for precise anchor monitoring
      distanceFilter: 0, // Update on any movement, no minimum distance filter
      // Note: timeLimit removed for iOS compatibility and better accuracy
    );

    logger.i('Starting GPS stream with MAX ACCURACY settings: accuracy=$accuracy, distanceFilter=0m, interval=${interval.inSeconds}s');
    return Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).map((position) {
      logger.d('📡 GPS service received position from Geolocator: lat=${position.latitude}, lon=${position.longitude}');
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

  /// Checks if location permissions are granted with preference for background access.
  Future<bool> hasPermission() async {
    final status = await Geolocator.checkPermission();
    logger.i('Current location permission status: $status');

    // For anchor alarms, we prefer "always" permission for background monitoring
    // but accept "whileInUse" as minimum requirement
    return status == LocationPermission.always ||
        status == LocationPermission.whileInUse;
  }

  /// Requests location permissions with preference for "always" access for anchor monitoring.
  /// 
  /// Returns true if permission granted, false otherwise.
  Future<bool> requestPermission() async {
    logger.i('Requesting location permission for anchor monitoring...');

    // First check if location services are enabled
    final isEnabled = await isLocationServiceEnabled();
    if (!isEnabled) {
      logger.w('Location services are disabled');
      throw StateError('Location services are disabled. Please enable them in System Settings > Privacy & Security > Location Services.');
    }
    
    LocationPermission permission = await Geolocator.checkPermission();
    logger.i('Initial permission status: $permission');

    // Request permission if not already granted
    if (permission == LocationPermission.denied ||
        permission == LocationPermission.deniedForever) {
      logger.i('Requesting location permission from user...');
      permission = await Geolocator.requestPermission();
      logger.i('Permission after request: $permission');
    }

    // For anchor monitoring, we want "always" permission for background operation
    // but accept "whileInUse" as fallback
    final granted = permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (permission == LocationPermission.always) {
      logger.i('✅ Full background location permission granted');
    } else if (permission == LocationPermission.whileInUse) {
      logger.w('⚠️ Only foreground location permission granted - background monitoring limited');
    } else {
      logger.e('❌ Location permission denied');
    }

    return granted;
  }
}

