import 'dart:convert';
import 'package:hive/hive.dart';
import '../models/anchor.dart';
import '../models/app_settings.dart';

/// Repository for local storage using Hive.
class LocalStorageRepository {
  static const String _settingsBoxName = 'settings';
  static const String _anchorBoxName = 'anchor'; // Reserved for future use

  /// Initializes Hive boxes.
  Future<void> initialize() async {
    // Open settings box (using untyped box for now since adapters aren't implemented)
    if (!Hive.isBoxOpen(_settingsBoxName)) {
      await Hive.openBox(_settingsBoxName);
    }
    
    // Open anchor box (using untyped box with JSON storage)
    if (!Hive.isBoxOpen(_anchorBoxName)) {
      await Hive.openBox(_anchorBoxName);
    }
    
    // Open tide cache box
    if (!Hive.isBoxOpen('tide_cache')) {
      await Hive.openBox('tide_cache');
    }
  }

  /// Saves the anchor to local storage using JSON.
  Future<void> saveAnchor(Anchor anchor) async {
    final box = Hive.box(_anchorBoxName);
    final json = jsonEncode(anchor.toJson());
    await box.put('current', json);
  }

  /// Gets the saved anchor from local storage.
  Anchor? getAnchor() {
    final box = Hive.box(_anchorBoxName);
    final jsonString = box.get('current') as String?;
    if (jsonString == null) {
      return null;
    }
    
    try {
      final json = jsonDecode(jsonString) as Map<String, dynamic>;
      return Anchor.fromJson(json);
    } catch (e) {
      // If parsing fails, return null (corrupted data)
      return null;
    }
  }

  /// Deletes the saved anchor.
  Future<void> deleteAnchor() async {
    final box = Hive.box(_anchorBoxName);
    await box.delete('current');
  }

  /// Saves app settings to local storage.
  Future<void> saveSettings(AppSettings settings) async {
    final box = Hive.box(_settingsBoxName);
    await box.put('unitSystem', settings.unitSystem.name);
    await box.put('themeMode', settings.themeMode.name);
    await box.put('defaultRadius', settings.defaultRadius);
    await box.put('alarmSensitivity', settings.alarmSensitivity);
    await box.put('worldTidesApiKey', settings.worldTidesApiKey);
    await box.put('soundEnabled', settings.soundEnabled);
    await box.put('vibrationEnabled', settings.vibrationEnabled);
  }

  /// Gets app settings from local storage.
  AppSettings getSettings() {
    final box = Hive.box(_settingsBoxName);
    
    // Return default settings if box is not open or no settings stored
    if (!Hive.isBoxOpen(_settingsBoxName)) {
      return const AppSettings();
    }
    
    return AppSettings(
      unitSystem: _parseUnitSystem(box.get('unitSystem', defaultValue: 'metric')),
      themeMode: _parseThemeMode(box.get('themeMode', defaultValue: 'system')),
      defaultRadius: box.get('defaultRadius', defaultValue: 50.0) as double? ?? 50.0,
      alarmSensitivity: box.get('alarmSensitivity', defaultValue: 0.5) as double? ?? 0.5,
      worldTidesApiKey: box.get('worldTidesApiKey', defaultValue: '40a47278-06b2-4f97-a7ca-0f7fa8962b63') as String? ?? '40a47278-06b2-4f97-a7ca-0f7fa8962b63',
      soundEnabled: box.get('soundEnabled', defaultValue: true) as bool? ?? true,
      vibrationEnabled: box.get('vibrationEnabled', defaultValue: true) as bool? ?? true,
    );
  }
  
  UnitSystem _parseUnitSystem(String value) {
    return UnitSystem.values.firstWhere(
      (e) => e.name == value,
      orElse: () => UnitSystem.metric,
    );
  }
  
  AppThemeMode _parseThemeMode(String value) {
    return AppThemeMode.values.firstWhere(
      (e) => e.name == value,
      orElse: () => AppThemeMode.system,
    );
  }
}

/// Hive adapter for Anchor (placeholder - would need code generation).
class AnchorAdapter extends TypeAdapter<Anchor> {
  @override
  final int typeId = 0;

  @override
  Anchor read(BinaryReader reader) {
    // This would need proper implementation or code generation
    throw UnimplementedError('Anchor adapter needs implementation');
  }

  @override
  void write(BinaryWriter writer, Anchor obj) {
    // This would need proper implementation or code generation
    throw UnimplementedError('Anchor adapter needs implementation');
  }
}

/// Hive adapter for AppSettings (placeholder - would need code generation).
class AppSettingsAdapter extends TypeAdapter<AppSettings> {
  @override
  final int typeId = 1;

  @override
  AppSettings read(BinaryReader reader) {
    // This would need proper implementation or code generation
    throw UnimplementedError('AppSettings adapter needs implementation');
  }

  @override
  void write(BinaryWriter writer, AppSettings obj) {
    // This would need proper implementation or code generation
    throw UnimplementedError('AppSettings adapter needs implementation');
  }
}

