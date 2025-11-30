/// Unit system for displaying measurements.
enum UnitSystem {
  metric,
  imperial,
}

/// Theme mode preference.
enum AppThemeMode {
  light,
  dark,
  system,
}

/// User preferences and app configuration.
class AppSettings {
  final UnitSystem unitSystem;
  final AppThemeMode themeMode;
  final double defaultRadius;
  final double alarmSensitivity;
  final double gpsAccuracyThreshold; // Meters - GPS accuracy worse than this triggers warning
  final String? worldTidesApiKey; // WorldTides API key for tide data
  final bool soundEnabled;
  final bool vibrationEnabled;

  // Firebase write timing configurations (seconds)
  final int positionUpdateInterval; // How often to send position updates to Firebase
  final int positionHistoryBatchInterval; // How often to batch position history updates

  // Alarm monitoring configurations (seconds)
  final int gpsLostThreshold; // How long without GPS updates before triggering lost warning
  final int gpsCheckInterval; // How often to check for GPS lost status
  final int gpsHysteresisDelay; // Hysteresis delay to prevent rapid on/off GPS warnings
  final int alarmAutoDismissThreshold; // How recent an alarm must be to auto-dismiss when returning to radius

  const AppSettings({
    this.unitSystem = UnitSystem.metric,
    this.themeMode = AppThemeMode.system,
    this.defaultRadius = 50.0,
    this.alarmSensitivity = 0.5,
    this.gpsAccuracyThreshold = 20.0, // Default: warn if GPS accuracy > 20m
    this.worldTidesApiKey = '40a47278-06b2-4f97-a7ca-0f7fa8962b63', // Default API key
    this.soundEnabled = true,
    this.vibrationEnabled = true,
    this.positionUpdateInterval = 5, // Default: send position updates every 5 seconds
    this.positionHistoryBatchInterval = 5, // Default: batch position history every 5 seconds
    this.gpsLostThreshold = 30, // Default: GPS lost after 30 seconds without updates
    this.gpsCheckInterval = 15, // Default: check GPS status every 15 seconds
    this.gpsHysteresisDelay = 5, // Default: 5 second hysteresis for GPS warnings
    this.alarmAutoDismissThreshold = 120, // Default: auto-dismiss recent alarms within 2 minutes
  }) :         assert(
          defaultRadius >= 1 && defaultRadius <= 100,
          'Default radius must be between 1 and 100 meters, got $defaultRadius',
        ),
        assert(
          alarmSensitivity >= 0 && alarmSensitivity <= 1,
          'Alarm sensitivity must be between 0 and 1, got $alarmSensitivity',
        ),
        assert(
          gpsAccuracyThreshold > 0,
          'GPS accuracy threshold must be positive, got $gpsAccuracyThreshold',
        ),
        assert(
          positionUpdateInterval >= 1 && positionUpdateInterval <= 60,
          'Position update interval must be between 1 and 60 seconds, got $positionUpdateInterval',
        ),
        assert(
          positionHistoryBatchInterval >= 1 && positionHistoryBatchInterval <= 60,
          'Position history batch interval must be between 1 and 60 seconds, got $positionHistoryBatchInterval',
        ),
        assert(
          gpsLostThreshold >= 10 && gpsLostThreshold <= 300,
          'GPS lost threshold must be between 10 and 300 seconds, got $gpsLostThreshold',
        ),
        assert(
          gpsCheckInterval >= 5 && gpsCheckInterval <= 60,
          'GPS check interval must be between 5 and 60 seconds, got $gpsCheckInterval',
        ),
        assert(
          gpsHysteresisDelay >= 1 && gpsHysteresisDelay <= 30,
          'GPS hysteresis delay must be between 1 and 30 seconds, got $gpsHysteresisDelay',
        ),
        assert(
          alarmAutoDismissThreshold >= 30 && alarmAutoDismissThreshold <= 600,
          'Alarm auto-dismiss threshold must be between 30 and 600 seconds, got $alarmAutoDismissThreshold',
        );

  /// Creates AppSettings from JSON map.
  factory AppSettings.fromJson(Map<String, dynamic> json) {
    return AppSettings(
      unitSystem: UnitSystem.values.firstWhere(
        (e) => e.name == json['unitSystem'],
        orElse: () => UnitSystem.metric,
      ),
      themeMode: AppThemeMode.values.firstWhere(
        (e) => e.name == json['themeMode'],
        orElse: () => AppThemeMode.system,
      ),
      defaultRadius: (json['defaultRadius'] as num?)?.toDouble() ?? 50.0,
      alarmSensitivity: (json['alarmSensitivity'] as num?)?.toDouble() ?? 0.5,
      gpsAccuracyThreshold: (json['gpsAccuracyThreshold'] as num?)?.toDouble() ?? 20.0,
      worldTidesApiKey: json['worldTidesApiKey'] as String? ?? '40a47278-06b2-4f97-a7ca-0f7fa8962b63',
      soundEnabled: json['soundEnabled'] as bool? ?? true,
      vibrationEnabled: json['vibrationEnabled'] as bool? ?? true,
      positionUpdateInterval: (json['positionUpdateInterval'] as num?)?.toInt() ?? 5,
      positionHistoryBatchInterval: (json['positionHistoryBatchInterval'] as num?)?.toInt() ?? 5,
      gpsLostThreshold: (json['gpsLostThreshold'] as num?)?.toInt() ?? 30,
      gpsCheckInterval: (json['gpsCheckInterval'] as num?)?.toInt() ?? 15,
      gpsHysteresisDelay: (json['gpsHysteresisDelay'] as num?)?.toInt() ?? 5,
      alarmAutoDismissThreshold: (json['alarmAutoDismissThreshold'] as num?)?.toInt() ?? 120,
    );
  }

