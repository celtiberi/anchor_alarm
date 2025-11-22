import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/position_update.dart';
import '../services/gps_service.dart';
import 'gps_service_provider.dart';
import '../utils/logger_setup.dart';

/// Provides the current position state.
final positionProvider = NotifierProvider<PositionNotifier, PositionUpdate?>(() {
  return PositionNotifier();
});

/// Provides the GPS monitoring state reactively.
/// This allows the UI to react to changes in GPS monitoring status.
final positionMonitoringStateProvider = NotifierProvider<PositionMonitoringStateNotifier, bool>(() {
  return PositionMonitoringStateNotifier();
});

/// Notifier that tracks whether GPS position monitoring is active.
class PositionMonitoringStateNotifier extends Notifier<bool> {
  @override
  bool build() {
    // Initialize from the position provider's current state
    return ref.read(positionProvider.notifier)._positionSubscription != null;
  }

  /// Updates the monitoring state.
  void setMonitoring(bool isMonitoring) {
    state = isMonitoring;
  }
}

/// Notifier for position state management.
class PositionNotifier extends Notifier<PositionUpdate?> {
  GpsService get _gpsService => ref.read(gpsServiceProvider);
  StreamSubscription<PositionUpdate>? _positionSubscription;

  @override
  PositionUpdate? build() {
    // Note: Position monitoring is started manually by the UI when needed
    // This prevents the "deactivated widget" error from auto-starting in build()
    return null;
  }

  /// Starts monitoring position updates with high frequency for anchor alarm accuracy.
  Future<void> startMonitoring({Duration interval = const Duration(seconds: 5)}) async {
    if (_positionSubscription != null) {
      return; // Already monitoring
    }

    try {
      logger.i('Starting GPS monitoring...');
      
      // Check if location services are enabled
      final isEnabled = await _gpsService.isLocationServiceEnabled();
      if (!isEnabled) {
        logger.w('Location services are disabled');
        throw StateError('Location services are disabled. Please enable them in System Settings.');
      }
      
      final hasPermission = await _gpsService.hasPermission();
      logger.i('Current permission status: $hasPermission');
      
      if (!hasPermission) {
        logger.i('Requesting location permission...');
        final granted = await _gpsService.requestPermission();
        logger.i('Permission request result: $granted');
        if (!granted) {
          throw StateError('Location permission denied. Please grant location access in System Settings > Privacy & Security > Location Services.');
        }
      }

      logger.i('Starting position stream...');
      _positionSubscription = _gpsService
          .getPositionStream(interval: interval)
          .listen(
            (position) {
              logger.d('📍 Position stream received: lat=${position.latitude}, lon=${position.longitude}');
              state = position;
              logger.d('📍 Position state updated: ${state != null ? 'lat=${state!.latitude}, lon=${state!.longitude}' : 'null'}');
            },
            onError: (error) {
              // Handle timeout errors gracefully (common in emulators without GPS)
              if (error is TimeoutException) {
                logger.w('GPS timeout - this is normal in emulators without GPS. Retrying...');
                // Don't stop monitoring, just log and continue
                // The stream will retry automatically
              } else {
                logger.e('Position stream error', error: error);
                // For other errors, we might want to stop monitoring
                // but for now, let's continue and let it retry
              }
            },
            cancelOnError: false, // Continue monitoring even after errors
          );
      logger.i('GPS monitoring started successfully');
      // Update reactive monitoring state
      ref.read(positionMonitoringStateProvider.notifier).setMonitoring(true);
    } catch (e, stackTrace) {
      logger.e(
        'Failed to start GPS monitoring',
        error: e,
        stackTrace: stackTrace,
      );
      // Update reactive monitoring state
      ref.read(positionMonitoringStateProvider.notifier).setMonitoring(false);
      throw StateError('Failed to start GPS monitoring: $e');
    }
  }

  /// Stops monitoring position updates.
  void stopMonitoring() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
    // Update reactive monitoring state
    ref.read(positionMonitoringStateProvider.notifier).setMonitoring(false);
  }

  /// Gets current position once.
  Future<PositionUpdate> getCurrentPosition() async {
    logger.i('🔍 Getting current GPS position...');
    try {
      logger.d('📍 Checking GPS permissions...');
      final hasPermission = await _gpsService.hasPermission();
      logger.d('📍 GPS permission status: $hasPermission');

      if (!hasPermission) {
        logger.i('📍 Requesting GPS permission...');
        final granted = await _gpsService.requestPermission();
        logger.d('📍 GPS permission granted: $granted');
        if (!granted) {
          throw StateError('Location permission denied');
        }
      }

      logger.d('📍 Getting current position from GPS service...');
      final position = await _gpsService.getCurrentPosition();
      logger.i('✅ Got GPS position: lat=${position.latitude}, lon=${position.longitude}');
      state = position;
      return position;
    } catch (e) {
      logger.e('❌ Failed to get current position', error: e);
      throw StateError('Failed to get current position: $e');
    }
  }

  void dispose() {
    stopMonitoring();
    // Additional cleanup for reactive state
    ref.read(positionMonitoringStateProvider.notifier).setMonitoring(false);
  }
}

