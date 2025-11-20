import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'ui/screens/map_screen.dart';
import 'providers/settings_provider.dart';
import 'providers/notification_service_provider.dart';
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
      
      // Initialize Hive for local storage
      await Hive.initFlutter();
      
      // Initialize Hive boxes before app starts
      final repository = LocalStorageRepository();
      await repository.initialize();
      
      // Initialize background alarm service
      final backgroundService = BackgroundAlarmService();
      await backgroundService.initialize();
      
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
    return true; // Return true to prevent default error handling
  };
}

class AnchorAlarmApp extends ConsumerWidget {
  const AnchorAlarmApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
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
      home: const MapScreen(),
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
