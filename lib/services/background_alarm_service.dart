import 'dart:async';
import 'dart:io';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_background_service_android/flutter_background_service_android.dart';
import 'package:hive/hive.dart';
import 'package:path_provider/path_provider.dart';
import '../utils/logger_setup.dart';
import '../repositories/local_storage_repository.dart';

/// Background service for monitoring anchor alarms when app is minimized.
/// This ensures alarms continue to work even when the app is in the background.
///
/// Note: Full implementation requires GPS service integration for background position updates.
/// This is a foundation that can be extended when background GPS is needed.

// Constants for timing
const Duration _backgroundCheckInterval = Duration(seconds: 5);

class BackgroundAlarmService {
  bool _isRunning = false;

  /// Initializes and starts the background service.
  Future<void> initialize() async {
    if (_isRunning) {
      return;
    }

    final service = FlutterBackgroundService();

    // Configure Android-specific settings
    await service.configure(
      androidConfiguration: AndroidConfiguration(
        onStart: onStart,
        autoStart: false, // Don't auto-start, only start when monitoring
        isForegroundMode: true,
        notificationChannelId: 'anchor_alarm_background',
        initialNotificationTitle: 'Anchor Alarm',
        initialNotificationContent: 'Monitoring anchor position',
        foregroundServiceNotificationId: 888,
      ),
      iosConfiguration: IosConfiguration(
        autoStart: false,
        onForeground: onStart,
        onBackground: onIosBackground,
      ),
    );

    _isRunning = true;
    logger.i('Background alarm service initialized');
  }

  /// Starts background monitoring when anchor is set.
  Future<void> startMonitoring() async {
    if (!_isRunning) {
      await initialize();
    }

    final service = FlutterBackgroundService();
    service.startService();
    logger.i('Background alarm monitoring started');
  }

  /// Stops background monitoring.
  Future<void> stopMonitoring() async {
    final service = FlutterBackgroundService();
    service.invoke('stop');
    logger.i('Background alarm monitoring stopped');
  }

  /// Disposes the service.
  void dispose() {
    stopMonitoring();
    _isRunning = false;
  }
}

/// Entry point for Android background service.
@pragma('vm:entry-point')
void onStart(ServiceInstance service) async {
  final repository = LocalStorageRepository();
  Timer? checkTimer;
  bool isRunning = true;

  // Set up foreground notification for Android
  if (service is AndroidServiceInstance) {
    service.setForegroundNotificationInfo(
      title: 'Anchor Alarm Active',
      content: 'Monitoring anchor position in background',
    );
  }

  // Initialize Hive for background service
  try {
    final appDir = await getApplicationDocumentsDirectory();
    Hive.init(appDir.path);
    logger.i('Background alarm service Hive initialized at: ${appDir.path}');
  } catch (e) {
    logger.e('Failed to initialize background Hive', error: e);
    // Stop service if we can't initialize storage
    if (service is AndroidServiceInstance) {
      service.stopSelf();
    }
    return;
  }

  // Initialize repository (open Hive boxes)
  try {
    await repository.initialize();
    logger.i('Background alarm service repository initialized');
  } catch (e) {
    logger.e('Failed to initialize background repository', error: e);
    // Stop service if we can't initialize storage
    if (service is AndroidServiceInstance) {
      service.stopSelf();
    }
    return;
  }

  // Handle stop command
  service.on('stop').listen((event) {
    isRunning = false;
    checkTimer?.cancel();
    if (service is AndroidServiceInstance) {
      service.stopSelf();
    }
  });

  // Check alarm conditions periodically
  checkTimer = Timer.periodic(_backgroundCheckInterval, (timer) async {
    if (!isRunning) {
      return; // Prevent execution after cancellation
    }

    try {
      final anchor = repository.getAnchor();
      if (anchor == null || !anchor.isActive) {
        // No active anchor, stop monitoring
        isRunning = false;
        timer.cancel();
        if (service is AndroidServiceInstance) {
          service.stopSelf();
        }
        return;
      }

      // TODO: Implement full background GPS monitoring
      // 1. Integrate with background location service (e.g., geolocator background mode)
      // 2. Get current position in background context
      // 3. Check alarm conditions using same logic as foreground
      // 4. Trigger notifications when alarms are detected
      // 5. Handle battery optimization and permissions for background location
      //
      // For now, this service only initializes but doesn't actually monitor GPS.
      // Full alarm checking requires foreground GPS access.

    } catch (e) {
      logger.e('Error in background alarm check', error: e);
    }
  });
}

/// iOS background handler.
@pragma('vm:entry-point')
Future<bool> onIosBackground(ServiceInstance service) async {
  // iOS background handling
  return true;
}

