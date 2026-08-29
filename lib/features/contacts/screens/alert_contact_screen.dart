import 'dart:async';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../services/notification_count_service.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../map/screens/map_screen.dart';
import '../../notifications/screens/notification_screen.dart';
import '../../auth/screens/settings_screen.dart';

class AlertContactScreen extends StatefulWidget {
  final String? userId;
  final String? userName;

  const AlertContactScreen({
    super.key,
    this.userId,
    this.userName,
  });

  @override
  State<AlertContactScreen> createState() => _AlertContactScreenState();
}

class _AlertContactScreenState extends State<AlertContactScreen> {
  int _selectedIndex = 3; // Settings tab (since accessed from Profile/Settings)
  int _unreadCount = 0;
  Timer? _unreadTimer;
  String? _resolvedUserId;

  final List<Map<String, dynamic>> _contacts = [
    {
      'name': 'Panabo City Police Station',
      'phone': '0998-598-7052',
      'isAuthorized': true,
      'type': 'police'
    },
    {
      'name': 'Panabo CDRRMO Rescue/Ambulance',
      'phone': '0998-598-7052',
      'isAuthorized': true,
      'type': 'rescue'
    },
    {
      'name': 'Panabo Fire Station',
      'phone': '0998-598-7053',
      'isAuthorized': true,
      'type': 'fire'
    },
    {
      'name': 'Barangay New Visayas emergency hotline',
      'phone': '0998-598-7054',
      'isAuthorized': true,
      'type': 'government'
    },
    {
      'name': 'Barangay Health Center',
      'phone': '0998-598-7055',
      'isAuthorized': true,
      'type': 'medical'
    },
  ];

  @override
  void initState() {
    super.initState();
    _pollUnreadCount();
    _loadPersonalContacts();
  }

  @override
  void dispose() {
    _unreadTimer?.cancel();
    super.dispose();
  }

  /// This screen can be opened without a userId (dashboard's shortcut passes
  /// none), so fall back to the session's saved userId — same pattern
  /// already used elsewhere in this file for familyCode.
  Future<String?> _getUserId() async {
    if (_resolvedUserId != null) return _resolvedUserId;
    if (widget.userId != null && widget.userId!.isNotEmpty) {
      _resolvedUserId = widget.userId;
      return _resolvedUserId;
    }
    final prefs = await SharedPreferences.getInstance();
    _resolvedUserId = prefs.getString('userId');
    return _resolvedUserId;
  }

  Future<void> _loadPersonalContacts() async {
    final userId = await _getUserId();
    if (userId == null || userId.isEmpty) return;

    final saved = await FirebaseService.getPersonalContacts(userId);
    if (!mounted || saved.isEmpty) return;

    setState(() {
      _contacts.addAll(saved.map((c) => {
            'id': c['id'],
            'name': c['Name']?.toString() ?? 'Unknown',
            'phone': c['Phone']?.toString() ?? '',
            'isAuthorized': false,
            'type': 'personal',
          }));
    });
  }

