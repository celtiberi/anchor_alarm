import 'package:logger/logger.dart';

/// Global logger instance for the app.
/// 
/// Usage:
/// ```dart
/// logger.d('Debug message');
/// logger.i('Info message');
/// logger.w('Warning message');
/// logger.e('Error message', error: e, stackTrace: stackTrace);
/// ```
final logger = Logger(
  printer: PrettyPrinter(
    methodCount: 2, // Number of method calls to be displayed
    errorMethodCount: 8, // Number of method calls if stacktrace is provided
    lineLength: 120,
    colors: true,
    printEmojis: true,
    dateTimeFormat: DateTimeFormat.onlyTimeAndSinceStart,
  ),
  level: Level.debug, // Set to Level.nothing in production if needed
);

