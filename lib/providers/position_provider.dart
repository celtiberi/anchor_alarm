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

/// Notifier for position state management.
class PositionNotifier extends Notifier<PositionUpdate?> {
  GpsService get _gpsService => ref.read(gpsServiceProvider);
  StreamSubscription<PositionUpdate>? _positionSubscription;

  @override
  PositionUpdate? build() {
    return null;
  }

  /// Starts monitoring position updates.
  Future<void> startMonitoring({Duration interval = const Duration(seconds: 15)}) async {
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
              state = position;
            },
            onError: (error) {
              logger.e('Position stream error', error: error);
            },
          );
      logger.i('GPS monitoring started successfully');
    } catch (e, stackTrace) {
      logger.e(
        'Failed to start GPS monitoring',
        error: e,
        stackTrace: stackTrace,
      );
      throw StateError('Failed to start GPS monitoring: $e');
    }
  }

  /// Stops monitoring position updates.
  void stopMonitoring() {
    _positionSubscription?.cancel();
    _positionSubscription = null;
  }

  /// Gets current position once.
  Future<PositionUpdate> getCurrentPosition() async {
    try {
      final hasPermission = await _gpsService.hasPermission();
      if (!hasPermission) {
        final granted = await _gpsService.requestPermission();
        if (!granted) {
          throw StateError('Location permission denied');
        }
      }

      final position = await _gpsService.getCurrentPosition();
      state = position;
      return position;
    } catch (e) {
      throw StateError('Failed to get current position: $e');
    }
  }

  void dispose() {
    stopMonitoring();
  }
}