  Future<void> _pollUnreadCount() async {
    await _refreshUnreadCount();
    _unreadTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshUnreadCount(),
    );
  }

  Future<void> _refreshUnreadCount() async {
    try {
      // The count is per-user now (a member's own reports must not light up
      // their own badge), so resolve the session userId rather than relying
      // on the widget arg this screen is often opened without.
      final userId = await _getUserId() ?? '';
      if (userId.isEmpty) return;

      final prefs = await SharedPreferences.getInstance();
      var familyCode = prefs.getString('familyCode') ?? '';
      if (familyCode.isEmpty) {
        final account = await FirebaseService.getUserById(userId);
        familyCode = account?['familyCode']?.toString() ?? '';
      }
      // No early return on an empty familyCode: updates on the user's own
      // reports (responder assigned / resolved) still count without one.

      final unread = await NotificationCountService.unreadCount(
        userId: userId,
        familyCode: familyCode,
        throwOnError: true,
      );

      if (mounted) setState(() => _unreadCount = unread);
    } catch (_) {
      // Leave _unreadCount as whatever it already was.
    }
  }

  List<Map<String, dynamic>> get _verifiedContacts =>
      _contacts.where((c) => c['isAuthorized'] == true).toList();

  List<Map<String, dynamic>> get _personalContacts =>
      _contacts.where((c) => c['isAuthorized'] != true).toList();

  void _onBottomNavTap(int index) {
    if (index == _selectedIndex) return;

    setState(() => _selectedIndex = index);

    switch (index) {
      case 0: // Home
        if (widget.userId != null && widget.userName != null) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (context) => DashboardScreen(
                userId: widget.userId!,
                userName: widget.userName!,
              ),
            ),
          );
        } else {
          Navigator.pop(context);
        }
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
          MaterialPageRoute(builder: (context) => const _NotifLauncher()),
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
      backgroundColor: const Color(0xFFAAD4F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFFAAD4F5),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.secondary,
                borderRadius: BorderRadius.circular(8),
              ),
              child: const Icon(Icons.security, color: Colors.white, size: 20),
            ),
            const SizedBox(width: 8),
            const Text(
              'LifeGuard360',
              style: TextStyle(
                color: AppColors.secondary,
                fontWeight: FontWeight.bold,
                fontSize: 18,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.account_circle,
                color: AppColors.secondary, size: 28),
            onPressed: () {},
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          Expanded(
            child: _buildContactsList(),
          ),
        ],
      ),
      bottomNavigationBar: _buildBottomNavigation(),
    );
  }

  Widget _buildHeader() {
    final totalCount = _contacts.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              const Expanded(
                child: Text(
                  'Emergency Contacts',
                  style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.5),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Text(
                  '$totalCount contacts',
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w600,
                    color: AppColors.secondary,
                  ),
                ),
              ),
            ],
          ),
        ),
        const Padding(
          padding: EdgeInsets.fromLTRB(20, 0, 20, 12),
          child: Text(
            'These contacts are verified local authorities and authorized emergency responders.',
            style: TextStyle(
              fontSize: 13,
              color: AppColors.secondary,
              height: 1.4,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildContactsList() {
    final verified = _verifiedContacts;
    final personal = _personalContacts;

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Column(
        children: [
          Expanded(
            child: ListView(
              padding:
                  const EdgeInsets.symmetric(horizontal: 8, vertical: 12),
              children: [
                if (verified.isNotEmpty) ...[
                  _buildSectionLabel(
                      'Verified Authorities', Icons.verified_user),
                  ...verified.map((c) => _buildContactCard(c)),
                  const SizedBox(height: 8),
                ],
                if (personal.isNotEmpty) ...[
                  _buildSectionLabel(
                      'Personal Contacts', Icons.people_outline),
                  ...personal.map((c) => _buildContactCard(c)),
                ],
              ],
            ),
          ),
          _buildAddButton(),
        ],
      ),
    );
  }

  Widget _buildSectionLabel(String label, IconData icon) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 6, 10, 8),
      child: Row(
        children: [
          Icon(icon, size: 15, color: AppColors.textLight),
          const SizedBox(width: 6),
          Text(
            label.toUpperCase(),
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              letterSpacing: 0.6,
              color: AppColors.textLight,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContactCard(Map<String, dynamic> contact) {
    IconData contactIcon;
    Color iconColor;
    final bool isPersonal = contact['isAuthorized'] != true;

    switch (contact['type']) {
      case 'police':
        contactIcon = Icons.local_police;
        iconColor = Colors.blue;
        break;
      case 'fire':
        contactIcon = Icons.local_fire_department;
        iconColor = Colors.red;
        break;
      case 'rescue':
        contactIcon = Icons.medical_services;
        iconColor = Colors.green;
        break;
      case 'medical':
        contactIcon = Icons.local_hospital;
        iconColor = Colors.teal;
        break;
      case 'government':
        contactIcon = Icons.account_balance;
        iconColor = Colors.orange;
        break;
      default:
        contactIcon = Icons.person;
        iconColor = AppColors.primary;
    }

    final card = Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFE0E0E0), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 4,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => _showCallConfirmationDialog(contact),
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: iconColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    contactIcon,
                    color: iconColor,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        contact['name'],
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(
                            Icons.phone,
                            size: 14,
                            color: AppColors.textLight,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            contact['phone'],
                            style: const TextStyle(
                              fontSize: 13,
                              color: AppColors.textLight,
                            ),
                          ),
                        ],
                      ),
                      if (contact['isAuthorized'] == true) ...[
                        const SizedBox(height: 6),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: Colors.green.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: Colors.green, width: 1),
                          ),
                          child: const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.verified, color: Colors.green, size: 13),
                              SizedBox(width: 4),
                              Text(
                                'Verified',
                                style: TextStyle(
                                  fontSize: 10,
                                  color: Colors.green,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _buildQuickCallButton(contact),
                if (isPersonal) ...[
                  const SizedBox(width: 4),
                  IconButton(
                    icon: Icon(Icons.delete_outline,
                        size: 20, color: AppColors.grey.withOpacity(0.8)),
                    onPressed: () => _confirmDeleteContact(contact),
                    tooltip: 'Remove contact',
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );

    return card;
  }

  Widget _buildQuickCallButton(Map<String, dynamic> contact) {
    return Material(
      color: AppColors.primary.withOpacity(0.1),
      borderRadius: BorderRadius.circular(10),
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => _showCallConfirmationDialog(contact),
        child: const Padding(
          padding: EdgeInsets.all(10),
          child: Icon(Icons.call, color: AppColors.primary, size: 20),
        ),
      ),
    );
  }

  Widget _buildAddButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: Color(0xFFE0E0E0), width: 1),
        ),
      ),
      child: Center(
        child: CustomButton(
          text: 'Add Personal Contact',
          icon: Icons.add_circle_outline,
          onPressed: () => _showAddContactDialog(context),
          fitContent: true,
        ),
      ),
    );
  }

  Widget _buildBottomNavigation() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: BottomNavigationBar(
        currentIndex: _selectedIndex,
        type: BottomNavigationBarType.fixed,
        selectedItemColor: AppColors.secondary,
        unselectedItemColor: AppColors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        backgroundColor: Colors.white,
        elevation: 0,
        onTap: _onBottomNavTap,
        items: [
          const BottomNavigationBarItem(
            icon: Icon(Icons.home, size: 28),
            label: 'Home',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.map, size: 28),
            label: 'Map',
          ),
          BottomNavigationBarItem(
            icon: Stack(
              clipBehavior: Clip.none,
              children: [
                const Icon(Icons.notifications_outlined, size: 28),
                if (_unreadCount > 0)
                  Positioned(
                    right: -6,
                    top: -4,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            label: 'Notifications',
          ),
          const BottomNavigationBarItem(
            icon: Icon(Icons.settings_outlined, size: 28),
            label: 'Settings',
          ),
        ],
      ),
    );
  }

  void _showCallConfirmationDialog(Map<String, dynamic> contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child:
                  const Icon(Icons.phone, color: AppColors.primary, size: 24),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Text(
                'Call Emergency Contact',
                style: TextStyle(fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Do you want to call ${contact['name']}?',
              style: const TextStyle(fontSize: 14, height: 1.4),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.phone, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    contact['phone'],
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber, size: 16),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'This call will be logged for emergency records',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textLight),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton.icon(
            onPressed: () {
              Navigator.pop(context);
              _makeEmergencyCall(contact);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            icon: const Icon(Icons.phone, size: 18),
            label: const Text('Call Now'),
          ),
        ],
      ),
    );
  }

  Future<void> _makeEmergencyCall(Map<String, dynamic> contact) async {
    final phone =
        (contact['phone'] as String).replaceAll(RegExp(r'[^0-9+]'), '');
    final callUri = Uri(scheme: 'tel', path: phone);

    if (await canLaunchUrl(callUri)) {
      await launchUrl(callUri);
    } else {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.error_outline, color: Colors.white),
              const SizedBox(width: 12),
              Expanded(
                child: Text('Unable to open dialer for ${contact['name']}'),
              ),
            ],
          ),
          backgroundColor: AppColors.danger,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 2),
        ),
      );
    }
  }

  void _confirmDeleteContact(Map<String, dynamic> contact) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('Remove Contact', style: TextStyle(fontSize: 18)),
        content: Text('Remove ${contact['name']} from your emergency contacts?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              setState(() => _contacts.remove(contact));

              final contactId = contact['id']?.toString();
              final userId = await _getUserId();
              if (contactId == null || userId == null || userId.isEmpty) {
                return;
              }
              final removed = await FirebaseService.removePersonalContact(
                userId: userId,
                contactId: contactId,
              );
              if (!removed && mounted) {
                // Couldn't delete server-side — put it back rather than let
                // the UI and database silently disagree.
                setState(() => _contacts.add(contact));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Failed to remove contact. Try again.'),
                    backgroundColor: AppColors.danger,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
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

  void _showAddContactDialog(BuildContext context) {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();

    showDialog(
      context: context,
      builder: (ctx) => _AddContactDialog(
        nameController: nameCtrl,
        phoneController: phoneCtrl,
        onAdd: (name, phone) async {
          final userId = await _getUserId();
          if (userId == null || userId.isEmpty) {
            return 'No active session — please log in again.';
          }

          final result = await FirebaseService.addPersonalContact(
            userId: userId,
            name: name,
            phone: phone,
          );

          if (result['success'] != true) {
            return result['error']?.toString() ?? 'Failed to save contact.';
          }

          setState(() {
            _contacts.add({
              'id': result['id'],
              'name': name,
              'phone': phone,
              'isAuthorized': false,
              'type': 'personal',
            });
          });
          return null;
        },
      ),
    );
  }
}

class _AddContactDialog extends StatefulWidget {
  final TextEditingController nameController;
  final TextEditingController phoneController;
  // Returns null on success, or an error message to show if saving failed.
  final Future<String?> Function(String name, String phone) onAdd;

  const _AddContactDialog({
    required this.nameController,
    required this.phoneController,
    required this.onAdd,
  });

  @override
  State<_AddContactDialog> createState() => _AddContactDialogState();
}

class _AddContactDialogState extends State<_AddContactDialog> {
  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
      child: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Icon(Icons.person_add,
                          color: AppColors.primary, size: 24),
                    ),
                    const SizedBox(width: 14),
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'Add Personal Contact',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: AppColors.secondary,
                            ),
                          ),
                          Text(
                            'Add a trusted emergency contact',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textLight),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: AppColors.grey),
                      onPressed: () => Navigator.pop(context),
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                CustomTextField(
                  controller: widget.nameController,
                  labelText: 'Contact Name',
                  hintText: 'Contact Name',
                  prefixIcon: Icons.person_outline,
                  onChanged: () => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a name';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                CustomTextField(
                  controller: widget.phoneController,
                  labelText: 'Phone Number',
                  hintText: 'Phone Number',
                  prefixIcon: Icons.phone_outlined,
                  keyboardType: TextInputType.phone,
                  onChanged: () => setState(() {}),
                  validator: (value) {
                    if (value == null || value.trim().isEmpty) {
                      return 'Please enter a phone number';
                    }
                    if (value.trim().length < 7) {
                      return 'Please enter a valid phone number';
                    }
                    return null;
                  },
                ),
                const SizedBox(height: 24),
                Row(
                  children: [
                    Expanded(
                      child: CustomButton(
                        text: 'Cancel',
                        onPressed: () => Navigator.pop(context),
                        color: AppColors.lightGrey,
                        textColor: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: CustomButton(
                        text: _isSaving ? 'Saving...' : 'Add Contact',
                        isLoading: _isSaving,
                        onPressed: _isSaving
                            ? () {}
                            : () async {
                                if (!_formKey.currentState!.validate()) {
                                  return;
                                }

                                final name = widget.nameController.text.trim();
                                final phone =
                                    widget.phoneController.text.trim();

                                setState(() => _isSaving = true);
                                final error = await widget.onAdd(name, phone);
                                if (!mounted) return;

                                if (error != null) {
                                  setState(() => _isSaving = false);
                                  ScaffoldMessenger.of(context).showSnackBar(
                                    SnackBar(
                                      content: Text(error),
                                      backgroundColor: AppColors.danger,
                                      behavior: SnackBarBehavior.floating,
                                      shape: RoundedRectangleBorder(
                                          borderRadius:
                                              BorderRadius.circular(10)),
                                    ),
                                  );
                                  return;
                                }

                                Navigator.pop(context);
                                ScaffoldMessenger.of(context).showSnackBar(
                                  SnackBar(
                                    content: const Row(
                                      children: [
                                        Icon(Icons.check_circle,
                                            color: Colors.white),
                                        SizedBox(width: 12),
                                        Expanded(
                                            child: Text(
                                                'Contact added successfully')),
                                      ],
                                    ),
                                    backgroundColor: AppColors.success,
                                    behavior: SnackBarBehavior.floating,
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(10)),
                                  ),
                                );
                              },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
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
