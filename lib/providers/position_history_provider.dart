import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/position_update.dart';
import '../models/anchor.dart';
import '../models/position_history_point.dart';
import 'position_provider.dart';
import 'anchor_provider.dart';

/// Provides the position history (track) when anchor is active.
/// Returns a list of position points with timestamps, recorded at time intervals.
final positionHistoryProvider = NotifierProvider<PositionHistoryNotifier, List<PositionHistoryPoint>>(() {
  return PositionHistoryNotifier();
});

/// Notifier for position history tracking.
class PositionHistoryNotifier extends Notifier<List<PositionHistoryPoint>> {
  /// Time interval between position dots (10 seconds for more frequent tracking)
  static const Duration _recordingInterval = Duration(seconds: 10);
  
  DateTime? _lastRecordedTime;

  @override
  List<PositionHistoryPoint> build() {
    // Set up listeners for position updates and anchor state changes
    ref.listen<PositionUpdate?>(positionProvider, (previous, next) {
      if (next != null) {
        _updateHistory(next);
      }
    });

    ref.listen<Anchor?>(anchorProvider, (previous, next) {
      // Clear history when anchor is cleared or deactivated
      if (next == null || !next.isActive) {
        state = [];
        _lastRecordedTime = null;
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
    
    // Record first position or if enough time has passed since last recording
    if (_lastRecordedTime == null || 
        now.difference(_lastRecordedTime!) >= _recordingInterval) {
      final newPoint = PositionHistoryPoint(
        position: LatLng(position.latitude, position.longitude),
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
    }
  }

  /// Clears the position history.
  void clearHistory() {
    state = [];
    _lastRecordedTime = null;
  }
}

