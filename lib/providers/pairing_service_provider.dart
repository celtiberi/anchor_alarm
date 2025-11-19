import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/pairing_service.dart';

/// Provides pairing service instance.
final pairingServiceProvider = Provider<PairingService>((ref) {
  return PairingService();
});

