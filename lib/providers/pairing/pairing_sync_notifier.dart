import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/anchor.dart';
import '../../models/position_update.dart';
import '../../models/alarm_event.dart';
import '../../utils/logger_setup.dart';
import '../service_providers.dart';
import '../anchor_provider.dart';
import '../gps_provider.dart';
import '../alarm_provider.dart';
import 'pairing_providers.dart';

/// Notifier for pairing sync logic (streams, monitoring).
class PairingSyncNotifier extends Notifier<void> {
  @override
  void build() {
    logger.i('PairingSyncNotifier initialized');

    // Check current state and start monitoring if appropriate
    final currentState = ref.read(pairingSessionStateProvider);
    logger.i(
      'PairingSyncNotifier: Checking current state - role=${currentState.role}, sessionToken=${currentState.sessionToken}',
    );
    if (currentState.isPrimary && currentState.sessionToken != null) {
      logger.i(
        'PairingSyncNotifier: Device is already primary with session token, starting monitoring sync',
      );
      try {
        _startMonitoringSync(currentState.sessionToken!);
      } catch (e) {
        logger.e(
          'Failed to start monitoring sync for existing session',
          error: e,
        );
      }
    }

    // Add error boundary for the entire listener
    try {
      ref.listen<PairingSessionState>(
        pairingSessionStateProvider,
        (previous, next) {
          try {
            _handlePairingStateChange(previous, next);
          } catch (e) {
            logger.e('Error handling pairing state change', error: e);
          }
        },
        // Handle errors in the stream itself
        onError: (error, stackTrace) {
          logger.e(
            'Error in pairing session state stream',
            error: error,
            stackTrace: stackTrace,
          );
        },
      );
    } catch (e) {
      logger.e('Failed to set up pairing state listener', error: e);
    }
  }

  void _handlePairingStateChange(
    PairingSessionState? previous,
    PairingSessionState next,
  ) {
    logger.i('🔗 Pairing state changed: ${previous?.role} -> ${next.role}');

    if (next.isPrimary &&
        next.sessionToken != null &&
        (previous == null ||
            !previous.isPrimary ||
            previous.sessionToken != next.sessionToken ||
            (previous.sessionToken == null && next.sessionToken != null))) {
      logger.i(
        '🚀 Starting monitoring sync for primary device with token: ${next.sessionToken}',
      );
      try {
        _startMonitoringSync(next.sessionToken!);
      } catch (e) {
        logger.e('Failed to start monitoring sync', error: e);
      }
    } else if (!next.isPrimary && previous?.isPrimary == true) {
      logger.i('🛑 Stopping monitoring service - leaving primary mode');
      Future.microtask(() async {
        try {
          if (!ref.mounted) return; // Check if still mounted before async operations
          await ref
              .read(sessionSyncServiceProvider)
              .stopMonitoringAsync(sessionToken: previous?.sessionToken);
          logger.i('✅ Monitoring service stopped successfully');
        } catch (e) {
          logger.e('Error stopping monitoring service', error: e);
        }
      });
    } else {
      logger.d('ℹ️ No action needed for pairing state change');
    }
  }

  void _startMonitoringSync(String sessionToken) {
    final sessionSyncService = ref.read(sessionSyncServiceProvider);

    // Create reactive streams that emit when providers change
    final anchorController = StreamController<Anchor?>.broadcast();
    final positionController = StreamController<PositionUpdate?>.broadcast();
    final alarmsController = StreamController<List<AlarmEvent>>.broadcast();

    // Listen to provider changes and emit to streams with error handling
    try {
      ref.listen<Anchor?>(anchorProvider, (previous, next) {
        try {
          anchorController.add(next);
        } catch (e) {
          logger.e('Error adding anchor to stream', error: e);
        }
      }, fireImmediately: true);

      ref.listen<PositionUpdate?>(positionProvider, (previous, next) {
        try {
          positionController.add(next);
        } catch (e) {
          logger.e('Error adding position to stream', error: e);
        }
      }, fireImmediately: true);

      ref.listen<List<AlarmEvent>>(activeAlarmsProvider, (previous, next) {
        try {
          alarmsController.add(next);
        } catch (e) {
          logger.e('Error adding alarms to stream', error: e);
        }
      }, fireImmediately: true);
    } catch (e) {
      logger.e('Error setting up provider listeners', error: e);
      // Clean up on setup failure
      anchorController.close();
      positionController.close();
      alarmsController.close();
      return;
    }

    try {
      sessionSyncService.startMonitoring(
        sessionToken: sessionToken,
        anchorStream: anchorController.stream.distinct(),
        positionStream: positionController.stream.distinct(),
        alarmsStream: alarmsController.stream.distinct(),
        currentAnchor: ref.read(anchorProvider),
        currentPosition: ref.read(positionProvider),
        currentAlarms: ref.read(activeAlarmsProvider),
      );
      logger.i(
        'Successfully started monitoring sync for session: $sessionToken',
      );
    } catch (e) {
      logger.e('Failed to start monitoring sync', error: e);
      // Clean up on failure
      anchorController.close();
      positionController.close();
      alarmsController.close();
      return;
    }

    // Clean up controllers when monitoring stops
    ref.onDispose(() {
      logger.d('Cleaning up monitoring stream controllers');
      anchorController.close();
      positionController.close();
      alarmsController.close();
    });
  }
}

