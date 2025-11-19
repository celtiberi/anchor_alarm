import 'package:permission_handler/permission_handler.dart' as ph;
import '../utils/logger_setup.dart';

/// Service for handling app permissions.
class PermissionService {
  /// Requests location permission.
  /// 
  /// Returns true if permission granted, false otherwise.
  Future<bool> requestLocationPermission() async {
    logger.i('Requesting location permission...');
    
    final status = await ph.Permission.location.request();
    final granted = status.isGranted;
    
    logger.i('Location permission status: $status (granted: $granted)');
    
    return granted;
  }

  /// Checks if location permission is granted.
  Future<bool> hasLocationPermission() async {
    final status = await ph.Permission.location.status;
    return status.isGranted;
  }

  /// Requests notification permission (Android 13+).
  /// 
  /// Returns true if permission granted, false otherwise.
  Future<bool> requestNotificationPermission() async {
    logger.i('Requesting notification permission...');
    
    final status = await ph.Permission.notification.request();
    final granted = status.isGranted;
    
    logger.i('Notification permission status: $status (granted: $granted)');
    
    return granted;
  }

  /// Checks if notification permission is granted.
  Future<bool> hasNotificationPermission() async {
    final status = await ph.Permission.notification.status;
    return status.isGranted;
  }

  /// Opens app settings for manual permission grant.
  Future<bool> openAppSettings() async {
    logger.i('Opening app settings...');
    return await ph.openAppSettings();
  }
}

