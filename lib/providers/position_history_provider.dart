import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/position_update.dart';
import '../models/anchor.dart';
import '../models/position_history_point.dart';
import '../utils/logger_setup.dart';
import 'gps_provider.dart';
import 'anchor_provider.dart';

/// Provides the position history (track) when anchor is active.
/// Returns a list of position points with timestamps, recorded at time intervals.
final positionHistoryProvider = NotifierProvider.autoDispose<PositionHistoryNotifier, List<PositionHistoryPoint>>(() {
  return PositionHistoryNotifier();
});

/// Notifier for position history tracking.
class PositionHistoryNotifier extends Notifier<List<PositionHistoryPoint>> {
  /// Time interval between position dots (10 seconds for more frequent tracking)
  static const Duration _recordingInterval = Duration(seconds: 10);

  /// Only record if GPS coordinates have actually changed (avoid duplicates)
  
  DateTime? _lastRecordedTime;
  LatLng? _lastRecordedPosition;

  @override
  List<PositionHistoryPoint> build() {
    // Set up listeners for position updates and anchor state changes
    ref.listen<PositionUpdate?>(positionProvider, (previous, next) {
      if (next != null) {
        logger.d('📍 Position history: Received position update - lat=${next.latitude.toStringAsFixed(6)}, lon=${next.longitude.toStringAsFixed(6)}');
        _updateHistory(next);
      }
    });

    ref.listen<Anchor?>(anchorProvider, (previous, next) {
      // Clear history when anchor is cleared or deactivated
      if (next == null || !next.isActive) {
        logger.d('📍 Position history: Clearing history (anchor cleared or deactivated)');
        state = [];
        _lastRecordedTime = null;
        _lastRecordedPosition = null;
      }
    });

    return [];
  }

  /// Updates position history when anchor is active.
  /// Only records positions at the specified time interval to create visible dots.
  /// Uses a sliding window: always adds new points, removes oldest when over limit.
  /// This prevents unbounded memory growth during long anchoring sessions.
  static const int _maxHistoryPoints = 500;
  
  void _updateHistory(PositionUpdate position) {
    final anchor = ref.read(anchorProvider);
    
    // Only track positions when anchor is set and active
    if (anchor == null || !anchor.isActive) {
      return;
    }

    final now = position.timestamp;
    final currentPosition = LatLng(position.latitude, position.longitude);
    
    // Record first position, or if enough time has passed AND position has changed
    if (_lastRecordedTime == null || 
        (now.difference(_lastRecordedTime!) >= _recordingInterval &&
         (_lastRecordedPosition == null ||
          currentPosition.latitude != _lastRecordedPosition!.latitude ||
          currentPosition.longitude != _lastRecordedPosition!.longitude))) {

      final newPoint = PositionHistoryPoint(
        position: currentPosition,
        timestamp: now,
      );
      
      // Sliding window: always add new point, remove oldest if over limit
      // This ensures we keep the most recent _maxHistoryPoints points
      final updatedState = [...state, newPoint];
      if (updatedState.length > _maxHistoryPoints) {
        // Keep only the most recent _maxHistoryPoints points (remove oldest)
        state = updatedState.sublist(updatedState.length - _maxHistoryPoints);
      } else {
        state = updatedState;
      }

      _lastRecordedTime = now;
      _lastRecordedPosition = currentPosition;
    }
  }

  /// Clears the position history.
  void clearHistory() {
    state = [];
    _lastRecordedTime = null;
    _lastRecordedPosition = null;
  }
}

