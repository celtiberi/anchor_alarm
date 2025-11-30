import 'dart:io';
import 'package:geolocator/geolocator.dart';
import '../models/position_update.dart';
import '../utils/logger_setup.dart';

/// Custom exceptions for GPS service operations.
class GpsServiceException implements Exception {
  final String message;
  GpsServiceException(this.message);

  @override
  String toString() => 'GpsServiceException: $message';
}

class GpsPermissionDeniedException implements Exception {
  final String message;
  GpsPermissionDeniedException(this.message);

  @override
  String toString() => 'GpsPermissionDeniedException: $message';
}

/// Service for GPS location tracking and position updates.
/// Optimized for maximum accuracy in anchor alarm applications.
///
/// Note: Requires FOREGROUND_SERVICE and FOREGROUND_SERVICE_LOCATION permissions in AndroidManifest.xml.
/// For app-terminated background, consider integrating with a background task plugin.
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
  /// Throws [GpsServiceException] if GPS is unavailable or permission denied.
  Future<PositionUpdate> getCurrentPosition() async {
    logger.i('🌍 GPS Service: Getting current position...');

    try {
      final position = await Geolocator.getCurrentPosition(
        locationSettings: LocationSettings(
          accuracy: LocationAccuracy
              .bestForNavigation, // Maximum accuracy for anchor monitoring
          // Note: timeLimit removed for better accuracy
        ),
      );

      logger.i(
        '✅ GPS Service: Got position: lat=${position.latitude}, lon=${position.longitude}',
      );

      // Normalize heading: -1.0 or invalid values mean "not available", so use null
      // Note: position.heading is non-nullable in geolocator, but -1.0 means "not available"
      double? heading = (position.heading >= 0 && position.heading <= 360)
          ? position.heading
          : null;

      return PositionUpdate(
        timestamp: position.timestamp, // Use GPS acquisition timestamp
        latitude: position.latitude,
        longitude: position.longitude,
        speed: position.speed >= 0 ? position.speed : null,
        accuracy: position.accuracy >= 0 ? position.accuracy : null,
        altitude: position.altitude,
        heading: heading,
      );
    } on PermissionDeniedException {
      throw GpsPermissionDeniedException(
        'Location permission denied for anchor monitoring',
      );
    } catch (e) {
      logger.e('❌ Failed to get current position', error: e);
      throw GpsServiceException('Failed to get current position: $e');
    }
  }

  /// Starts listening to position updates with maximum accuracy for anchor monitoring.
  ///
  /// Returns a stream of position updates with no enforced interval—updates occur as soon as available.
  /// Throws [GpsServiceException] if GPS is unavailable or permission denied.
  Stream<PositionUpdate> getPositionStream({
    LocationAccuracy accuracy = LocationAccuracy.bestForNavigation,
  }) {
    // Platform-specific settings for maximum responsiveness
    LocationSettings locationSettings;
    if (Platform.isAndroid) {
      locationSettings = AndroidSettings(
        accuracy: accuracy,
        distanceFilter: 0,
        // No intervalDuration: defaults to 0ms for updates as soon as available
        foregroundNotificationConfig: const ForegroundNotificationConfig(
          notificationTitle: 'Anchor Alarm Active',
          notificationText: 'Monitoring boat position for anchor drift',
          enableWakeLock: true, // Keeps CPU awake for updates
        ),
      );
    } else if (Platform.isIOS) {
      locationSettings = AppleSettings(
        accuracy: accuracy,
        distanceFilter: 0,
        activityType: ActivityType
            .otherNavigation, // Better for boat/water-based tracking
        pauseLocationUpdatesAutomatically: false, // Keep updating in background
        showBackgroundLocationIndicator: true, // User awareness for background
      );
    } else {
      // Fallback for other platforms
      locationSettings = LocationSettings(
        accuracy: accuracy,
        distanceFilter: 0,
      );
    }

    logger.i(
      'Starting GPS stream with MAX ACCURACY settings: accuracy=$accuracy, distanceFilter=0m, no enforced interval (updates as soon as available), platform=${Platform.operatingSystem}, settingsType=${locationSettings.runtimeType}',
    );
    return Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).map((position) {
      // GPS position received - passed to position stream
      // Use position.timestamp for accuracy (when GPS acquired the position)
      final timestamp = position.timestamp;

      // Normalize heading: -1.0 or invalid values mean "not available", so use null
      // Note: position.heading is non-nullable in geolocator, but -1.0 means "not available"
      double? heading = (position.heading >= 0 && position.heading <= 360)
          ? position.heading
          : null;

      return PositionUpdate(
        timestamp: timestamp,
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

  /// Opens the device's location settings page.
  /// Useful when permissions are deniedForever to guide user to enable manually.
  Future<bool> openLocationSettings() async {
    try {
      return await Geolocator.openLocationSettings();
    } catch (e) {
      logger.w('Failed to open location settings: $e');
      return false;
    }
  }

  /// Requests location permissions with preference for "always" access for anchor monitoring.
  ///
  /// Returns true if permission granted, false otherwise.
  /// Throws [GpsServiceException] if location services are disabled.
  Future<bool> requestPermission() async {
    logger.i('Requesting location permission for anchor monitoring...');

    // First check if location services are enabled
    final isEnabled = await isLocationServiceEnabled();
    if (!isEnabled) {
      logger.w('Location services are disabled - opening location settings');
      await openLocationSettings();
      throw GpsServiceException(
        'Location services are disabled. Please enable them in System Settings > Privacy & Security > Location Services.',
      );
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

    // If only whileInUse granted, try to escalate to always for background access
    if (permission == LocationPermission.whileInUse) {
      logger.i('Escalating to request background permission...');
      permission =
          await Geolocator.requestPermission(); // Second request prompts for "always"
      logger.i('Permission after escalation: $permission');
    }

    // For anchor monitoring, we want "always" permission for background operation
    // but accept "whileInUse" as fallback
    final granted =
        permission == LocationPermission.always ||
        permission == LocationPermission.whileInUse;

    if (permission == LocationPermission.always) {
      logger.i('✅ Full background location permission granted');
    } else if (permission == LocationPermission.whileInUse) {
      logger.w(
        '⚠️ Only foreground location permission granted - background monitoring limited',
      );
    } else if (permission == LocationPermission.deniedForever) {
      logger.e(
        '❌ Location permission permanently denied - opening app settings',
      );
      await Geolocator.openAppSettings(); // Guide user to enable manually
    } else {
      logger.e('❌ Location permission denied');
    }

    return granted;
  }
}
