import 'dart:async';
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
import '../../providers/pairing_session_provider.dart';
import '../../providers/remote_anchor_provider.dart';
import '../../providers/remote_position_provider.dart';
import '../../providers/remote_position_history_provider.dart';
import '../../providers/remote_alarm_provider.dart';
import '../../providers/remote_monitoring_status_provider.dart';
import '../../models/anchor.dart';
import '../../models/position_update.dart';
import '../../models/alarm_event.dart';
import '../../models/app_settings.dart';
import '../../utils/distance_calculator.dart';
import '../../utils/distance_formatter.dart';
import '../../utils/logger_setup.dart';
import '../../providers/alarm_provider.dart';
import '../../models/position_history_point.dart';
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
  LatLng? _displayAnchorPosition;
  List<LatLng>? _cachedPolygonPoints;
  LatLng? _cachedPolygonCenter;
  double? _cachedPolygonRadius;
  Anchor? _previousAnchor;
  final Set<String> _shownWarningIds = {}; // Track which warnings have been shown
  bool _positionMonitoringStarted = false;
  bool _isInfoCardExpanded = true; // Track if info card is expanded
  bool _isDraggingRadius = false; // Track if radius slider is being dragged
  double _sliderRadiusValue = 0.0; // Local state for slider value during dragging
  
  @override
  void initState() {
    super.initState();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();

    // Only start GPS monitoring for primary devices (secondary devices get position from primary via Firebase)
    final monitoringState = ref.read(pairingSessionStateProvider);
    if (!_positionMonitoringStarted && !monitoringState.isSecondary) {
      try {
        ref.read(positionProvider.notifier).startMonitoring();
        _positionMonitoringStarted = true;
        logger.i('Started position monitoring for primary device');
      } catch (e, stackTrace) {
        logger.e('Failed to start position monitoring', error: e, stackTrace: stackTrace);
      }
    }
  }

  @override
  void dispose() {
    ref.read(positionProvider.notifier).stopMonitoring();
    _mapController.dispose();
    super.dispose();
  }

  Widget _buildAlarmBanner(AlarmEvent alarm, AppSettings settings) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.error,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          Icon(Icons.warning, color: theme.colorScheme.onError, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'ANCHOR ALARM: ${alarm.type.name.toUpperCase()}',
                  style: TextStyle(
                    color: theme.colorScheme.onError,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
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
              ],
            ),
          ),
          ElevatedButton(
            onPressed: () {
              // Manual dismiss - stop monitoring
              ref.read(activeAlarmsProvider.notifier).acknowledgeAlarm(alarm.id);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: theme.colorScheme.onError,
              foregroundColor: theme.colorScheme.error,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: Text(
              'DISMISS',
              style: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontWeight: FontWeight.bold,
                color: theme.colorScheme.error, // Explicit high-contrast color
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoCard(Anchor? anchor, PositionUpdate? position, AppSettings settings, bool isMonitoring, PairingSessionState monitoringState) {
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
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Radius: ${formatDistance(anchor.radius, settings.unitSystem)}',
                    style: TextStyle(fontSize: 14),
                  ),
                  if (position != null) ...[
                    const SizedBox(height: 4),
                    Builder(
                      builder: (context) {
                        final distance = calculateDistance(
                          anchor.latitude,
                          anchor.longitude,
                          position.latitude,
                          position.longitude,
                        );
                        final isWithinRadius = distance <= anchor.radius;
                        return Text(
                          'Distance: ${formatDistance(distance, settings.unitSystem)} ${isWithinRadius ? "(within radius)" : "(OUTSIDE RADIUS)"}',
                          style: TextStyle(
                            fontSize: 14,
                            color: isWithinRadius ? null : Colors.red,
                            fontWeight: isWithinRadius ? null : FontWeight.bold,
                          ),
                        );
                      },
                    ),
                  ],
                ] else ...[
                  Text(
                    'No Anchor Set',
                    style: TextStyle(
                      fontSize: 16,
                      color: Colors.grey,
                    ),
                  ),
                ],
                // Position info
                if (position != null) ...[
                  const SizedBox(height: 12),
                  Text(
                    'Current Position',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Speed: ${position.speed != null ? formatSpeed(position.speed!, settings.unitSystem) : "N/A"}',
                    style: TextStyle(fontSize: 14),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Accuracy: ${position.accuracy != null ? formatAccuracy(position.accuracy!, settings.unitSystem) : "N/A"}',
                    style: TextStyle(fontSize: 14),
                  ),
                ],
                // Raise anchor button - only shown when anchor is set and on primary device
                if (anchor != null && !monitoringState.isSecondary) ...[
                  const SizedBox(height: 16),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton.icon(
                      onPressed: () async {
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
            child:             ElevatedButton.icon(
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
                onPressed: () => ref.read(activeAlarmsProvider.notifier).startMonitoring(),
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
                    'Anchor Radius: ${formatDistance(anchor.radius, ref.watch(settingsProvider).unitSystem)}',
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
                      } finally {
                        _isDraggingRadius = false;
                      }
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

  Color _getAnchorCircleColor(Anchor anchor, PositionUpdate? position, BuildContext context, {double? currentRadius}) {
    final theme = Theme.of(context);

    if (position == null) {
      // Use warning color if GPS is lost
      return theme.colorScheme.tertiary;
    }

    final distance = calculateDistance(
      anchor.latitude,
      anchor.longitude,
      position.latitude,
      position.longitude,
    );

    // Error color when boat is outside radius, primary when inside
    final effectiveRadius = currentRadius ?? anchor.radius;
    return distance > effectiveRadius
        ? theme.colorScheme.error
        : theme.colorScheme.primary;
  }

  Future<PositionUpdate> _getCurrentPositionWithTimeout() async {
    return await ref.read(positionProvider.notifier)
        .getCurrentPosition()
        .timeout(
          const Duration(seconds: 10),
          onTimeout: () {
            throw TimeoutException('GPS position request timed out. Please check GPS signal.');
          },
        );
  }

  Future<void> _createAnchorFromPosition(PositionUpdate position, AppSettings settings) async {
    await ref.read(anchorProvider.notifier).setAnchor(
          latitude: position.latitude,
          longitude: position.longitude,
          radius: settings.defaultRadius,
        );
  }

  Future<void> _adjustMapForNewAnchor() async {
    final anchor = ref.read(anchorProvider);
    if (anchor != null) {
      final zoomLevel = _calculateZoomForRadius(anchor.radius);
      final center = LatLng(anchor.latitude, anchor.longitude);

      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _mapController.move(center, zoomLevel);
        }
      });
    }
  }

  void _handleAnchorSet(PositionUpdate position, AppSettings settings) {
    logger.i('Anchor set at ${position.latitude}, ${position.longitude} with zoom ${_calculateZoomForRadius(settings.defaultRadius)}');
    // Note: Monitoring is now started explicitly by user via button
  }

  void _handleTimeoutError(TimeoutException e) {
    logger.e('Timeout getting GPS position: $e');
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('$e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  void _handleAnchorSetupError(Object e, [StackTrace? stackTrace]) {
    logger.e('Failed to set anchor', error: e, stackTrace: stackTrace);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Failed to set anchor: $e'),
          backgroundColor: Theme.of(context).colorScheme.error,
          duration: const Duration(seconds: 5),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final monitoringState = ref.watch(pairingSessionStateProvider);

    // Use remote providers for secondary devices, local providers for primary/none
    final anchorAsync = monitoringState.isSecondary
        ? ref.watch(remoteAnchorProvider)
        : AsyncValue.data(ref.watch(anchorProvider));
    final positionAsync = monitoringState.isSecondary
        ? ref.watch(remotePositionProvider)
        : AsyncValue.data(ref.watch(positionProvider));
    final positionHistoryAsync = monitoringState.isSecondary
        ? ref.watch(remotePositionHistoryProvider)
        : AsyncValue.data(ref.watch(positionHistoryProvider));
    final alarmsAsync = monitoringState.isSecondary
        ? ref.watch(remoteAlarmProvider)
        : AsyncValue.data(ref.watch(activeAlarmsProvider));

    final settings = ref.watch(settingsProvider);

    // Extract values from async results
    final anchor = anchorAsync.value;
    final position = positionAsync.value;
    final positionHistory = positionHistoryAsync.value ?? [];
    final alarms = alarmsAsync.value ?? [];

    // Determine monitoring status based on device role
    final bool isMonitoring;
    final pairingState = ref.watch(pairingSessionStateProvider);
    if (pairingState.isSecondary) {
      // For secondary devices, use remote monitoring status
      final remoteMonitoringAsync = ref.watch(remoteMonitoringStatusProvider);
      isMonitoring = remoteMonitoringAsync.value ?? false;
    } else {
      // For primary devices, use local monitoring status
      isMonitoring = ref.read(activeAlarmsProvider.notifier).isMonitoring;
    }
    final activeAlarms = alarms.where((a) => a.severity == Severity.alarm).toList();
    final activeWarnings = alarms.where((a) => a.severity == Severity.warning).toList();

    // Listen for monitoring state changes to handle GPS monitoring
    ref.listen<PairingSessionState>(pairingSessionStateProvider, (previous, next) {
      // If device just became secondary, stop GPS monitoring
      if (previous?.isSecondary != true && next.isSecondary) {
        logger.i('Device became secondary - stopping local GPS monitoring');
        ref.read(positionProvider.notifier).stopMonitoring();
        _positionMonitoringStarted = false;
      }
      // If device just became primary, start GPS monitoring
      else if (previous?.isPrimary != true && next.isPrimary && !_positionMonitoringStarted) {
        logger.i('Device became primary - starting GPS monitoring');
        try {
          ref.read(positionProvider.notifier).startMonitoring();
          _positionMonitoringStarted = true;
        } catch (e) {
          logger.e('Failed to start GPS monitoring when becoming primary', error: e);
        }
      }
    });

    // Auto-start monitoring when anchor is set (only for primary devices)
    if (!monitoringState.isSecondary) {
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
        _shownWarningIds.removeWhere((id) => !activeWarnings.any((w) => w.id == id));
      }
    });

    // Update anchor display position
    LatLng? displayAnchorPosition = _displayAnchorPosition;
    if (!_isDraggingAnchor) {
      if (anchor != null) {
        final newPosition = LatLng(anchor.latitude, anchor.longitude);
        final currentPosition = displayAnchorPosition;
        final isNewAnchor = _previousAnchor == null;
        final radiusChanged = _previousAnchor?.radius != anchor.radius;

        if (currentPosition == null ||
            currentPosition.latitude != newPosition.latitude ||
            currentPosition.longitude != newPosition.longitude ||
            radiusChanged) {
          displayAnchorPosition = newPosition;
          _displayAnchorPosition = newPosition;
          _cachedPolygonPoints = null;

          if (isNewAnchor || (radiusChanged && (anchor.radius - (_previousAnchor?.radius ?? anchor.radius)).abs() > 10)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                final zoomLevel = _calculateZoomForRadius(anchor.radius);
                _mapController.move(newPosition, zoomLevel);
              }
            });
          }
        }
      } else if (displayAnchorPosition != null) {
        displayAnchorPosition = null;
        _displayAnchorPosition = null;
        _cachedPolygonPoints = null;
      }
    }
    _previousAnchor = anchor;

    // Update local slider value when anchor changes
    if (anchor != null && !_isDraggingRadius) {
      _sliderRadiusValue = anchor.radius;
    }

    // Calculate map center
    LatLng? centerPoint;
    if (position != null) {
      centerPoint = LatLng(position.latitude, position.longitude);
    } else if (anchor != null) {
      centerPoint = LatLng(anchor.latitude, anchor.longitude);
    }

    // For secondary devices, use a default center if no data is available yet
    // For primary devices, wait for GPS signal
    final shouldShowLoading = centerPoint == null && !pairingState.isSecondary;

    return Scaffold(
      appBar: _buildAppBar(),
      body: shouldShowLoading
          ? _buildLoadingState()
          : _buildMapStack(anchor, position, positionHistory, displayAnchorPosition, activeAlarms, settings, isMonitoring, centerPoint ?? const LatLng(0, 0), currentRadius: _isDraggingRadius ? _sliderRadiusValue : null),
    );
  }

  /// Calculates appropriate zoom level to show the full anchor radius circle.
  /// Returns zoom level that ensures the radius is visible with some padding.
  double _calculateZoomForRadius(double radiusMeters) {
    // Approximate: at zoom 18, 1 pixel ≈ 0.6 meters
    // We want the radius to be about 1/3 of the visible area for good visibility
    // Formula: zoom = 18 - log2(radius / (screenWidth * 0.3 / 0.6))
    // Simplified: zoom = 18 - log2(radius / 50) for typical phone screen
    const double baseZoom = 18.0;
    const double baseRadius = 50.0; // 50m at zoom 18 fills about 1/3 of screen

    if (radiusMeters <= 0) return baseZoom;

    // Calculate zoom: larger radius needs lower zoom
    final zoom = baseZoom - math.log(radiusMeters / baseRadius) / math.ln2;

    // Clamp to valid zoom range
    return zoom.clamp(5.0, 19.0);
  }

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
            Icon(Icons.info_outline, color: theme.colorScheme.onSurface),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: theme.colorScheme.surfaceContainerHighest,
        duration: const Duration(seconds: 4),
        action: SnackBarAction(
          label: 'Dismiss',
          textColor: theme.colorScheme.primary,
          onPressed: () {
            // Remove from shown warning IDs immediately to prevent re-showing
            _shownWarningIds.remove(warning.id);
            ref.read(activeAlarmsProvider.notifier).acknowledgeAlarm(warning.id);
          },
        ),
      ),
    );
  }

  @override
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
  }

  /// Gets a cached circle polygon from a center point and radius in meters.
  /// The polygon will scale correctly with map zoom since it's defined in geographic coordinates.
  /// 
  /// [center] must not be null. This method assumes non-null input but includes defensive checks.
  List<LatLng> _getCachedCirclePolygon(LatLng center, double radiusMeters) {
    // Defensive null check (should never happen, but prevents crashes)
    if (center.latitude.isNaN || center.longitude.isNaN || radiusMeters.isNaN || radiusMeters <= 0) {
      logger.w('Invalid parameters to _getCachedCirclePolygon: center=$center, radius=$radiusMeters');
      return [];
    }
    
    // Return cached polygon if center and radius haven't changed
    final cachedCenter = _cachedPolygonCenter;
    final cachedRadius = _cachedPolygonRadius;
    final cachedPoints = _cachedPolygonPoints;
    
    if (cachedPoints != null &&
        cachedCenter != null &&
        cachedRadius != null &&
        (cachedCenter.latitude - center.latitude).abs() < 0.000001 &&
        (cachedCenter.longitude - center.longitude).abs() < 0.000001 &&
        (cachedRadius - radiusMeters).abs() < 0.01) {
      return cachedPoints;
    }
    
    // Generate new polygon
    final newPolygon = _createCirclePolygon(center, radiusMeters);
    _cachedPolygonPoints = newPolygon;
    _cachedPolygonCenter = center;
    _cachedPolygonRadius = radiusMeters;
    
    return newPolygon;
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

  /// Builds the app bar with navigation actions.

  // Removed automatic anchor listener - monitoring is now explicit

  void _handleWarnings(List<AlarmEvent> activeWarnings, AppSettings settings) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        for (final warning in activeWarnings) {
          if (!_shownWarningIds.contains(warning.id)) {
            _shownWarningIds.add(warning.id);
            (() {
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
                      Icon(Icons.info_outline, color: theme.colorScheme.onSurface),
                      const SizedBox(width: 12),
                      Expanded(child: Text(message)),
                    ],
                  ),
                  backgroundColor: theme.colorScheme.surfaceContainerHighest,
                  duration: const Duration(seconds: 4),
                  action: SnackBarAction(
                    label: 'Dismiss',
                    textColor: theme.colorScheme.primary,
                    onPressed: () {
                      // Remove from shown warning IDs immediately to prevent re-showing
                      _shownWarningIds.remove(warning.id);
                      ref.read(activeAlarmsProvider.notifier).acknowledgeAlarm(warning.id);
                    },
                  ),
                ),
              );
            })();
          }
        }
        _shownWarningIds.removeWhere((id) => !activeWarnings.any((w) => w.id == id));
      }
    });
  }

  LatLng? _updateAnchorDisplay(Anchor? anchor) {
    LatLng? displayAnchorPosition = _displayAnchorPosition;

    if (!_isDraggingAnchor) {
      if (anchor != null) {
        final newPosition = LatLng(anchor.latitude, anchor.longitude);
        final currentPosition = displayAnchorPosition;
        final isNewAnchor = _previousAnchor == null;
        final radiusChanged = _previousAnchor?.radius != anchor.radius;

        if (currentPosition == null ||
            currentPosition.latitude != newPosition.latitude ||
            currentPosition.longitude != newPosition.longitude ||
            radiusChanged) {
          displayAnchorPosition = newPosition;
          _displayAnchorPosition = newPosition;
          _cachedPolygonPoints = null;

          if (isNewAnchor || (radiusChanged && (anchor.radius - (_previousAnchor?.radius ?? anchor.radius)).abs() > 10)) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) {
                final zoomLevel = (() {
                  // Approximate: at zoom 18, 1 pixel ≈ 0.6 meters
                  // We want the radius to be about 1/3 of the visible area for good visibility
                  // Formula: zoom = 18 - log2(radius / (screenWidth * 0.3 / 0.6))
                  // Simplified: zoom = 18 - log2(radius / 50) for typical phone screen
                  const double baseZoom = 18.0;
                  const double baseRadius = 50.0; // 50m at zoom 18 fills about 1/3 of screen

                  final radiusMeters = anchor.radius;
                  if (radiusMeters <= 0) return baseZoom;

                  // Calculate zoom: larger radius needs lower zoom
                  final zoom = baseZoom - math.log(radiusMeters / baseRadius) / math.ln2;

                  // Clamp to valid zoom range
                  return zoom.clamp(5.0, 19.0);
                })();
                _mapController.move(newPosition, zoomLevel);
              }
            });
          }
        }
      } else if (displayAnchorPosition != null) {
        displayAnchorPosition = null;
        _displayAnchorPosition = null;
        _cachedPolygonPoints = null;
      }
    }

    _previousAnchor = anchor;
    return displayAnchorPosition;
  }

  LatLng? _calculateCenterPoint(PositionUpdate? position, Anchor? anchor) {
    if (position != null) {
      return LatLng(position.latitude, position.longitude);
    } else if (anchor != null) {
      return LatLng(anchor.latitude, anchor.longitude);
    }
    return null;
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
          child: Icon(
            Icons.location_on,
            color: Theme.of(context).colorScheme.error,
            size: 30,
          ),
        ),
      );
    }

    // Note: Anchor marker is handled by DragMarkers layer, not MarkerLayer
    return markers;
  }

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
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
          tooltip: 'Settings',
        ),
      ],
    );
  }

  /// Builds the loading state when GPS is not available.
  Widget _buildLoadingState() {
    final monitoringState = ref.watch(pairingSessionStateProvider);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          const CircularProgressIndicator(),
          const SizedBox(height: 16),
          Text(
            monitoringState.isSecondary
                ? 'Waiting for position data from primary device...'
                : 'Waiting for GPS signal...',
          ),
        ],
      ),
    );
  }

  /// Builds the main map stack with all overlays.
  Widget _buildMapStack(
    Anchor? anchor,
    PositionUpdate? position,
    List<PositionHistoryPoint> positionHistory,
    LatLng? displayAnchorPosition,
    List<AlarmEvent> activeAlarms,
    AppSettings settings,
    bool isMonitoring,
    LatLng centerPoint, {
    double? currentRadius,
  }) {
    final monitoringState = ref.watch(pairingSessionStateProvider);
    return Stack(
      children: [
        _buildMap(anchor, position, positionHistory, displayAnchorPosition, centerPoint, currentRadius: currentRadius),
        ..._buildMapOverlays(anchor, position, activeAlarms, settings, isMonitoring, monitoringState),
      ],
    );
  }

  /// Builds the FlutterMap widget with all map layers.
  Widget _buildMap(
    Anchor? anchor,
    PositionUpdate? position,
    List<PositionHistoryPoint> positionHistory,
    LatLng? displayAnchorPosition,
    LatLng centerPoint, {
    double? currentRadius,
  }) {
    return FlutterMap(
      key: _mapKey,
      mapController: _mapController,
      options: MapOptions(
        initialCenter: centerPoint,
        initialZoom: 18.0,
        minZoom: 5.0,
        maxZoom: 20.0,
        backgroundColor: Colors.white,
        interactionOptions: InteractionOptions(
          flags: _isDraggingAnchor
              ? InteractiveFlag.none
              : InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: _buildMapLayers(anchor, position, positionHistory, displayAnchorPosition, currentRadius: currentRadius),
    );
  }

  /// Builds all map layers as a list of widgets.
  List<Widget> _buildMapLayers(
    Anchor? anchor,
    PositionUpdate? position,
    List<PositionHistoryPoint> positionHistory,
    LatLng? displayAnchorPosition, {
    double? currentRadius,
  }) {
    return [
      // Base map layer
      TileLayer(
        urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.anchor_alarm',
        maxZoom: 19,
        errorTileCallback: (tile, error, stackTrace) {
          logger.w('Failed to load OpenStreetMap tile: $error');
        },
      ),

      // Nautical overlay
      TileLayer(
        urlTemplate: 'https://tiles.openseamap.org/seamark/{z}/{x}/{y}.png',
        userAgentPackageName: 'com.example.anchor_alarm',
        maxZoom: 18,
        errorTileCallback: (tile, error, stackTrace) {
          logger.w('Failed to load OpenSeaMap tile: $error');
        },
      ),

      // Position history trail
      if (positionHistory.length > 1)
        PolylineLayer(
          polylines: [
            Polyline(
              points: positionHistory.map((point) => point.position).toList(),
              strokeWidth: 2.0,
              color: Theme.of(context).colorScheme.primary,
            ),
          ],
        ),

      // Markers
      MarkerLayer(markers: _buildMarkers(anchor, position)),

      // Anchor radius circle
      if (anchor != null && anchor.isActive && displayAnchorPosition != null)
        PolygonLayer(
          polygons: [
            Polygon(
              points: _getCachedCirclePolygon(displayAnchorPosition, currentRadius ?? anchor!.radius),
              color: _getAnchorCircleColor(anchor, position, context, currentRadius: currentRadius).withValues(alpha: 0.2),
              borderColor: _getAnchorCircleColor(anchor, position, context, currentRadius: currentRadius),
              borderStrokeWidth: 2.0,
            ),
          ],
        ),

      // Draggable anchor marker
      if (anchor != null && displayAnchorPosition != null)
        DragMarkers(
          markers: [
            DragMarker(
              point: displayAnchorPosition,
              size: const Size(40, 40),
              offset: const Offset(0.0, -20.0),
              builder: (ctx, point, isDragging) => Container(
                decoration: BoxDecoration(
                  color: isDragging
                      ? Theme.of(context).colorScheme.primaryContainer.withValues(alpha: 0.8)
                      : Theme.of(context).colorScheme.surface.withValues(alpha: 0.9),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.primary,
                    width: 2,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Theme.of(context).colorScheme.shadow.withValues(alpha: 0.3),
                      blurRadius: 4,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: Icon(
                  Icons.anchor,
                  color: Theme.of(context).colorScheme.primary,
                  size: 24,
                ),
              ),
              onDragStart: (details, point) {
                setState(() => _isDraggingAnchor = true);
                ref.read(activeAlarmsProvider.notifier).pauseMonitoring();
                logger.d('Started dragging anchor');
              },
              onDragUpdate: (details, point) {
                setState(() => _displayAnchorPosition = point);
              },
              onDragEnd: (details, point) async {
                try {
                  setState(() {
                    _isDraggingAnchor = false;
                    _displayAnchorPosition = point;
                    _cachedPolygonPoints = null;
                  });
                  ref.read(anchorProvider.notifier).updateAnchorPosition(
                        latitude: point.latitude,
                        longitude: point.longitude,
                      );
                  ref.read(activeAlarmsProvider.notifier).resumeMonitoring();
                } catch (e, stackTrace) {
                  logger.e('Error in onDragEnd', error: e, stackTrace: stackTrace);
                  setState(() {
                    _isDraggingAnchor = false;
                    final anchor = ref.read(anchorProvider);
                    if (anchor != null) {
                      _displayAnchorPosition = LatLng(anchor.latitude, anchor.longitude);
                    }
                    _cachedPolygonPoints = null;
                  });
                  ref.read(activeAlarmsProvider.notifier).resumeMonitoring();
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text('Failed to update anchor position: $e'),
                        backgroundColor: Theme.of(context).colorScheme.error,
                      ),
                    );
                  }
                }
              },
            ),
          ],
        ),
    ];
  }

  /// Builds all map overlays (banners, info cards, controls, attribution).
  List<Widget> _buildMapOverlays(
    Anchor? anchor,
    PositionUpdate? position,
    List<AlarmEvent> activeAlarms,
    AppSettings settings,
    bool isMonitoring,
    PairingSessionState monitoringState,
  ) {
    return [
      // Alarm banner
      if (activeAlarms.isNotEmpty)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _buildAlarmBanner(activeAlarms.first, settings),
        ),

      // Info overlay
      Positioned(
        top: activeAlarms.isNotEmpty ? 80 : 16,
        left: 16,
        right: 16,
        child: _buildInfoCard(anchor, position, settings, isMonitoring, monitoringState),
      ),

      // Anchor controls (only for primary devices)
      if (!monitoringState.isSecondary) ...[
        Positioned(
          bottom: 80,
          left: 16,
          right: 16,
          child: _buildAnchorControls(anchor, isMonitoring),
        ),
      ],

      // Attribution
      Positioned(
        bottom: 0,
        left: 0,
        right: 0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.8),
          child: Text(
            'Nautical data © OpenSeaMap contributors | Map © OpenStreetMap',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              fontSize: 10 * MediaQuery.textScalerOf(context).scale(1.0),
            ),
            textAlign: TextAlign.center,
          ),
        ),
      ),
    ];
  }
}

