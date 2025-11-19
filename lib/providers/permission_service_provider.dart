import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/permission_service.dart';

/// Provides permission service instance.
final permissionServiceProvider = Provider<PermissionService>((ref) {
  return PermissionService();
});

