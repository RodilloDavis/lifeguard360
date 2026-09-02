// lib/features/auth/screens/settings_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/background_service.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../../services/family_members_cache_service.dart';
import '../../auth/screens/login_screen.dart';
import '../../contacts/screens/alert_contact_screen.dart';
import '../../dashboard/screens/family_settings_screen.dart';
import '../../notifications/screens/report_history_screen.dart';
import '../../../services/overlay_service.dart';
import '../../../services/online_status_service.dart';
import '../../../main.dart' show refreshFcmChannel;
import 'set_account_password_screen.dart';

class SettingsScreen extends StatefulWidget {
  final String? userId;
  final String? userName;

  const SettingsScreen({super.key, this.userId, this.userName});

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen>
    with WidgetsBindingObserver {
  bool _bubbleBusy = false;
  bool _loadingCircle = false;
  bool _loadingHistory = false;
  Map<String, dynamic>? _authInfo;
  final FlutterLocalNotificationsPlugin _flnp =
      FlutterLocalNotificationsPlugin();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _syncBubbleState();
    _loadAuthInfo();
    _checkDndAccess();
  }

  Future<void> _loadAuthInfo() async {
    final userId = widget.userId;
    if (userId == null || userId.isEmpty) return;
    final info = await FirebaseService.getAccountAuthInfo(userId);
    if (mounted) setState(() => _authInfo = info);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Catches the case where the user dragged the bubble onto the close
    // target while the app was backgrounded — no overlay event reaches this
    // screen in that window, so re-check once the app is frontmost again.
    if (state == AppLifecycleState.resumed) {
      // Also recovers the switch from a stuck _bubbleBusy: enabling the
      // bubble sends the user to the system "Display over other apps"
      // settings screen and awaits the platform plugin's permission-result
      // future, which — if that future never resolves (a known failure
      // mode when the OS recreates the Activity while it's away, dropping
      // the plugin's pending callback) — left onChanged permanently null,
      // i.e. a switch that looks broken until the app is killed and
      // reopened. Resuming is the natural point to recover from that: the
      // user is back, so reset busy and re-derive the actual on/off state
      // directly instead of continuing to wait on a future that may never
      // complete. Harmless no-op on the normal fast path, where permission
      // was already granted and the app never left the foreground at all.
      if (_bubbleBusy) setState(() => _bubbleBusy = false);
      _syncBubbleState();
      _recheckDndAccessOnResume();
    }
  }

  /// Reconciles [OverlayService.enabledNotifier] with the persisted on/off
  /// preference. Needed once at startup (the notifier defaults to false
  /// before anything has run) and again on resume, to pick up e.g. a
  /// drag-to-close dismissal that happened while this screen wasn't open to
  /// hear about it directly.
  ///
  /// Deliberately does NOT also require [OverlayService.isActive] — the
  /// bubble is only ever on screen while the app is backgrounded (see
  /// _LifecycleWrapper in main.dart), so it's always inactive while this
  /// very screen is in the foreground. Requiring it here would make the
  /// switch show "off" the instant the user opens Settings, which is wrong:
  /// the preference is still on, the bubble just isn't visible right now.
  Future<void> _syncBubbleState() async {
    OverlayService.enabledNotifier.value = await OverlayService.isEnabled();
  }

  Future<void> _toggleSosBubble(bool value) async {
    if (_bubbleBusy) return;
    HapticFeedback.selectionClick();
    setState(() => _bubbleBusy = true);

    final result = await OverlayService.setEnabled(value);

    if (!mounted) return;
    setState(() => _bubbleBusy = false);

    // Turning it on can fail if the user declines the overlay permission.
    if (value && !result) {
      _showSnackBar(
        'Permission needed. Enable "Display over other apps" for '
        'LifeGuard360 to use the floating SOS bubble.',
        color: AppColors.danger,
      );
    }
  }

