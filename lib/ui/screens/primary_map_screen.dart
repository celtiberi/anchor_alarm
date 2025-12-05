import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:flutter_map_dragmarker/flutter_map_dragmarker.dart';
import '../../providers/anchor_provider.dart';
import '../../providers/gps_provider.dart';
import '../../providers/position_history_provider.dart';
import '../../providers/settings_provider.dart';
import '../../models/anchor.dart';
import '../../models/position_update.dart';
import '../../models/alarm_event.dart';
import '../../models/app_settings.dart';
import '../../utils/distance_calculator.dart';
import '../../utils/distance_formatter.dart';
import '../../utils/logger_setup.dart';
import '../../utils/map_utils.dart';
import '../../providers/service_providers.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import '../../providers/alarm_provider.dart';
import '../../models/position_history_point.dart';
import 'settings_screen.dart';

/// Map screen for primary devices with full control over anchor and monitoring.
class PrimaryMapScreen extends ConsumerStatefulWidget {
  const PrimaryMapScreen({super.key});

  @override
  ConsumerState<PrimaryMapScreen> createState() => _PrimaryMapScreenState();
}

class _PrimaryMapScreenState extends ConsumerState<PrimaryMapScreen> {
  final MapController _mapController = MapController();
  final GlobalKey _mapKey = GlobalKey();
  bool _isDraggingAnchor = false;
  LatLng? _displayAnchorPosition;
  List<LatLng>? _cachedPolygonPoints;
  LatLng? _cachedPolygonCenter;
  double? _cachedPolygonRadius;
  final Set<String> _shownWarningIds = {}; // Track which warnings have been shown
  bool _positionMonitoringStarted = false;
  bool _isInfoCardExpanded = true; // Track if info card is expanded
  bool _isDraggingRadius = false; // Track if radius slider is being dragged
  double _sliderRadiusValue = 25.0; // Default radius in meters

