import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart'
    as bg;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../utils/logger_setup.dart';
import '../repositories/local_storage_repository.dart';
import '../services/alarm_service.dart';
import '../models/anchor.dart';
import '../models/position_update.dart';
import '../models/app_settings.dart';

/// Background service for monitoring anchor alarms when app is minimized.
/// Uses flutter_background_geolocation for reliable GPS tracking and geofencing.
/// This ensures alarms continue to work even when the app is in the background.

class BackgroundAlarmService {
  bool _isMonitoring = false;
  bool _isInitialized = false; // Track initialization state
  final LocalStorageRepository _repository = LocalStorageRepository();
  AlarmService? _alarmService;
  PositionUpdate?
  _lastKnownPosition; // Track last known position for immediate geofence alarms
  late final FlutterLocalNotificationsPlugin _notifications;

  BackgroundAlarmService({AppSettings? initialSettings}) {
    _notifications = FlutterLocalNotificationsPlugin();

    // If settings provided, initialize AlarmService immediately
    if (initialSettings != null) {
      _alarmService = AlarmService(settings: initialSettings);
    }
  }

  /// Initializes background geolocation with optimal settings for anchor monitoring.
  Future<void> initialize() async {
    if (_isInitialized) {
      logger.d('Background service already initialized, skipping');
      return;
    }

    // Initialize repository for background access
    await _repository.initialize();

    // Initialize AlarmService with proper settings (only if not already initialized in constructor)
    if (_alarmService == null) {
      // Load settings from repository
      final AppSettings settings = _repository.getSettings();
      _alarmService = AlarmService(settings: settings);
    }

    // Initialize notifications
    await _initializeNotifications();

    // Configure background geolocation for anchor alarm use case (v5.0.0-beta.2)
    // Configure background geolocation for anchor alarm use case (v5.0.0-beta.2)
    // Using backward-compatible flat config - v5 supports legacy APIs
    await bg.BackgroundGeolocation.ready(
      bg.Config(
        // GPS accuracy optimized for marine environment
        desiredAccuracy: bg.Config.DESIRED_ACCURACY_HIGH,

        // Distance filter: only update when moved significantly (saves battery)
        distanceFilter: 5.0, // 5 meters - good balance for anchor monitoring
        // Stationary detection: stop GPS when not moving (battery saving)
        stationaryRadius: 10.0, // 10m radius to detect when boat is anchored
        // Background operation settings
        stopOnTerminate: false, // Continue after app termination
        startOnBoot: true, // Restart after device reboot
        preventSuspend: true, // Keep GPS active when screen off
        // Notification settings for Android foreground service
        notification: bg.Notification(
          title: 'Anchor Alarm Active',
          text: 'Monitoring boat position',
          channelName: 'Anchor Alarm Background',
          sticky: true,
        ),

        // Debug settings (set to false for production)
        debug: false,
        logLevel: bg.Config.LOG_LEVEL_INFO,

        // Background fetch settings
        enableHeadless: true,
        heartbeatInterval: 60, // Check every minute when stationary
        // Disable activity recognition - we don't need physical activity monitoring for GPS-based anchor alarms
        disableMotionActivityUpdates: true,
      ),
    );

    // Set up event handlers
    _setupEventHandlers();

    _isInitialized = true;
    logger.i('Background geolocation initialized for anchor alarm monitoring');
  }

  /// Updates the AlarmService with current settings.
  void updateSettings(AppSettings settings) {
    _alarmService = AlarmService(settings: settings);
  }

  /// Initializes local notifications for background alarms.
  Future<void> _initializeNotifications() async {
    const androidSettings = AndroidInitializationSettings(
      '@mipmap/ic_launcher',
    );
    const iosSettings = DarwinInitializationSettings();
    final settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(settings);

    // Create notification channel for Android
    const androidChannel = AndroidNotificationChannel(
      'anchor_alarm_channel',
      'Anchor Alarm',
      description: 'Anchor drift notifications',
      importance: Importance.max,
    );

    await _notifications
        .resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin
        >()
        ?.createNotificationChannel(androidChannel);
  }

