import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/local_storage_repository.dart';

/// Provides local storage repository instance.
final localStorageRepositoryProvider =
    Provider<LocalStorageRepository>((ref) {
  return LocalStorageRepository();
});

