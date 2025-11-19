import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alarm_event.dart';
import '../models/app_settings.dart';
import '../utils/logger_setup.dart';

/// Service for handling alarm notifications (sound, vibration).
class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;

  /// Initializes the notification service.
  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    const androidSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosSettings = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    await _notifications.initialize(
      initSettings,
      onDidReceiveNotificationResponse: _onNotificationTapped,
    );

    _initialized = true;
    logger.i('Notification service initialized');
  }


  /// Handles notification tap.
  void _onNotificationTapped(NotificationResponse response) {
    logger.d('Notification tapped: ${response.id}');
    // Could navigate to alarm details or acknowledge alarm
  }

  /// Triggers an alarm notification based on settings.
  Future<void> triggerAlarm(AlarmEvent alarm, AppSettings settings) async {
    logger.i('Triggering alarm: ${alarm.type} at ${alarm.distanceFromAnchor.toStringAsFixed(1)}m');

    // Sound notification
    if (settings.soundEnabled) {
      await _playSound();
    }

    // Vibration
    if (settings.vibrationEnabled) {
      await _vibrate();
    }

    // Local notification (always show for visibility)
    await _showLocalNotification(alarm);
  }

  /// Plays alarm sound.
  Future<void> _playSound() async {
    try {
      // Use system sound for alarm
      await SystemSound.play(SystemSoundType.alert);
      logger.d('Alarm sound played');
    } catch (e) {
      logger.w('Failed to play alarm sound: $e');
    }
  }

  /// Triggers device vibration.
  Future<void> _vibrate() async {
    try {
      // Vibrate pattern: vibrate for 500ms, pause 200ms, vibrate 500ms
      await HapticFeedback.vibrate();
      
      // For longer vibration pattern, use a timer
      Timer(const Duration(milliseconds: 700), () {
        HapticFeedback.vibrate();
      });
      
      logger.d('Vibration triggered');
    } catch (e) {
      logger.w('Failed to vibrate: $e');
    }
  }


  /// Shows a local notification for the alarm.
  Future<void> _showLocalNotification(AlarmEvent alarm) async {
    if (!_initialized) {
      await initialize();
    }

    final androidDetails = AndroidNotificationDetails(
      'anchor_alarm',
      'Anchor Alarms',
      channelDescription: 'Notifications for anchor drift alarms',
      importance: Importance.max,
      priority: Priority.high,
      playSound: false, // We handle sound separately
      enableVibration: false, // We handle vibration separately
      icon: '@mipmap/ic_launcher',
    );

    final iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: false, // We handle sound separately
    );

    final details = NotificationDetails(
      android: androidDetails,
      iOS: iosDetails,
    );

    String title;
    String body;

    switch (alarm.type) {
      case AlarmType.driftExceeded:
        title = 'Anchor Alarm';
        body =
            'Boat has drifted ${alarm.distanceFromAnchor.toStringAsFixed(1)}m from anchor';
        break;
      case AlarmType.gpsLost:
        title = 'GPS Lost';
        body = 'GPS signal lost. Position tracking unavailable.';
        break;
      case AlarmType.gpsInaccurate:
        title = 'GPS Inaccurate';
        body = 'GPS accuracy is poor. Position may be unreliable.';
        break;
    }

    await _notifications.show(
      alarm.id.hashCode, // Use hash of ID as notification ID
      title,
      body,
      details,
    );

    logger.d('Local notification shown: $title');
  }

  /// Cancels all notifications.
  Future<void> cancelAll() async {
    await _notifications.cancelAll();
    logger.d('All notifications cancelled');
  }

  /// Cancels a specific notification.
  Future<void> cancel(int notificationId) async {
    await _notifications.cancel(notificationId);
  }

  /// Disposes resources.
  void dispose() {
    // No resources to dispose
  }
}

