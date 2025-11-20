import 'package:dio/dio.dart';
import 'package:hive_flutter/hive_flutter.dart';
import '../utils/logger_setup.dart';
import '../models/tide_cache.dart';

/// Service for querying tide information.
/// Uses WorldTides API (free tier available for international waters).
/// Caches tide data for 12 hours to minimize API calls.
class TideService {
  final Dio _dio = Dio();
  
  // WorldTides API endpoint
  // Note: Requires API key - user should set this in settings
  // Free tier: https://www.worldtides.info/api
  static const String _worldTidesUrl = 'https://www.worldtides.info/api';
  
  // Cache box name
  static const String _cacheBoxName = 'tide_cache';
  
  String? _apiKey;
  
  /// Sets the WorldTides API key.
  /// Get a free key at: https://www.worldtides.info/api
  void setApiKey(String? apiKey) {
    _apiKey = apiKey;
  }
  
  /// Gets cache key for a location (rounded to ~1km precision).
  String _getCacheKey(double latitude, double longitude) {
    // Round to ~1km precision (0.01 degrees ≈ 1km)
    final latRounded = (latitude * 100).round() / 100;
    final lonRounded = (longitude * 100).round() / 100;
    return '${latRounded.toStringAsFixed(2)},${lonRounded.toStringAsFixed(2)}';
  }
  
  /// Gets cached tide data for a location.
  TideCache? _getCachedTide(double latitude, double longitude) {
    try {
      if (!Hive.isBoxOpen(_cacheBoxName)) {
        return null;
      }
      
      final box = Hive.box(_cacheBoxName);
      final key = _getCacheKey(latitude, longitude);
      final cachedData = box.get(key);
      
      if (cachedData == null) {
        return null;
      }
      
      final cache = TideCache.fromJson(cachedData as Map<String, dynamic>);
      
      if (cache.isValid()) {
        logger.d('Using cached tide data for $latitude, $longitude');
        return cache;
      } else {
        logger.d('Cached tide data expired for $latitude, $longitude');
        // Remove expired cache
        box.delete(key);
        return null;
      }
    } catch (e) {
      logger.w('Failed to get cached tide data: $e');
      return null;
    }
  }
  
  /// Saves tide data to cache.
  void _saveTideCache(double latitude, double longitude, TideCache cache) {
    try {
      if (!Hive.isBoxOpen(_cacheBoxName)) {
        return;
      }
      
      final box = Hive.box(_cacheBoxName);
      final key = _getCacheKey(latitude, longitude);
      box.put(key, cache.toJson());
      logger.d('Saved tide data to cache for $latitude, $longitude');
    } catch (e) {
      logger.w('Failed to save tide cache: $e');
    }
  }
  
  /// Gets current tide height at a location.
  /// Returns tide height in meters relative to chart datum, or null if unavailable.
  /// Uses cached data if available and valid (within 12 hours).
  Future<double?> getCurrentTideHeight(double latitude, double longitude) async {
    // Check cache first
    final cached = _getCachedTide(latitude, longitude);
    if (cached != null) {
      return cached.getCurrentTideHeight();
    }
    
    if (_apiKey == null || _apiKey.isEmpty) {
      logger.w('WorldTides API key not set. Tide data unavailable.');
      return null;
    }
    
    try {
      final response = await _dio.get(
        _worldTidesUrl,
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'key': _apiKey,
          'datum': 'CD', // Chart Datum
          'hours': 12, // Get 12 hours of data for caching
        },
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final heights = data['heights'] as List<dynamic>?;
        
        if (heights != null && heights.isNotEmpty) {
          // Parse and cache the data
          final tideHeights = heights.map((h) {
            final heightData = h as Map<String, dynamic>;
            return TideHeight(
              dt: DateTime.fromMillisecondsSinceEpoch(
                (heightData['dt'] as int) * 1000,
              ),
              height: (heightData['height'] as num).toDouble(),
            );
          }).toList();
          
          final cache = TideCache(
            latitude: latitude,
            longitude: longitude,
            timestamp: DateTime.now(),
            heights: tideHeights,
          );
          
          _saveTideCache(latitude, longitude, cache);
          
          // Get the first (current) tide height
          final height = tideHeights.first.height;
          logger.d('Current tide height: ${height}m at $latitude, $longitude');
          return height;
        }
      }
      
      logger.w('No tide data found for $latitude, $longitude');
      return null;
    } catch (e, stackTrace) {
      logger.e(
        'Failed to get tide data',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
  
  /// Gets tide height at a specific time.
  /// Uses cached data if available and valid.
  Future<double?> getTideHeightAtTime(
    double latitude,
    double longitude,
    DateTime time,
  ) async {
    // Check cache first
    final cached = _getCachedTide(latitude, longitude);
    if (cached != null) {
      return cached.getTideHeightAtTime(time);
    }
    
    // If not in cache, fetch current data (which will be cached)
    await getCurrentTideHeight(latitude, longitude);
    
    // Try cache again
    final cachedAfterFetch = _getCachedTide(latitude, longitude);
    if (cachedAfterFetch != null) {
      return cachedAfterFetch.getTideHeightAtTime(time);
    }
    
    return null;
  }
  
  /// Gets minimum tide height in the next N hours.
  /// Uses cached data if available and valid.
  Future<double?> getMinTideHeight(
    double latitude,
    double longitude,
    int hours,
  ) async {
    // Check cache first
    final cached = _getCachedTide(latitude, longitude);
    if (cached != null) {
      return cached.getMinTideHeight(hours);
    }
    
    if (_apiKey == null || _apiKey.isEmpty) {
      logger.w('WorldTides API key not set. Tide data unavailable.');
      return null;
    }
    
    try {
      final response = await _dio.get(
        _worldTidesUrl,
        queryParameters: {
          'lat': latitude,
          'lon': longitude,
          'key': _apiKey,
          'datum': 'CD',
          'hours': 12, // Get 12 hours for caching
        },
      );
      
      if (response.statusCode == 200 && response.data != null) {
        final data = response.data as Map<String, dynamic>;
        final heights = data['heights'] as List<dynamic>?;
        
        if (heights != null && heights.isNotEmpty) {
          // Parse and cache the data
          final tideHeights = heights.map((h) {
            final heightData = h as Map<String, dynamic>;
            return TideHeight(
              dt: DateTime.fromMillisecondsSinceEpoch(
                (heightData['dt'] as int) * 1000,
              ),
              height: (heightData['height'] as num).toDouble(),
            );
          }).toList();
          
          final cache = TideCache(
            latitude: latitude,
            longitude: longitude,
            timestamp: DateTime.now(),
            heights: tideHeights,
          );
          
          _saveTideCache(latitude, longitude, cache);
          
          // Find minimum height in requested hours
          double? minHeight;
          final cutoffTime = DateTime.now().add(Duration(hours: hours));
          
          for (final height in tideHeights) {
            if (height.dt.isAfter(cutoffTime)) break;
            if (minHeight == null || height.height < minHeight) {
              minHeight = height.height;
            }
          }
          
          if (minHeight != null) {
            logger.d('Min tide height in next $hours hours: ${minHeight}m');
            return minHeight;
          }
        }
      }
      
      return null;
    } catch (e, stackTrace) {
      logger.e(
        'Failed to get min tide height',
        error: e,
        stackTrace: stackTrace,
      );
      return null;
    }
  }
}

