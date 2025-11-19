/// Cached tide data for a location.
class TideCache {
  final double latitude;
  final double longitude;
  final DateTime timestamp;
  final List<TideHeight> heights; // Tide heights for the next 12+ hours

  TideCache({
    required this.latitude,
    required this.longitude,
    required this.timestamp,
    required this.heights,
  });

  /// Creates TideCache from JSON.
  factory TideCache.fromJson(Map<String, dynamic> json) {
    return TideCache(
      latitude: (json['latitude'] as num).toDouble(),
      longitude: (json['longitude'] as num).toDouble(),
      timestamp: DateTime.parse(json['timestamp'] as String),
      heights: (json['heights'] as List<dynamic>)
          .map((h) => TideHeight.fromJson(h as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Converts TideCache to JSON.
  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'timestamp': timestamp.toIso8601String(),
      'heights': heights.map((h) => h.toJson()).toList(),
    };
  }

  /// Checks if cache is still valid (within 12 hours).
  bool isValid() {
    final age = DateTime.now().difference(timestamp);
    return age.inHours < 12;
  }

  /// Gets current tide height from cache.
  double? getCurrentTideHeight() {
    if (heights.isEmpty) return null;
    return heights.first.height;
  }

  /// Gets minimum tide height in the next N hours from cache.
  double? getMinTideHeight(int hours) {
    if (heights.isEmpty) return null;

    final cutoffTime = DateTime.now().add(Duration(hours: hours));
    double? minHeight;

    for (final height in heights) {
      if (height.dt.isAfter(cutoffTime)) break;
      if (minHeight == null || height.height < minHeight) {
        minHeight = height.height;
      }
    }

    return minHeight;
  }

  /// Gets tide height at a specific time from cache.
  double? getTideHeightAtTime(DateTime time) {
    if (heights.isEmpty) return null;

    // Find closest time
    TideHeight? closest;
    int minTimeDiff = 2147483647;

    for (final height in heights) {
      final timeDiff = (height.dt.difference(time).inSeconds).abs();
      if (timeDiff < minTimeDiff) {
        minTimeDiff = timeDiff;
        closest = height;
      }
    }

    return closest?.height;
  }
}

/// Represents a single tide height measurement.
class TideHeight {
  final DateTime dt;
  final double height;

  TideHeight({
    required this.dt,
    required this.height,
  });

  factory TideHeight.fromJson(Map<String, dynamic> json) {
    return TideHeight(
      dt: DateTime.fromMillisecondsSinceEpoch((json['dt'] as int) * 1000),
      height: (json['height'] as num).toDouble(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'dt': dt.millisecondsSinceEpoch ~/ 1000,
      'height': height,
    };
  }
}

