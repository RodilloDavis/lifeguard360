import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../../models/user_model.dart';
import '../../../models/family_model.dart';
import '../../../models/family_member_model.dart';
import 'dashboard_screen.dart';
import '../../map/screens/map_screen.dart';
import '../../notifications/screens/notification_screen.dart';

class FamilySettingsScreen extends StatefulWidget {
  final String currentUserId;
  final String familyId;
  final bool isAdmin;

  const FamilySettingsScreen({
    super.key,
    required this.currentUserId,
    required this.familyId,
    required this.isAdmin,
  });

  @override
  State<FamilySettingsScreen> createState() => _FamilySettingsScreenState();
}

class _FamilySettingsScreenState extends State<FamilySettingsScreen> {
  // widget.familyId is actually the family *code* — that's how every
  // FirebaseService family/member lookup is keyed (Families/{code}/...),
  // matching how the caller (SettingsScreen) resolves and passes it in.
  String get _familyCode => widget.familyId;

  List<UserModel> _familyMembers = [];
  FamilyModel? _currentFamily;
  bool _isLoading = true;
  int _selectedIndex = 3; // Settings tab

  @override
  void initState() {
    super.initState();
    _loadFamilySettings();
  }

  Future<void> _loadFamilySettings() async {
    setState(() => _isLoading = true);

    try {
      final familyData = await FirebaseService.getFamilyByCode(_familyCode);
      // throwOnError so a failed fetch reaches the catch block below instead
      // of silently resolving as an empty member list.
      final membersData = await FirebaseService.getFamilyMembersWithLocations(
          _familyCode,
          throwOnError: true);

      final now = DateTime.now();
      final family = FamilyModel(
        familyId: _familyCode,
        familyName: familyData?['FamilyName']?.toString() ?? 'Family',
        familyCode: _familyCode,
        createdBy: familyData?['CreatedBy']?.toString() ?? '',
        members: membersData.map((m) => m['userId']?.toString() ?? '').toList(),
        createdAt: now,
        updatedAt: now,
      );

      final members = membersData
          .map((m) => _memberMapToUserModel(m))
          .toList()
        ..sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));

      if (mounted) {
        setState(() {
          _currentFamily = family;
          _familyMembers = members;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('❌ Error loading family settings: $e');
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  // Mirrors profile_screen.dart's _memberMapToUserModel — email isn't part
  // of the payload FirebaseService.getFamilyMembersWithLocations returns
  // (it isn't stored per-member, only per-account, and isn't needed for
  // display here), so it's left blank rather than faked.
  UserModel _memberMapToUserModel(Map<String, dynamic> m) {
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
      familyId: _familyCode,
      createdAt: now,
      updatedAt: now,
    );
  }

  void _onBottomNavTap(int index) {
    if (index == _selectedIndex) return;

    setState(() => _selectedIndex = index);

    // Get current user info for navigation. Falls back to a placeholder
    // rather than `_familyMembers.first` — that throws on an empty list,
    // which happens whenever the fetch above fails or is still loading.
    final currentUser = _familyMembers.firstWhere(
      (m) => m.userId == widget.currentUserId,
      orElse: () => UserModel(
        userId: widget.currentUserId,
        name: '',
        email: '',
        role: 'Member',
        status: 'Offline',
        familyId: _familyCode,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );

    switch (index) {
      case 0: // Home
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
            builder: (context) => DashboardScreen(
              userId: widget.currentUserId,
              userName: currentUser.name,
            ),
          ),
        );
        break;
      case 1: // Map
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(
              builder: (context) => MapScreen(
                    userId: widget.currentUserId,
                    familyCode: _currentFamily?.familyCode ?? '',
                  )),
        );
        break;
      case 2: // Notifications
        Navigator.pushReplacement(
          context,
          MaterialPageRoute(builder: (context) => const _NotifLauncher()),
        );
        break;
      case 3: // Settings - Current screen
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
          'Family Settings',
          style: TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _loadFamilySettings,
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    const SizedBox(height: 20),
                    _buildFamilyInfoCard(),
                    const SizedBox(height: 16),
                    _buildMembersSection(),
                    const SizedBox(height: 20),
                  ],
                ),
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

