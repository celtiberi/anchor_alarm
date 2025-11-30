import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anchor.dart';
import '../repositories/local_storage_repository.dart';
import 'service_providers.dart';
import 'alarm_provider.dart';
import '../utils/logger_setup.dart';

/// Provides the current anchor state.
final anchorProvider = NotifierProvider.autoDispose<AnchorNotifier, Anchor?>(() {
  return AnchorNotifier();
});

/// Notifier for anchor state management.
class AnchorNotifier extends Notifier<Anchor?> {
  LocalStorageRepository get _repository => ref.read(localStorageRepositoryProvider);

  @override
  Anchor? build() {
    // Load anchor from local storage if it exists
    final savedAnchor = _repository.getAnchor();
    logger.i('⚓ Anchor provider build() called - loaded anchor: $savedAnchor');
    return savedAnchor;
  }

  /// Sets a new anchor point.
  Future<void> setAnchor({
    required double latitude,
    required double longitude,
    required double radius,
  }) async {
    final now = DateTime.now();
    final anchor = Anchor(
      id: now.millisecondsSinceEpoch.toString(),
      latitude: latitude,
      longitude: longitude,
      radius: radius,
      createdAt: now,
      isActive: true,
    );

    logger.i('⚓ Setting new anchor: lat=$latitude, lon=$longitude, radius=$radius');
    await _repository.saveAnchor(anchor);
    state = anchor;
    logger.i('✅ Anchor set successfully in local state and saved to storage');
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
    logger.i('Clearing anchor and stopping monitoring');
    await _repository.deleteAnchor();
    state = null;

    // Stop monitoring when anchor is cleared
    logger.i('Stopping monitoring due to anchor clear');
    ref.read(activeAlarmsProvider.notifier).stopMonitoring();
    logger.i('Anchor cleared successfully');
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

