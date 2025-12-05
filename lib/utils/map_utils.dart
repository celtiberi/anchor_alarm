import 'dart:math' as math;
import 'package:flutter/material.dart';
import '../models/anchor.dart';
import '../models/position_update.dart';
import 'distance_calculator.dart';

/// Utility functions for map-related operations shared between primary and secondary screens.

/// Gets the appropriate color for the anchor radius circle based on boat position.
/// Returns error color when boat is outside radius, primary color when inside,
/// and tertiary color when GPS position is unavailable.
Color getAnchorCircleColor(Anchor anchor, PositionUpdate? position, BuildContext context, {double? currentRadius}) {
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

  // Use current radius during dragging, otherwise use anchor radius
  final effectiveRadius = currentRadius ?? anchor.radius;

  // Error color when boat is outside radius, primary when inside
  return distance > effectiveRadius
      ? theme.colorScheme.error
      : theme.colorScheme.primary;
}

/// Calculates appropriate zoom level to show the full anchor radius circle.
/// Returns zoom level that ensures the radius is visible with some padding.
double calculateZoomForRadius(double radiusMeters) {
  // Approximate: at zoom 18, 1 pixel ≈ 0.6 meters
  // We want the radius to be about 1/3 of the visible area for good visibility
  // Formula: zoom = 18 - log2(radius / (screenWidth * 0.3 / 0.6))
  // Simplified: zoom = 18 - log2(radius / 50) for typical phone screen
  const double baseZoom = 18.0;
  const double baseRadius = 50.0; // 50m at zoom 18 fills about 1/3 of screen

  if (radiusMeters <= 0) return baseZoom;

  // Calculate zoom: larger radius needs lower zoom
  final zoom = baseZoom - math.log(radiusMeters / baseRadius) / math.ln2;
  return zoom.clamp(5.0, 22.0); // Clamp to reasonable zoom range (increased max for small radii)
}