  Widget _buildFamilyInfoCard() {
    if (_currentFamily == null) return const SizedBox.shrink();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(
                  Icons.family_restroom,
                  color: AppColors.primary,
                  size: 28,
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _currentFamily!.familyName,
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      '${_familyMembers.length} member${_familyMembers.length != 1 ? 's' : ''}',
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textLight,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          const Divider(),
          const SizedBox(height: 12),
          _buildInfoRow('Family Code', _currentFamily!.familyCode),
          const SizedBox(height: 8),
          _buildInfoRow(
            'Created',
            _formatDate(_currentFamily!.createdAt),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(
          label,
          style: const TextStyle(
            fontSize: 14,
            color: AppColors.textLight,
          ),
        ),
        Text(
          value,
          style: const TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.secondary,
          ),
        ),
      ],
    );
  }

  Widget _buildMembersSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
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
          Padding(
            padding: const EdgeInsets.all(20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Family Members',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary,
                  ),
                ),
                if (widget.isAdmin)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.amber.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Row(
                      children: [
                        Icon(Icons.star, color: Colors.amber, size: 14),
                        SizedBox(width: 4),
                        Text(
                          'Admin',
                          style: TextStyle(
                            fontSize: 12,
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
          const Divider(height: 1),
          if (_familyMembers.isEmpty)
            const Padding(
              padding: EdgeInsets.all(40),
              child: Center(
                child: Text(
                  'No members found',
                  style: TextStyle(
                    color: AppColors.textLight,
                    fontSize: 14,
                  ),
                ),
              ),
            )
          else
            ListView.separated(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              padding: const EdgeInsets.all(12),
              itemCount: _familyMembers.length,
              separatorBuilder: (context, index) => const SizedBox(height: 8),
              itemBuilder: (context, index) {
                return _buildMemberCard(_familyMembers[index]);
              },
            ),
        ],
      ),
    );
  }

  Widget _buildMemberCard(UserModel member) {
    final isCurrentUser = member.userId == widget.currentUserId;
    final isCreator = member.userId == _currentFamily?.createdBy;
    final canManage = widget.isAdmin && !isCurrentUser;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isCurrentUser
            ? AppColors.primary.withOpacity(0.05)
            : AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isCurrentUser
              ? AppColors.primary.withOpacity(0.3)
              : Colors.transparent,
          width: isCurrentUser ? 2 : 0,
        ),
      ),
      child: Row(
        children: [
          Stack(
            children: [
              CircleAvatar(
                radius: 28,
                backgroundColor: isCurrentUser
                    ? AppColors.primary
                    : AppColors.secondary.withOpacity(0.7),
                child: Text(
                  member.name[0].toUpperCase(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
              ),
              Positioned(
                right: 0,
                bottom: 0,
                child: Container(
                  width: 14,
                  height: 14,
                  decoration: BoxDecoration(
                    color: member.status == 'Online'
                        ? Colors.green
                        : AppColors.grey,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 2),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: isCurrentUser
                              ? AppColors.primary
                              : AppColors.secondary,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isCurrentUser) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.primary,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'You',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                    if (isCreator) ...[
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.amber.withOpacity(0.2),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text(
                          'Creator',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.amber,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
                if (member.email.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(
                    member.email,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.textLight,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                const SizedBox(height: 4),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 8,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        member.role,
                        style: const TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      member.status,
                      style: TextStyle(
                        fontSize: 12,
                        color: member.status == 'Online'
                            ? Colors.green
                            : AppColors.grey,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (canManage &&
              ['Father', 'Mother', 'Guardian'].contains(member.role)) ...[
            const SizedBox(width: 8),
            GestureDetector(
              onTap: () => _showRemoveMemberDialog(member),
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.danger.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: AppColors.danger.withOpacity(0.4),
                  ),
                ),
                child: const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.person_remove,
                        size: 14, color: AppColors.danger),
                    SizedBox(width: 4),
                    Text(
                      'Remove',
                      style: TextStyle(
                        fontSize: 11,
                        color: AppColors.danger,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
          if (canManage) ...[
            const SizedBox(width: 4),
            PopupMenuButton<String>(
              icon: const Icon(Icons.more_vert, color: AppColors.grey),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              onSelected: (value) {
                switch (value) {
                  case 'edit_role':
                    _showEditRoleDialog(member);
                    break;
                  case 'permissions':
                    _showPermissionsDialog(member);
                    break;
                  case 'remove':
                    _showRemoveMemberDialog(member);
                    break;
                }
              },
              itemBuilder: (context) => [
                const PopupMenuItem(
                  value: 'edit_role',
                  child: Row(
                    children: [
                      Icon(Icons.edit, size: 18, color: AppColors.primary),
                      SizedBox(width: 12),
                      Text('Edit Role'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'permissions',
                  child: Row(
                    children: [
                      Icon(Icons.security, size: 18, color: AppColors.accent),
                      SizedBox(width: 12),
                      Text('Permissions'),
                    ],
                  ),
                ),
                const PopupMenuItem(
                  value: 'remove',
                  child: Row(
                    children: [
                      Icon(Icons.person_remove,
                          size: 18, color: AppColors.danger),
                      SizedBox(width: 12),
                      Text('Remove'),
                    ],
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  void _showEditRoleDialog(UserModel member) {
    // The dialog's own builder parameter is also named `context` and shadows
    // this one — after Navigator.pop closes the dialog, that inner context
    // is a deactivated element, so ScaffoldMessenger.of(context) on it throws
    // "Looking up a deactivated widget's ancestor is unsafe" even though this
    // screen (and this outer context) is still very much alive. Capture the
    // screen's own context here so the post-pop snackbar has something valid
    // to attach to.
    final screenContext = context;
    String selectedRole = member.role;
    final roles = [
      'Father',
      'Mother',
      'Son',
      'Daughter',
      'Guardian',
      'Grandfather',
      'Grandmother',
      'Uncle',
      'Aunt',
      'Other',
    ];

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Row(
            children: [
              Icon(Icons.edit, color: AppColors.primary),
              SizedBox(width: 12),
              Text('Edit Role'),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Change role for ${member.name}',
                style:
                    const TextStyle(fontSize: 14, color: AppColors.textLight),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.grey.withOpacity(0.3)),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: selectedRole,
                    isExpanded: true,
                    icon: const Icon(Icons.arrow_drop_down,
                        color: AppColors.primary),
                    items: roles.map((role) {
                      return DropdownMenuItem<String>(
                        value: role,
                        child: Text(role),
                      );
                    }).toList(),
                    onChanged: (value) {
                      if (value != null) {
                        setDialogState(() {
                          selectedRole = value;
                        });
                      }
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                final result = await FirebaseService.updateMemberRole(
                  familyCode: _familyCode,
                  userId: member.userId,
                  role: selectedRole,
                );
                if (!mounted) return;
                ScaffoldMessenger.of(screenContext).showSnackBar(
                  SnackBar(
                    content: Text(result['success'] == true
                        ? 'Role updated to $selectedRole'
                        : 'Failed to update role: ${result['error']}'),
                    backgroundColor: result['success'] == true
                        ? AppColors.success
                        : AppColors.danger,
                  ),
                );
                if (result['success'] == true) _loadFamilySettings();
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }

  void _showPermissionsDialog(UserModel member) {
    final permissions = Permissions.forRole(member.role);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.security, color: AppColors.accent),
            SizedBox(width: 12),
            Text('Member Permissions'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              member.name,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 20),
            _buildPermissionItem('View Location', permissions.viewLocation),
            _buildPermissionItem('Send SOS', permissions.sendSOS),
            _buildPermissionItem('Receive Alerts', permissions.receiveAlerts),
            _buildPermissionItem('Manage Members', permissions.manageMembers),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
        ],
      ),
    );
  }

  Widget _buildPermissionItem(String label, bool enabled) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            size: 20,
            color: enabled ? Colors.green : AppColors.grey,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                color: enabled ? AppColors.secondary : AppColors.textLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _showRemoveMemberDialog(UserModel member) {
    // Same shadowing pitfall as _showEditRoleDialog: the dialog builder's
    // own `context` parameter isn't this screen's — it's deactivated the
    // moment Navigator.pop closes the dialog, so the post-pop snackbar needs
    // this outer, still-alive context instead.
    final screenContext = context;
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
            Text('Remove Member'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Are you sure you want to remove ${member.name} from the family?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.danger.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Text(
                'This action cannot be undone. The member will need to rejoin using the family code.',
                style: TextStyle(
                  fontSize: 12,
                  color: AppColors.danger,
                  height: 1.4,
                ),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);

              final result = await FirebaseService.leaveFamily(
                userId: member.userId,
                familyCode: _familyCode,
              );

              if (!mounted) return;
              ScaffoldMessenger.of(screenContext).showSnackBar(
                SnackBar(
                  content: Text(result['success'] == true
                      ? '${member.name} removed from family'
                      : 'Failed to remove member: ${result['error']}'),
                  backgroundColor: result['success'] == true
                      ? AppColors.success
                      : AppColors.danger,
                ),
              );
              if (result['success'] == true) _loadFamilySettings();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  String _formatDate(DateTime date) {
    return '${date.day}/${date.month}/${date.year}';
  }
}

// ── _NotifLauncher ────────────────────────────────────────────────────────────
// Reads userId + familyCode from SharedPreferences then opens NotificationScreen.
class _NotifLauncher extends StatefulWidget {
  const _NotifLauncher();
  @override
  State<_NotifLauncher> createState() => _NotifLauncherState();
}

class _NotifLauncherState extends State<_NotifLauncher> {
  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? '';
    final familyCode = prefs.getString('familyCode') ?? '';
    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) =>
            NotificationScreen(userId: userId, familyCode: familyCode),
      ),
    );
  }

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}
