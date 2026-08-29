import 'dart:math';
import '../models/user_model.dart';
import '../models/family_model.dart';
import '../models/family_member_model.dart';

class FamilyService {
  static final FamilyService _instance = FamilyService._internal();
  factory FamilyService() => _instance;
  FamilyService._internal();

  final Map<String, FamilyModel> _families = {};
  final Map<String, UserModel> _users = {};
  final Map<String, FamilyMemberModel> _familyMembers = {};

  Future<Map<String, dynamic>> createFamilyWithUser({
    required String userId,
    required String userName,
    required String userEmail,
    required String familyName,
    required String role,
    String mobile = '',
    String barangay = '',
    String zipCode = '',
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    final familyId = _generateId();
    final familyCode = FamilyModel.generateFamilyCode();
    final now = DateTime.now();

    final family = FamilyModel(
      familyId: familyId,
      familyName: familyName,
      familyCode: familyCode,
      createdBy: userId,
      members: [userId],
      createdAt: now,
      updatedAt: now,
    );

    _families[familyId] = family;

    final user = UserModel(
      userId: userId,
      name: userName,
      email: userEmail,
      mobile: mobile,
      barangay: barangay,
      zipCode: zipCode,
      role: role,
      status: 'Online',
      currentLocation: LocationData(
        latitude: 7.1907,
        longitude: 125.4553,
        address: barangay.isNotEmpty ? barangay : 'Barangay New Visayas',
      ),
      familyId: familyId,
      createdAt: now,
      updatedAt: now,
    );

    _users[userId] = user;

    final familyMember = FamilyMemberModel(
      userId: userId,
      familyId: familyId,
      role: role,
      permissions: Permissions.forRole(role),
      joinedAt: now,
    );

    _familyMembers[userId] = familyMember;

    return {
      'familyId': familyId,
      'familyCode': familyCode,
      'userId': userId,
    };
  }

  Future<UserModel> joinExistingFamily({
    required String userId,
    required String userName,
    required String userEmail,
    required String role,
    required String familyCode,
    String mobile = '',
    String barangay = '',
    String zipCode = '',
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    final family = await verifyFamilyCode(familyCode);
    if (family == null) {
      throw Exception('Invalid family code');
    }

    final now = DateTime.now();

    final user = UserModel(
      userId: userId,
      name: userName,
      email: userEmail,
      mobile: mobile,
      barangay: barangay,
      zipCode: zipCode,
      role: role,
      status: 'Online',
      currentLocation: LocationData(
        latitude: 7.1907,
        longitude: 125.4553,
        address: barangay.isNotEmpty ? barangay : 'Barangay New Visayas',
      ),
      familyId: family.familyId,
      createdAt: now,
      updatedAt: now,
    );

    _users[userId] = user;

    final familyMember = FamilyMemberModel(
      userId: userId,
      familyId: family.familyId,
      role: role,
      permissions: Permissions.forRole(role),
      joinedAt: now,
    );

    _familyMembers[userId] = familyMember;

    final updatedMembers = List<String>.from(family.members)..add(userId);
    _families[family.familyId] = family.copyWith(
      members: updatedMembers,
      updatedAt: now,
    );

    return user;
  }

  Future<FamilyModel?> verifyFamilyCode(String familyCode) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    try {
      final family = _families.values.firstWhere(
        (family) => family.familyCode == familyCode,
      );
      return family;
    } catch (e) {
      return null;
    }
  }

  Future<UserModel> addUserToFamily({
    required String name,
    required String email,
    required String role,
    required String familyCode,
    String mobile = '',
    String barangay = '',
    String zipCode = '',
  }) async {
    await Future.delayed(const Duration(milliseconds: 800));

    final family = await verifyFamilyCode(familyCode);
    if (family == null) {
      throw Exception('Invalid family code');
    }

    final userId = _generateId();
    final now = DateTime.now();

    final user = UserModel(
      userId: userId,
      name: name,
      email: email,
      mobile: mobile,
      barangay: barangay,
      zipCode: zipCode,
      role: role,
      status: 'Offline',
      currentLocation: null,
      familyId: family.familyId,
      createdAt: now,
      updatedAt: now,
    );

    _users[userId] = user;

    final familyMember = FamilyMemberModel(
      userId: userId,
      familyId: family.familyId,
      role: role,
      permissions: Permissions.forRole(role),
      joinedAt: now,
    );

    _familyMembers[userId] = familyMember;

    final updatedMembers = List<String>.from(family.members)..add(userId);
    _families[family.familyId] = family.copyWith(
      members: updatedMembers,
      updatedAt: now,
    );

    return user;
  }

  Future<List<UserModel>> getFamilyMembers(String familyId) async {
    await Future.delayed(const Duration(milliseconds: 300));

    final family = _families[familyId];
    if (family == null) {
      return [];
    }

    final members = family.members
        .map((userId) => _users[userId])
        .where((user) => user != null)
        .cast<UserModel>()
        .toList();

    return members;
  }

  Future<FamilyModel?> getFamilyById(String familyId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _families[familyId];
  }

  Future<UserModel?> getUserById(String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _users[userId];
  }

  Future<FamilyModel?> getUserFamily(String userId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    final user = _users[userId];
    if (user == null) {
      return null;
    }
    
    return _families[user.familyId];
  }

  Future<void> updateUserStatus(String userId, String status) async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    final user = _users[userId];
    if (user != null) {
      _users[userId] = user.copyWith(
        status: status,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<void> updateUserLocation(String userId, LocationData location) async {
    await Future.delayed(const Duration(milliseconds: 300));
    
    final user = _users[userId];
    if (user != null) {
      _users[userId] = user.copyWith(
        currentLocation: location,
        updatedAt: DateTime.now(),
      );
    }
  }

  Future<void> removeUserFromFamily(String userId) async {
    await Future.delayed(const Duration(milliseconds: 500));
    
    final user = _users[userId];
    if (user != null) {
      final family = _families[user.familyId];
      if (family != null) {
        final updatedMembers = List<String>.from(family.members)
          ..remove(userId);
        
        _families[family.familyId] = family.copyWith(
          members: updatedMembers,
          updatedAt: DateTime.now(),
        );
      }
      
      _users.remove(userId);
      _familyMembers.remove(userId);
    }
  }

  Future<String?> getFamilyCode(String familyId) async {
    await Future.delayed(const Duration(milliseconds: 300));
    return _families[familyId]?.familyCode;
  }

  String _generateId() {
    return 'id_${DateTime.now().millisecondsSinceEpoch}_${Random().nextInt(9999)}';
  }

  void printDebugInfo() {
    print('=== FAMILY SERVICE DEBUG ===');
    print('Total Families: ${_families.length}');
    print('Total Users: ${_users.length}');
    print('Total Family Members: ${_familyMembers.length}');
    
    _families.forEach((id, family) {
      print('Family: ${family.familyName} (${family.familyCode}) - ${family.members.length} members');
    });
    
    _users.forEach((id, user) {
      print('User: ${user.name} (${user.role}) - Status: ${user.status} - Barangay: ${user.barangay}');
    });
    print('============================');
  }

  void clearAllData() {
    _families.clear();
    _users.clear();
    _familyMembers.clear();
  }
}