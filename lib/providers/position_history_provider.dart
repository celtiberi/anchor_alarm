import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/position_update.dart';
import '../models/anchor.dart';
import 'position_provider.dart';
import 'anchor_provider.dart';

/// Provides the position history (track) when anchor is active.
final positionHistoryProvider = NotifierProvider<PositionHistoryNotifier, List<LatLng>>(() {
  return PositionHistoryNotifier();
});

/// Notifier for position history tracking.
class PositionHistoryNotifier extends Notifier<List<LatLng>> {
  @override
  List<LatLng> build() {
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
      }
    });

    return [];
  }

  /// Updates position history when anchor is active.
  void _updateHistory(PositionUpdate position) {
    final anchor = ref.read(anchorProvider);
    
    // Only track positions when anchor is set and active
    if (anchor == null || !anchor.isActive) {
      return;
    }

    final newPoint = LatLng(position.latitude, position.longitude);
    
    // Add new position to history
    state = [...state, newPoint];
  }

  /// Clears the position history.
  void clearHistory() {
    state = [];
  }
}

