import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/photo_cache.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../../models/user_model.dart';
import '../../../models/family_model.dart';
import 'edit_profile_screen.dart';
import 'change_password_screen.dart';
import 'family_settings_screen.dart';
import 'invite_members_screen.dart';
import 'dashboard_screen.dart';
import '../../map/screens/map_screen.dart';
import '../../notifications/screens/notification_screen.dart';
import '../../auth/screens/settings_screen.dart';

class ProfileScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const ProfileScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  UserModel? _currentUser;
  FamilyModel? _currentFamily;
  List<UserModel> _familyMembers = [];
  bool _isLoading = true;
  bool _isAdmin = false;
  bool _sosSound = true;
  bool _autoSendLocation = true;
  int _selectedIndex =
      3; // Settings tab is selected (profile is accessed from settings)

  @override
  void initState() {
    super.initState();
    _loadUserProfile();
  }

  Future<void> _loadUserProfile() async {
    setState(() => _isLoading = true);
    try {
      // Get the user's account directly from Firebase (source of truth)
      final account = await FirebaseService.getUserById(widget.userId);
      final familyCode = account?['familyCode']?.toString() ?? '';

      if (account != null && familyCode.isNotEmpty) {
        // Get the family record (name, code, creator) from Firebase
        final familyData = await FirebaseService.getFamilyByCode(familyCode);

        // Get every member of this family, including their role + online
        // status. throwOnError so a failed fetch here falls into the outer
        // catch below instead of silently resolving as an empty member
        // list — which would otherwise fall through to the "no family
        // found" branch and misleadingly tell a user who really is in a
        // family that they aren't.
        final membersData = await FirebaseService.getFamilyMembersWithLocations(
            familyCode,
            throwOnError: true);

        final createdBy = familyData?['CreatedBy']?.toString() ?? '';
        final familyName = familyData?['FamilyName']?.toString() ??
            account['familyName']?.toString() ??
            'Family';

        final now = DateTime.now();

        final family = FamilyModel(
          familyId: familyCode,
          familyName: familyName,
          familyCode: familyCode,
          createdBy: createdBy,
          members:
              membersData.map((m) => m['userId']?.toString() ?? '').toList(),
          createdAt: now,
          updatedAt: now,
        );

        final members = membersData
            .map((m) => _memberMapToUserModel(m, familyCode))
            .toList()
          ..sort(
            (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()),
          );

        final currentUser = members.firstWhere(
          (member) => member.userId == widget.userId,
          orElse: () => UserModel(
            userId: widget.userId,
            name: account['userName']?.toString() ?? widget.userName,
            email: account['userEmail']?.toString() ?? '',
            mobile: account['mobileNumber']?.toString() ?? '',
            barangay: account['barangay']?.toString() ?? '',
            zipCode: account['zipCode']?.toString() ?? '',
            role: account['familyRole']?.toString() ?? 'Member',
            status: account['onlineStatus']?.toString() ?? 'Online',
            familyId: familyCode,
            photoUrl: account['photoUrl']?.toString() ?? '',
            createdAt: now,
            updatedAt: now,
          ),
        ).copyWith(photoUrl: account['photoUrl']?.toString() ?? '');

        // Admin = the person who created the family
        final isAdmin = createdBy.isNotEmpty && createdBy == widget.userId;

        if (mounted) {
          setState(() {
            _currentFamily = family;
            _currentUser = currentUser;
            _familyMembers = members;
            _isAdmin = isAdmin;
            _isLoading = false;
          });
        }
      } else {
        // No family found
        if (mounted) {
          setState(() {
            _currentUser = UserModel(
              userId: widget.userId,
              name: account?['userName']?.toString() ?? widget.userName,
              email: account?['userEmail']?.toString() ?? '',
              mobile: account?['mobileNumber']?.toString() ?? '',
              barangay: account?['barangay']?.toString() ?? '',
              zipCode: account?['zipCode']?.toString() ?? '',
              role: account?['familyRole']?.toString() ?? 'Member',
              status: account?['onlineStatus']?.toString() ?? 'Online',
              familyId: '',
              photoUrl: account?['photoUrl']?.toString() ?? '',
              createdAt: DateTime.now(),
              updatedAt: DateTime.now(),
            );
            _currentFamily = null;
            _familyMembers = [];
            _isAdmin = false;
            _isLoading = false;
          });
        }
      }
    } catch (e) {
      debugPrint('❌ Error loading profile: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  /// Converts a raw Firebase member map (userId, name, role, onlineStatus,
  /// latitude, longitude, ...) into a [UserModel] used by the UI below.
  UserModel _memberMapToUserModel(Map<String, dynamic> m, String familyCode) {
    final lat = m['latitude'];
    final lng = m['longitude'];
    LocationData? location;
    if (lat != null && lng != null) {
      location = LocationData(
        latitude: (lat as num).toDouble(),
        longitude: (lng as num).toDouble(),
        address: '',
      );
    }

    final now = DateTime.now();

    return UserModel(
      userId: m['userId']?.toString() ?? '',
      name: m['name']?.toString() ?? 'Unknown',
      email: '',
      role: m['role']?.toString() ?? 'Member',
      status: m['onlineStatus']?.toString() ?? 'Offline',
      currentLocation: location,
      familyId: familyCode,
      createdAt: now,
      updatedAt: now,
    );
  }

  void _onBottomNavTap(int index) {
    if (index == _selectedIndex) return; // Already on this tab

    setState(() => _selectedIndex = index);

    switch (index) {
      case 0: // Home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DashboardScreen(
              userId: widget.userId,
              userName: _currentUser?.name ?? widget.userName,
            ),
          ),
        );
        break;
      case 1: // Map
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => const MapScreen(
                    userId: '',
                    familyCode: '',
                  )),
        );
        break;
      case 2: // Notifications
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => NotificationScreen(
                  userId: widget.userId ?? '',
                  familyCode: _currentFamily?.familyCode ?? '')),
        );
        break;
      case 3: // Settings
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => SettingsScreen(
                  userId: widget.userId, userName: widget.userName)),
        );
        break;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Profile',
          style: TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              child: Column(
                children: [
                  _buildProfileHeader(),
                  const SizedBox(height: 20),
                  _buildProfileActions(),
                  const SizedBox(height: 16),
                  _buildFamilySection(),
                  const SizedBox(height: 16),
                  _buildEmergencyPreferences(),
                  const SizedBox(height: 16),
                  _buildAccountSecurity(),
                  const SizedBox(height: 20),
                ],
              ),
            ),
      bottomNavigationBar: _buildBottomNavigationBar(),
    );
  }

  Widget _buildBottomNavigationBar() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onBottomNavTap,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.secondary,
        unselectedItemColor: AppColors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        elevation: 0,
        items: const [
          BottomNavigationBarItem(
            icon: Icon(Icons.home, size: 28),
            label: 'Home',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.map, size: 28),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.notifications_outlined, size: 28),
            label: 'Notifications',
          ),
          BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined, size: 28),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  Widget _buildProfileHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: const BoxDecoration(
        color: Colors.white,
      ),
      child: Column(
        children: [
          Stack(
            children: [
              Container(
                width: 100,
                height: 100,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.primary.withOpacity(0.2),
                  border: Border.all(
                    color: AppColors.primary,
                    width: 3,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: _buildHeaderAvatarContent(),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 32,
                  height: 32,
                  decoration: BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Text(
            _currentUser?.name ?? widget.userName,
            style: const TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  _currentUser?.role ?? 'Member',
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                    color: AppColors.primary,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              if (_isAdmin)
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.amber.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Row(
                    children: [
                      Icon(Icons.star, color: Colors.amber, size: 16),
                      SizedBox(width: 4),
                      Text(
                        'Admin',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: Colors.amber,
                        ),
                      ),
                    ],
                  ),
                ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 8,
                height: 8,
                decoration: const BoxDecoration(
                  color: Colors.green,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 6),
              const Text(
                'Online',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.green,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// Shows the saved profile photo, falling back to the initials avatar
  /// when there is none or the stored data is malformed.
  Widget _buildHeaderAvatarContent() {
    final photoData = _currentUser?.photoUrl ?? '';
    // Cached decode — see PhotoCache. Also lets the image cache hit across
    // rebuilds instead of re-decoding the photo each time.
    final bytes = PhotoCache.decode(photoData);
    if (bytes == null) return _buildHeaderInitials();

    return Image.memory(
      bytes,
      width: 100,
      height: 100,
      fit: BoxFit.cover,
      // Decoded near display size (100 logical px at up to ~3x density)
      // rather than at the source photo's full camera resolution.
      cacheWidth: 300,
      cacheHeight: 300,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) => _buildHeaderInitials(),
    );
  }

  Widget _buildHeaderInitials() {
    return Center(
      child: Text(
        _currentUser?.name.isNotEmpty == true
            ? _currentUser!.name[0].toUpperCase()
            : 'U',
        style: const TextStyle(
          fontSize: 40,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildProfileActions() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Profile Actions',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          ),
          _buildMenuItem(
            icon: Icons.edit,
            title: 'Edit Profile',
            subtitle: 'Change name, photo, and role',
            onTap: () async {
              final result = await Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => EditProfileScreen(
                    userId: widget.userId,
                    currentUser: _currentUser!,
                    isAdmin: _isAdmin,
                  ),
                ),
              );

              // If EditProfileScreen returned updated data
              if (result != null && result is Map<String, dynamic>) {
                final newName = result['name'] as String?;
                final newRole = result['role'] as String?;
                final newPhotoUrl = result['photoUrl'] as String?;

                if (newName != null) {
                  // Update the local UserModel
                  setState(() {
                    _currentUser = _currentUser!.copyWith(
                      name: newName,
                      role: newRole ?? _currentUser!.role,
                      photoUrl: newPhotoUrl ?? _currentUser!.photoUrl,
                    );
                  });

                  // Update SharedPreferences so the Dashboard uses the new name
                  final prefs = await SharedPreferences.getInstance();
                  await prefs.setString('userName', newName);
                }
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildFamilySection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 15,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Family Header ───────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.family_restroom,
                    color: AppColors.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _currentFamily != null
                            ? _currentFamily!.familyName
                            : 'No Family Yet',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _currentFamily != null
                            ? '${_familyMembers.length} member${_familyMembers.length != 1 ? 's' : ''}'
                            : 'Join or create a family',
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.textLight,
                        ),
                      ),
                    ],
                  ),
                ),
                if (_currentFamily != null && _isAdmin)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.amber.withOpacity(0.4),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.star, color: Colors.amber, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            color: Colors.amber,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),

          const Divider(height: 1, color: AppColors.lightGrey),

          // ── Family Code ────────────────────────────────────────────────────
          if (_currentFamily != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Row(
                children: [
                  const Icon(Icons.qr_code, color: AppColors.grey, size: 16),
                  const SizedBox(width: 8),
                  Text(
                    'Family Code: ${_currentFamily!.familyCode}',
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.textLight,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ),
            ),

          // ── Admin Badge ────────────────────────────────────────────────────
          if (_currentFamily != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: Colors.amber.withOpacity(0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.workspace_premium,
                      color: Colors.amber,
                      size: 16,
                    ),
                    const SizedBox(width: 6),
                    Text(
                      'Admin: ${_getAdminName()}',
                      style: const TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Colors.amber,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Members List ──────────────────────────────────────────────────
          if (_familyMembers.isNotEmpty) ...[
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Text(
                'Family Members',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondary,
                ),
              ),
            ),
            const SizedBox(height: 8),
            ..._familyMembers.map((member) => _buildMemberCard(member)),
            const SizedBox(height: 8),
          ],

          // ── No Family State ──────────────────────────────────────────────
          if (_currentFamily == null)
            Padding(
              padding: const EdgeInsets.all(24),
              child: Center(
                child: Column(
                  children: [
                    Icon(
                      Icons.people_outline,
                      size: 48,
                      color: AppColors.grey.withOpacity(0.5),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Not in a family yet',
                      style: TextStyle(
                        color: AppColors.textLight,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'Join or create a family from the dashboard',
                      style: TextStyle(
                        color: AppColors.textLight,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
            ),

          // ── Action Buttons ─────────────────────────────────────────────────
          if (_currentFamily != null) ...[
            const Divider(height: 1, color: AppColors.lightGrey),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  if (_isAdmin)
                    _buildActionChip(
                      icon: Icons.settings,
                      label: 'Manage Family',
                      color: AppColors.primary,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => FamilySettingsScreen(
                              currentUserId: widget.userId,
                              familyId: _currentFamily!.familyId,
                              isAdmin: _isAdmin,
                            ),
                          ),
                        ).then((_) => _loadUserProfile());
                      },
                    ),
                  if (_isAdmin)
                    _buildActionChip(
                      icon: Icons.person_add,
                      label: 'Invite Members',
                      color: Colors.green,
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => InviteMembersScreen(
                              familyId: _currentFamily!.familyId,
                              familyCode: _currentFamily!.familyCode,
                              userId: widget.userId,
                              userName: _currentUser?.name ?? widget.userName,
                            ),
                          ),
                        );
                      },
                    ),
                  if (_isAdmin)
                    _buildActionChip(
                      icon: Icons.swap_horiz,
                      label: 'Transfer Admin',
                      color: Colors.orange,
                      onTap: _showTransferAdminDialog,
                    ),
                  if (!_isAdmin)
                    _buildActionChip(
                      icon: Icons.exit_to_app,
                      label: 'Leave Family',
                      color: AppColors.danger,
                      onTap: _showLeaveFamilyDialog,
                    ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  String _getAdminName() {
    if (_currentFamily == null) return 'Unknown';
    final admin = _familyMembers.firstWhere(
      (member) => member.userId == _currentFamily!.createdBy,
      orElse: () => _familyMembers.first,
    );
    return admin.name;
  }

  Widget _buildMemberCard(UserModel member) {
    final isCurrentUser = member.userId == widget.userId;
    final isFamilyAdmin =
        _currentFamily != null && member.userId == _currentFamily!.createdBy;

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? AppColors.primary.withOpacity(0.05)
            : AppColors.lightGrey,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isCurrentUser
              ? AppColors.primary.withOpacity(0.3)
              : Colors.transparent,
          width: isCurrentUser ? 1.5 : 0,
        ),
      ),
      child: Row(
        children: [
          CircleAvatar(
            radius: 20,
            backgroundColor: isFamilyAdmin
                ? Colors.amber.withOpacity(0.2)
                : isCurrentUser
                    ? AppColors.primary
                    : AppColors.grey.withOpacity(0.3),
            child: Text(
              member.name[0].toUpperCase(),
              style: TextStyle(
                color: isFamilyAdmin
                    ? Colors.amber
                    : isCurrentUser
                        ? Colors.white
                        : AppColors.secondary,
                fontWeight: FontWeight.bold,
                fontSize: 16,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(
                        member.name,
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight:
                              isCurrentUser ? FontWeight.bold : FontWeight.w500,
                          color: isCurrentUser
                              ? AppColors.primary
                              : AppColors.secondary,
                        ),
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            fontSize: 9,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    if (isFamilyAdmin) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              Icons.star,
                              color: Colors.amber,
                              size: 10,
                            ),
                            const SizedBox(width: 2),
                            const Text(
                              'Admin',
                              style: TextStyle(
                                fontSize: 9,
                                color: Colors.amber,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),
                const SizedBox(height: 2),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 6,
                        vertical: 2,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        member.role.isNotEmpty ? member.role : 'Member',
                        style: const TextStyle(
                          fontSize: 10,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 6,
                      height: 6,
                      decoration: BoxDecoration(
                        color: member.status == 'Online'
                            ? Colors.green
                            : AppColors.grey,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      member.status,
                      style: TextStyle(
                        fontSize: 10,
                        color: member.status == 'Online'
                            ? Colors.green
                            : AppColors.grey,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          // Admin-only control to remove this member from the family
          if (_isAdmin && !isCurrentUser)
            IconButton(
              icon: const Icon(
                Icons.person_remove_outlined,
                color: AppColors.danger,
                size: 20,
              ),
              tooltip: 'Remove ${member.name}',
              onPressed: () => _confirmRemoveMember(member),
            ),
        ],
      ),
    );
  }

  /// Shows a confirmation dialog and, if confirmed, removes [member] from
  /// the family. Only ever called from an admin-only control.
  void _confirmRemoveMember(UserModel member) {
    if (_currentFamily == null) return;

    bool isRemoving = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.person_remove, color: AppColors.danger),
                SizedBox(width: 12),
                Text('Remove Member'),
              ],
            ),
            content: Text(
              'Are you sure you want to remove ${member.name} from the family? '
              'They will need a new invitation to rejoin.',
              style: const TextStyle(fontSize: 14),
            ),
            actions: [
              TextButton(
                onPressed:
                    isRemoving ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: isRemoving
                    ? null
                    : () async {
                        setDialogState(() => isRemoving = true);

                        final result = await FirebaseService.leaveFamily(
                          userId: member.userId,
                          familyCode: _currentFamily!.familyCode,
                        );

                        if (!mounted) return;

                        Navigator.pop(dialogContext);

                        if (result['success'] == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                '${member.name} has been removed from the family',
                              ),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                          await _loadUserProfile();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                result['error']?.toString() ??
                                    'Failed to remove member',
                              ),
                              backgroundColor: AppColors.danger,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger,
                  disabledBackgroundColor: AppColors.danger.withOpacity(0.3),
                ),
                child: isRemoving
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Remove'),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildActionChip({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return ActionChip(
      avatar: Icon(icon, size: 16, color: color),
      label: Text(
        label,
        style: TextStyle(
          fontSize: 12,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
      onPressed: onTap,
      backgroundColor: color.withOpacity(0.08),
      side: BorderSide(
        color: color.withOpacity(0.3),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
      ),
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 8,
      ),
    );
  }

  Widget _buildEmergencyPreferences() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Emergency Preferences',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          ),
          _buildSwitchItem(
            icon: Icons.volume_up,
            title: 'SOS Sound',
            subtitle: 'Play sound when SOS is activated',
            value: _sosSound,
            onChanged: (value) {
              setState(() => _sosSound = value);
            },
          ),
          _buildSwitchItem(
            icon: Icons.location_on,
            title: 'Auto-send Location',
            subtitle: 'Send location automatically on SOS',
            value: _autoSendLocation,
            onChanged: (value) {
              setState(() => _autoSendLocation = value);
            },
          ),
        ],
      ),
    );
  }

  Widget _buildAccountSecurity() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Account & Security',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          ),
          _buildMenuItem(
            icon: Icons.lock,
            title: 'Change Password',
            subtitle: 'Update your password',
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => ChangePasswordScreen(
                    userId: widget.userId,
                  ),
                ),
              );
            },
          ),
          _buildMenuItem(
            icon: Icons.logout,
            title: 'Logout',
            subtitle: 'Sign out of your account',
            onTap: _showLogoutDialog,
          ),
          _buildMenuItem(
            icon: Icons.delete_forever,
            title: 'Delete Account',
            subtitle: 'Permanently delete your account',
            iconColor: AppColors.danger,
            titleColor: AppColors.danger,
            onTap: _showDeleteAccountDialog,
          ),
        ],
      ),
    );
  }

  Widget _buildMenuItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    Color? iconColor,
    Color? titleColor,
  }) {
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(
            top: BorderSide(color: AppColors.lightGrey, width: 0.5),
          ),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: (iconColor ?? AppColors.primary).withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Icon(
                icon,
                color: iconColor ?? AppColors.primary,
                size: 22,
              ),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.w600,
                      color: titleColor ?? AppColors.secondary,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textLight,
                    ),
                  ),
                ],
              ),
            ),
            Icon(
              Icons.arrow_forward_ios,
              size: 16,
              color: AppColors.grey.withOpacity(0.5),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSwitchItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required bool value,
    required ValueChanged<bool> onChanged,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.lightGrey, width: 0.5),
        ),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              icon,
              color: AppColors.primary,
              size: 22,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondary,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  subtitle,
                  style: const TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
            activeThumbColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  void _showTransferAdminDialog() {
    if (_currentFamily == null) return;

    // Every other member is eligible to become the new admin
    final eligibleMembers =
        _familyMembers.where((m) => m.userId != widget.userId).toList();

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning_amber, color: Colors.amber),
            SizedBox(width: 12),
            Text('Transfer Admin Rights'),
          ],
        ),
        content: Text(
          eligibleMembers.isEmpty
              ? 'There are no other members in this family to transfer admin rights to.'
              : 'This will allow you to transfer admin rights to another family member. You will become a regular member after the transfer.',
          style: const TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: eligibleMembers.isEmpty
                ? null
                : () {
                    Navigator.pop(context);
                    _showSelectNewAdminDialog(eligibleMembers);
                  },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
              disabledBackgroundColor: Colors.amber.withOpacity(0.3),
            ),
            child: const Text('Continue'),
          ),
        ],
      ),
    );
  }

  /// Lets the current admin pick which family member becomes the next admin.
  void _showSelectNewAdminDialog(List<UserModel> eligibleMembers) {
    String? selectedUserId;
    bool isTransferring = false;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
            ),
            title: const Row(
              children: [
                Icon(Icons.swap_horiz, color: Colors.amber),
                SizedBox(width: 12),
                Expanded(child: Text('Choose New Admin')),
              ],
            ),
            content: SizedBox(
              width: double.maxFinite,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Select the family member who will become the new admin.',
                    style: TextStyle(fontSize: 13, color: AppColors.textLight),
                  ),
                  const SizedBox(height: 12),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 320),
                    child: ListView.separated(
                      shrinkWrap: true,
                      itemCount: eligibleMembers.length,
                      separatorBuilder: (_, __) => const SizedBox(height: 6),
                      itemBuilder: (context, index) {
                        final member = eligibleMembers[index];
                        final isSelected = member.userId == selectedUserId;

                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: isTransferring
                              ? null
                              : () => setDialogState(
                                  () => selectedUserId = member.userId),
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 8,
                            ),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? Colors.amber.withOpacity(0.12)
                                  : Colors.transparent,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                color: isSelected
                                    ? Colors.amber
                                    : AppColors.lightGrey,
                                width: isSelected ? 1.5 : 1,
                              ),
                            ),
                            child: Row(
                              children: [
                                CircleAvatar(
                                  radius: 18,
                                  backgroundColor:
                                      AppColors.grey.withOpacity(0.3),
                                  child: Text(
                                    member.name.isNotEmpty
                                        ? member.name[0].toUpperCase()
                                        : '?',
                                    style: const TextStyle(
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        member.name,
                                        style: const TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: AppColors.secondary,
                                        ),
                                      ),
                                      Text(
                                        member.role.isNotEmpty
                                            ? member.role
                                            : 'Member',
                                        style: const TextStyle(
                                          fontSize: 11,
                                          color: AppColors.textLight,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                Radio<String>(
                                  value: member.userId,
                                  groupValue: selectedUserId,
                                  activeColor: Colors.amber,
                                  onChanged: isTransferring
                                      ? null
                                      : (value) => setDialogState(
                                          () => selectedUserId = value),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed:
                    isTransferring ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancel'),
              ),
              ElevatedButton(
                onPressed: (selectedUserId == null || isTransferring)
                    ? null
                    : () async {
                        final selectedMember = eligibleMembers.firstWhere(
                          (m) => m.userId == selectedUserId,
                        );

                        setDialogState(() => isTransferring = true);

                        final result = await FirebaseService.transferAdmin(
                          familyCode: _currentFamily!.familyCode,
                          currentAdminId: widget.userId,
                          newAdminId: selectedMember.userId,
                          newAdminName: selectedMember.name,
                        );

                        if (!mounted) return;

                        Navigator.pop(dialogContext);

                        if (result['success'] == true) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                'Admin rights transferred to ${selectedMember.name}',
                              ),
                              backgroundColor: AppColors.success,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                          await _loadUserProfile();
                        } else {
                          ScaffoldMessenger.of(context).showSnackBar(
                            SnackBar(
                              content: Text(
                                result['error']?.toString() ??
                                    'Failed to transfer admin rights',
                              ),
                              backgroundColor: AppColors.danger,
                              behavior: SnackBarBehavior.floating,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10),
                              ),
                            ),
                          );
                        }
                      },
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber,
                  disabledBackgroundColor: Colors.amber.withOpacity(0.3),
                ),
                child: isTransferring
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Transfer'),
              ),
            ],
          );
        },
      ),
    );
  }

  void _showLeaveFamilyDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.warning, color: AppColors.danger),
            SizedBox(width: 12),
            Text('Leave Family'),
          ],
        ),
        content: const Text(
          'Are you sure you want to leave this family? You will need an invitation to rejoin.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              // Leave family logic
              Navigator.pop(context);
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(
                  content: Text('You have left the family'),
                  backgroundColor: AppColors.danger,
                ),
              );
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('Leave'),
          ),
        ],
      ),
    );
  }

  void _showLogoutDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout, color: Colors.amber),
            SizedBox(width: 12),
            Text('Logout'),
          ],
        ),
        content: const Text(
          'Are you sure you want to logout?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Logout logic
              Navigator.pop(context);
              Navigator.pop(context); // Return to previous screen
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.amber,
            ),
            child: const Text('Logout'),
          ),
        ],
      ),
    );
  }

  void _showDeleteAccountDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.delete_forever, color: AppColors.danger),
            SizedBox(width: 12),
            Text('Delete Account'),
          ],
        ),
        content: const Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '⚠️ This action is permanent and cannot be undone!',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.bold,
                color: AppColors.danger,
              ),
            ),
            SizedBox(height: 12),
            Text(
              'Deleting your account will:',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
            ),
            SizedBox(height: 8),
            Text(
              '• Remove you from your family\n'
              '• Delete all your data\n'
              '• Disable emergency features\n'
              '• Cannot be recovered',
              style: TextStyle(fontSize: 13),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _showFinalDeleteConfirmation();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
  }

  void _showFinalDeleteConfirmation() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Text(
          'Final Confirmation',
          style: TextStyle(color: AppColors.danger),
        ),
        content: const Text(
          'Type "DELETE" to confirm account deletion',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              // Delete account logic
              Navigator.pop(context);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
            ),
            child: const Text('Confirm Delete'),
          ),
        ],
      ),
    );
  }
}
