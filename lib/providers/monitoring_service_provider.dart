import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/monitoring_service.dart';
import '../repositories/firestore_repository.dart';
import 'firestore_provider.dart';

/// Provides monitoring service instance.
final monitoringServiceProvider = Provider<MonitoringService>((ref) {
  final firestore = ref.read(firestoreRepositoryProvider);
  return MonitoringService(firestore: firestore);
});

