import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Provider that tracks locally dismissed alarms on secondary devices.
/// These dismissals are local-only and don't sync to Firebase.
final localAlarmDismissalProvider =
    NotifierProvider.autoDispose<LocalAlarmDismissalNotifier, Set<String>>(() {
  return LocalAlarmDismissalNotifier();
});

/// Notifier for tracking locally dismissed alarm IDs.
class LocalAlarmDismissalNotifier extends Notifier<Set<String>> {
  @override
  Set<String> build() {
    return {};
  }

  /// Dismisses an alarm locally (secondary devices only).
  void dismissLocally(String alarmId) {
    state = {...state, alarmId};
  }

  /// Checks if an alarm is locally dismissed.
  bool isDismissed(String alarmId) {
    return state.contains(alarmId);
  }

  /// Clears all local dismissals.
  void clear() {
    state = {};
  }
}

