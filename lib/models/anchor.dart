/// Represents the anchor point that the boat should stay within.
class Anchor {
  final String id;
  final double latitude;
  final double longitude;
  final double radius;
  final DateTime createdAt;
  final DateTime? updatedAt;
  final bool isActive;

  Anchor({
    required this.id,
    required this.latitude,
    required this.longitude,
    required this.radius,
    required this.createdAt,
    this.updatedAt,
    this.isActive = true,
  }) : assert(
          latitude >= -90 && latitude <= 90,
          'Latitude must be between -90 and 90, got $latitude',
        ),
        assert(
          longitude >= -180 && longitude <= 180,
          'Longitude must be between -180 and 180, got $longitude',
        ),
        assert(
          radius >= 20 && radius <= 100,
          'Radius must be between 20 and 100 meters, got $radius',
        ),
        assert(id.isNotEmpty, 'Anchor ID cannot be empty');

  /// Creates a copy of this anchor with updated fields.
  Anchor copyWith({
    String? id,
    double? latitude,
    double? longitude,
    double? radius,
    DateTime? createdAt,
    DateTime? updatedAt,
    bool? isActive,
  }) {
    return Anchor(
      id: id ?? this.id,
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      radius: radius ?? this.radius,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Anchor &&
        other.id == id &&
        other.latitude == latitude &&
        other.longitude == longitude &&
        other.radius == radius &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.isActive == isActive;
  }

  @override
  int get hashCode {
    return Object.hash(
      id,
      latitude,
      longitude,
      radius,
      createdAt,
      updatedAt,
      isActive,
    );
  }

  /// Creates Anchor from JSON map.
  factory Anchor.fromJson(Map<String, dynamic> json) {
    return Anchor(
      id: json['id'] as String,
      latitude: json['latitude'] as double,
      longitude: json['longitude'] as double,
      radius: json['radius'] as double,
      createdAt: DateTime.parse(json['createdAt'] as String),
      updatedAt: json['updatedAt'] != null
          ? DateTime.parse(json['updatedAt'] as String)
          : null,
      isActive: json['isActive'] as bool? ?? true,
    );
  }

  /// Converts Anchor to JSON map.
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'latitude': latitude,
      'longitude': longitude,
      'radius': radius,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt?.toIso8601String(),
      'isActive': isActive,
    };
  }

  @override
  String toString() {
    return 'Anchor(id: $id, lat: $latitude, lon: $longitude, radius: $radius, active: $isActive)';
  }
}

