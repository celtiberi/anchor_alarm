import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../../providers/settings_provider.dart';
import '../../providers/pairing_providers.dart';
import '../../providers/remote_data_providers.dart';
import '../../providers/local_alarm_dismissal_provider.dart';
import '../../providers/service_providers.dart';
import '../../models/anchor.dart';
import '../../models/position_update.dart';
import '../../models/alarm_event.dart';
import '../../models/app_settings.dart';
import '../../utils/distance_calculator.dart';
import '../../utils/distance_formatter.dart';
import '../../utils/logger_setup.dart';
import '../../utils/map_utils.dart';
import '../../models/position_history_point.dart';
import 'settings_screen.dart';

/// Map screen for secondary devices with read-only view of primary device's data.
class SecondaryMapScreen extends ConsumerStatefulWidget {
  const SecondaryMapScreen({super.key});

  @override
  ConsumerState<SecondaryMapScreen> createState() => _SecondaryMapScreenState();
}

class _SecondaryMapScreenState extends ConsumerState<SecondaryMapScreen> {
  final MapController _mapController = MapController();
  final GlobalKey _mapKey = GlobalKey();
  List<LatLng>? _cachedPolygonPoints;
  LatLng? _cachedPolygonCenter;
  double? _cachedPolygonRadius;
  final Set<String> _shownWarningIds =
      {}; // Track which warnings have been shown
  bool _isInfoCardExpanded = true; // Track if info card is expanded
  LatLng? _lastCenterPoint; // Track last center point to detect changes
  DateTime? _roleChangeTime; // Track when role changed to force loading state
  bool _mapRendered = false; // Track if FlutterMap has been rendered

