import 'dart:async';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/monitoring_service.dart';
import '../models/position_update.dart';
import 'pairing_session_provider.dart';
import 'monitoring_service_provider.dart';
import 'anchor_provider.dart';
import 'position_provider.dart';
import 'position_history_provider.dart';
import 'alarm_provider.dart';
import '../utils/logger_setup.dart';

/// Provider that manages starting/stopping monitoring service sync.
/// This provider watches the pairing session state and automatically
/// starts/stops the monitoring service when entering/exiting primary mode.
class PairingSyncNotifier extends Notifier<void> {
  @override
  void build() {
    logger.i('PairingSyncNotifier initialized');
    // Listen for pairing session state changes
    ref.listen<PairingSessionState>(pairingSessionStateProvider, (previous, next) {
      logger.i('🔗 PAIRING STATE CHANGED: ${previous?.role} -> ${next.role}');
      logger.i('🔗 Previous session token: ${previous?.sessionToken}');
      logger.i('🔗 Current session token: ${next.sessionToken}');

      if (next.isPrimary && next.sessionToken != null &&
          (previous == null || !previous.isPrimary || previous.sessionToken != next.sessionToken)) {
        // Start syncing to Firebase
        logger.i('🚀 STARTING MONITORING SYNC for primary device with token: ${next.sessionToken}');
        _startMonitoringSync(next.sessionToken!);
      } else if (!next.isPrimary && previous?.isPrimary == true) {
        // Stop syncing when leaving primary mode
        logger.i('🛑 STOPPING MONITORING SERVICE - leaving primary mode with token: ${previous?.sessionToken}');
        ref.read(monitoringServiceProvider).stopMonitoring(sessionToken: previous?.sessionToken);
        logger.i('🛑 STOPPED MONITORING SERVICE SYNC');
      } else {
        logger.i('ℹ️ No action needed for pairing state change');
      }
    });
  }

  void _startMonitoringSync(String sessionToken) {
    final monitoringService = ref.read(monitoringServiceProvider);

    // Create streams that watch the providers
    final anchorStream = Stream.periodic(
      const Duration(seconds: 1),
      (_) => ref.read(anchorProvider),
    ).distinct();

    // Create position stream by polling the provider
    final positionStream = Stream.periodic(
      const Duration(seconds: 2),
      (_) {
        final position = ref.read(positionProvider);
        logger.d('📡 Position stream polled, got: ${position != null ? 'lat=${position.latitude}, lon=${position.longitude}' : 'null'}');
        return position;
      },
    ).distinct();

    final positionHistoryStream = Stream.periodic(
      const Duration(seconds: 5),
      (_) => ref.read(positionHistoryProvider),
    );

    final alarmsStream = Stream.periodic(
      const Duration(seconds: 2),
      (_) => ref.read(activeAlarmsProvider),
    );

    monitoringService.startMonitoring(
      sessionToken: sessionToken,
      anchorStream: anchorStream,
      positionStream: positionStream,
      alarmsStream: alarmsStream,
      positionHistoryStream: positionHistoryStream,
    );
  }
}

final pairingSyncProvider = NotifierProvider<PairingSyncNotifier, void>(() {
  return PairingSyncNotifier();
});

void _startMonitoringSync(
  Ref ref,
  MonitoringService monitoringService,
  String sessionToken,
) {
  try {
    // Create streams that watch the providers
    final anchorStream = Stream.periodic(
      const Duration(seconds: 1),
      (_) => ref.read(anchorProvider),
    ).distinct();
    
    // Create position stream by polling the provider
    final positionStream = Stream.periodic(
      const Duration(seconds: 2),
      (_) => ref.read(positionProvider),
    ).distinct();

    final positionHistoryStream = Stream.periodic(
      const Duration(seconds: 5),
      (_) => ref.read(positionHistoryProvider),
    );

    // Convert alarm notifier to stream
    final alarmsStream = Stream.periodic(
      const Duration(seconds: 5),
      (_) => ref.read(activeAlarmsProvider),
    );

    monitoringService.startMonitoring(
      sessionToken: sessionToken,
      anchorStream: anchorStream,
      positionStream: positionStream,
      alarmsStream: alarmsStream,
      positionHistoryStream: positionHistoryStream,
    );
    logger.i('Started monitoring service sync for session: $sessionToken');
  } catch (e) {
    logger.e('Failed to start monitoring service sync', error: e);
  }
}

