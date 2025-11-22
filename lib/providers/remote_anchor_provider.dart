import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/anchor.dart';
import 'anchor_provider.dart';
import 'pairing_session_provider.dart';
import 'firestore_provider.dart';
import '../repositories/firestore_repository.dart';
import '../utils/logger_setup.dart';

/// Provides anchor data from Firebase for secondary devices.
/// This provider ONLY handles reading from Firebase - does not provide local data.
/// Use effectiveAnchorProvider to get the appropriate data source based on device role.
final remoteAnchorProvider = StreamProvider<Anchor?>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (pairingState.isSecondary && pairingState.sessionToken != null) {
    // Secondary device: read anchor from Firebase
    final firestore = ref.read(firestoreRepositoryProvider);
    yield* firestore.getSessionDataStream(pairingState.sessionToken!).asyncMap((data) {
      final anchorData = data['anchor'] as Map<String, dynamic>?;
      if (anchorData == null) {
        return null;
      }

      try {
        return Anchor(
          id: 'remote_anchor',
          latitude: anchorData['lat'] as double,
          longitude: anchorData['lon'] as double,
          radius: anchorData['radius'] as double,
          createdAt: DateTime.now(), // Firebase doesn't store this
          isActive: anchorData['isActive'] as bool? ?? true,
        );
      } catch (e) {
        logger.e('Failed to parse anchor from Firebase', error: e);
        return null;
      }
    }).handleError((error) {
      logger.e('Error in remote anchor stream', error: error);
      return null;
    });
  } else {
    // Not a secondary device or no session - no data to provide
    yield null;
  }
});

