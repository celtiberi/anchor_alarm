import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/position_update.dart';
import 'position_provider.dart';
import 'pairing_session_provider.dart';
import 'firestore_provider.dart';
import '../repositories/firestore_repository.dart';
import '../utils/logger_setup.dart';

/// Provides position data from Firebase for secondary devices.
/// This provider ONLY handles reading from Firebase - does not provide local data.
/// Use effectivePositionProvider to get the appropriate data source based on device role.
final remotePositionProvider = StreamProvider<PositionUpdate?>((ref) async* {
  final pairingState = ref.watch(pairingSessionStateProvider);

  if (pairingState.isSecondary && pairingState.sessionToken != null) {
    // Secondary device: read position from Firebase
    logger.i('Secondary device listening for position data from session: ${pairingState.sessionToken}');
    final firestore = ref.read(firestoreRepositoryProvider);
    yield* firestore.getSessionDataStream(pairingState.sessionToken!).asyncMap((data) {
      logger.d('📨 Received session data keys: ${data.keys.toList()}');

      // Check if boatPosition exists at all
      if (!data.containsKey('boatPosition')) {
        logger.w('🚨 boatPosition field does not exist in session document');
        logger.d('📄 Full session data: $data');
        return null;
      }

      final positionData = data['boatPosition'] as Map<String, dynamic>?;
      if (positionData == null) {
        logger.w('⚠️ boatPosition field exists but is null in session document');
        logger.d('📄 Full session data: $data');
        return null;
      }

      logger.i('🎯 Found boatPosition data: $positionData');

      try {
        return PositionUpdate(
          timestamp: DateTime.parse(positionData['timestamp'] as String),
          latitude: positionData['lat'] as double,
          longitude: positionData['lon'] as double,
          speed: positionData['speed'] as double?,
          accuracy: positionData['accuracy'] as double?,
        );
      } catch (e) {
        logger.e('Failed to parse position from Firebase', error: e);
        return null;
      }
    }).handleError((error) {
      logger.e('Error in remote position stream', error: error);
      return null;
    });
  } else {
    // Not a secondary device or no session - no data to provide
    yield null;
  }
});