  // ── Circle Management ────────────────────────────────────────────────────
  // The screen this leads to (FamilySettingsScreen) already exists and works
  // — it just needs the family code and whether this user is its admin,
  // neither of which SettingsScreen has on hand, so this fetches them on tap
  // rather than leaving the tile pointing nowhere.
  Future<void> _openCircleManagement() async {
    final userId = widget.userId;
    if (userId == null || userId.isEmpty) {
      _showSnackBar('Please open Settings from the main menu to continue.');
      return;
    }
    if (_loadingCircle) return;
    HapticFeedback.selectionClick();
    setState(() => _loadingCircle = true);

    try {
      final account = await FirebaseService.getUserById(userId);
      final familyCode = account?['familyCode']?.toString() ?? '';
      if (familyCode.isEmpty) {
        if (mounted) {
          _showSnackBar('Join or create a family first to manage your circle.');
        }
        return;
      }

      final familyData = await FirebaseService.getFamilyByCode(familyCode);
      final createdBy = familyData?['CreatedBy']?.toString() ?? '';
      final isAdmin = createdBy.isNotEmpty && createdBy == userId;

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FamilySettingsScreen(
            currentUserId: userId,
            familyId: familyCode,
            isAdmin: isAdmin,
          ),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Circle Management fetch: $e');
      if (mounted) {
        _showSnackBar('Could not load your family right now. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingCircle = false);
    }
  }

  // ── Report History ────────────────────────────────────────────────────────
  // Same "resolve familyCode on tap" pattern as _openCircleManagement above
  // — this screen only ever receives userId/userName, never the familyCode
  // itself.
  Future<void> _openReportHistory() async {
    final userId = widget.userId;
    if (userId == null || userId.isEmpty) {
      _showSnackBar('Please open Settings from the main menu to continue.');
      return;
    }
    if (_loadingHistory) return;
    HapticFeedback.selectionClick();
    setState(() => _loadingHistory = true);

    try {
      final account = await FirebaseService.getUserById(userId);
      final familyCode = account?['familyCode']?.toString() ?? '';
      if (familyCode.isEmpty) {
        if (mounted) {
          _showSnackBar('Join or create a family first to see report history.');
        }
        return;
      }

      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ReportHistoryScreen(familyCode: familyCode),
        ),
      );
    } catch (e) {
      debugPrint('⚠️ Report History fetch: $e');
      if (mounted) {
        _showSnackBar('Could not load report history right now. Try again.');
      }
    } finally {
      if (mounted) setState(() => _loadingHistory = false);
    }
  }

  // ── Do Not Disturb bypass ─────────────────────────────────────────────────
  //
  // Android has an actual API for this — NotificationChannel.setBypassDnd()
  // — but it only takes effect for an app that holds "Notification policy
  // access", a protected permission only the user can grant (there's no
  // silent/automatic path to it, by design: it's the same permission class
  // that lets an app read or change the device's Do Not Disturb state).
  // AppBackgroundService/main.dart create LifeGuard360's alert channels
  // with bypassDnd: true once this is granted (see their _Dnd channel ids);
  // requestNotificationPolicyAccess() below is what actually gets there —
  // one grant, covering every alert channel, instead of a user having to
  // find and flip a toggle on each one individually in system settings.
  bool? _dndAccessGranted;

  Future<bool> _checkDndAccess() async {
    final granted = await _flnp
            .resolvePlatformSpecificImplementation<
                AndroidFlutterLocalNotificationsPlugin>()
            ?.hasNotificationPolicyAccess() ??
        false;
    if (mounted) setState(() => _dndAccessGranted = granted);
    return granted;
  }

  Future<void> _showDndGuidance() async {
    HapticFeedback.selectionClick();
    if (!mounted) return;
    final alreadyGranted = await _checkDndAccess();
    if (!mounted) return;

    if (alreadyGranted) {
      await showDialog(
        context: context,
        builder: (dialogContext) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text('Already granted'),
          content: const Text(
            'LifeGuard360 already has Do Not Disturb access — SOS, shake '
            'SOS, emergency report, and dispatcher alerts will sound and '
            'show even while your phone is in Do Not Disturb.',
            style: TextStyle(fontSize: 13.5, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('OK'),
            ),
          ],
        ),
      );
      return;
    }

