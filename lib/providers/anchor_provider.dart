import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anchor.dart';
import '../repositories/local_storage_repository.dart';
import 'local_storage_provider.dart';

/// Provides the current anchor state.
final anchorProvider = NotifierProvider<AnchorNotifier, Anchor?>(() {
  return AnchorNotifier();
});

/// Notifier for anchor state management.
class AnchorNotifier extends Notifier<Anchor?> {
  LocalStorageRepository get _repository => ref.read(localStorageRepositoryProvider);

  @override
  Anchor? build() {
    // Load anchor synchronously on first build
    final anchor = _repository.getAnchor();
    return anchor;
  }

  /// Sets a new anchor point.
  Future<void> setAnchor({
    required double latitude,
    required double longitude,
    required double radius,
  }) async {
    final anchor = Anchor(
      id: DateTime.now().millisecondsSinceEpoch.toString(),
      latitude: latitude,
      longitude: longitude,
      radius: radius,
      createdAt: DateTime.now(),
      isActive: true,
    );

    await _repository.saveAnchor(anchor);
    state = anchor;
  }

  /// Updates anchor position (for drag adjustment).
  Future<void> updateAnchorPosition({
    required double latitude,
    required double longitude,
  }) async {
    if (state == null) {
      throw StateError('Cannot update anchor: no anchor is set');
    }

    final updatedAnchor = state!.copyWith(
      latitude: latitude,
      longitude: longitude,
      updatedAt: DateTime.now(),
    );

    await _repository.saveAnchor(updatedAnchor);
    state = updatedAnchor;
  }

  /// Updates anchor radius.
  Future<void> updateRadius(double radius) async {
    if (state == null) {
      throw StateError('Cannot update radius: no anchor is set');
    }

    final updatedAnchor = state!.copyWith(radius: radius);
    await _repository.saveAnchor(updatedAnchor);
    state = updatedAnchor;
  }

  /// Clears the anchor.
  Future<void> clearAnchor() async {
    await _repository.deleteAnchor();
    state = null;
  }

  /// Toggles anchor active state.
  Future<void> toggleActive() async {
    if (state == null) {
      throw StateError('Cannot toggle: no anchor is set');
    }

    final updatedAnchor = state!.copyWith(isActive: !state!.isActive);
    await _repository.saveAnchor(updatedAnchor);
    state = updatedAnchor;
  }
}

