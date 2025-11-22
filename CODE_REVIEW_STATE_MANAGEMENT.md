r# Code Review: State Management Issues

## Summary
Reviewed all providers for variables that should be Riverpod providers but are currently stored as private fields accessed via getters.

## Issues Found

### ✅ FIXED: `isMonitoring` in `AlarmNotifier`
**Location:** `lib/providers/alarm_provider.dart`

**Problem:** `_isMonitoring` was a private field accessed via getter `isMonitoring`, which doesn't trigger UI rebuilds when it changes.

**Solution:** Created `alarmMonitoringStateProvider` as a reactive provider that tracks monitoring state. Updated `AlarmNotifier` to update this provider whenever monitoring starts/stops.

**Status:** ✅ Fixed

---

### ⚠️ MINOR: `deviceId` in `PairingSessionNotifier`
**Location:** `lib/providers/pairing_provider.dart`

**Issue:** `_deviceId` is accessed via getter `deviceId` and loaded asynchronously. The UI accesses it via `ref.read(pairingSessionProvider.notifier).deviceId`, which is not reactive.

**Current Behavior:**
- `deviceId` is loaded asynchronously in `_loadDeviceId()` (called from `build()` but not awaited)
- All code paths that use `deviceId` either:
  - Call `await _loadDeviceId()` first (e.g., `createSession()`, `joinSession()`)
  - Check for null (e.g., `settings_screen.dart`)

**Impact:** Low - The code handles null checks, and `deviceId` is a one-time initialization that doesn't change after loading.

**Recommendation:** Consider making `deviceId` part of the provider state or creating a separate `deviceIdProvider` if the UI needs to reactively wait for it to load. However, this is not critical since all access points handle the async loading.

**Status:** ⚠️ Acceptable (not critical)

---

## Variables That Are NOT Issues

### ✅ `_isPaused` in `AlarmNotifier`
- Only used internally within the notifier
- Never accessed via getter from outside
- No UI needs to react to pause state changes
- **Status:** ✅ Fine as-is

### ✅ `_positionSubscription` in `PositionNotifier`
- Internal state for managing the subscription
- Never accessed from outside
- **Status:** ✅ Fine as-is

### ✅ Position monitoring status
- UI doesn't need to know if position monitoring is active
- UI only uses the position value, which is already reactive (`PositionUpdate?`)
- **Status:** ✅ Fine as-is

---

## Best Practices Applied

1. ✅ State that changes and needs UI updates should be part of provider state
2. ✅ Internal implementation details (like subscriptions) can remain private
3. ✅ One-time initialization values that don't change can use getters if null is handled

---

## Recommendations

1. **Consider making `deviceId` reactive** if you want the UI to show a loading state while it's being loaded, but this is optional since current code handles it well.

2. **Pattern to follow:** When you have state that:
   - Changes over time
   - Needs to trigger UI rebuilds
   - Is accessed from outside the notifier
   
   → Make it part of the provider state or create a separate reactive provider.

