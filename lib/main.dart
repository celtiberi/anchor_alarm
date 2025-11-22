import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:app_links/app_links.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'ui/screens/primary_map_screen.dart';
import 'ui/screens/secondary_map_screen.dart';
import 'providers/settings_provider.dart';
import 'providers/notification_service_provider.dart';
import 'providers/pairing_session_provider.dart';
import 'providers/pairing_sync_provider.dart';
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
      
      // Initialize Firebase (must be done before other services)
      try {
        await Firebase.initializeApp();
        logger.i('Firebase initialized successfully');
        
        // Sign in anonymously for Firestore access
        final auth = FirebaseAuth.instance;
        if (auth.currentUser == null) {
          await auth.signInAnonymously();
          logger.i('Signed in anonymously: ${auth.currentUser?.uid}');
        } else {
          logger.i('Already signed in: ${auth.currentUser?.uid}');
        }
      } catch (e, stack) {
        logger.e(
          'Failed to initialize Firebase',
          error: e,
          stackTrace: stack,
        );
        // Fail fast - don't continue if Firebase initialization fails
        rethrow;
      }
      
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
      logger.e(
        'Uncaught Error',
        error: error,
        stackTrace: stack,
      );
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
    logger.e(
      'Platform Error',
      error: error,
      stackTrace: stack,
    );
    return true;   // Return true to prevent default error handling
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
  appLinks.uriLinkStream.listen((uri) {
    _handleDeepLink(uri);
  }, onError: (error) {
    logger.e('Deep link error', error: error);
  });
}

/// Handles a deep link URI.
void _handleDeepLink(Uri uri) {
  logger.i('Received deep link: $uri');
  
  if (uri.scheme == 'anchorapp' && uri.host == 'join') {
    final token = uri.queryParameters['token'] ?? uri.queryParameters['sessionId'];
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

    logger.i('MapScreenRouter: pairingState.role=${pairingState.role}, isSecondary=${pairingState.isSecondary}, sessionToken=${pairingState.sessionToken}');

    // Show appropriate screen based on pairing role
    if (pairingState.isSecondary) {
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
          ref.read(pairingSessionStateProvider.notifier).joinSecondarySession(token!);
          logger.i('Processed pending deep link: $token');
        } catch (e) {
          logger.e('Failed to process pending deep link', error: e);
        }
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    // Initialize auto-creation of pairing sessions
    ref.read(pairingSessionAutoCreateProvider);
    // Initialize monitoring sync (watches for primary mode and starts syncing)
    ref.read(pairingSyncProvider);
    
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
          data: MediaQuery.of(context).copyWith(textScaler: TextScaler.linear(1.0)),
          child: child!,
        );
      },
    );
  }
}
