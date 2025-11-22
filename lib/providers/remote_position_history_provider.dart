import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:latlong2/latlong.dart';
import '../models/position_history_point.dart';
import 'position_history_provider.dart';
import 'pairing_session_provider.dart';
import 'firestore_provider.dart';
import '../repositories/firestore_repository.dart';
import '../utils/logger_setup.dart';

/// Provides position history that syncs to/from Firebase based on pairing role.
final remotePositionHistoryProvider = StreamProvider<List<PositionHistoryPoint>>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (!pairingState.isPaired) {
    // Not paired, just use local history
    yield ref.watch(positionHistoryProvider);
    yield* Stream.periodic(
      const Duration(seconds: 5),
      (_) => ref.watch(positionHistoryProvider),
    );
    return;
  }

  if (pairingState.isPrimary) {
    // Primary device: stream local history changes
    yield ref.watch(positionHistoryProvider);
    yield* Stream.periodic(
      const Duration(seconds: 5),
      (_) => ref.watch(positionHistoryProvider),
    );
  } else if (pairingState.isSecondary && pairingState.sessionToken != null) {
    // Secondary device: read from Firebase
    final firestore = ref.read(firestoreRepositoryProvider);
    yield* firestore.getSessionDataStream(pairingState.sessionToken!).asyncMap((data) {
      final historyData = data['positionHistory'] as List<dynamic>?;
      if (historyData == null) {
        return <PositionHistoryPoint>[];
      }
      
      try {
        return historyData.map((item) {
          final map = item as Map<String, dynamic>;
          return PositionHistoryPoint(
            position: LatLng(
              map['lat'] as double,
              map['lon'] as double,
            ),
            timestamp: DateTime.parse(map['timestamp'] as String),
          );
        }).toList();
      } catch (e) {
        logger.e('Failed to parse position history from Firebase', error: e);
        return <PositionHistoryPoint>[];
      }
    }).handleError((error) {
      logger.e('Error in monitoring position history stream', error: error);
      return <PositionHistoryPoint>[];
    });
  }
});

