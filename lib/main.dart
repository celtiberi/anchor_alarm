import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'firebase_options.dart';
import 'repositories/realtime_database_repository.dart';
import 'ui/screens/primary_map_screen.dart';
import 'ui/screens/secondary_map_screen.dart';
import 'providers/settings_provider.dart';
import 'providers/service_providers.dart';
import 'providers/pairing_providers.dart';
import 'services/notification_service.dart';
import 'services/background_alarm_service.dart';
import 'models/app_settings.dart';
import 'utils/logger_setup.dart';
import 'repositories/local_storage_repository.dart';

void main() async {
  // Set up error handlers for logging (before zone)
  _setupErrorHandlers();

  // Run app in a zone to catch all async errors
  runZonedGuarded(
    () async {
      // Initialize Flutter bindings inside the zone
      WidgetsFlutterBinding.ensureInitialized();

      // Initialize Firebase with proper error handling
      try {
        await Firebase.initializeApp(
          options: DefaultFirebaseOptions.currentPlatform,
        );
        logger.i('Firebase initialized successfully');
        logger.i(
          'Firebase app databaseURL: ${Firebase.app().options.databaseURL}',
        );

        // Log Firebase app details
        final auth = FirebaseAuth.instance;
        logger.i('Auth app: ${auth.app.name}');
        logger.i(
          'Firebase Database URL configured: ${DefaultFirebaseOptions.currentPlatform.databaseURL}',
        );
      } catch (e) {
        if (e.toString().contains('duplicate-app')) {
          logger.i(
            'Firebase already initialized (hot reload), using existing instance',
          );
          // Log Firebase app details for existing instance
          final auth = FirebaseAuth.instance;
          logger.i('Auth app: ${auth.app.name}');
          logger.i(
            'Firebase Database URL configured: ${DefaultFirebaseOptions.currentPlatform.databaseURL}',
          );
        } else {
          logger.w(
            'Failed to initialize Firebase (likely offline), operating in offline mode',
            error: e,
          );
          // Continue in offline mode - Firebase will work once network returns
          logger.i(
            '🚢 Operating in offline mode - GPS, anchor monitoring, and alarms will work normally',
          );
        }
      }

      // Initialize repository and ensure authentication early
      final repo = RealtimeDatabaseRepository();
      repo.init(); // RTDB offline persistence

      try {
        await repo.ensureAuthenticated();
        logger.i('Authentication initialized successfully');

        // Run initial cleanup and set up periodic cleanup (every 6 hours)
        try {
          await repo.deleteExpiredSessions();
          logger.i('🧹 Initial session cleanup completed');

          // Set up periodic cleanup every 6 hours
          Timer.periodic(const Duration(hours: 6), (timer) async {
            try {
              await repo.deleteExpiredSessions();
              logger.i('🧹 Periodic session cleanup completed');
            } catch (e) {
              logger.w('Periodic session cleanup failed', error: e);
            }
          });
        } catch (cleanupError) {
          logger.w('Initial session cleanup failed', error: cleanupError);
        }
      } catch (authError) {
        logger.w(
          'Failed to initialize authentication (likely offline or disabled), operating in offline mode',
          error: authError,
        );
        // Log detailed error info for debugging
        if (authError is FirebaseAuthException) {
          logger.w(
            'Auth error code: ${authError.code}, message: ${authError.message}',
          );
        }
        // Continue in offline mode - Firebase will work once network returns
      }

      // RTDB offline persistence is enabled in RealtimeDatabaseRepository.init()

      // Initialize Hive for local storage
      await Hive.initFlutter();

      // Initialize Hive boxes before app starts
      final repository = LocalStorageRepository();
      await repository.initialize();

      // Initialize background alarm service
      final backgroundService = BackgroundAlarmService();
      await backgroundService.initialize();

      // Initialize deep linking
      _initializeDeepLinking();

      runApp(
        ProviderScope(
          overrides: [
            // Initialize notification service on app start
            notificationServiceProvider.overrideWith((ref) {
              final service = NotificationService();
              service.initialize();
              return service;
            }),
          ],
          child: const AnchorAlarmApp(),
        ),
      );
    },
    (error, stack) {
      logger.e('Uncaught Error', error: error, stackTrace: stack);
    },
  );
}

/// Sets up global error handlers to log all errors.
void _setupErrorHandlers() {
  // Handle Flutter framework errors
  FlutterError.onError = (FlutterErrorDetails details) {
    FlutterError.presentError(details);
    logger.e(
      'Flutter Error',
      error: details.exception,
      stackTrace: details.stack,
    );
  };

  // Handle async errors outside of Flutter framework
  PlatformDispatcher.instance.onError = (error, stack) {
    logger.e('Platform Error', error: error, stackTrace: stack);
    return true; // Return true to prevent default error handling
  };
}

