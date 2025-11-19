import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../repositories/firestore_repository.dart';

/// Provides Firestore repository instance.
final firestoreRepositoryProvider = Provider<FirestoreRepository>((ref) {
  return FirestoreRepository();
});

