import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/gps_service.dart';

/// Provides GPS service instance.
final gpsServiceProvider = Provider<GpsService>((ref) {
  return GpsService();
});

