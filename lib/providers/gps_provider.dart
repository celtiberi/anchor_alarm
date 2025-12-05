import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/position_update.dart';
import '../services/gps_service.dart';
import '../utils/logger_setup.dart';

/// Custom exceptions for GPS provider operations.
class GpsNotifierException extends StateError {
  GpsNotifierException(super.message);
}

class GpsPermissionDeniedException extends GpsNotifierException {
  GpsPermissionDeniedException()
    : super('Location permission denied. Please grant access in settings.');
}

class GpsServiceUnavailableException extends GpsNotifierException {
  GpsServiceUnavailableException()
    : super(
        'Location services are disabled. Please enable them in System Settings.',
      );
}

/// GPS Service Provider: Provides the GPS service instance for dependency injection.
final gpsServiceProvider = Provider<GpsService>((ref) {
  return GpsService();
});

/// GPS Provider: Manages GPS position monitoring and state for the UI.
/// Provides reactive access to current position, monitoring status, and GPS controls.
final gpsProvider = NotifierProvider.autoDispose<GpsNotifier, PositionUpdate?>(
  () {
    return GpsNotifier();
  },
);

/// Provides the GPS monitoring state reactively.
/// This is derived from the GPS provider's monitoring state.
final gpsMonitoringStateProvider = Provider.autoDispose<bool>((ref) {
  return ref.read(gpsProvider.notifier).isMonitoring;
});

/// Legacy alias for backward compatibility
final positionProvider = gpsProvider;
final positionMonitoringStateProvider = gpsMonitoringStateProvider;

/// GPS Notifier: Manages GPS monitoring, permissions, and position state.
/// Provides methods to start/stop GPS monitoring and get current position.
class GpsNotifier extends Notifier<PositionUpdate?> {
  late final GpsService _gpsService = ref.read(gpsServiceProvider);
  StreamSubscription<PositionUpdate>? _positionSubscription;

  /// Callback to notify when foreground GPS monitoring state changes
  void Function(bool isMonitoring)? onMonitoringStateChanged;

  @override
  PositionUpdate? build() {
    // Set up disposal to clean up GPS monitoring when provider is disposed
    ref.onDispose(() {
      logger.d('GpsNotifier disposing...');
      // Cancel subscription to stop GPS stream callbacks
      _positionSubscription?.cancel();
      _positionSubscription = null;
      logger.d('GpsNotifier disposed - GPS monitoring stopped');
    });

    // Note: Position monitoring is started manually by the UI when needed
    // This prevents the "deactivated widget" error from auto-starting in build()
    return null;
  }

  /// Starts monitoring position updates with maximum responsiveness for anchor alarm accuracy.
  Future<void> startMonitoring() async {
    if (_positionSubscription != null) {
      logger.w('GPS monitoring already active, skipping start');
      return; // Already monitoring
    }

    try {
      logger.i('🚀 STARTING GPS MONITORING...');

      // Check if location services are enabled
      final isEnabled = await _gpsService.isLocationServiceEnabled();
      if (!isEnabled) {
        logger.w('Location services are disabled');
        throw GpsServiceUnavailableException();
      }

      final hasPermission = await _gpsService.hasPermission();
      logger.i('Current permission status: $hasPermission');

      if (!hasPermission) {
        logger.i('Requesting location permission...');
        final granted = await _gpsService.requestPermission();
        logger.i('Permission request result: $granted');
        if (!granted) {
          throw GpsPermissionDeniedException();
        }
      }

      logger.i('Starting position stream...');
      _positionSubscription = _gpsService.getPositionStream().listen(
        (position) {
          logger.d('🔄 GPS PROVIDER: Position update received - lat=${position.latitude.toStringAsFixed(6)}, lon=${position.longitude.toStringAsFixed(6)}, accuracy=${position.accuracy?.toStringAsFixed(1)}m');
          // Check if provider is still mounted and has an active subscription
          if (ref.mounted && _positionSubscription != null) {
            try {
              final oldPosition = state;
              state = position;
              logger.d('✅ GPS PROVIDER: State updated successfully. Old: ${oldPosition != null ? 'lat=${oldPosition.latitude.toStringAsFixed(6)}, lon=${oldPosition.longitude.toStringAsFixed(6)}' : 'null'} → New: lat=${position.latitude.toStringAsFixed(6)}, lon=${position.longitude.toStringAsFixed(6)}');
            } catch (e) {
              logger.w(
                'Failed to update position state - provider may be disposed: $e',
              );
            }
          } else {
            logger.w('🚨 GPS PROVIDER: Provider not mounted or subscription cancelled - ignoring position update');
          }
        },
        onError: (error) {
          // Handle timeout errors gracefully (common in emulators without GPS)
          if (error is TimeoutException) {
            logger.w(
              'GPS timeout - this is normal in emulators without GPS. Retrying...',
            );
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
      // Notify listeners that foreground GPS is now active
      onMonitoringStateChanged?.call(true);
      // Update reactive monitoring state
    } catch (e, stackTrace) {
      logger.e(
        'Failed to start GPS monitoring',
        error: e,
        stackTrace: stackTrace,
      );
      // All errors in this method are already GpsNotifierException subclasses
      rethrow;
    }
  }

  /// Stops monitoring position updates.
  void stopMonitoring() {
    if (_positionSubscription != null) {
      logger.d('Stopping GPS position monitoring...');
      _positionSubscription!.cancel();
      _positionSubscription = null;
      logger.d('GPS position monitoring stopped');
      // Notify listeners that foreground GPS is now inactive
      onMonitoringStateChanged?.call(false);
    }
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
          throw GpsPermissionDeniedException();
        }
      }

      logger.d('📍 Getting current position from GPS service...');
      final position = await _gpsService.getCurrentPosition();
      logger.i(
        '✅ Got GPS position: lat=${position.latitude}, lon=${position.longitude}',
      );
      state = position;
      return position;
    } catch (e) {
      logger.e('❌ Failed to get current position', error: e);
      // All errors in this method are already GpsNotifierException subclasses
      rethrow;
    }
  }

  /// Returns whether GPS monitoring is currently active.
  bool get isMonitoring => _positionSubscription != null;
}
