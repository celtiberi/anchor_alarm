import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../services/notification_service.dart';
import '../services/permission_service.dart';
import '../services/session_sync_service.dart';
import '../services/bandwidth_tracker.dart';
import '../repositories/local_storage_repository.dart';
import '../repositories/realtime_database_repository.dart';
import '../utils/logger_setup.dart';
import 'settings_provider.dart';

/// Provides Firebase Auth instance for consistent auth usage across the app.
final firebaseAuthProvider = Provider<FirebaseAuth>((ref) {
  return FirebaseAuth.instance;
});

/// Provides local storage repository instance.
final localStorageRepositoryProvider = Provider<LocalStorageRepository>((ref) {
  return LocalStorageRepository();
});

/// Provides notification service instance with proper initialization and disposal.
final notificationServiceProvider = Provider<NotificationService>((ref) {
  final service = NotificationService();

  // Initialize on first access (async, but don't await)
  service.initialize();

  // Dispose on provider disposal
  ref.onDispose(() {
    service.dispose();
  });

  return service;
});

/// Provides permission service instance.
final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

/// Provides Realtime Database repository instance with consistent auth.
final realtimeDatabaseRepositoryProvider = Provider<RealtimeDatabaseRepository>((ref) {
  try {
    final auth = ref.read(firebaseAuthProvider);
    final bandwidthTracker = ref.read(bandwidthTrackerProvider);
    logger.i('Creating RealtimeDatabaseRepository with auth and bandwidth tracking');

    final repo = RealtimeDatabaseRepository(auth: auth, bandwidthTracker: bandwidthTracker);
    // Persistence is now set up in constructor

    logger.i('RealtimeDatabaseRepository created successfully');
    return repo;
  } catch (e, stack) {
    logger.e('Failed to create RealtimeDatabaseRepository', error: e, stackTrace: stack);
    // Return a repository with default auth as fallback
    final fallbackRepo = RealtimeDatabaseRepository();
    // Persistence is now set up in constructor
    logger.w('Using fallback RealtimeDatabaseRepository without explicit auth');
    return fallbackRepo;
  }
});

/// Provides session sync service instance for pushing primary device data to Firebase.
final sessionSyncServiceProvider = Provider<SessionSyncService>((ref) {
  final realtimeDb = ref.read(realtimeDatabaseRepositoryProvider);
  final settings = ref.watch(settingsProvider);
  return SessionSyncService(realtimeDb: realtimeDb, settings: settings);
});

/// Provides connectivity monitoring for offline/online detection.
final connectivityProvider = StreamProvider<List<ConnectivityResult>>((ref) async* {
  final connectivity = Connectivity();

  // Emit initial connectivity state
  yield await connectivity.checkConnectivity();

  // Listen for connectivity changes
  await for (final result in connectivity.onConnectivityChanged) {
    yield result;
  }
});

/// Provides bandwidth tracking service for monitoring data usage.
final bandwidthTrackerProvider = Provider<BandwidthTracker>((ref) {
  final tracker = BandwidthTracker();

  // Dispose on provider disposal
  ref.onDispose(() {
    tracker.dispose();
  });

  return tracker;
});