  /// Sets up event handlers for location and geofence events.
  void _setupEventHandlers() {
    // Handle location updates
    bg.BackgroundGeolocation.onLocation(_onLocation);

    // Handle geofence events (when boat exits anchor radius)
    bg.BackgroundGeolocation.onGeofence(_onGeofence);

    // Note: Event handlers are registered but FBG doesn't return subscriptions
    // The removeListeners() call in dispose() handles cleanup
  }

  /// Starts background monitoring when anchor is set.
  Future<void> startMonitoring(Anchor anchor) async {
    if (_isMonitoring) {
      logger.d('Background monitoring already active');
      return;
    }

    // Ensure initialized before starting monitoring
    if (!_isInitialized) {
    await initialize();
    }

    // Add geofence around anchor position
    await bg.BackgroundGeolocation.addGeofence(
      bg.Geofence(
        identifier: 'ANCHOR_RADIUS',
        latitude: anchor.latitude,
        longitude: anchor.longitude,
        radius: anchor.radius,
        notifyOnEntry: false, // Only notify on exit (when drifting)
        notifyOnExit: true,
        notifyOnDwell: false,
        loiteringDelay: 0,
      ),
    );

    // Start background tracking
    await bg.BackgroundGeolocation.start();
    _isMonitoring = true;

    logger.i(
      'Background anchor monitoring started - geofence radius: ${anchor.radius}m',
    );
  }

  /// Stops background monitoring.
  Future<void> stopMonitoring() async {
    if (!_isMonitoring) {
      return;
    }

    // Remove geofence
    await bg.BackgroundGeolocation.removeGeofence('ANCHOR_RADIUS');

    // Stop background tracking
    await bg.BackgroundGeolocation.stop();
    _isMonitoring = false;

    logger.i('Background anchor monitoring stopped');
  }

  /// Updates the anchor position (called when anchor is moved).
  Future<void> updateAnchor(Anchor anchor) async {
    if (!_isMonitoring) {
      return;
    }

    // Remove old geofence and add new one
    await bg.BackgroundGeolocation.removeGeofence('ANCHOR_RADIUS');
    await bg.BackgroundGeolocation.addGeofence(
      bg.Geofence(
        identifier: 'ANCHOR_RADIUS',
        latitude: anchor.latitude,
        longitude: anchor.longitude,
        radius: anchor.radius,
        notifyOnEntry: false,
        notifyOnExit: true,
        notifyOnDwell: false,
        loiteringDelay: 0,
      ),
    );

    logger.i('Background geofence updated to new anchor position');
  }

  /// Disposes the service and cleans up resources.
  void dispose() {
    stopMonitoring();
    bg.BackgroundGeolocation.removeListeners();
    _isInitialized = false; // Reset initialization state
  }

  /// Handles location updates from background geolocation.
  void _onLocation(bg.Location location) {
    try {
      logger.d(
        'Background location update: ${location.coords.latitude}, ${location.coords.longitude}',
      );

      // Convert to our PositionUpdate format
      final position = PositionUpdate(
        timestamp: DateTime.parse(location.timestamp),
        latitude: location.coords.latitude,
        longitude: location.coords.longitude,
      );

      // Store as last known position for immediate geofence alarms
      _lastKnownPosition = position;

      // Get current anchor
      final anchor = _repository.getAnchor();
      if (anchor == null || !anchor.isActive) {
        logger.w('No active anchor in background location update');
        return;
      }

      // Check for drift alarm using AlarmService
      final distance = _alarmService!.checkDrift(anchor, position);
      if (distance != null &&
          _alarmService!.shouldTriggerAlarm(anchor, distance)) {
        _triggerBackgroundAlarm(anchor, position, distance);
      }
    } catch (e) {
      logger.e('Error processing background location', error: e);
    }
  }

