// lib/features/settings/screens/setting_screen.dart

import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/background_service.dart';
import '../../auth/screens/login_screen.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _sectionHeader('General Settings'),
            SwitchListTile(
              secondary: _icon(Icons.location_on_outlined),
              title: const Text(
                'Location Sharing',
                style: TextStyle(fontWeight: FontWeight.w500),
              ),
              subtitle: const Text(
                'Allow others to see your live location',
                style: TextStyle(fontSize: 12),
              ),
              value: true,
              onChanged: (_) {},
              activeThumbColor: AppColors.primary,
            ),
            _tile(Icons.group_outlined, 'Circle Management',
                'Manage your family and friends'),
            _tile(Icons.notifications_active_outlined, 'Smart Notifications',
                'Customize your alerts'),
            _tile(Icons.contact_emergency_outlined, 'Emergency Contacts',
                'Manage SOS contacts'),
            const Divider(height: 32),
            _sectionHeader('Support'),
            _tile(Icons.help_outline, 'Help & Support', null),
            _tile(Icons.info_outline, 'About LifeGuard360', null),
            const SizedBox(height: 40),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: ElevatedButton.icon(
                onPressed: _logout,
                icon: const Icon(Icons.logout),
                label: const Text(
                  'Logout',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.danger.withOpacity(0.1),
                  foregroundColor: AppColors.danger,
                  elevation: 0,
                  side: const BorderSide(color: AppColors.danger),
                  padding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── Logout ──────────────────────────────────────────────────────────────────

  Future<void> _logout() async {
    await AppBackgroundService.stop();

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
        child: Text(
          title,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.primary,
          ),
        ),
      );

  Widget _icon(IconData icon) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: AppColors.lightGrey,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: AppColors.secondary, size: 20),
      );

  Widget _tile(IconData icon, String title, String? subtitle) => ListTile(
        leading: _icon(icon),
        title: Text(
          title,
          style: const TextStyle(fontWeight: FontWeight.w500, fontSize: 14),
        ),
        subtitle: subtitle != null
            ? Text(subtitle, style: const TextStyle(fontSize: 12))
            : null,
        trailing: const Icon(
          Icons.chevron_right,
          size: 20,
          color: AppColors.grey,
        ),
        onTap: () {},
      );
}