  @override
  Widget build(BuildContext context) {
    // Track role changes to force loading state during transitions
    ref.listen<PairingSessionState>(pairingSessionStateProvider, (
      previous,
      next,
    ) {
      if (previous?.role != next.role) {
        _roleChangeTime = DateTime.now();
      }
    });

    // Listen to anchor changes and update map center
    ref.listen<AsyncValue<Anchor?>>(remoteAnchorProvider, (previous, next) {
      final anchor = next.value;
      final prevAnchor = previous?.value;
      if (anchor != null && mounted && _mapRendered) {
        final centerPoint = LatLng(anchor.latitude, anchor.longitude);

        // Only update zoom if anchor position changed (not just radius)
        double zoomLevel = _mapController.camera.zoom; // Keep current zoom
        if (prevAnchor == null ||
            prevAnchor.latitude != anchor.latitude ||
            prevAnchor.longitude != anchor.longitude) {
          // Anchor position changed - recalculate zoom for new position
          zoomLevel = calculateZoomForRadius(anchor.radius);
          logger.d(
            'Secondary map centered on anchor: ${anchor.latitude}, ${anchor.longitude}',
          );
        } else {
          // Only radius changed - keep current zoom level
          logger.d(
            'Secondary map radius changed to ${anchor.radius}m, keeping current zoom',
          );
        }

        _mapController.move(centerPoint, zoomLevel);
      }
    });

    // Listen to position changes and center map if no anchor is set
    ref.listen<AsyncValue<PositionUpdate?>>(remotePositionProvider, (
      previous,
      next,
    ) {
      final position = next.value;
      if (position != null && mounted && _mapRendered) {
        final currentAnchor = ref.read(remoteAnchorProvider).value;
        // Only center on position if there's no anchor set
        if (currentAnchor == null) {
          final centerPoint = LatLng(position.latitude, position.longitude);
          const zoomLevel = 18.0; // Default zoom for position-only centering
          _mapController.move(centerPoint, zoomLevel);
          logger.d(
            'Secondary map centered on boat position (no anchor): ${position.latitude}, ${position.longitude}',
          );
        }
      }
    });

    final anchorAsync = ref.watch(remoteAnchorProvider);
    final positionAsync = ref.watch(remotePositionProvider);
    final positionHistory = ref.watch(secondaryPositionHistoryProvider);
    final alarmsAsync = ref.watch(remoteAlarmProvider);
    final settings = ref.watch(settingsProvider);

    // Extract values from async results
    final anchor = anchorAsync.value;
    final position = positionAsync.value;
    final alarms = alarmsAsync.value ?? [];

    // Determine monitoring status
    final monitoringAsync = ref.watch(remoteMonitoringStatusProvider);
    final isMonitoring = monitoringAsync.value ?? false;

    final activeAlarms = alarms
        .where((a) => a.severity == Severity.alarm)
        .toList();
    final activeWarnings = alarms
        .where((a) => a.severity == Severity.warning)
        .toList();

    // Show loading state for first 2 seconds after role change to allow async operations to complete
    final timeSinceRoleChange = DateTime.now().difference(
      _roleChangeTime ?? DateTime.now(),
    );
    final forceLoading =
        _roleChangeTime != null &&
        timeSinceRoleChange < const Duration(seconds: 2);

    // Allow map to show if we have some data and loading period is over
    final hasData = anchor != null || position != null;
    final canShowMap = !forceLoading && hasData;

    if (!canShowMap) {
      return Scaffold(
        appBar: _buildAppBar(),
        body: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text('Loading data from primary device...'),
            ],
          ),
        ),
      );
    }

    // Handle warnings
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        for (final warning in activeWarnings) {
          if (!_shownWarningIds.contains(warning.id)) {
            _shownWarningIds.add(warning.id);
            _showWarningSnackBar(warning, settings);
          }
        }
        _shownWarningIds.removeWhere(
          (id) => !activeWarnings.any((w) => w.id == id),
        );
      }
    });

    // Calculate map center - always center on anchor if available
    LatLng centerPoint;
    if (anchor != null) {
      centerPoint = LatLng(anchor.latitude, anchor.longitude);
    } else if (position != null) {
      centerPoint = LatLng(position.latitude, position.longitude);
    } else {
      // Default center if no data available yet
      centerPoint = const LatLng(0, 0);
    }

    // Move map if center point changed and map is ready
    if (_lastCenterPoint != null &&
        _lastCenterPoint != centerPoint &&
        mounted &&
        _mapRendered) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted && _mapRendered) {
          double zoomLevel = 18.0;
          if (anchor != null) {
            zoomLevel = calculateZoomForRadius(anchor.radius);
          }
          _mapController.move(centerPoint, zoomLevel);
          logger.d(
            'Secondary map recentered to: ${centerPoint.latitude}, ${centerPoint.longitude}',
          );
        }
      });
    }
    _lastCenterPoint = centerPoint;

    return Scaffold(
      appBar: _buildAppBar(),
      body: _buildMapStack(
        anchor,
        position,
        positionHistory,
        activeAlarms,
        settings,
        isMonitoring,
        centerPoint,
      ),
    );
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      title: const Text('Anchor Alarm - Secondary'),
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

  Widget _buildMapStack(
    Anchor? anchor,
    PositionUpdate? position,
    List<PositionHistoryPoint> positionHistory,
    List<AlarmEvent> activeAlarms,
    AppSettings settings,
    bool isMonitoring,
    LatLng centerPoint,
  ) {
    // Calculate zoom level
    double zoomLevel = 18.0;
    if (anchor != null) {
      zoomLevel = calculateZoomForRadius(anchor.radius);
    }

    return Stack(
      children: [
        FlutterMap(
          key: _mapKey,
          mapController: _mapController,
          options: MapOptions(
            initialCenter: centerPoint,
            initialZoom: zoomLevel,
            maxZoom: 19.0,
            minZoom: 5.0,
            onMapReady: () {
              // Initial map setup
              _mapRendered = true;
              _mapController.move(centerPoint, zoomLevel);
            },
          ),
          children: [
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.sailorsparrot.anchoralarm',
            ),
            // Position history trail
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
            if (anchor != null)
              PolygonLayer(
                polygons: [
                  Polygon(
                    points: _getAnchorRadiusPolygonPoints(
                      LatLng(anchor.latitude, anchor.longitude),
                      anchor.radius,
                    ),
                    color: getAnchorCircleColor(
                      anchor,
                      position,
                      context,
                    ).withValues(alpha: 0.2),
                    borderColor: getAnchorCircleColor(
                      anchor,
                      position,
                      context,
                    ),
                    borderStrokeWidth: 2.0,
                  ),
                ],
              ),
            // Markers
            MarkerLayer(markers: _buildMarkers(anchor, position)),
          ],
        ),
        // Alarm banner - show for awareness but without dismiss button
        if (activeAlarms.isNotEmpty)
          Positioned(
            top: 10,
            left: 16,
            right: 16,
            child: _buildAlarmBanner(activeAlarms.first, settings),
          ),
        // Info card - positioned at top, account for alarm banner
        Positioned(
          top: activeAlarms.isNotEmpty ? 160 : 16,
          left: 16,
          right: 16,
          child: _buildInfoCard(anchor, position, settings, isMonitoring),
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
                Icon(Icons.warning, color: theme.colorScheme.onError, size: 24),
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
                TextButton.icon(
                  onPressed: () {
                    // Dismiss alarm locally on secondary device
                    ref
                        .read(localAlarmDismissalProvider.notifier)
                        .dismissLocally(alarm.id);
                    // Stop notification sounds/vibration
                    ref.read(notificationServiceProvider).stopAlarm();
                  },
                  icon: Icon(
                    Icons.close,
                    color: theme.colorScheme.onError,
                    size: 20,
                  ),
                  label: Text(
                    'DISMISS',
                    style: TextStyle(
                      color: theme.colorScheme.onError,
                      fontWeight: FontWeight.bold,
                      fontSize: 12,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    minimumSize: Size.zero,
                    tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            if (alarm.type == AlarmType.driftExceeded)
              Text(
                'Drifted ${formatDistance(alarm.distanceFromAnchor, settings.unitSystem)} from anchor',
                style: TextStyle(
                  color: theme.colorScheme.onError,
                  fontSize: 12,
                ),
              )
            else if (alarm.type == AlarmType.gpsLost)
              Text(
                'GPS signal lost',
                style: TextStyle(
                  color: theme.colorScheme.onError,
                  fontSize: 12,
                ),
              )
            else if (alarm.type == AlarmType.gpsInaccurate)
              Text(
                'GPS accuracy poor',
                style: TextStyle(
                  color: theme.colorScheme.onError,
                  fontSize: 12,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoCard(
    Anchor? anchor,
    PositionUpdate? position,
    AppSettings settings,
    bool isMonitoring,
  ) {
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

              // Expanded content
              if (_isInfoCardExpanded) ...[
                const SizedBox(height: 12),
                // Anchor info
                if (anchor != null) ...[
                  Text(
                    'Anchor Set',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                      'Distance from anchor: ${formatDistance(calculateDistance(anchor.latitude, anchor.longitude, position.latitude, position.longitude), settings.unitSystem)}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ] else if (position != null) ...[
                  Text(
                    'GPS Position Available',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
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
                    'Waiting for position data from primary device...',
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

  List<Marker> _buildMarkers(Anchor? anchor, PositionUpdate? position) {
    final markers = <Marker>[];

    // Current position marker
    if (position != null) {
      markers.add(
        Marker(
          point: LatLng(position.latitude, position.longitude),
          child: const Icon(Icons.my_location, color: Colors.blue, size: 30),
        ),
      );
    }

    // Anchor marker
    if (anchor != null) {
      markers.add(
        Marker(
          point: LatLng(anchor.latitude, anchor.longitude),
          child: const Icon(Icons.anchor, color: Colors.red, size: 30),
        ),
      );
    }

    return markers;
  }

  List<LatLng> _getAnchorRadiusPolygonPoints(
    LatLng center,
    double radiusMeters,
  ) {
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
      final lng =
          center.longitude +
          radiusDegrees *
              math.cos(angle) /
              math.cos(center.latitude * math.pi / 180);
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
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: Colors.orange,
        duration: const Duration(seconds: 4),
      ),
    );
  }
}
