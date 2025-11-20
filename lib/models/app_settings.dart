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

  const AppSettings({
    this.unitSystem = UnitSystem.metric,
    this.themeMode = AppThemeMode.system,
    this.defaultRadius = 50.0,
    this.alarmSensitivity = 0.5,
    this.gpsAccuracyThreshold = 20.0, // Default: warn if GPS accuracy > 20m
    this.worldTidesApiKey = '40a47278-06b2-4f97-a7ca-0f7fa8962b63', // Default API key
    this.soundEnabled = true,
    this.vibrationEnabled = true,
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
        other.vibrationEnabled == vibrationEnabled;
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
    );
  }

  @override
  String toString() {
    return 'AppSettings(unitSystem: $unitSystem, themeMode: $themeMode, defaultRadius: $defaultRadius, alarmSensitivity: $alarmSensitivity)';
  }
}