  /// Converts AppSettings to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'unitSystem': unitSystem.name,
      'themeMode': themeMode.name,
      'defaultRadius': defaultRadius,
      'alarmSensitivity': alarmSensitivity,
      'gpsAccuracyThreshold': gpsAccuracyThreshold,
      'worldTidesApiKey': worldTidesApiKey,
      'soundEnabled': soundEnabled,
      'vibrationEnabled': vibrationEnabled,
      'positionUpdateInterval': positionUpdateInterval,
      'positionHistoryBatchInterval': positionHistoryBatchInterval,
      'gpsLostThreshold': gpsLostThreshold,
      'gpsCheckInterval': gpsCheckInterval,
      'gpsHysteresisDelay': gpsHysteresisDelay,
      'alarmAutoDismissThreshold': alarmAutoDismissThreshold,
    };
  }

  /// Creates a copy with updated fields.
  AppSettings copyWith({
    UnitSystem? unitSystem,
    AppThemeMode? themeMode,
    double? defaultRadius,
    double? alarmSensitivity,
    double? gpsAccuracyThreshold,
    String? worldTidesApiKey,
    bool? soundEnabled,
    bool? vibrationEnabled,
    int? positionUpdateInterval,
    int? positionHistoryBatchInterval,
    int? gpsLostThreshold,
    int? gpsCheckInterval,
    int? gpsHysteresisDelay,
    int? alarmAutoDismissThreshold,
  }) {
    return AppSettings(
      unitSystem: unitSystem ?? this.unitSystem,
      themeMode: themeMode ?? this.themeMode,
      defaultRadius: defaultRadius ?? this.defaultRadius,
      alarmSensitivity: alarmSensitivity ?? this.alarmSensitivity,
      gpsAccuracyThreshold: gpsAccuracyThreshold ?? this.gpsAccuracyThreshold,
      worldTidesApiKey: worldTidesApiKey ?? this.worldTidesApiKey,
      soundEnabled: soundEnabled ?? this.soundEnabled,
      vibrationEnabled: vibrationEnabled ?? this.vibrationEnabled,
      positionUpdateInterval: positionUpdateInterval ?? this.positionUpdateInterval,
      positionHistoryBatchInterval: positionHistoryBatchInterval ?? this.positionHistoryBatchInterval,
      gpsLostThreshold: gpsLostThreshold ?? this.gpsLostThreshold,
      gpsCheckInterval: gpsCheckInterval ?? this.gpsCheckInterval,
      gpsHysteresisDelay: gpsHysteresisDelay ?? this.gpsHysteresisDelay,
      alarmAutoDismissThreshold: alarmAutoDismissThreshold ?? this.alarmAutoDismissThreshold,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is AppSettings &&
        other.unitSystem == unitSystem &&
        other.themeMode == themeMode &&
        other.defaultRadius == defaultRadius &&
        other.alarmSensitivity == alarmSensitivity &&
        other.gpsAccuracyThreshold == gpsAccuracyThreshold &&
        other.worldTidesApiKey == worldTidesApiKey &&
        other.soundEnabled == soundEnabled &&
        other.vibrationEnabled == vibrationEnabled &&
        other.positionUpdateInterval == positionUpdateInterval &&
        other.positionHistoryBatchInterval == positionHistoryBatchInterval &&
        other.gpsLostThreshold == gpsLostThreshold &&
        other.gpsCheckInterval == gpsCheckInterval &&
        other.gpsHysteresisDelay == gpsHysteresisDelay &&
        other.alarmAutoDismissThreshold == alarmAutoDismissThreshold;
  }

  @override
  int get hashCode {
    return Object.hash(
      unitSystem,
      themeMode,
      defaultRadius,
      alarmSensitivity,
      gpsAccuracyThreshold,
      worldTidesApiKey,
      soundEnabled,
      vibrationEnabled,
      positionUpdateInterval,
      positionHistoryBatchInterval,
      gpsLostThreshold,
      gpsCheckInterval,
      gpsHysteresisDelay,
      alarmAutoDismissThreshold,
    );
  }

  @override
  String toString() {
    return 'AppSettings(unitSystem: $unitSystem, themeMode: $themeMode, defaultRadius: $defaultRadius, alarmSensitivity: $alarmSensitivity)';
  }
}

