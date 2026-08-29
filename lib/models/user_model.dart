class LocationData {
  final double latitude;
  final double longitude;
  final String address;

  LocationData({
    required this.latitude,
    required this.longitude,
    required this.address,
  });

  factory LocationData.fromJson(Map<String, dynamic> json) {
    return LocationData(
      latitude: (json['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (json['longitude'] as num?)?.toDouble() ?? 0.0,
      address: json['address'] ?? '',
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'latitude': latitude,
      'longitude': longitude,
      'address': address,
    };
  }

  LocationData copyWith({
    double? latitude,
    double? longitude,
    String? address,
  }) {
    return LocationData(
      latitude: latitude ?? this.latitude,
      longitude: longitude ?? this.longitude,
      address: address ?? this.address,
    );
  }
}

class UserModel {
  final String userId;
  final String name;
  final String email;
  final String mobile;
  final String barangay;
  final String zipCode;
  final String role;
  final String status;
  final LocationData? currentLocation;
  final String familyId;
  final String photoUrl;
  final DateTime createdAt;
  final DateTime updatedAt;

  UserModel({
    required this.userId,
    required this.name,
    required this.email,
    this.mobile = '',
    this.barangay = '',
    this.zipCode = '',
    required this.role,
    this.status = 'Offline',
    this.currentLocation,
    required this.familyId,
    this.photoUrl = '',
    required this.createdAt,
    required this.updatedAt,
  });

  factory UserModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      final str = value.toString();
      final dt = DateTime.tryParse(str);
      return dt ?? DateTime.now();
    }

    LocationData? parseLocation(dynamic value) {
      if (value == null) return null;
      if (value is Map<String, dynamic>) return LocationData.fromJson(value);
      return null;
    }

    return UserModel(
      userId: json['userId'] ?? '',
      name: json['name'] ?? '',
      email: json['email'] ?? '',
      mobile: json['mobile'] ?? '',
      barangay: json['barangay'] ?? '',
      zipCode: json['zipCode'] ?? '',
      role: json['role'] ?? '',
      status: json['status'] ?? 'Offline',
      currentLocation: parseLocation(json['currentLocation']),
      familyId: json['familyId'] ?? '',
      photoUrl: json['photoUrl'] ?? '',
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'name': name,
      'email': email,
      'mobile': mobile,
      'barangay': barangay,
      'zipCode': zipCode,
      'role': role,
      'status': status,
      'currentLocation': currentLocation?.toJson(),
      'familyId': familyId,
      'photoUrl': photoUrl,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  UserModel copyWith({
    String? userId,
    String? name,
    String? email,
    String? mobile,
    String? barangay,
    String? zipCode,
    String? role,
    String? status,
    LocationData? currentLocation,
    String? familyId,
    String? photoUrl,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return UserModel(
      userId: userId ?? this.userId,
      name: name ?? this.name,
      email: email ?? this.email,
      mobile: mobile ?? this.mobile,
      barangay: barangay ?? this.barangay,
      zipCode: zipCode ?? this.zipCode,
      role: role ?? this.role,
      status: status ?? this.status,
      currentLocation: currentLocation ?? this.currentLocation,
      familyId: familyId ?? this.familyId,
      photoUrl: photoUrl ?? this.photoUrl,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }
}
