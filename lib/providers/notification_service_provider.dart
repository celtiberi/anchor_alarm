import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/notification_service.dart';

/// Provides notification service instance.
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