  /// Handles geofence exit events (boat has drifted outside anchor radius).
  void _onGeofence(bg.GeofenceEvent event) {
    try {
      if (event.identifier == 'ANCHOR_RADIUS' && event.action == 'EXIT') {
        logger.w(
          '🚨 BACKGROUND GEOFENCE EXIT: Boat has drifted outside anchor radius!',
        );

        // Get current position and anchor
        final anchor = _repository.getAnchor();
        if (anchor == null) {
          logger.e('No anchor found for geofence exit event');
          return;
        }

        // Use the most recent known position for immediate alarm triggering
        // This avoids delays from getCurrentPosition() calls
        if (_lastKnownPosition != null) {
          logger.i('Using cached position for geofence alarm trigger');
          final distance = _alarmService!.checkDrift(
            anchor,
            _lastKnownPosition!,
          );
          if (distance != null) {
            _triggerBackgroundAlarm(anchor, _lastKnownPosition!, distance);
          }
        } else {
          logger.w(
            'No cached position available for geofence alarm, falling back to getCurrentPosition',
          );
          // Fallback to getCurrentPosition if no cached position (shouldn't happen in normal operation)
          bg.BackgroundGeolocation.getCurrentPosition()
              .then((bg.Location location) {
                final position = PositionUpdate(
                  timestamp: DateTime.parse(location.timestamp),
                  latitude: location.coords.latitude,
                  longitude: location.coords.longitude,
                );

                final distance = _alarmService!.checkDrift(anchor, position);
                if (distance != null) {
                  _triggerBackgroundAlarm(anchor, position, distance);
                }
              })
              .catchError((error) {
                logger.e(
                  'Failed to get current position for geofence alarm',
                  error: error,
                );
              });
        }
      }
    } catch (e) {
      logger.e('Error processing background geofence event', error: e);
    }
  }

  /// Triggers an alarm notification in the background.
  Future<void> _triggerBackgroundAlarm(
    Anchor anchor,
    PositionUpdate position,
    double distance,
  ) async {
    try {
      // Create and save the alarm event for foreground sync
      final alarm = _alarmService!.createDriftAlarm(anchor, position, distance);
      await _repository.saveBackgroundAlarmEvent(alarm);

      // Show full-featured local notification with sound and vibration
      await _showAlarmNotification(distance);

      // Update the persistent notification to show alarm state
      bg.BackgroundGeolocation.setConfig(
        bg.Config(
          notification: bg.Notification(
            title: '🚨 ANCHOR ALARM!',
            text: 'Drift detected: ${distance.toStringAsFixed(1)}m from anchor',
            channelName: 'Anchor Alarm Alert',
            sticky: true,
          ),
        ),
      );

      logger.w(
        '🚨 BACKGROUND ALARM TRIGGERED: Drift ${distance.toStringAsFixed(1)}m from anchor',
      );
    } catch (e) {
      logger.e('Error triggering background alarm', error: e);
    }
  }

  /// Shows a full-featured alarm notification using flutter_local_notifications.
  Future<void> _showAlarmNotification(double distance) async {
    logger.i(
      'Showing alarm notification for ${distance.toStringAsFixed(1)}m drift',
    );
    final androidDetails = AndroidNotificationDetails(
      'anchor_alarm_channel',
      'Anchor Alarm',
      channelDescription: 'Anchor drift notifications',
      importance: Importance.max,
      enableVibration: true,
      enableLights: true,
      ledColor: const Color(0xFFFF0000), // Red LED
      ledOnMs: 1000,
      ledOffMs: 500,
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'default',
      badgeNumber: 1,
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    await _notifications.show(
      DateTime.now().millisecondsSinceEpoch ~/
          1000, // Unique ID based on timestamp
      '🚨 ANCHOR ALARM!',
      'Drift detected: ${distance.toStringAsFixed(1)}m from anchor',
      details,
    );
  }
}
