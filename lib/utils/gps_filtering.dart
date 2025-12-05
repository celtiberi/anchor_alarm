import 'dart:math';
import '../models/position_update.dart';
import 'logger_setup.dart';

/// Simple 1D Kalman Filter for smoothing a single dimension (e.g., lat or lon).
class KalmanFilter1D {
  double _estimate; // Current estimate
  double _errorEstimate; // Error in estimate
  final double _processNoise; // How much the true value can change (tune for boat speed)

  KalmanFilter1D({
    double initialEstimate = 0.0,
    double initialError = 1.0,
    double processNoise = 0.01, // Small for slow drift
  })  : _estimate = initialEstimate,
        _errorEstimate = initialError,
        _processNoise = processNoise;

  /// Update with a new measurement (position value and its accuracy).
  double update(double measurement, double measurementAccuracy) {
    // Predict
    _errorEstimate += _processNoise;

    // Update
    final kalmanGain = _errorEstimate / (_errorEstimate + pow(measurementAccuracy, 2)); // Use accuracy as noise
    _estimate += kalmanGain * (measurement - _estimate);
    _errorEstimate *= (1 - kalmanGain);

    return _estimate;
  }
}

/// GPS filtering utilities for handling noisy GPS data and preventing jumping around.
class GpsFiltering {
  static double _accuracyThreshold = 10.0; // meters - tune based on testing
  static double _processNoise = 0.0001; // For lat/lon degrees

  /// Configures filtering parameters for testing and tuning.
  static void configure({
    double? accuracyThreshold,
    double? processNoise,
  }) {
    if (accuracyThreshold != null) {
      _accuracyThreshold = accuracyThreshold;
      logger.i('🛰️ GPS Filtering: Accuracy threshold set to ${_accuracyThreshold}m');
    }
    if (processNoise != null) {
      _processNoise = processNoise;
      logger.i('🛰️ GPS Filtering: Process noise set to $_processNoise');
      // Reset filters to apply new parameters
      resetFilters();
    }
  }

  // Static filters for continuous smoothing
  static KalmanFilter1D? _latFilter;
  static KalmanFilter1D? _lonFilter;

  /// Applies accuracy filtering to a position update.
  /// Returns null if accuracy is too poor (above threshold).
  static PositionUpdate? filterByAccuracy(
    PositionUpdate position, {
    double? accuracyThreshold,
  }) {
    final threshold = accuracyThreshold ?? _accuracyThreshold;
    if (position.accuracy == null || position.accuracy! > threshold) {
      logger.d(
        '🛰️ GPS Filtering: Ignoring position with poor accuracy: ${position.accuracy}m (threshold: ${threshold}m)',
      );
      return null;
    }
    return position;
  }

  /// Applies Kalman filtering for position smoothing.
  /// Uses separate filters for latitude and longitude.
  static PositionUpdate smoothWithKalman(PositionUpdate raw) {
    // Initialize filters if needed (reinitialize if process noise changed)
    _latFilter ??= KalmanFilter1D(
      initialEstimate: raw.latitude,
      processNoise: _processNoise,
    );
    _lonFilter ??= KalmanFilter1D(
      initialEstimate: raw.longitude,
      processNoise: _processNoise,
    );

    // Use accuracy as measurement noise, fallback to configured threshold if not available
    final measurementAccuracy = raw.accuracy ?? _accuracyThreshold;

    final smoothedLat = _latFilter!.update(raw.latitude, measurementAccuracy);
    final smoothedLon = _lonFilter!.update(raw.longitude, measurementAccuracy);

    final smoothed = PositionUpdate(
      timestamp: raw.timestamp,
      latitude: smoothedLat,
      longitude: smoothedLon,
      accuracy: raw.accuracy,
      speed: raw.speed,
      heading: raw.heading,
    );

    logger.d(
      '🛰️ GPS Filtering: Kalman smoothed position - raw: (${raw.latitude.toStringAsFixed(6)}, ${raw.longitude.toStringAsFixed(6)}) -> smoothed: (${smoothedLat.toStringAsFixed(6)}, ${smoothedLon.toStringAsFixed(6)})',
    );

    return smoothed;
  }

  /// Applies both accuracy filtering and Kalman smoothing.
  /// Returns null if accuracy filtering rejects the position.
  static PositionUpdate? filterAndSmooth(PositionUpdate raw, {
    double? accuracyThreshold,
  }) {
    // First apply accuracy filtering
    final accuracyFiltered = filterByAccuracy(raw, accuracyThreshold: accuracyThreshold ?? _accuracyThreshold);
    if (accuracyFiltered == null) {
      return null;
    }

    // Then apply Kalman smoothing
    return smoothWithKalman(accuracyFiltered);
  }

  /// Resets the Kalman filters (useful when starting a new session or repositioning).
  static void resetFilters() {
    logger.i('🛰️ GPS Filtering: Resetting Kalman filters');
    _latFilter = null;
    _lonFilter = null;
  }

  /// Gets current filter statistics for debugging.
  static Map<String, dynamic> getFilterStats() {
    return {
      'latFilterInitialized': _latFilter != null,
      'lonFilterInitialized': _lonFilter != null,
      'accuracyThreshold': _accuracyThreshold,
      'processNoise': _processNoise,
    };
  }
}
