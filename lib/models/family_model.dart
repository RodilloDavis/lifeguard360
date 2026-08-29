import 'dart:math';

class FamilyModel {
  final String familyId;
  final String familyName;
  final String familyCode;
  final String createdBy;
  final List<String> members;
  final DateTime createdAt;
  final DateTime updatedAt;

  FamilyModel({
    required this.familyId,
    required this.familyName,
    required this.familyCode,
    required this.createdBy,
    required this.members,
    required this.createdAt,
    required this.updatedAt,
  });

  factory FamilyModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic value) {
      if (value == null) return DateTime.now();
      if (value is DateTime) return value;
      final str = value.toString();
      final dt = DateTime.tryParse(str);
      return dt ?? DateTime.now();
    }

    final membersList = (json['members'] as List<dynamic>?)
            ?.map((e) => e.toString())
            .toList() ??
        <String>[];

    return FamilyModel(
      familyId: json['familyId'] ?? '',
      familyName: json['familyName'] ?? '',
      familyCode: json['familyCode'] ?? '',
      createdBy: json['createdBy'] ?? '',
      members: membersList,
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'familyId': familyId,
      'familyName': familyName,
      'familyCode': familyCode,
      'createdBy': createdBy,
      'members': members,
      'createdAt': createdAt.toIso8601String(),
      'updatedAt': updatedAt.toIso8601String(),
    };
  }

  FamilyModel copyWith({
    String? familyId,
    String? familyName,
    String? familyCode,
    String? createdBy,
    List<String>? members,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) {
    return FamilyModel(
      familyId: familyId ?? this.familyId,
      familyName: familyName ?? this.familyName,
      familyCode: familyCode ?? this.familyCode,
      createdBy: createdBy ?? this.createdBy,
      members: members ?? List<String>.from(this.members),
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  static String generateFamilyCode() {
    final random = Random();
    return (100000 + random.nextInt(900000)).toString();
  }
}