  @override
  void initState() {
    super.initState();
    // Start GPS monitoring for primary device
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _startGPSMonitoring();
    });
  }

  void _startGPSMonitoring() {
    if (!_positionMonitoringStarted) {
      logger.i('Primary device starting GPS monitoring');
      try {
        ref.read(positionProvider.notifier).startMonitoring();
        _positionMonitoringStarted = true;
      } catch (e) {
        logger.e('Failed to start GPS monitoring on primary device', error: e);
      }
    }
  }


  @override
  Widget build(BuildContext context) {
    // Optimize provider watches - only watch what changes frequently
    final anchor = ref.watch(anchorProvider);
    final position = ref.watch(positionProvider);
    final positionHistory = ref.watch(positionHistoryProvider);
    final alarms = ref.watch(activeAlarmsProvider) ;
    final settings = ref.watch(settingsProvider);
    final isMonitoring = ref.read(activeAlarmsProvider.notifier).isMonitoring;

    // Cache expensive computations
    final activeAlarms = alarms.where((a) => a.severity == Severity.alarm).toList();
    final activeWarnings = alarms.where((a) => a.severity == Severity.warning).toList();

    // Only watch connectivity when needed
    final connectivityAsync = ref.watch(connectivityProvider);
    final connectivityList = connectivityAsync.maybeWhen(
      data: (data) => data,
      orElse: () => <ConnectivityResult>[],
    );
    final isOffline = connectivityList.isEmpty || connectivityList.contains(ConnectivityResult.none);

    // Auto-start monitoring when anchor is set
    ref.listen<Anchor?>(anchorProvider, (previous, next) {
      // Only auto-start if transitioning from no anchor to having an anchor
      if (next != null && next.isActive && previous == null) {
        try {
          ref.read(activeAlarmsProvider.notifier).startMonitoring();
          logger.i('Auto-started monitoring for new anchor');
        } catch (e, stackTrace) {
          logger.e('Failed to auto-start monitoring for new anchor', error: e, stackTrace: stackTrace);
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Anchor set, but monitoring failed to start. Use "Restart Monitoring" button.'),
                backgroundColor: Theme.of(context).colorScheme.error,
                duration: const Duration(seconds: 3),
              ),
            );
          }
        }
      }
    });

    // Handle warnings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        for (final warning in activeWarnings) {
          if (!_shownWarningIds.contains(warning.id)) {
            _shownWarningIds.add(warning.id);
            _showWarningSnackBar(warning, settings);
          }
        }
        _shownWarningIds.removeWhere((id) => !activeWarnings.any((w) => w.id == id));
      }
    });

    // Update anchor display position
    LatLng? displayAnchorPosition = _displayAnchorPosition;
    if (!_isDraggingAnchor) {
      displayAnchorPosition = anchor != null ? LatLng(anchor.latitude, anchor.longitude) : null;
    }

    // Calculate map center
    LatLng? centerPoint;
    if (position != null) {
      centerPoint = LatLng(position.latitude, position.longitude);
    } else if (anchor != null) {
      centerPoint = LatLng(anchor.latitude, anchor.longitude);
    }

    final shouldShowLoading = centerPoint == null;

    return Scaffold(
      appBar: _buildAppBar(),
      body: shouldShowLoading
          ? _buildLoadingState()
          : _buildMapStack(anchor, position, displayAnchorPosition, positionHistory, activeAlarms, settings, isMonitoring, isOffline, centerPoint),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Anchor Alarm'),
      actions: [
        IconButton(
          icon: const Icon(Icons.settings),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (context) => const SettingsScreen()),
            );
          },
        ),
      ],
    );
  }

  Widget _buildLoadingState() {
    return Container(
      color: Theme.of(context).colorScheme.surface,
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Waiting for GPS signal...'),
          ],
        ),
      ),
    );
  }

  Widget _buildMapStack(Anchor? anchor, PositionUpdate? position,
      LatLng? displayAnchorPosition, List<PositionHistoryPoint> positionHistory, List<AlarmEvent> activeAlarms, AppSettings settings, bool isMonitoring, bool isOffline, LatLng centerPoint) {
    // Use current slider value during dragging for real-time circle updates
    final currentRadius = _isDraggingRadius ? _sliderRadiusValue : null;

    // Calculate effective radius for display (accounting for sensitivity like alarm logic)
    double? displayRadius;
    if (anchor != null) {
      final baseRadius = currentRadius ?? anchor.radius;
      // Apply same sensitivity calculation as alarm service
      const double maxSensitivityReduction = 0.2; // Maximum 20% reduction in radius
      final sensitivityMultiplier = settings.alarmSensitivity.clamp(0.0, 1.0) * maxSensitivityReduction;
      displayRadius = baseRadius * (1.0 - sensitivityMultiplier);
    }

    // Calculate zoom level
    double zoomLevel = 18.0;
    if (anchor != null && displayRadius != null) {
      zoomLevel = calculateZoomForRadius(displayRadius);
    }


    return Stack(
      children: [
        FlutterMap(
          key: _mapKey,
          mapController: _mapController,
          options: MapOptions(
            initialCenter: centerPoint,
            initialZoom: zoomLevel,
            maxZoom: 22.0,
            minZoom: 5.0,
            // Disable rotation to keep north "up"
            interactionOptions: InteractionOptions(
              flags: InteractiveFlag.drag | InteractiveFlag.pinchZoom | InteractiveFlag.doubleTapZoom,
              // Exclude rotate to prevent map rotation
            ),
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sailorsparrot.anchoralarm',
            ),
            // Position history trail - only show if we have history
            if (positionHistory.isNotEmpty)
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: positionHistory.map((p) => p.position).toList(),
                    color: Colors.blue.withValues(alpha: 0.6),
                    strokeWidth: 3.0,
                  ),
                ],
              ),
            // Anchor radius circle
            if (anchor != null && displayAnchorPosition != null && displayRadius != null)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _getAnchorRadiusPolygonPoints(displayAnchorPosition, displayRadius),
                    color: getAnchorCircleColor(anchor, position, context, currentRadius: currentRadius).withValues(alpha: 0.2),
                    borderColor: getAnchorCircleColor(anchor, position, context, currentRadius: currentRadius),
                    borderStrokeWidth: 2.0,
                  ),
                ],
              ),
            // Markers
            MarkerLayer(
              markers: _buildMarkers(anchor, position),
            ),
            // Drag marker for anchor
            if (anchor != null && displayAnchorPosition != null)
              DragMarkers(
                markers: [
                  DragMarker(
                    point: displayAnchorPosition,
                    size: const Size.square(120.0),
                    builder: (context, pos, isDragging) {
                      if (isDragging) {
                        _isDraggingAnchor = true;
                      }
                      return Icon(
                        Icons.anchor,
                        size: 40,
                        color: isDragging ? Colors.orange : Colors.red,
                      );
                    },
                    onDragUpdate: (details, point) {
                      setState(() {
                        _displayAnchorPosition = point;
                      });
                    },
                    onDragEnd: (details, point) async {
                      try {
                        await ref.read(anchorProvider.notifier).updateAnchorPosition(latitude: point.latitude, longitude: point.longitude);
                        setState(() {
                          _displayAnchorPosition = null;
                          _isDraggingAnchor = false;
                          _cachedPolygonPoints = null;
                        });
                      } catch (e, stackTrace) {
                        logger.e('Error updating anchor position', error: e, stackTrace: stackTrace);
                        setState(() {
                          _displayAnchorPosition = null;
                          _isDraggingAnchor = false;
                        });
                      }
                    },
                  ),
                ],
              ),
          ],
        ),
        // Alarm banner
        if (activeAlarms.isNotEmpty)
          Positioned(
            top: 10,
            left: 10,
            right: 10,
            child: _buildAlarmBanner(activeAlarms.first, settings),
          ),
        // Info card - positioned at top like in original screen
        Positioned(
          top: activeAlarms.isNotEmpty ? 160 : 16,
          left: 16,
          right: 16,
          child: _buildInfoCard(anchor, position, settings, isMonitoring, isOffline),
        ),
        // Anchor controls - positioned at bottom
        Positioned(
          bottom: 16,
          left: 16,
          right: 16,
          child: _buildAnchorControls(anchor, isMonitoring),
        ),
      ],
    );
  }

  Widget _buildAlarmBanner(AlarmEvent alarm, AppSettings settings) {
    final theme = Theme.of(context);
    return Card(
      color: theme.colorScheme.error,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  Icons.warning,
                  color: theme.colorScheme.onError,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'ALARM',
                    style: TextStyle(
                      color: theme.colorScheme.onError,
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (alarm.type == AlarmType.driftExceeded)
              Text(
                'Drifted ${formatDistance(alarm.distanceFromAnchor, settings.unitSystem)} from anchor',
                style: TextStyle(color: theme.colorScheme.onError, fontSize: 12),
              )
            else if (alarm.type == AlarmType.gpsLost)
              Text(
                'GPS signal lost',
                style: TextStyle(color: theme.colorScheme.onError, fontSize: 12),
              )
            else if (alarm.type == AlarmType.gpsInaccurate)
              Text(
                'GPS accuracy poor',
                style: TextStyle(color: theme.colorScheme.onError, fontSize: 12),
              ),
            const SizedBox(height: 8),
            ElevatedButton(
              onPressed: () {
                // Manual dismiss - stop monitoring
                ref.read(activeAlarmsProvider.notifier).acknowledgeAlarm(alarm.id);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.white,
                foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: Text(
                'DISMISS',
                style: Theme.of(context).textTheme.labelLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Colors.black,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(Anchor? anchor, PositionUpdate? position, AppSettings settings, bool isMonitoring, bool isOffline) {
    return Card(
      elevation: 4,
      child: InkWell(
        onTap: () {
          setState(() {
            _isInfoCardExpanded = !_isInfoCardExpanded;
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // Monitoring status - always visible, with expand/collapse icon
              Row(
                children: [
                  Icon(
                    isMonitoring ? Icons.visibility : Icons.visibility_off,
                    color: isMonitoring ? Colors.green : Colors.orange,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      isMonitoring ? 'Monitoring Active' : 'Monitoring Paused',
                      style: TextStyle(
                        color: isMonitoring ? Colors.green : Colors.orange,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                  Icon(
                    _isInfoCardExpanded ? Icons.expand_less : Icons.expand_more,
                    size: 20,
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
              // Offline indicator
              if (isOffline)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Row(
                    children: [
                      Icon(
                        Icons.cloud_off,
                        color: Colors.orange,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'Offline Mode',
                        style: TextStyle(
                          color: Colors.orange,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),

              // Expanded content
              if (_isInfoCardExpanded) ...[
                const SizedBox(height: 12),
                // Anchor info
                if (anchor != null) ...[
                  Text(
                    'Anchor Set',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lat: ${anchor.latitude.toStringAsFixed(6)}, Lon: ${anchor.longitude.toStringAsFixed(6)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  Text(
                    'Radius: ${formatDistance(anchor.radius, settings.unitSystem)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (position != null) ...[
                    const SizedBox(height: 8),
                    Text(
                      'Current Position',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Lat: ${position.latitude.toStringAsFixed(6)}, Lon: ${position.longitude.toStringAsFixed(6)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      'Distance from anchor: ${formatDistance(
                        calculateDistance(
                          anchor.latitude,
                          anchor.longitude,
                          position.latitude,
                          position.longitude,
                        ),
                        settings.unitSystem,
                      )}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                  // Raise anchor button - shown when anchor is set
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final confirmed = await showDialog<bool>(
                          context: context,
                          builder: (context) => AlertDialog(
                            title: const Text('Clear Anchor'),
                            content: const Text(
                              'This will stop monitoring and clear the current anchor position. '
                              'Are you sure?',
                            ),
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
                          try {
                            // Clear all alarms and stop monitoring BEFORE clearing anchor
                            ref.read(activeAlarmsProvider.notifier).clearAllAlarms();
                            ref.read(activeAlarmsProvider.notifier).stopMonitoring();

                            // Clear anchor
                            await ref.read(anchorProvider.notifier).clearAnchor();

                            // Clear position history
                            ref.read(positionHistoryProvider.notifier).clearHistory();

                            // Clear cached polygon
                            setState(() {
                              _displayAnchorPosition = null;
                              _cachedPolygonPoints = null;
                              _cachedPolygonCenter = null;
                              _cachedPolygonRadius = null;
                            });
                          } catch (e, stackTrace) {
                            logger.e('Error clearing anchor', error: e, stackTrace: stackTrace);
                            if (mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                SnackBar(
                                  content: Text('Failed to clear anchor: $e'),
                                  backgroundColor: Theme.of(context).colorScheme.error,
                                ),
                              );
                            }
                          }
                        }
                      },
                      icon: const Icon(Icons.anchor),
                      label: const Text('Raise Anchor'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.orange,
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 12),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ),
                ] else if (position != null) ...[
                  Text(
                    'GPS Position Available',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Lat: ${position.latitude.toStringAsFixed(6)}, Lon: ${position.longitude.toStringAsFixed(6)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ] else ...[
                  Text(
                    'Waiting for GPS signal...',
                    style: TextStyle(
                      fontSize: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAnchorControls(Anchor? anchor, bool isMonitoring) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (anchor == null) ...[
          // Set anchor button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              onPressed: () async {
                try {
                  final position = await _getCurrentPositionWithTimeout();
                  final settings = ref.read(settingsProvider);
                  await _createAnchorFromPosition(position, settings);
                  await _adjustMapForNewAnchor();
                  _handleAnchorSet(position, settings);
                } on TimeoutException catch (e) {
                  _handleTimeoutError(e);
                } catch (e, stackTrace) {
                  _handleAnchorSetupError(e, stackTrace);
                }
              },
              icon: const Icon(Icons.anchor),
              label: const Text('Set Anchor'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            ),
          ),
        ] else ...[
          // Anchor controls
          if (!isMonitoring) ...[
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () async {
                  logger.i('🔄 USER ACTION: Restart Monitoring button pressed');
                  try {
                    await ref.read(activeAlarmsProvider.notifier).startMonitoringAsync();
                    logger.i('✅ USER ACTION: Restart Monitoring completed successfully');
                  } catch (e) {
                    logger.e('❌ USER ACTION: Restart Monitoring failed', error: e);
                    // Show error to user if needed
                    if (context.mounted) {
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(
                          content: Text('Failed to restart monitoring: $e'),
                          backgroundColor: Colors.red,
                        ),
                      );
                    }
                  }
                },
                icon: const Icon(Icons.play_arrow),
                label: const Text('Restart Monitoring'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          // Anchor radius slider
          Card(
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Anchor Radius: ${formatDistance(_isDraggingRadius ? _sliderRadiusValue : anchor.radius, ref.watch(settingsProvider).unitSystem)}',
                    style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Slider(
                    value: _sliderRadiusValue,
                    min: 1.0,
                    max: 100.0,
                    divisions: 99,
                    label: '${_sliderRadiusValue.round()}m',
                    onChanged: (value) {
                      // Update local slider value for smooth visual feedback
                      setState(() {
                        _sliderRadiusValue = value;
                      });

                      // Pause monitoring once when dragging starts to prevent false alarms
                      if (!_isDraggingRadius) {
                        _isDraggingRadius = true;
                        ref.read(activeAlarmsProvider.notifier).pauseMonitoring();
                      }
                    },
                    onChangeEnd: (value) async {
                      try {
                        await ref.read(anchorProvider.notifier).updateRadius(_sliderRadiusValue);
                        // Resume monitoring after radius update
                        ref.read(activeAlarmsProvider.notifier).resumeMonitoring();
                      } catch (e, stackTrace) {
                        logger.e('Error updating anchor radius', error: e, stackTrace: stackTrace);
                        // Ensure monitoring is resumed even on error
                        ref.read(activeAlarmsProvider.notifier).resumeMonitoring();
                        if (mounted) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text('Failed to update anchor radius: $e'),
                              backgroundColor: Theme.of(context).colorScheme.error,
                            ),
                          );
                        }
                      }
                      setState(() {
                        _isDraggingRadius = false;
                      });
                    },
                  ),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  List<Marker> _buildMarkers(Anchor? anchor, PositionUpdate? position) {
    final markers = <Marker>[];

    // Current position marker
    if (position != null) {
      markers.add(
        Marker(
          point: LatLng(position.latitude, position.longitude),
          child: const Icon(
            Icons.my_location,
            color: Colors.blue,
            size: 30,
          ),
        ),
      );
    }

    // Anchor marker (only if not being dragged)
    if (anchor != null && !_isDraggingAnchor) {
      markers.add(
        Marker(
          point: LatLng(anchor.latitude, anchor.longitude),
          child: const Icon(
            Icons.anchor,
            color: Colors.red,
            size: 30,
          ),
        ),
      );
    }

    return markers;
  }

  List<LatLng> _getAnchorRadiusPolygonPoints(LatLng center, double radiusMeters) {
    // Cache polygon points for performance
    if (_cachedPolygonPoints != null &&
        _cachedPolygonCenter == center &&
        (_cachedPolygonRadius ?? 0) == radiusMeters) {
      return _cachedPolygonPoints!;
    }

    const int segments = 64;
    final points = <LatLng>[];

    // Convert radius from meters to approximate degrees (rough approximation)
    final radiusDegrees = radiusMeters / 111320; // ~111km per degree latitude

    for (int i = 0; i <= segments; i++) {
      final angle = (i * 2 * math.pi) / segments;
      final lat = center.latitude + radiusDegrees * math.sin(angle);
      final lng = center.longitude + radiusDegrees * math.cos(angle) / math.cos(center.latitude * math.pi / 180);
      points.add(LatLng(lat, lng));
    }

    // Cache the result
    _cachedPolygonPoints = points;
    _cachedPolygonCenter = center;
    _cachedPolygonRadius = radiusMeters;

    return points;
  }

  /// Gets the color for the anchor circle based on boat position.
  /// Returns error color (red) when boat is outside radius, primary color (blue) when inside.

  /// Calculates appropriate zoom level to show the full anchor radius circle.
  /// Returns zoom level that ensures the radius is visible with some padding.

  /// Shows a warning as a SnackBar (non-intrusive).
  void _showWarningSnackBar(AlarmEvent warning, AppSettings settings) {
    final theme = Theme.of(context);
    String message;
    if (warning.type == AlarmType.gpsLost) {
      message = 'GPS signal lost';
    } else if (warning.type == AlarmType.gpsInaccurate) {
      message = 'GPS accuracy poor';
    } else {
      message = 'Warning: ${warning.type.name}';
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            Icon(
              Icons.warning,
              color: theme.colorScheme.onInverseSurface,
              size: 20,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(message),
            ),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
  }

  Future<PositionUpdate> _getCurrentPositionWithTimeout() async {
    try {
      final position = await ref.read(positionProvider.notifier).getCurrentPosition().timeout(
        const Duration(seconds: 10),
        onTimeout: () => throw TimeoutException('GPS timeout'),
      );
      return position;
    } catch (e) {
      throw TimeoutException('Failed to get GPS position: $e');
    }
  }

  Future<void> _createAnchorFromPosition(PositionUpdate position, AppSettings settings) async {
    await ref.read(anchorProvider.notifier).setAnchor(
      latitude: position.latitude,
      longitude: position.longitude,
      radius: _sliderRadiusValue,
    );
  }

  Future<void> _adjustMapForNewAnchor() async {
    final anchor = ref.read(anchorProvider);
    if (anchor != null) {
      final zoom = calculateZoomForRadius(anchor.radius);
      _mapController.move(LatLng(anchor.latitude, anchor.longitude), zoom);
    }
  }

  void _handleAnchorSet(PositionUpdate position, AppSettings settings) {
    // Update slider to match current anchor radius
    final anchor = ref.read(anchorProvider);
    if (anchor != null) {
      setState(() {
        _sliderRadiusValue = anchor.radius;
      });
    }
  }

  void _handleTimeoutError(TimeoutException e) {
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('GPS timeout - could not get current position'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }

  void _handleAnchorSetupError(Object e, StackTrace stackTrace) {
    logger.e('Error setting anchor', error: e, stackTrace: stackTrace);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set anchor: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
        ),
      );
    }
  }
}

