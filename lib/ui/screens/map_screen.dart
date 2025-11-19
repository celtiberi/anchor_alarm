import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import '../../providers/anchor_provider.dart';
import '../../providers/position_provider.dart';
import '../../providers/position_history_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/anchor.dart';
import '../../models/position_update.dart';
import '../../models/app_settings.dart';
import '../../models/alarm_event.dart';
import '../../utils/distance_calculator.dart';
import '../../utils/logger_setup.dart';
import '../../providers/alarm_provider.dart';
import 'settings_screen.dart';
import 'pairing_screen.dart';

/// Main map screen showing nautical map with anchor and current position.
class MapScreen extends ConsumerStatefulWidget {
  const MapScreen({super.key});

  @override
  ConsumerState<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends ConsumerState<MapScreen> {
  final MapController _mapController = MapController();
  final GlobalKey _mapKey = GlobalKey();
  bool _isDraggingAnchor = false;
  String? _shownAlarmId; // Track which alarm dialog has been shown
  LatLng? _displayAnchorPosition;
  LatLng? _originalAnchorPosition;

  @override
  void initState() {
    super.initState();
    // Start position monitoring when screen loads
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(positionProvider.notifier).startMonitoring();
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  @override
  void dispose() {
    ref.read(positionProvider.notifier).stopMonitoring();
    _mapController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final anchor = ref.watch(anchorProvider);
    final position = ref.watch(positionProvider);
    final positionHistory = ref.watch(positionHistoryProvider);
    final settings = ref.watch(settingsProvider);
    final alarms = ref.watch(activeAlarmsProvider);
    
    // Show alarm dialog for unacknowledged alarms
    final unacknowledgedAlarms = alarms.where((a) => !a.acknowledged).toList();
    if (unacknowledgedAlarms.isNotEmpty) {
      final latestAlarm = unacknowledgedAlarms.first;
      // Only show dialog if we haven't shown it for this alarm yet
      if (_shownAlarmId != latestAlarm.id) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            _showAlarmDialog(context, latestAlarm);
            _shownAlarmId = latestAlarm.id;
          }
        });
      }
    } else {
      // Reset shown alarm ID when no alarms
      _shownAlarmId = null;
    }
    
    // Initialize display position if anchor exists and display position is null
    if (anchor != null && _displayAnchorPosition == null && !_isDraggingAnchor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _displayAnchorPosition = LatLng(anchor.latitude, anchor.longitude);
            logger.d('Initialized display anchor position: (${_displayAnchorPosition!.latitude}, ${_displayAnchorPosition!.longitude})');
          });
        }
      });
    } else if (anchor == null && _displayAnchorPosition != null) {
      // Clear display position when anchor is cleared
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _displayAnchorPosition = null;
            _isDraggingAnchor = false;
            _originalAnchorPosition = null;
            logger.d('Cleared display anchor position');
          });
        }
      });
    } else if (anchor != null && 
               _displayAnchorPosition != null && 
               !_isDraggingAnchor &&
               (anchor.latitude != _displayAnchorPosition!.latitude ||
                anchor.longitude != _displayAnchorPosition!.longitude)) {
      // Update display position if anchor changed externally (not during drag)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() {
            _displayAnchorPosition = LatLng(anchor.latitude, anchor.longitude);
            logger.d('Updated display anchor position from external change: (${_displayAnchorPosition!.latitude}, ${_displayAnchorPosition!.longitude})');
          });
        }
      });
    }

    // Determine center point for map
    LatLng? centerPoint;
    if (position != null) {
      centerPoint = LatLng(position.latitude, position.longitude);
    } else if (anchor != null) {
      centerPoint = LatLng(anchor.latitude, anchor.longitude);
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text('Anchor Alarm'),
        actions: [
          IconButton(
            icon: const Icon(Icons.devices),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const PairingScreen(),
                ),
              );
            },
            tooltip: 'Device Pairing',
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => const SettingsScreen(),
                ),
              );
            },
          ),
        ],
      ),
      body: centerPoint == null
          ? const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(),
                  SizedBox(height: 16),
                  Text('Waiting for GPS signal...'),
                ],
              ),
            )
          : Stack(
              children: [
                // Map
                FlutterMap(
                  key: _mapKey,
                  mapController: _mapController,
                  options: MapOptions(
                    initialCenter: centerPoint,
                    initialZoom: 16.3, // Zoom level to show approximately 200m
                    minZoom: 5.0,
                    maxZoom: 19.0, // Match OpenStreetMap tile maxZoom
                    backgroundColor: Colors.white,
                    interactionOptions: const InteractionOptions(
                      flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
                    ),
                    // Note: Anchorages are shown visually in OpenSeaMap seamark tiles.
                    // Querying Overpass API for anchorage data is unreliable due to sparse coverage.
                    // The seamark tiles already display anchorage icons when zoomed in.
                  ),
                  children: [
                    // Base map layer (OpenStreetMap)
                    TileLayer(
                      urlTemplate:
                          'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.anchor_alarm',
                      maxZoom: 19,
                      errorTileCallback: (tile, error, stackTrace) {
                        logger.w('Failed to load OpenStreetMap tile: $error');
                      },
                    ),
                    // OpenSeaMap nautical overlay (seamarks, buoys, depths soundings, anchorages, harbors, etc.)
                    // Note: In flutter_map 8.2+, overlay layers are transparent by default
                    TileLayer(
                      urlTemplate:
                          'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
                      userAgentPackageName: 'com.example.anchor_alarm',
                      maxZoom: 18,
                      errorTileCallback: (tile, error, stackTrace) {
                        logger.w('Failed to load OpenSeaMap tile: $error');
                      },
                    ),
                    // Position history track (polyline showing boat movement)
                    if (positionHistory.isNotEmpty)
                      PolylineLayer(
                        polylines: [
                          Polyline(
                            points: positionHistory,
                            strokeWidth: 2.0,
                            color: Colors.orange,
                          ),
                        ],
                      ),
                    // Other markers (e.g., current position)
                    MarkerLayer(
                      markers: _buildMarkers(anchor, position),
                    ),
                    // Anchor radius circle (geographic polygon that scales with zoom)
                    if (anchor != null && anchor.isActive && _displayAnchorPosition != null)
                      PolygonLayer(
                        polygons: <Polygon>[
                          Polygon(
                            points: _createCirclePolygon(
                              _displayAnchorPosition!,
                              anchor.radius,
                            ),
                            color: Colors.blue.withValues(alpha: 0.2),
                            borderColor: Colors.blue,
                            borderStrokeWidth: 2.0,
                          ),
                        ],
                      ),
                    // Draggable anchor marker layer
                    // IMPORTANT: DragMarkers must be LAST so it renders on top and can receive touch events
                    if (anchor != null && _displayAnchorPosition != null)
                      DragMarkers(
                        markers: [
                          DragMarker(
                            point: _displayAnchorPosition!,
                            size: const Size(60, 60), // Increased size for better hit area
                            offset: const Offset(0.0, -30.0), // Align icon tip with point
                            builder: (ctx, point, isDragging) {
                              logger.d('DragMarker builder: isDragging=$isDragging, point=(${point.latitude}, ${point.longitude})');
                              return Container(
                                decoration: BoxDecoration(
                                  color: isDragging ? Colors.orange : Colors.blue,
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: Colors.white,
                                    width: 2,
                                  ),
                                ),
                                child: const Icon(
                                  Icons.anchor,
                                  color: Colors.white,
                                  size: 30,
                                ),
                              );
                            },
                            onDragStart: (details, point) {
                              logger.i('DragMarker onDragStart: point=(${point.latitude}, ${point.longitude})');
                              setState(() {
                                _isDraggingAnchor = true;
                                _originalAnchorPosition = _displayAnchorPosition;
                                _displayAnchorPosition = point;
                              });
                            },
                            onDragUpdate: (details, point) {
                              logger.d('DragMarker onDragUpdate: point=(${point.latitude}, ${point.longitude})');
                              setState(() {
                                _displayAnchorPosition = point;
                              });
                            },
                            onDragEnd: (details, point) {
                              logger.i('DragMarker onDragEnd: point=(${point.latitude}, ${point.longitude})');
                              // No auto-save here; wait for user confirm
                            },
                          ),
                        ],
                      ),
                  ],
                ),
                // Info overlay
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: _buildInfoCard(anchor, position, settings),
                ),
                // Anchor controls
                Positioned(
                  bottom: 16,
                  left: 16,
                  right: 16,
                  child: _buildAnchorControls(anchor),
                ),
                // Attribution
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    color: Colors.black.withValues(alpha: 0.5),
                    child: const Text(
                      'Nautical data © OpenSeaMap contributors | Map © OpenStreetMap',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
        );
  }

  List<Marker> _buildMarkers(Anchor? anchor, PositionUpdate? position) {
    final markers = <Marker>[];

    // Current position marker
    if (position != null) {
      markers.add(
        Marker(
          point: LatLng(position.latitude, position.longitude),
          width: 30,
          height: 30,
          child: const Icon(
            Icons.location_on,
            color: Colors.red,
            size: 30,
          ),
        ),
      );
    }

    // Note: Anchorage markers are shown visually in OpenSeaMap seamark tiles.
    // Querying Overpass API for anchorage data is unreliable due to sparse coverage
    // and frequent timeouts. The seamark tiles already display anchorage icons
    // when zoomed in (typically zoom level 12-16+).

    // Anchor marker is now handled by DragMarkers layer
    return markers;
  }

  /// Shows an alarm dialog for the given alarm event.
  Future<void> _showAlarmDialog(BuildContext context, AlarmEvent alarm) async {
    await showDialog(
      context: context,
      barrierDismissible: false, // Must explicitly dismiss
      builder: (BuildContext context) {
        return AlertDialog(
          backgroundColor: Colors.red.shade700,
          title: Row(
            children: [
              const Icon(Icons.warning, color: Colors.white, size: 32),
              const SizedBox(width: 12),
              const Expanded(
                child: Text(
                  'ANCHOR ALARM',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'ALARM TYPE: ${alarm.type.name.toUpperCase()}',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
              const SizedBox(height: 12),
              if (alarm.type == AlarmType.driftExceeded) ...[
                Text(
                  'Your boat has drifted ${alarm.distanceFromAnchor.toStringAsFixed(1)} meters from the anchor position.',
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                ),
                const SizedBox(height: 8),
                Text(
                  'Anchor radius: ${alarm.distanceFromAnchor.toStringAsFixed(1)}m',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ] else if (alarm.type == AlarmType.gpsLost) ...[
                const Text(
                  'GPS signal has been lost. Position tracking is unavailable.',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ] else if (alarm.type == AlarmType.gpsInaccurate) ...[
                const Text(
                  'GPS accuracy is poor. Position may be unreliable.',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
              ],
            ],
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                ref.read(activeAlarmsProvider.notifier).acknowledgeAlarm(alarm.id);
              },
              style: TextButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.red.shade700,
                padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
              ),
              child: const Text(
                'DISMISS',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  Widget _buildInfoCard(
    Anchor? anchor,
    PositionUpdate? position,
    settings,
  ) {
    String distanceText = 'N/A';
    if (anchor != null && position != null) {
      final distance = calculateDistance(
        anchor.latitude,
        anchor.longitude,
        position.latitude,
        position.longitude,
      );
      distanceText = settings.unitSystem == UnitSystem.metric
          ? '${distance.toStringAsFixed(1)} m'
          : '${(distance * 3.28084).toStringAsFixed(1)} ft';
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Distance from Anchor: $distanceText',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            if (position != null) ...[
              const SizedBox(height: 8),
              Text(
                'Speed: ${position.speed != null ? (position.speed! * 3.6).toStringAsFixed(1) : "N/A"} km/h',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              Text(
                'Accuracy: ${position.accuracy != null ? position.accuracy!.toStringAsFixed(1) : "N/A"} m',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildAnchorControls(Anchor? anchor) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Radius adjustment slider (when anchor is set)
            if (anchor != null && !_isDraggingAnchor) ...[
              Row(
                children: [
                  const Icon(Icons.radio_button_unchecked, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Anchor Radius: ${anchor.radius.toStringAsFixed(0)} m',
                          style: Theme.of(context).textTheme.titleSmall,
                        ),
                        Slider(
                          value: anchor.radius,
                          min: 20,
                          max: 100,
                          divisions: 16,
                          label: '${anchor.radius.toStringAsFixed(0)} m',
                          onChanged: (value) {
                            ref.read(anchorProvider.notifier).updateRadius(value);
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const Divider(),
            ],
            // Control buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                if (anchor == null)
                  ElevatedButton.icon(
                    onPressed: () => _setAnchorFromCurrentPosition(),
                    icon: const Icon(Icons.anchor),
                    label: const Text('Set Anchor'),
                  )
                else ...[
                  if (_isDraggingAnchor) ...[
                    ElevatedButton.icon(
                      onPressed: _confirmAnchorDrag,
                      icon: const Icon(Icons.check),
                      label: const Text('Confirm'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.green,
                      ),
                    ),
                    ElevatedButton.icon(
                      onPressed: _cancelAnchorDrag,
                      icon: const Icon(Icons.cancel),
                      label: const Text('Cancel'),
                    ),
                  ],
                  ElevatedButton.icon(
                    onPressed: () => _clearAnchor(),
                    icon: const Icon(Icons.delete),
                    label: const Text('Clear'),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _setAnchorFromCurrentPosition() async {
    try {
      final position = await ref.read(positionProvider.notifier).getCurrentPosition();
      final settings = ref.read(settingsProvider);
      
      await ref.read(anchorProvider.notifier).setAnchor(
            latitude: position.latitude,
            longitude: position.longitude,
            radius: settings.defaultRadius,
          );
      
      // Start alarm monitoring when anchor is set
      ref.read(activeAlarmsProvider.notifier).startMonitoring();
      logger.i('Anchor set at ${position.latitude}, ${position.longitude}');
    } catch (e, stackTrace) {
      logger.e(
        'Failed to set anchor',
        error: e,
        stackTrace: stackTrace,
      );
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to set anchor: $e'),
            backgroundColor: Colors.red,
            duration: const Duration(seconds: 5),
          ),
        );
      }
    }
  }


  void _confirmAnchorDrag() {
    if (_displayAnchorPosition == null) {
      return;
    }

    ref.read(anchorProvider.notifier).updateAnchorPosition(
          latitude: _displayAnchorPosition!.latitude,
          longitude: _displayAnchorPosition!.longitude,
        );

    logger.i('Anchor position confirmed: ${_displayAnchorPosition!.latitude}, ${_displayAnchorPosition!.longitude}');

    setState(() {
      _isDraggingAnchor = false;
      _originalAnchorPosition = null;
    });
  }

  void _cancelAnchorDrag() {
    logger.i('Anchor drag cancelled');
    setState(() {
      if (_originalAnchorPosition != null) {
        _displayAnchorPosition = _originalAnchorPosition;
      }
      _isDraggingAnchor = false;
      _originalAnchorPosition = null;
    });
  }

  Future<void> _clearAnchor() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear Anchor'),
        content: const Text('Are you sure you want to clear the anchor?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );

    if (confirmed == true) {
      await ref.read(anchorProvider.notifier).clearAnchor();
      
      // Stop alarm monitoring when anchor is cleared
      ref.read(activeAlarmsProvider.notifier).stopMonitoring();
    }
  }

  /// Creates a circle polygon from a center point and radius in meters.
  /// The polygon will scale correctly with map zoom since it's defined in geographic coordinates.
  List<LatLng> _createCirclePolygon(LatLng center, double radiusMeters) {
    const int points = 64; // Number of points to approximate the circle
    const double earthRadiusMeters = 6371000; // Earth's radius in meters
    
    final List<LatLng> polygonPoints = [];
    
    for (int i = 0; i <= points; i++) {
      final double angle = (i * 360.0 / points) * (math.pi / 180.0);
      
      // Calculate the destination point using the bearing and distance
      final double lat1Rad = center.latitude * (math.pi / 180.0);
      final double lon1Rad = center.longitude * (math.pi / 180.0);
      final double angularDistance = radiusMeters / earthRadiusMeters;
      
      final double lat2Rad = math.asin(
        math.sin(lat1Rad) * math.cos(angularDistance) +
        math.cos(lat1Rad) * math.sin(angularDistance) * math.cos(angle),
      );
      
      final double lon2Rad = lon1Rad + math.atan2(
        math.sin(angle) * math.sin(angularDistance) * math.cos(lat1Rad),
        math.cos(angularDistance) - math.sin(lat1Rad) * math.sin(lat2Rad),
      );
      
      polygonPoints.add(
        LatLng(
          lat2Rad * (180.0 / math.pi),
          lon2Rad * (180.0 / math.pi),
        ),
      );
    }
    
    return polygonPoints;
  }
}