/// Initializes deep linking to handle anchorapp://join links.
void _initializeDeepLinking() {
  final appLinks = AppLinks();

  // Handle initial link (if app was opened via deep link)
  appLinks.getInitialLink().then((uri) {
    if (uri != null) {
      _handleDeepLink(uri);
    }
  });

  // Handle links while app is running
  appLinks.uriLinkStream.listen(
    (uri) {
      _handleDeepLink(uri);
    },
    onError: (error) {
      logger.e('Deep link error', error: error);
    },
  );
}

/// Handles a deep link URI.
void _handleDeepLink(Uri uri) {
  logger.i('Received deep link: $uri');

  if (uri.scheme == 'anchorapp' && uri.host == 'join') {
    final token =
        uri.queryParameters['token'] ?? uri.queryParameters['sessionId'];
    if (token != null && token.isNotEmpty) {
      logger.i('Processing join deep link with token: $token');
      // The pairing session provider will handle this when the app is ready
      // We'll store it temporarily or handle it via a provider
      _pendingDeepLinkToken = token;
    } else {
      logger.w('Deep link missing token parameter');
    }
  }
}

String? _pendingDeepLinkToken;

/// Router widget that shows the appropriate map screen based on pairing role.
class MapScreenRouter extends ConsumerWidget {
  const MapScreenRouter({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final pairingState = ref.watch(pairingSessionStateProvider);

    logger.i(
      'MapScreenRouter: pairingState.role=${pairingState.role}, isSecondary=${pairingState.isSecondary}, sessionToken=${pairingState.sessionToken}',
    );

    // Show appropriate screen based on pairing role
    // Default to primary screen if no session exists yet
    if (pairingState.isSecondary && pairingState.sessionToken != null) {
      logger.i('MapScreenRouter: Showing SecondaryMapScreen');
      return const SecondaryMapScreen();
    } else {
      logger.i('MapScreenRouter: Showing PrimaryMapScreen');
      return const PrimaryMapScreen();
    }
  }
}

class AnchorAlarmApp extends ConsumerStatefulWidget {
  const AnchorAlarmApp({super.key});

  @override
  ConsumerState<AnchorAlarmApp> createState() => _AnchorAlarmAppState();
}

class _AnchorAlarmAppState extends ConsumerState<AnchorAlarmApp> {
  @override
  void initState() {
    super.initState();
    // Handle pending deep link after first frame
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _handlePendingDeepLink();
    });
  }

  void _handlePendingDeepLink() {
    if (_pendingDeepLinkToken != null) {
      final token = _pendingDeepLinkToken;
      _pendingDeepLinkToken = null;

      // Small delay to ensure providers are ready
      Future.delayed(const Duration(milliseconds: 500), () {
        try {
          ref
              .read(pairingSessionStateProvider.notifier)
              .joinSecondarySession(token!);
          logger.i('Processed pending deep link: $token');
        } catch (e) {
          logger.e('Failed to process pending deep link', error: e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize monitoring sync (watches for primary mode and starts syncing)
    ref.read(pairingSyncProvider);

    // Monitor connectivity for offline sync
    ref.listen<AsyncValue<List<ConnectivityResult>>>(connectivityProvider, (
      previous,
      next,
    ) {
      final connectivityList = next.maybeWhen(
        data: (data) => data,
        orElse: () => <ConnectivityResult>[],
      );

      final previousConnectivityList =
          previous?.maybeWhen(
            data: (data) => data,
            orElse: () => <ConnectivityResult>[],
          ) ??
          <ConnectivityResult>[];

      final isOnline =
          connectivityList.isNotEmpty &&
          !connectivityList.contains(ConnectivityResult.none);
      final wasOffline =
          previousConnectivityList.isEmpty ||
          previousConnectivityList.contains(ConnectivityResult.none);

      if (isOnline && wasOffline) {
        // Connectivity restored - attempt to sync offline data
        logger.i(
          '📡 Connectivity restored, attempting to sync offline data...',
        );
        // Give a brief moment for any pending session creation to complete
        Future.delayed(const Duration(milliseconds: 100), () {
          ref.read(pairingSessionStateProvider.notifier).syncOfflineData();
        });
      }
    });

    final settings = ref.watch(settingsProvider);

    final themeMode = switch (settings.themeMode) {
      AppThemeMode.light => ThemeMode.light,
      AppThemeMode.dark => ThemeMode.dark,
      AppThemeMode.system => ThemeMode.system,
    };

    return MaterialApp(
      title: 'Anchor Alarm',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.blue,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: themeMode,
      home: const MapScreenRouter(),
      // Show error banner in debug mode
      builder: (context, child) {
        return MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(textScaler: TextScaler.linear(1.0)),
          child: child!,
        );
      },
    );
  }
}
