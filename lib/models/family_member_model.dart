class FamilyMemberModel {
  final String userId;
  final String familyId;
  final String role;
  final Permissions permissions;
  final DateTime joinedAt;

  FamilyMemberModel({
    required this.userId,
    required this.familyId,
    required this.role,
    required this.permissions,
    required this.joinedAt,
  });

  factory FamilyMemberModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      final str = value.toString();
      final dt = DateTime.tryParse(str);
      return dt ?? DateTime.now();
    }

    return FamilyMemberModel(
      userId: json['userId'] ?? '',
      familyId: json['familyId'] ?? '',
      role: json['role'] ?? '',
      permissions: Permissions.fromJson(json['permissions'] ?? {}),
      joinedAt: parseDate(json['joinedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'userId': userId,
      'familyId': familyId,
      'role': role,
      'permissions': permissions.toJson(),
      'joinedAt': joinedAt.toIso8601String(),
    };
  }

  FamilyMemberModel copyWith({
    String? userId,
    String? familyId,
    String? role,
    Permissions? permissions,
    DateTime? joinedAt,
  }) {
    return FamilyMemberModel(
      userId: userId ?? this.userId,
      familyId: familyId ?? this.familyId,
      role: role ?? this.role,
      permissions: permissions ?? this.permissions,
      joinedAt: joinedAt ?? this.joinedAt,
    );
  }
}

class Permissions {
  final bool viewLocation;
  final bool sendSOS;
  final bool receiveAlerts;
  final bool manageMembers;

  Permissions({
    required this.viewLocation,
    required this.sendSOS,
    required this.receiveAlerts,
    required this.manageMembers,
  });

  factory Permissions.fromJson(Map<String, dynamic> json) {
    return Permissions(
      viewLocation: json['viewLocation'] ?? true,
      sendSOS: json['sendSOS'] ?? true,
      receiveAlerts: json['receiveAlerts'] ?? true,
      manageMembers: json['manageMembers'] ?? false,
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'viewLocation': viewLocation,
      'sendSOS': sendSOS,
      'receiveAlerts': receiveAlerts,
      'manageMembers': manageMembers,
    };
  }

  factory Permissions.forRole(String role) {
    final isParent = role == 'Father' || role == 'Mother' || role == 'Guardian';
    return Permissions(
      viewLocation: true,
      sendSOS: true,
      receiveAlerts: true,
      manageMembers: isParent,
    );
  }

  Permissions copyWith({
    bool? viewLocation,
    bool? sendSOS,
    bool? receiveAlerts,
    bool? manageMembers,
  }) {
    return Permissions(
      viewLocation: viewLocation ?? this.viewLocation,
      sendSOS: sendSOS ?? this.sendSOS,
      receiveAlerts: receiveAlerts ?? this.receiveAlerts,
      manageMembers: manageMembers ?? this.manageMembers,
    );
  }
}
