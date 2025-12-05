import 'dart:async';

/// Categories of bandwidth usage for tracking.
enum BandwidthCategory { firebaseDatabase, firebaseAuth, httpRequests, total }

/// Tracks bandwidth usage across different categories.
/// Logs usage statistics every few minutes.
class BandwidthTracker {
  static const Duration _logInterval = Duration(minutes: 5);

  final Map<BandwidthCategory, int> _bytesSent = {};
  final Map<BandwidthCategory, int> _bytesReceived = {};
  final DateTime _startTime = DateTime.now();
  Timer? _logTimer;

  BandwidthTracker() {
    // Initialize all categories to 0
    for (final category in BandwidthCategory.values) {
      _bytesSent[category] = 0;
      _bytesReceived[category] = 0;
    }

    // Start periodic logging
    _startPeriodicLogging();

    print('📊 Bandwidth tracker initialized - will log usage every 5 minutes');
  }

  void _startPeriodicLogging() {
    _logTimer = Timer.periodic(_logInterval, (_) => _logBandwidthUsage());
  }

  /// Records bandwidth usage for a specific category.
  void recordUsage({
    required BandwidthCategory category,
    int bytesSent = 0,
    int bytesReceived = 0,
  }) {
    _bytesSent[category] = (_bytesSent[category] ?? 0) + bytesSent;
    _bytesReceived[category] = (_bytesReceived[category] ?? 0) + bytesReceived;

    // Also update totals
    _bytesSent[BandwidthCategory.total] =
        (_bytesSent[BandwidthCategory.total] ?? 0) + bytesSent;
    _bytesReceived[BandwidthCategory.total] =
        (_bytesReceived[BandwidthCategory.total] ?? 0) + bytesReceived;

    // Debug: Log when data is recorded (only for significant amounts)
    final total = bytesSent + bytesReceived;
    if (total > 1000) {
      // Only log for significant bandwidth usage
      print(
        '📊 Recorded $total bytes for ${category.name} ($bytesSent sent, $bytesReceived received)',
      );
    }
  }

  /// Records Firebase Realtime Database operation bandwidth.
  /// Estimates bytes based on typical operation sizes.
  void recordFirebaseDatabaseOperation({
    int bytesSent = 0,
    int bytesReceived = 0,
  }) {
    recordUsage(
      category: BandwidthCategory.firebaseDatabase,
      bytesSent: bytesSent,
      bytesReceived: bytesReceived,
    );
  }

  /// Records Firebase Auth operation bandwidth.
  void recordFirebaseAuthOperation({int bytesSent = 0, int bytesReceived = 0}) {
    recordUsage(
      category: BandwidthCategory.firebaseAuth,
      bytesSent: bytesSent,
      bytesReceived: bytesReceived,
    );
  }

  /// Records HTTP request bandwidth.
  void recordHttpRequest({int bytesSent = 0, int bytesReceived = 0}) {
    recordUsage(
      category: BandwidthCategory.httpRequests,
      bytesSent: bytesSent,
      bytesReceived: bytesReceived,
    );
  }

  /// Logs current bandwidth usage statistics.
  void _logBandwidthUsage() {
    final now = DateTime.now();
    final uptime = now.difference(_startTime);
    final uptimeStr = '${uptime.inHours}h ${uptime.inMinutes.remainder(60)}m';

    // Use simple print instead of logger to avoid stack traces
    print('📊 BANDWIDTH USAGE SINCE APP START ($uptimeStr):');

    // Calculate totals
    int totalSent = 0;
    int totalReceived = 0;

    for (final category in BandwidthCategory.values) {
      if (category == BandwidthCategory.total) {
        continue; // Skip the computed total
      }

      final sent = _bytesSent[category] ?? 0;
      final received = _bytesReceived[category] ?? 0;
      final categoryTotal = sent + received;

      totalSent += sent;
      totalReceived += received;

      if (categoryTotal > 0) {
        final sentKB = _formatBytes(sent);
        final receivedKB = _formatBytes(received);
        final totalKB = _formatBytes(categoryTotal);

        print(
          '  ${category.name.padRight(18)}: ${totalKB.padLeft(8)} ($sentKB sent, $receivedKB recv)',
        );
      } else {
        print(
          '  ${category.name.padRight(18)}: ${'0.00 KB'.padLeft(8)} (no data)',
        );
      }
    }

    // Show grand total
    final grandTotal = totalSent + totalReceived;
    final grandTotalKB = _formatBytes(grandTotal);
    final totalSentKB = _formatBytes(totalSent);
    final totalReceivedKB = _formatBytes(totalReceived);

    print(
      '  ${'TOTAL'.padRight(18)}: ${grandTotalKB.padLeft(8)} ($totalSentKB sent, $totalReceivedKB recv)',
    );
    print('');
  }

  /// Formats bytes to human readable format (KB/MB)
  String _formatBytes(int bytes) {
    if (bytes >= 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    } else if (bytes >= 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    } else {
      return '$bytes B';
    }
  }

  /// Manually triggers a bandwidth report (for testing/debugging)
  void logReport() {
    _logBandwidthUsage();
  }

  /// Gets current bandwidth usage statistics.
  Map<BandwidthCategory, Map<String, int>> getCurrentUsage() {
    final result = <BandwidthCategory, Map<String, int>>{};

    for (final category in BandwidthCategory.values) {
      result[category] = {
        'sent': _bytesSent[category] ?? 0,
        'received': _bytesReceived[category] ?? 0,
      };
    }

    return result;
  }

  /// Resets all bandwidth counters.
  void reset() {
    for (final category in BandwidthCategory.values) {
      _bytesSent[category] = 0;
      _bytesReceived[category] = 0;
    }
    print('🔄 Bandwidth counters reset');
  }

  /// Stops periodic logging and cleans up resources.
  void dispose() {
    _logTimer?.cancel();
    _logTimer = null;
  }
}
