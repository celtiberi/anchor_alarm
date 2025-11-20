import 'dart:async';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import '../models/alarm_event.dart';
import '../models/app_settings.dart';
import '../utils/logger_setup.dart';
import '../utils/distance_formatter.dart';

/// Service for handling alarm notifications (sound, vibration).
class NotificationService {
  final FlutterLocalNotificationsPlugin _notifications =
      FlutterLocalNotificationsPlugin();
  bool _initialized = false;
  Timer? _vibrationTimer;
  Timer? _soundTimer;
  bool _isAlarmActive = false;

  // Constants for timing
  static const Duration _vibrationInterval = Duration(seconds: 2);
  static const Duration _soundInterval = Duration(seconds: 3);

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
  /// Starts continuous vibration/sound if not already active.
  Future<void> triggerAlarm(AlarmEvent alarm, AppSettings settings) async {
    logger.i('Triggering alarm: ${alarm.type} at ${alarm.distanceFromAnchor.toStringAsFixed(1)}m');

    // Start continuous alarm if not already active
    if (!_isAlarmActive) {
      _isAlarmActive = true;
      
      // Start continuous vibration
      if (settings.vibrationEnabled) {
        _startContinuousVibration();
      }
      
      // Start continuous sound
      if (settings.soundEnabled) {
        _startContinuousSound();
      }
    }

    // Local notification (always show for visibility)
    await _showLocalNotification(alarm, settings);
  }
  
  /// Stops all alarm notifications (vibration and sound).
  void stopAlarm() {
    _isAlarmActive = false;
    _vibrationTimer?.cancel();
    _vibrationTimer = null;
    _soundTimer?.cancel();
    _soundTimer = null;
    logger.d('Alarm notifications stopped');
  }

  /// Starts continuous vibration pattern while alarm is active.
  void _startContinuousVibration() {
    _vibrationTimer?.cancel();
    
    // Vibrate immediately
    HapticFeedback.vibrate();

    // Repeat vibration pattern while alarm is active
    _vibrationTimer = Timer.periodic(_vibrationInterval, (timer) {
      if (!_isAlarmActive) {
        timer.cancel();
        return;
      }
      try {
        HapticFeedback.vibrate();
      } catch (e) {
        logger.w('Failed to vibrate: $e');
      }
    });
    
    logger.d('Continuous vibration started');
  }

  /// Starts continuous sound pattern while alarm is active.
  void _startContinuousSound() {
    _soundTimer?.cancel();
    
    // Play sound immediately
    SystemSound.play(SystemSoundType.alert);

    // Repeat sound while alarm is active
    _soundTimer = Timer.periodic(_soundInterval, (timer) {
      if (!_isAlarmActive) {
        timer.cancel();
        return;
      }
      try {
        SystemSound.play(SystemSoundType.alert);
      } catch (e) {
        logger.w('Failed to play alarm sound: $e');
      }
    });
    
    logger.d('Continuous sound started');
  }


  /// Shows a local notification for the alarm.
  Future<void> _showLocalNotification(AlarmEvent alarm, AppSettings settings) async {
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
            'Boat has drifted ${formatDistance(alarm.distanceFromAnchor, settings.unitSystem)} from anchor';
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
    stopAlarm();
    _notifications.cancelAll();
  }
}