    await showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Let alerts through Do Not Disturb'),
        content: const SingleChildScrollView(
          child: Text(
            'When your phone\'s Do Not Disturb is on, LifeGuard360\'s '
            'alerts — SOS, shake SOS, a family member\'s emergency report, '
            'dispatcher messages — arrive completely silently by default: '
            'no sound, no banner.\n\n'
            'Granting Do Not Disturb access below fixes this for all of '
            'them at once, in one tap on the next screen — no need to hunt '
            'down and flip a setting for each alert type individually.\n\n'
            'This only changes what LifeGuard360 itself can do — it does '
            'not turn Do Not Disturb on or off, and every other app is '
            'completely unaffected.',
            style: TextStyle(fontSize: 13.5, height: 1.4),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Not now'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.secondary,
              foregroundColor: Colors.white,
            ),
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _requestDndAccess();
            },
            child: const Text('Grant Access'),
          ),
        ],
      ),
    );
  }

  Future<void> _requestDndAccess() async {
    final androidPlugin = _flnp.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    try {
      await androidPlugin?.requestNotificationPolicyAccess();
    } catch (e) {
      debugPrint('⚠️ requestNotificationPolicyAccess: $e');
    }
    // The system settings screen this opens is a separate Activity, so
    // there's no result to await — didChangeAppLifecycleState's `resumed`
    // case (below) is what actually picks up whatever the user decided
    // once they come back, the same pattern _syncBubbleState already uses
    // for the overlay permission.
  }

  // Re-checks Do Not Disturb access and, if it was just granted, has
  // AppBackgroundService (re)create the alert channels immediately instead
  // of waiting for the next full app restart — see refreshAlertChannels's
  // doc comment for why a fresh grant needs a fresh channel id to actually
  // take effect.
  Future<void> _recheckDndAccessOnResume() async {
    final wasGranted = _dndAccessGranted;
    final granted = await _checkDndAccess();
    if (granted && wasGranted != true) {
      await AppBackgroundService.refreshAlertChannels();
      await refreshFcmChannel();
      if (mounted) {
        _showSnackBar(
          '✅ Do Not Disturb access granted — alerts will now break '
          'through.',
        );
      }
    }
  }

  void _showSnackBar(String message, {Color? color}) {
    ScaffoldMessenger.of(context)
      ..clearSnackBars()
      ..showSnackBar(
        SnackBar(
          content: Text(message),
          backgroundColor: color ?? AppColors.secondary,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          duration: const Duration(seconds: 4),
        ),
      );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Settings',
          style: TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.bold,
            fontSize: 19,
          ),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
          children: [
            _sectionHeader('General'),
            _card([
              // Not a real toggle: nothing in this app ever gates location
              // updates behind a preference, so a Switch here would let a
              // user believe they'd turned sharing off while it kept
              // running underneath — a false sense of privacy in a safety
              // app. Shown as a plain status row instead.
              _statusRow(
                Icons.location_on_outlined,
                'Location Sharing',
                'Always on — required for family safety features',
                badge: 'Always On',
                badgeColor: AppColors.success,
              ),
              _divider(),
              ValueListenableBuilder<bool>(
                valueListenable: OverlayService.enabledNotifier,
                builder: (context, sosBubbleOn, _) {
                  return SwitchListTile(
                    secondary: _icon(Icons.bubble_chart_outlined),
                    title: const Text(
                      'Floating SOS Bubble',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                    subtitle: const Text(
                      'Show a bubble over other apps. Tap it 5 times to '
                      'alert your family.',
                      style: TextStyle(fontSize: 12),
                    ),
                    value: sosBubbleOn,
                    onChanged: _bubbleBusy ? null : _toggleSosBubble,
                    activeColor: AppColors.danger,
                  );
                },
              ),
            ]),
            _sectionHeader('Family & Alerts'),
            _card([
              _tile(
                Icons.group_outlined,
                'Circle Management',
                'Manage your family and friends',
                onTap: _openCircleManagement,
                loading: _loadingCircle,
              ),
              _divider(),
              _tile(
                Icons.notifications_active_outlined,
                'Smart Notifications',
                'Customize your alerts',
                comingSoon: true,
              ),
              _divider(),
              _tile(
                Icons.do_not_disturb_on_outlined,
                'Do Not Disturb',
                _dndAccessGranted == true
                    ? 'Alerts already break through — tap for details'
                    : 'Make sure SOS and emergency alerts break through',
                onTap: _showDndGuidance,
              ),
              _divider(),
              _tile(
                Icons.history,
                'Report History',
                'Browse all family reports by date',
                onTap: _openReportHistory,
                loading: _loadingHistory,
              ),
              _divider(),
              _tile(
                Icons.contact_emergency_outlined,
                'Emergency Contacts',
                'Manage SOS contacts',
                onTap: () {
                  HapticFeedback.selectionClick();
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => AlertContactScreen(
                        userId: widget.userId,
                        userName: widget.userName,
                      ),
                    ),
                  );
                },
              ),
            ]),
            if (_authInfo != null &&
                _authInfo!['hasGoogle'] == true &&
                _authInfo!['hasPassword'] == false) ...[
              _sectionHeader('Account'),
              _card([
                _tile(
                  Icons.password_rounded,
                  'Set Account Password',
                  'Add a password so you can also log in without Google',
                  onTap: () {
                    HapticFeedback.selectionClick();
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => SetAccountPasswordScreen(
                          accountEmail: _authInfo!['email'] as String,
                        ),
                      ),
                    ).then((_) => _loadAuthInfo());
                  },
                ),
              ]),
            ],
            _sectionHeader('Support'),
            _card([
              _tile(Icons.help_outline, 'Help & Support', null,
                  comingSoon: true),
              _divider(),
              _tile(Icons.info_outline, 'About LifeGuard360', null,
                  onTap: () {
                HapticFeedback.selectionClick();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const _AboutScreen()),
                );
              }),
            ]),
            const SizedBox(height: 24),
            ElevatedButton.icon(
              onPressed: _confirmLogout,
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
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Logout ──────────────────────────────────────────────────────────────────

  void _confirmLogout() {
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
        ),
        title: const Row(
          children: [
            Icon(Icons.logout, color: AppColors.danger),
            SizedBox(width: 12),
            Text('Log Out'),
          ],
        ),
        content: const Text(
          'Are you sure you want to log out?',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('No'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _logout();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Yes'),
          ),
        ],
      ),
    );
  }

  Future<void> _logout() async {
    try {
      await OnlineStatusService.instance.logout();
    } catch (e) {
      debugPrint('⚠️ Error marking offline during logout: $e');
    }

    try {
      await AppBackgroundService.stop();
    } catch (e) {
      debugPrint('⚠️ Error stopping background service during logout: $e');
    }

    // Clear the stored session so SplashRouter's next cold-start check
    // (lib/main.dart) sees no userId and routes to LoginScreen instead of
    // straight back into the dashboard.
    try {
      final prefs = await SharedPreferences.getInstance();
      final familyCode = prefs.getString('familyCode') ?? '';
      // Drop the cached family/member list too — otherwise a different
      // account logging in on this same device would instant-paint from
      // this account's family data before its own fetch ever lands.
      if (familyCode.isNotEmpty) {
        await FamilyMembersCacheService.clear(familyCode);
      }
      await prefs.remove('userId');
      await prefs.remove('userName');
      await prefs.remove('familyCode');
    } catch (e) {
      debugPrint('⚠️ Error clearing session during logout: $e');
    }

    if (!mounted) return;
    Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
      MaterialPageRoute(builder: (_) => const LoginScreen()),
      (_) => false,
    );
  }

  // ── Helpers ─────────────────────────────────────────────────────────────────

  Widget _sectionHeader(String title) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 20, 6, 8),
        child: Text(
          title.toUpperCase(),
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.6,
            color: AppColors.textLight,
          ),
        ),
      );

  Widget _card(List<Widget> children) => Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(children: children),
      );

  Widget _divider() =>
      const Divider(height: 1, indent: 16, endIndent: 16, color: AppColors.lightGrey);

  Widget _icon(IconData icon, {Color? color}) => Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: (color ?? AppColors.secondary).withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Icon(icon, color: color ?? AppColors.secondary, size: 20),
      );

  Widget _statusRow(
    IconData icon,
    String title,
    String subtitle, {
    required String badge,
    required Color badgeColor,
  }) =>
      ListTile(
        leading: _icon(icon),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w500)),
        subtitle: Text(subtitle, style: const TextStyle(fontSize: 12)),
        trailing: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
          decoration: BoxDecoration(
            color: badgeColor.withOpacity(0.1),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: badgeColor.withOpacity(0.3)),
          ),
          child: Text(
            badge,
            style: TextStyle(
                fontSize: 11, fontWeight: FontWeight.bold, color: badgeColor),
          ),
        ),
      );

  Widget _tile(
    IconData icon,
    String title,
    String? subtitle, {
    VoidCallback? onTap,
    bool comingSoon = false,
    bool loading = false,
  }) {
    final disabled = comingSoon || (onTap == null && !loading);
    return ListTile(
      leading: _icon(icon, color: disabled ? AppColors.grey : null),
      title: Text(
        title,
        style: TextStyle(
          fontWeight: FontWeight.w500,
          fontSize: 14,
          color: disabled ? AppColors.grey : AppColors.textDark,
        ),
      ),
      subtitle: subtitle != null
          ? Text(subtitle,
              style: TextStyle(
                  fontSize: 12,
                  color: disabled ? AppColors.grey : AppColors.textLight))
          : null,
      trailing: loading
          ? const SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: AppColors.primary),
            )
          : comingSoon
              ? Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: AppColors.grey.withOpacity(0.12),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: const Text(
                    'Soon',
                    style: TextStyle(
                        fontSize: 10.5,
                        fontWeight: FontWeight.bold,
                        color: AppColors.grey),
                  ),
                )
              : const Icon(Icons.chevron_right,
                  size: 20, color: AppColors.grey),
      onTap: loading
          ? null
          : comingSoon
              ? () {
                  HapticFeedback.selectionClick();
                  _showSnackBar('$title is coming soon.');
                }
              : onTap,
    );
  }
}

// ── About screen ─────────────────────────────────────────────────────────────
// Static app-identity info only (name, version, purpose) — deliberately no
// fabricated support content or FAQ, since none exists elsewhere in the app.
class _AboutScreen extends StatelessWidget {
  const _AboutScreen();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'About',
          style: TextStyle(color: AppColors.secondary, fontWeight: FontWeight.bold),
        ),
      ),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: [
            const SizedBox(height: 16),
            Center(
              child: Container(
                width: 72,
                height: 72,
                decoration: const BoxDecoration(
                  color: AppColors.secondary,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.security, color: Colors.white, size: 36),
              ),
            ),
            const SizedBox(height: 16),
            const Center(
              child: Text(
                'LifeGuard360',
                style: TextStyle(
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary),
              ),
            ),
            const SizedBox(height: 4),
            const Center(
              child: Text(
                'Version 1.0.0',
                style: TextStyle(fontSize: 13, color: AppColors.textLight),
              ),
            ),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.04),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: const Text(
                'LifeGuard360 helps families stay connected and respond fast '
                'during emergencies — live location sharing, one-tap SOS '
                'alerts, and real-time emergency reporting for your circle.',
                style: TextStyle(fontSize: 13.5, color: AppColors.textDark, height: 1.5),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
