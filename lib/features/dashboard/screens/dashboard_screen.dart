import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/services.dart';
import 'package:qr_flutter/qr_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/photo_avatar.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../emergency/screens/emergency_selection_screen.dart';
import '../../map/screens/map_screen.dart';
import '../../map/screens/family_tracking_screen.dart';
import '../../auth/screens/settings_screen.dart';
import '../../contacts/screens/alert_contact_screen.dart';
import '../../safety/screens/safety_tips_screen.dart';
import '../../messages/screens/message_screen.dart';
import 'invite_members_screen.dart';
import 'join_family_member_screen.dart';
import 'profile_screen.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../../services/online_status_service.dart';
import '../../notifications/screens/notification_screen.dart';
import '../../../services/notification_count_service.dart';
import '../../emergency/screens/my_reports_screen.dart';
import '../../map/screens/member_directions_screen.dart';
import '../../../services/emergency_status_service.dart';

class DashboardScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const DashboardScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<DashboardScreen> createState() => _DashboardScreenState();
}

class _DashboardScreenState extends State<DashboardScreen>
    with RouteAware, WidgetsBindingObserver {
  int _selectedIndex = 0;
  int _unreadCount = 0;

  // Shake SOS detection itself lives solely in AppBackgroundService — it
  // runs continuously (foreground, backgrounded, or killed), so a second
  // *detector* here would double-fire on every shake (see
  // background_service.dart's TASK 6). What's below is purely a UI mirror:
  // while this screen is open, the background service tells us when its
  // cancel countdown starts/ends so we can show an in-app dialog instead of
  // (not in addition to) its notification-based one. Either UI writes to the
  // same 'shakeSosCancelled' flag the background service already polls, so
  // there remains exactly one authoritative cancel/confirm decision.
  StreamSubscription? _shakeStartedSub;
  StreamSubscription? _shakeEndedSub;
  BuildContext? _shakeDialogContext;

  // `mounted` alone isn't a reliable enough guard for the network calls the
  // 10s unread-count timer fires: cancelling the timer in dispose() only
  // stops FUTURE ticks, not a fetch already in flight when the widget is
  // disposed — that request can still resolve afterwards and call setState
  // on a defunct element. Set synchronously in dispose(), before anything
  // else, so every check against it is unambiguous.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    OnlineStatusService.instance.initialize(widget.userId);
    FirebaseService.startLocationTracking(widget.userId);
    _pollUnreadCount();

    // Start emergency status polling for this family
    _loadFamilyCodeAndStartPolling();

    FlutterBackgroundService().invoke('appForeground', {'foreground': true});
    _shakeStartedSub = FlutterBackgroundService()
        .on('shakeCountdownStarted')
        .listen((event) {
      final seconds = (event?['seconds'] as num?)?.toInt() ?? 10;
      _showShakeCancelDialog(seconds);
    });
    _shakeEndedSub =
        FlutterBackgroundService().on('shakeCountdownEnded').listen((_) {
      _dismissShakeCancelDialog();
    });
  }

  Future<void> _loadFamilyCodeAndStartPolling() async {
    final prefs = await SharedPreferences.getInstance();
    var familyCode = prefs.getString('familyCode') ?? '';
    if (familyCode.isEmpty) {
      final account = await FirebaseService.getUserById(widget.userId);
      familyCode = account?['familyCode']?.toString() ?? '';
    }
    if (familyCode.isNotEmpty) {
      EmergencyStatusService.instance.startPolling(familyCode);
    }
  }

  Timer? _unreadTimer;

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    FirebaseService.stopLocationTracking();
    _unreadTimer?.cancel();
    EmergencyStatusService.instance.dispose();
    FlutterBackgroundService().invoke('appForeground', {'foreground': false});
    _shakeStartedSub?.cancel();
    _shakeEndedSub?.cancel();
    super.dispose();
  }

  Future<void> _pollUnreadCount() async {
    await _refreshUnreadCount();
    _unreadTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshUnreadCount(),
    );
  }

  Future<void> _refreshUnreadCount() async {
    if (_disposed) return;
    try {
      final prefs = await SharedPreferences.getInstance();
      var familyCode = prefs.getString('familyCode') ?? '';
      if (familyCode.isEmpty) {
        final account = await FirebaseService.getUserById(widget.userId);
        familyCode = account?['familyCode']?.toString() ?? '';
      }
      if (_disposed) return;

      // throwOnError so a dropped poll lands in the catch below instead of
      // silently resolving to 0 — which would otherwise hide the badge on a
      // network hiccup even when there really are unread items.
      final unread = await NotificationCountService.unreadCount(
        userId: widget.userId,
        familyCode: familyCode,
        throwOnError: true,
      );

      if (!_disposed && mounted) setState(() => _unreadCount = unread);
    } catch (_) {
      // Leave _unreadCount as whatever it already was.
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    // Presence ("Online"/"Offline") is deliberately NOT touched here.
    // OnlineStatusService now tracks real network connectivity for the
    // whole session instead — backgrounding or closing the app must not
    // mark the user offline, or their last known location would look
    // stale/greyed-out on the family map the moment they leave the app.
    //
    // The in-app high-frequency Geolocator stream below is a different
    // concern: it's just the FOREGROUND location source, layered on top of
    // AppBackgroundService's own lower-frequency background tracking, which
    // keeps running regardless of this lifecycle callback.
    switch (state) {
      case AppLifecycleState.resumed:
        FirebaseService.startLocationTracking(widget.userId);
        FlutterBackgroundService()
            .invoke('appForeground', {'foreground': true});
        _unreadTimer ??= Timer.periodic(
          const Duration(seconds: 10),
          (_) => _refreshUnreadCount(),
        );
        _refreshUnreadCount(); // catch up immediately
        EmergencyStatusService.instance.resume();
        break;
      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
      case AppLifecycleState.hidden:
        FirebaseService.stopLocationTracking();
        FlutterBackgroundService()
            .invoke('appForeground', {'foreground': false});
        // Neither of these delivers real-time SOS/alerts on its own — that's
        // FCM push plus the background service, both unaffected by this.
        // These are just UI-refresh polls, so no point paying for the
        // network round-trip behind a screen nobody can see.
        _unreadTimer?.cancel();
        _unreadTimer = null;
        EmergencyStatusService.instance.pause();
        break;
      case AppLifecycleState.inactive:
        break;
    }
  }

  /// Mirrors AppBackgroundService's shake countdown as an in-app dialog.
  /// Cancelling here writes the same 'shakeSosCancelled' flag the background
  /// service's own notification-based countdown already polls every second
  /// — so cancelling through this popup also cancels the report AND that
  /// notification, without this screen ever deciding the outcome itself.
  void _showShakeCancelDialog(int totalSeconds) {
    if (!mounted || _shakeDialogContext != null) return;

    // The siren itself is played by AppBackgroundService, which is always
    // running (whether or not this dialog is showing) and keeps it looping
    // for the whole countdown, stopping only on cancel or once the report is
    // sent — see background_service.dart's TASK 6. This dialog is UI only.

    int secondsLeft = totalSeconds;
    StateSetter? dialogSetState;
    Timer? countdownTimer;

    // Shared by the CANCEL button and the system back gesture below — either
    // way of closing this dialog must count as cancelling the SOS, or the
    // background countdown (and its looping siren) would keep running with
    // no visible way left to stop it.
    Future<void> cancelShakeSos() async {
      countdownTimer?.cancel();
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('shakeSosCancelled', true);
      _popShakeDialog();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(children: [
              Icon(Icons.check_circle, color: Colors.white),
              SizedBox(width: 12),
              Text('SOS cancelled.', style: TextStyle(color: Colors.white)),
            ]),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        _shakeDialogContext = ctx;
        return PopScope(
          canPop: false,
          onPopInvokedWithResult: (didPop, result) {
            if (!didPop) cancelShakeSos();
          },
          child: StatefulBuilder(builder: (_, setState) {
          dialogSetState = setState;
          return AlertDialog(
            backgroundColor: const Color(0xFF1A1A2E),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Text('📳 ', style: TextStyle(fontSize: 24)),
              Text('Shake SOS',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ]),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Sending SOS in ${secondsLeft}s',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 22,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                const Text(
                  'Shake detected — tap CANCEL to abort.',
                  style: TextStyle(color: Colors.white60, fontSize: 14),
                ),
                const SizedBox(height: 16),
                LinearProgressIndicator(
                  value: secondsLeft / totalSeconds,
                  backgroundColor: Colors.white24,
                  color: Colors.redAccent,
                ),
              ],
            ),
            actions: [
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: cancelShakeSos,
                  icon: const Icon(Icons.cancel, color: Colors.white),
                  label: const Text('✋  CANCEL SOS',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.redAccent,
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10)),
                  ),
                ),
              ),
            ],
          );
          }),
        );
      },
    ).then((_) {
      countdownTimer?.cancel();
      _shakeDialogContext = null;
    });

    countdownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      secondsLeft--;
      if (secondsLeft <= 0) {
        timer.cancel();
        // Let the background service's own timer be what actually decides
        // and saves the report — this dialog just stops mirroring it once
        // its countdown reaches zero. The 'shakeCountdownEnded' event closes
        // it a moment later regardless, this just avoids sitting at "0s".
        _popShakeDialog();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(children: [
                Icon(Icons.warning_amber_rounded, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                    child: Text('🚨 Shake SOS triggered! Alerting your family…',
                        style: TextStyle(fontWeight: FontWeight.bold))),
              ]),
              backgroundColor: Color(0xFFCC0000),
              duration: Duration(seconds: 4),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
        return;
      }
      dialogSetState?.call(() {});
    });
  }

  void _dismissShakeCancelDialog() => _popShakeDialog();

  void _popShakeDialog() {
    final dialogContext = _shakeDialogContext;
    if (dialogContext == null) return;
    _shakeDialogContext = null;
    if (Navigator.of(dialogContext).canPop()) {
      Navigator.of(dialogContext).pop();
    }
  }

  void _onItemTapped(int index) {
    setState(() => _selectedIndex = index);
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> screens = [
      DashboardHome(userId: widget.userId, userName: widget.userName),
      MapScreen(
        userId: widget.userId,
        userName: widget.userName,
        showBackButton: false,
      ),
      _NotificationWrapper(userId: widget.userId),
      SettingsScreen(userId: widget.userId, userName: widget.userName),
    ];

    return Scaffold(
      backgroundColor: AppColors.canvas,
      body: IndexedStack(index: _selectedIndex, children: screens),
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
        onTap: _onItemTapped,
        type: BottomNavigationBarType.fixed,
        backgroundColor: Colors.white,
        selectedItemColor: AppColors.secondary,
        unselectedItemColor: AppColors.grey,
        selectedFontSize: 12,
        unselectedFontSize: 12,
        elevation: 0,
        items: [
          const BottomNavigationBarItem(
              icon: Icon(Icons.home, size: 28), label: 'Home'),
          const BottomNavigationBarItem(
              icon: Icon(Icons.map, size: 28), label: 'Map'),
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
              icon: Icon(Icons.settings_outlined, size: 28), label: 'Settings'),
        ],
      ),
    );
  }
}

class DashboardHome extends StatefulWidget {
  final String userId;
  final String userName;

  const DashboardHome({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<DashboardHome> createState() => _DashboardHomeState();
}

class _DashboardHomeState extends State<DashboardHome>
    with AutomaticKeepAliveClientMixin, WidgetsBindingObserver {
  String _familyCode = '';
  String _familyName = '';
  bool _isAdmin = false;
  List<Map<String, dynamic>> _familyMembers = [];
  bool _isLoading = true;

  // Store the user's name - will be updated from SharedPreferences
  String _displayName = '';

  // Emergency status tracking
  StreamController<Map<String, Set<String>>>? _emergencyStreamController;
  Set<String> _activeEmergencyUserIds = {};

  // Re-fetches Online/Offline + last-seen for the current member list.
  //
  // _loadMemberStatuses() previously only ran as part of _loadUserFamily(),
  // which only happens on initState, pull-to-refresh, or returning from a
  // few specific screens. So another member going online on their own
  // device never showed up here until this device's user manually pulled to
  // refresh — the online dot was really "online as of whenever I last
  // reloaded", not live. This timer keeps it live the same way
  // EmergencyStatusService already polls active emergencies.
  Timer? _memberStatusTimer;

  // `mounted` alone isn't a reliable enough guard for the network call the
  // 10s member-status timer fires: cancelling the timer in dispose() only
  // stops FUTURE ticks, not a refresh already in flight when the widget is
  // disposed — that request can still resolve afterwards and call setState
  // on a defunct element. Set synchronously in dispose(), before anything
  // else, so every check against it is unambiguous.
  bool _disposed = false;

  @override
  bool get wantKeepAlive => true;

  @override
  void initState() {
    super.initState();
    print('📱 DashboardHome initState');
    WidgetsBinding.instance.addObserver(this);
    _loadDisplayName();
    _loadUserFamily();
    _setupEmergencyStatusListener();
    _startMemberStatusPolling();
  }

  // Presence polling is only worth doing while the user can actually see the
  // result. Left running in the background it kept firing a network request
  // and a full setState() rebuild of the member list every 10 seconds behind
  // a screen nobody was looking at — pure battery and main-thread cost. The
  // background service keeps real presence/SOS delivery alive regardless of
  // this timer, so pausing it loses nothing.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (state == AppLifecycleState.resumed) {
      _startMemberStatusPolling();
      _refreshMemberStatuses(); // catch up immediately on return
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _memberStatusTimer?.cancel();
      _memberStatusTimer = null;
    }
  }

  void _startMemberStatusPolling() {
    _memberStatusTimer?.cancel();
    _memberStatusTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshMemberStatuses();
    });
  }

  /// Lightweight refresh: re-reads presence/location for the members already
  /// on screen without re-fetching the family/member list itself (that's
  /// what the full _loadUserFamily() reload is for).
  Future<void> _refreshMemberStatuses() async {
    if (_disposed || !mounted || _familyCode.isEmpty || _familyMembers.isEmpty) {
      return;
    }
    await _loadMemberStatuses(_familyMembers, _familyCode);
    if (!_disposed && mounted) setState(() {});
  }

  /// Load the user's name from SharedPreferences
  Future<void> _loadDisplayName() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString('userName') ?? widget.userName;
      if (mounted) {
        setState(() {
          _displayName = name;
        });
        print('📱 Loaded display name: $_displayName');
      }
    } catch (e) {
      print('❌ Error loading display name: $e');
      if (mounted) {
        setState(() {
          _displayName = widget.userName;
        });
      }
    }
  }

  void _setupEmergencyStatusListener() {
    print('🔴 Setting up emergency status listener');
    _emergencyStreamController =
        StreamController<Map<String, Set<String>>>.broadcast();
    EmergencyStatusService.instance.addListener(_emergencyStreamController!);
    _emergencyStreamController!.stream.listen((activeMap) {
      print('📢 Emergency status stream received update: $activeMap');
      if (mounted) {
        setState(() {
          _activeEmergencyUserIds = activeMap[_familyCode] ?? {};
          print('✅ Updated _activeEmergencyUserIds: $_activeEmergencyUserIds');
          print(
              '🎨 Family members should now show red for: $_activeEmergencyUserIds');
        });
      }
    });
  }

  @override
  void dispose() {
    print('📱 DashboardHome dispose');
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _memberStatusTimer?.cancel();
    if (_emergencyStreamController != null) {
      EmergencyStatusService.instance
          .removeListener(_emergencyStreamController!);
      _emergencyStreamController!.close();
    }
    super.dispose();
  }

  Future<void> _loadUserFamily() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    // getUserById swallows network errors and returns null on failure (see
    // FirebaseService.getUserById), so a plain offline cold start — no
    // earlier successful load in this session to fall back on — would
    // otherwise leave _familyCode at its empty default forever, showing
    // "No Family Yet" for a user who really is in one. Seed from the
    // familyCode/familyName persisted at login/join (see login_screen.dart)
    // before the network call, so this screen — and MyReportsScreen, which
    // keys its own local report cache off _familyCode — have the right
    // value to work with even when the account fetch below can't reach
    // Firebase at all.
    if (_familyCode.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      final cachedCode = prefs.getString('familyCode') ?? '';
      final cachedName = prefs.getString('familyName') ?? '';
      if (cachedCode.isNotEmpty && mounted) {
        setState(() {
          _familyCode = cachedCode;
          _familyName = cachedName;
        });
      }
    }

    try {
      final account = await FirebaseService.getUserById(widget.userId);
      if (account == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final familyCode = account['familyCode']?.toString() ?? '';
      print('📱 Loaded familyCode: "$familyCode"');

      if (familyCode.isEmpty) {
        if (mounted) {
          setState(() {
            _familyCode = '';
            _familyName = '';
            _isAdmin = false;
            _familyMembers = [];
            _isLoading = false;
          });
        }
        return;
      }

      final family = await FirebaseService.getFamilyByCode(familyCode);
      if (family == null) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final familyName = family['FamilyName']?.toString() ?? '';
      final createdBy = family['CreatedBy']?.toString() ?? '';
      final membersRaw = family['Members'];

      final List<Map<String, dynamic>> members = [];
      if (membersRaw != null && membersRaw is Map) {
        membersRaw.forEach((key, value) {
          if (value is Map) {
            members.add({
              'userId': value['UserId']?.toString() ?? key.toString(),
              'name': value['Name']?.toString() ?? 'Unknown',
              'role': value['Role']?.toString() ?? 'Member',
              'joinedAt': value['JoinedAt']?.toString() ?? '',
              'status': 'Online',
            });
          }
        });
      }

      members.sort((a, b) {
        if (a['userId'] == widget.userId) return -1;
        if (b['userId'] == widget.userId) return 1;
        if (a['role'] == 'Admin') return -1;
        if (b['role'] == 'Admin') return 1;
        return a['name'].compareTo(b['name']);
      });

      await _loadMemberStatuses(members, familyCode);

      // Started only NOW that we're about to set _familyCode, rather than
      // right after the family lookup several awaits above. Starting it
      // earlier raced _setupEmergencyStatusListener's stream handler: its
      // very first poll routinely resolved before _familyCode was actually
      // assigned below, so it read activeMap[_familyCode] against the OLD
      // (empty) value. Since EmergencyStatusService only notifies on a state
      // CHANGE, that wrong read was never corrected afterwards — a member
      // already mid-emergency at load time would silently never turn red.
      EmergencyStatusService.instance.startPolling(familyCode);

      if (mounted) {
        setState(() {
          _familyCode = familyCode;
          _familyName = familyName;
          _isAdmin = createdBy == widget.userId;
          _familyMembers = members;
          _isLoading = false;
          // Seeded directly rather than waiting on the next broadcast —
          // startPolling() above only fires that broadcast when its
          // cross-session cache disagrees with what it just fetched, which
          // it won't if an earlier mount of this screen already polled this
          // same family and nothing has changed since.
          _activeEmergencyUserIds =
              EmergencyStatusService.instance.getActiveEmergencyUserIds(familyCode);
        });
        // Keeps the offline fallback above current — so the NEXT cold start
        // falls back to this family, not whatever was last cached at
        // login/join, if the two have ever drifted.
        unawaited(SharedPreferences.getInstance().then(
            (prefs) => prefs.setString('familyName', familyName)));
        print('📱 Family members loaded: ${members.length} members');
        print('📱 Current user ID: ${widget.userId}');
        print('📱 Family members list: ${members.map((m) => m['userId'])}');
      }
    } catch (e) {
      print('❌ Error loading family: $e');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadMemberStatuses(
      List<Map<String, dynamic>> members, String familyCode) async {
    try {
      // throwOnError so a network failure actually reaches this catch block
      // instead of silently resolving as an empty list — without it, the
      // loop below would overwrite every member's real photo/status/location
      // with the 'Offline'/blank defaults on a single dropped poll, exactly
      // like MyReportsScreen's data used to before the same fix there.
      final membersWithLocations =
          await FirebaseService.getFamilyMembersWithLocations(familyCode,
              throwOnError: true);

      final statusMap = <String, String>{};
      final lastSeenMap = <String, String>{};
      final latMap = <String, double?>{};
      final lngMap = <String, double?>{};
      final locUpdatedMap = <String, String>{};
      final photoMap = <String, String>{};

      for (final m in membersWithLocations) {
        final id = m['userId']?.toString() ?? '';
        statusMap[id] = m['onlineStatus']?.toString() ?? 'Offline';
        lastSeenMap[id] = m['lastSeen']?.toString() ?? '';
        latMap[id] =
            m['latitude'] != null ? (m['latitude'] as num).toDouble() : null;
        lngMap[id] =
            m['longitude'] != null ? (m['longitude'] as num).toDouble() : null;
        locUpdatedMap[id] = m['lastUpdated']?.toString() ?? '';
        photoMap[id] = m['photoUrl']?.toString() ?? '';
      }

      for (final member in members) {
        final id = member['userId']?.toString() ?? '';
        member['status'] = statusMap[id] ?? 'Offline';
        member['lastSeen'] = lastSeenMap[id] ?? '';
        member['latitude'] = latMap[id];
        member['longitude'] = lngMap[id];
        member['locationUpdated'] = locUpdatedMap[id] ?? '';
        // Each member's OWN photo, keyed by their own userId — never the
        // current (logged-in) user's photo.
        member['photoUrl'] = photoMap[id] ?? '';
      }
    } catch (e) {
      print('⚠️ Could not load member statuses: $e');
    }
  }

  // "Add Member" here really means "invite a new member" — there's no real
  // account-creation-on-someone-else's-behalf mechanism anywhere in this
  // app's Firebase layer (see InviteMembersScreen/JoinFamilyScreen: a new
  // member always signs up with their own account, then joins using the
  // family code). This used to open AddFamilyMemberScreen, which collected
  // a name/email and tried to "add" them directly against a mock service
  // that was never connected to Firebase — it could never have worked for a
  // real user. Routing to the same InviteMembersScreen the Profile screen's
  // "Invite Members" action already uses correctly shares the real code/QR.
  Future<void> _navigateToAddMember() async {
    if (_familyCode.isEmpty) {
      _showNoFamilyDialog();
      return;
    }
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => InviteMembersScreen(
          familyId: _familyCode,
          familyCode: _familyCode,
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }

  Future<void> _navigateToJoinFamily() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => JoinFamilyScreen(
          userId: widget.userId,
          userName: widget.userName,
          userEmail: '${widget.userName.toLowerCase()}@example.com',
        ),
      ),
    );
    if (result == true) await _loadUserFamily();
  }

  Future<void> _navigateToProfile() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
    // Reload the display name from SharedPreferences after returning from profile
    await _loadDisplayName();
    // Also reload family data to refresh the member list
    _loadUserFamily();
  }

  Future<void> _navigateToMessages() async {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MessageScreen(
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }

  void _showNoFamilyDialog() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Row(children: [
          Icon(Icons.info_outline, color: AppColors.primary),
          SizedBox(width: 12),
          Text('No Family Found'),
        ]),
        content: const Text(
          'You need to join or create a family first before adding members.',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel')),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _navigateToJoinFamily();
            },
            child: const Text('Join Family'),
          ),
        ],
      ),
    );
  }

  void _showMemberOptionsDialog() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text('Family Options',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary)),
            const SizedBox(height: 24),
            if (_familyCode.isEmpty) ...[
              _buildOptionItem(
                icon: Icons.group_add,
                title: 'Join Family',
                subtitle: 'Join an existing family circle',
                color: AppColors.primary,
                onTap: () {
                  Navigator.pop(context);
                  _navigateToJoinFamily();
                },
              ),
            ] else ...[
              _buildOptionItem(
                icon: Icons.person_add_alt_1,
                title: 'Add Member',
                subtitle: 'Invite a new family member',
                color: AppColors.primary,
                onTap: () {
                  Navigator.pop(context);
                  _navigateToAddMember();
                },
              ),
              const SizedBox(height: 12),
              _buildOptionItem(
                icon: Icons.qr_code,
                title: 'Show Family Code',
                subtitle: 'Share code: $_familyCode',
                color: AppColors.success,
                onTap: () {
                  Navigator.pop(context);
                  _showFamilyCodeDialog();
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  void _showFamilyCodeDialog() {
    showDialog(
      context: context,
      barrierDismissible: true,
      builder: (_) => _FamilyCodeDialog(
        familyCode: _familyCode,
        familyName: _familyName,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    super.build(context);
    // The header's dark gradient bleeds up behind the status bar (see
    // SafeArea(top: false) below), so the system's default DARK status-bar
    // icons became invisible against it — force light/white icons here to
    // match. Scoped to just this screen: the other bottom-nav tabs sit on
    // light backgrounds and still want the default dark icons, and since
    // IndexedStack only paints the active child, this AnnotatedRegion only
    // takes effect while Home is the visible tab.
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.canvas,
        // top: false so the gradient hero bleeds behind the status bar — the
        // header adds the inset back as padding itself.
        body: SafeArea(
          top: false,
          bottom: false,
          child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
                onRefresh: _loadUserFamily,
                child: CustomScrollView(
                  // Bouncing physics carries momentum through the whole
                  // gesture instead of stopping dead at the edges, which is
                  // what makes the scroll feel smooth rather than abrupt.
                  physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics(),
                  ),
                  slivers: [
                    SliverToBoxAdapter(
                      child: RepaintBoundary(child: _buildHeader()),
                    ),
                    SliverPersistentHeader(
                      pinned: true,
                      delegate: _StickyReportsDelegate(
                        child: _buildMyReportsCard(),
                      ),
                    ),
                    SliverToBoxAdapter(
                      child: Column(
                        children: [
                          RepaintBoundary(child: _buildSOSCard()),
                          const SizedBox(height: 22),
                          _buildFamilyMembersCard(),
                          const SizedBox(height: 22),
                          RepaintBoundary(child: _buildQuickActions()),
                          const SizedBox(height: 24),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
        ),
      ),
    );
  }

  /// Gradient hero: app bar row + greeting, sharing the same palette as the
  /// login / sign-up screens so the app reads as one product.
  Widget _buildHeader() {
    // Use the name from SharedPreferences if available, otherwise fallback
    final displayName =
        _displayName.isNotEmpty ? _displayName : widget.userName;
    final hasFamily = _familyName.isNotEmpty;

    return Container(
      padding: EdgeInsets.fromLTRB(
        16,
        MediaQuery.of(context).padding.top + 12,
        16,
        22,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [AppColors.secondary, AppColors.primary],
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(28)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.18),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.shield_rounded,
                    color: Colors.white, size: 22),
              ),
              const SizedBox(width: 10),
              const Text('LifeGuard360',
                  style: TextStyle(
                      fontSize: 19,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
              const Spacer(),
              _headerIconButton(
                icon: Icons.message_outlined,
                tooltip: 'Messages',
                onTap: _navigateToMessages,
              ),
              const SizedBox(width: 10),
              _headerIconButton(
                icon: Icons.person_outline_rounded,
                tooltip: 'Profile',
                onTap: _navigateToProfile,
              ),
            ],
          ),
          const SizedBox(height: 22),
          Text(
            'Hi $displayName!',
            style: const TextStyle(
              fontSize: 26,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              height: 1.1,
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Flexible(
                child: Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        hasFamily
                            ? Icons.family_restroom_rounded
                            : Icons.group_add_outlined,
                        color: Colors.white,
                        size: 16,
                      ),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(
                          hasFamily
                              ? '$_familyName Family'
                              : 'No family yet — join or create one',
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            fontSize: 13,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (_familyCode.isNotEmpty) ...[
                const SizedBox(width: 8),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.16),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(Icons.qr_code_rounded,
                          color: Colors.white, size: 15),
                      const SizedBox(width: 6),
                      Text(
                        _familyCode,
                        style: const TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w600,
                          fontSize: 13,
                          letterSpacing: 0.4,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }

  Widget _headerIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: Colors.white.withOpacity(0.18),
        shape: const CircleBorder(),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.all(9),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
        ),
      ),
    );
  }

  /// The app's primary action. Emergency reporting is the whole point of the
  /// product, so it gets full width, the danger colour and the largest tap
  /// target on the screen rather than the small neutral button it had before.
  Widget _buildSOSCard() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(18),
        elevation: 6,
        shadowColor: AppColors.danger.withOpacity(0.45),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => EmergencySelectionScreen(
                userId: widget.userId,
                userName: widget.userName,
              ),
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.22),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.sos_rounded,
                      color: Colors.white, size: 26),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Report an Emergency',
                          style: TextStyle(
                              color: Colors.white,
                              fontSize: 17,
                              fontWeight: FontWeight.bold)),
                      SizedBox(height: 2),
                      Text('Alert your family and responders now',
                          style:
                              TextStyle(color: Colors.white70, fontSize: 12)),
                    ],
                  ),
                ),
                const Icon(Icons.arrow_forward_rounded,
                    color: Colors.white, size: 22),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildFamilyMembersCard() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 15,
              offset: const Offset(0, 4))
        ],
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Row(
              children: [
                const Text('Family Members',
                    style: TextStyle(
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary)),
                const Spacer(),
                if (_familyMembers.isNotEmpty)
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Text(
                      '${_familyMembers.length}',
                      style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.success,
                          fontWeight: FontWeight.bold),
                    ),
                  ),
              ],
            ),
          ),
          if (_familyName.isNotEmpty)
            Container(
              margin: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.primary.withOpacity(0.12),
                    AppColors.primary.withOpacity(0.05),
                  ],
                ),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.primary.withOpacity(0.25)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.family_restroom,
                      color: AppColors.primary, size: 20),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      '$_familyName Family',
                      style: const TextStyle(
                          fontSize: 15,
                          fontWeight: FontWeight.bold,
                          color: AppColors.primary),
                    ),
                  ),
                  if (_isAdmin)
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 3),
                      decoration: BoxDecoration(
                        color: Colors.amber.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.star, color: Colors.amber, size: 12),
                          SizedBox(width: 4),
                          Text('Admin',
                              style: TextStyle(
                                  fontSize: 11,
                                  color: Colors.amber,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 12),
          if (_familyMembers.isEmpty)
            _buildEmptyFamilyState()
          else
            _buildMembersList(),
          _buildAddMemberButton(),
        ],
      ),
    );
  }

  Widget _buildEmptyFamilyState() {
    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        children: [
          Icon(Icons.people_outline,
              size: 64, color: AppColors.grey.withOpacity(0.3)),
          const SizedBox(height: 16),
          Text(
            _familyCode.isEmpty ? 'No Family Yet' : 'No Members Yet',
            style: const TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary),
          ),
          const SizedBox(height: 8),
          Text(
            _familyCode.isEmpty
                ? 'Join or create a family to get started'
                : 'Add family members to start tracking',
            textAlign: TextAlign.center,
            style: const TextStyle(fontSize: 14, color: AppColors.textLight),
          ),
        ],
      ),
    );
  }

  // Height of roughly 3 member cards (each ~95dp including its bottom
  // margin) — the card shows this many at a glance and scrolls internally
  // for the rest, so a long family list no longer pushes everything below
  // it (Add Member button, etc.) far down the page.
  static const double _memberListHeight = 290;

  Widget _buildMembersList() {
    final needsScroll = _familyMembers.length > 3;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: SizedBox(
        height: needsScroll
            ? _memberListHeight
            : null,
        child: needsScroll
            ? ListView.builder(
                padding: EdgeInsets.zero,
                itemCount: _familyMembers.length,
                itemBuilder: (context, index) {
                  final member = _familyMembers[index];
                  return RepaintBoundary(
                    child: _buildMemberItem(
                      member,
                      member['userId'] == widget.userId,
                      _activeEmergencyUserIds.contains(member['userId']),
                    ),
                  );
                },
              )
            : Column(
                children: [
                  for (final member in _familyMembers)
                    RepaintBoundary(
                      child: _buildMemberItem(
                        member,
                        member['userId'] == widget.userId,
                        _activeEmergencyUserIds.contains(member['userId']),
                      ),
                    ),
                ],
              ),
      ),
    );
  }

  /// Renders a member's own saved profile photo (BoxFit.cover, clipped to
  /// the circle) when they have one, falling back to the initials avatar
  /// when they don't, or when the stored photo data is missing/corrupt.
  Widget _buildMemberAvatar({
    required String name,
    required String photoUrl,
    required Color backgroundColor,
    required Color textColor,
  }) {
    final initials = Text(
      name.isNotEmpty ? name[0].toUpperCase() : '?',
      style: TextStyle(
        color: textColor,
        fontWeight: FontWeight.bold,
        fontSize: 18,
      ),
    );

    // This list rebuilds on a 10-second presence poll — PhotoAvatar caches
    // the decoded base64 bytes (PhotoCache) or the fetched network image
    // (CachedNetworkImage) so that rebuild never re-does the actual photo
    // work, only the cheap lookup.
    return CircleAvatar(
      radius: 24,
      backgroundColor: backgroundColor,
      child: ClipOval(
        child: PhotoAvatar(photoUrl: photoUrl, size: 48, initials: initials),
      ),
    );
  }

  Widget _buildMemberItem(
      Map<String, dynamic> member, bool isCurrentUser, bool isInEmergency) {
    final name = member['name']?.toString() ?? 'Unknown';
    final role = member['role']?.toString() ?? 'Member';
    final status = member['status']?.toString() ?? 'Offline';
    final lastSeen = member['lastSeen']?.toString() ?? '';
    final locationUpdated = member['locationUpdated']?.toString() ?? '';
    final lat = member['latitude'] as double?;
    final lng = member['longitude'] as double?;
    // This member's OWN saved photo — looked up by THEIR userId
    // (Family Circle → member userId → that user's Account → PhotoUrl),
    // never the currently logged-in user's photo.
    final photoUrl = member['photoUrl']?.toString() ?? '';
    final isOnline = status == 'Online';
    final isAdmin = role == 'Admin';
    final hasLocation = lat != null && lng != null;

    // Emergency styling
    final emergencyColor = isInEmergency ? AppColors.danger : null;
    final backgroundColor = isInEmergency
        ? AppColors.danger.withOpacity(0.12)
        : isCurrentUser
            ? AppColors.primary.withOpacity(0.05)
            : AppColors.lightGrey;
    final borderColor = isInEmergency
        ? AppColors.danger
        : isCurrentUser
            ? AppColors.primary.withOpacity(0.2)
            : Colors.transparent;
    final borderWidth = isInEmergency ? 2.0 : (isCurrentUser ? 2.0 : 0.0);
    final nameColor = isInEmergency ? AppColors.danger : AppColors.secondary;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: isCurrentUser
            ? null
            : () {
                if (!hasLocation) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(
                      content: Text('$name has not shared their location yet.'),
                      backgroundColor: Colors.orange,
                      behavior: SnackBarBehavior.floating,
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10)),
                    ),
                  );
                  return;
                }
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MemberDirectionsScreen(
                      memberName: name,
                      memberRole: role,
                      memberLat: lat!,
                      memberLng: lng!,
                      locationUpdated: locationUpdated,
                      isOnline: isOnline,
                    ),
                  ),
                );
              },
        child: Container(
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: backgroundColor,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: borderColor, width: borderWidth),
          ),
          child: Row(
            children: [
              Stack(
                children: [
                  _buildMemberAvatar(
                    name: name,
                    photoUrl: photoUrl,
                    backgroundColor: isInEmergency
                        ? AppColors.danger.withOpacity(0.2)
                        : isCurrentUser
                            ? AppColors.primary.withOpacity(0.2)
                            : AppColors.grey.withOpacity(0.2),
                    textColor: isInEmergency
                        ? AppColors.danger
                        : isCurrentUser
                            ? AppColors.primary
                            : AppColors.secondary,
                  ),
                  Positioned(
                    right: 0,
                    bottom: 0,
                    child: Container(
                      width: 14,
                      height: 14,
                      decoration: BoxDecoration(
                        color: isOnline ? Colors.green : Colors.grey,
                        shape: BoxShape.circle,
                        border: Border.all(color: Colors.white, width: 2),
                      ),
                    ),
                  ),
                ],
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
                            name,
                            style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 15,
                                color: nameColor),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isInEmergency) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                              color: AppColors.danger,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.warning_amber_rounded,
                                    color: Colors.white, size: 12),
                                SizedBox(width: 4),
                                Text('EMERGENCY',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.white,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                        if (isCurrentUser) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.primary,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Text('You',
                                style: TextStyle(
                                    fontSize: 9,
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                          ),
                        ],
                        if (isAdmin && !isCurrentUser) ...[
                          const SizedBox(width: 6),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.amber.withOpacity(0.2),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.star, color: Colors.amber, size: 10),
                                SizedBox(width: 2),
                                Text('Admin',
                                    style: TextStyle(
                                        fontSize: 9,
                                        color: Colors.amber,
                                        fontWeight: FontWeight.bold)),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          isOnline ? 'Online' : 'Offline',
                          style: TextStyle(
                            color: isOnline ? Colors.green : AppColors.grey,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                        if (!isOnline && lastSeen.isNotEmpty) ...[
                          const SizedBox(width: 4),
                          Flexible(
                            child: Text(
                              '· Last seen: $lastSeen',
                              style: const TextStyle(
                                  fontSize: 11, color: AppColors.textLight),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    if (!isCurrentUser) ...[
                      const SizedBox(height: 3),
                      Row(
                        children: [
                          Icon(
                            hasLocation ? Icons.directions : Icons.location_off,
                            size: 11,
                            color: hasLocation
                                ? AppColors.primary
                                : AppColors.grey,
                          ),
                          const SizedBox(width: 3),
                          Text(
                            hasLocation
                                ? 'Tap for directions'
                                : 'No location yet',
                            style: TextStyle(
                              fontSize: 10,
                              color: hasLocation
                                  ? AppColors.primary
                                  : AppColors.grey,
                              fontWeight: hasLocation
                                  ? FontWeight.w600
                                  : FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  if (role.isNotEmpty && role != 'Admin')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: isInEmergency
                            ? AppColors.danger.withOpacity(0.2)
                            : AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(role,
                          style: TextStyle(
                              fontSize: 11,
                              color: isInEmergency
                                  ? AppColors.danger
                                  : AppColors.primary,
                              fontWeight: FontWeight.w600)),
                    ),
                  const SizedBox(height: 6),
                  if (isCurrentUser)
                    Icon(Icons.location_on,
                        color: isInEmergency
                            ? AppColors.danger
                            : AppColors.primary,
                        size: 20)
                  else
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        color: hasLocation
                            ? (isInEmergency
                                ? AppColors.danger.withOpacity(0.1)
                                : AppColors.primary.withOpacity(0.1))
                            : AppColors.lightGrey,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Icon(
                        hasLocation ? Icons.directions : Icons.location_off,
                        size: 18,
                        color: hasLocation
                            ? (isInEmergency
                                ? AppColors.danger
                                : AppColors.primary)
                            : AppColors.grey,
                      ),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAddMemberButton() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: const BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.lightGrey, width: 1)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          CustomButton(
            text: _familyCode.isEmpty ? 'Join or Add Family' : 'Add Member',
            icon:
                _familyCode.isEmpty ? Icons.group_add : Icons.person_add_alt_1,
            onPressed: _showMemberOptionsDialog,
            fitContent: true,
            color: Colors.transparent,
            textColor: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildOptionItem({
    required IconData icon,
    required String title,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: color.withOpacity(0.1),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: color.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                  color: color, borderRadius: BorderRadius.circular(10)),
              child: Icon(icon, color: Colors.white, size: 24),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(title,
                      style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary)),
                  const SizedBox(height: 2),
                  Text(subtitle,
                      style: const TextStyle(
                          fontSize: 12, color: AppColors.textLight)),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios, size: 16, color: color),
          ],
        ),
      ),
    );
  }

  Widget _buildQuickActions() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.only(left: 4, bottom: 12),
            child: Text('Quick Actions',
                style: TextStyle(
                    fontSize: 17,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary)),
          ),
          Row(
            children: [
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.map_outlined,
                  label: 'Track Family',
                  color: AppColors.primary,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => FamilyTrackingScreen(
                        currentUserId: widget.userId,
                        currentUserName: widget.userName,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.contact_phone_outlined,
                  label: 'Alert Contact',
                  color: AppColors.danger,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => const AlertContactScreen()),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _buildQuickActionCard(
                  icon: Icons.lightbulb_outline,
                  label: 'Safety Tips',
                  color: AppColors.success,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const SafetyTipsScreen()),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildQuickActionCard({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.12),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 8),
          child: Column(
            children: [
              Container(
                padding: const EdgeInsets.all(11),
                decoration: BoxDecoration(
                  color: color.withOpacity(0.12),
                  shape: BoxShape.circle,
                ),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(height: 10),
              Text(label,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w600,
                      color: AppColors.secondary)),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMyReportsCard() {
    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => MyReportsScreen(
            userId: widget.userId,
            userName: widget.userName,
            familyCode: _familyCode,
          ),
        ),
      ),
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            colors: [AppColors.primary, AppColors.accent],
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
          ),
          borderRadius: BorderRadius.circular(14),
          boxShadow: [
            BoxShadow(
              color: AppColors.primary.withOpacity(0.25),
              blurRadius: 10,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.assignment_outlined,
                  color: Colors.white, size: 26),
            ),
            const SizedBox(width: 14),
            const Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('My Emergency Reports',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.bold)),
                  SizedBox(height: 2),
                  Text('Track status of your submitted reports',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                ],
              ),
            ),
            const Icon(Icons.arrow_forward_ios,
                color: Colors.white70, size: 16),
          ],
        ),
      ),
    );
  }
}

// Sticky delegate
class _StickyReportsDelegate extends SliverPersistentHeaderDelegate {
  final Widget child;
  const _StickyReportsDelegate({required this.child});

  static const double _height = 110.0;

  @override
  double get minExtent => _height;
  @override
  double get maxExtent => _height;

  @override
  Widget build(
      BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: AppColors.canvas,
      foregroundDecoration: overlapsContent
          ? const BoxDecoration(
              boxShadow: [
                BoxShadow(
                  color: Color(0x18000000),
                  blurRadius: 6,
                  offset: Offset(0, 3),
                ),
              ],
            )
          : null,
      padding: const EdgeInsets.fromLTRB(0, 8, 0, 16),
      child: child,
    );
  }

  @override
  bool shouldRebuild(_StickyReportsDelegate old) => old.child != child;
}

class _FamilyCodeDialog extends StatefulWidget {
  final String familyCode;
  final String familyName;

  const _FamilyCodeDialog({
    required this.familyCode,
    required this.familyName,
  });

  @override
  State<_FamilyCodeDialog> createState() => _FamilyCodeDialogState();
}

class _FamilyCodeDialogState extends State<_FamilyCodeDialog>
    with SingleTickerProviderStateMixin {
  late TabController _tab;
  bool _copied = false;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  void _copyCode() {
    Clipboard.setData(ClipboardData(text: widget.familyCode));
    setState(() => _copied = true);
    Future.delayed(const Duration(seconds: 2), () {
      if (mounted) setState(() => _copied = false);
    });
  }

  void _showFullScreenQr() {
    Navigator.pop(context);
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (_) => GestureDetector(
        onTap: () => Navigator.pop(context),
        child: Scaffold(
          backgroundColor: Colors.transparent,
          body: Center(
            child: GestureDetector(
              onTap: () {},
              child: Container(
                margin: const EdgeInsets.all(24),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(24),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        const Spacer(),
                        IconButton(
                          onPressed: () => Navigator.pop(context),
                          icon: const Icon(Icons.close,
                              color: AppColors.secondary),
                        ),
                      ],
                    ),
                    const Text(
                      'Scan to Join Family',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      widget.familyName,
                      style: const TextStyle(
                        fontSize: 14,
                        color: AppColors.textLight,
                      ),
                    ),
                    const SizedBox(height: 24),
                    QrImageView(
                      data: widget.familyCode,
                      version: QrVersions.auto,
                      size: 260,
                      backgroundColor: Colors.white,
                      eyeStyle: const QrEyeStyle(
                        eyeShape: QrEyeShape.square,
                        color: AppColors.secondary,
                      ),
                      dataModuleStyle: const QrDataModuleStyle(
                        dataModuleShape: QrDataModuleShape.square,
                        color: AppColors.primary,
                      ),
                    ),
                    const SizedBox(height: 20),
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 24, vertical: 12),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.08),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: AppColors.primary.withOpacity(0.25)),
                      ),
                      child: Text(
                        widget.familyCode,
                        style: const TextStyle(
                          fontSize: 30,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 10,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Text(
                      'Tap anywhere outside to close',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textLight),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      backgroundColor: Colors.white,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 40),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            padding: const EdgeInsets.fromLTRB(20, 20, 8, 0),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: AppColors.primary.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: const Icon(Icons.group,
                      color: AppColors.primary, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Family Invite',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                        ),
                      ),
                      if (widget.familyName.isNotEmpty)
                        Text(
                          widget.familyName,
                          style: const TextStyle(
                              fontSize: 12, color: AppColors.textLight),
                        ),
                    ],
                  ),
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: AppColors.grey),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.splashBackground,
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.all(4),
              child: TabBar(
                controller: _tab,
                indicator: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(10),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.08),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                indicatorSize: TabBarIndicatorSize.tab,
                labelColor: AppColors.primary,
                unselectedLabelColor: AppColors.grey,
                labelStyle:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                unselectedLabelStyle:
                    const TextStyle(fontWeight: FontWeight.w500, fontSize: 13),
                dividerColor: Colors.transparent,
                tabs: const [
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.tag, size: 16),
                        SizedBox(width: 6),
                        Text('Code'),
                      ],
                    ),
                  ),
                  Tab(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.qr_code_2, size: 16),
                        SizedBox(width: 6),
                        Text('QR Code'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(
            height: 260,
            child: TabBarView(
              controller: _tab,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Text(
                        'Share this code with family members',
                        textAlign: TextAlign.center,
                        style:
                            TextStyle(fontSize: 13, color: AppColors.textLight),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(
                            vertical: 22, horizontal: 16),
                        decoration: BoxDecoration(
                          color: AppColors.primary.withOpacity(0.07),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: AppColors.primary.withOpacity(0.3),
                            width: 2,
                          ),
                        ),
                        child: Text(
                          widget.familyCode.isNotEmpty
                              ? widget.familyCode
                              : '------',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 40,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 12,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 16),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _copyCode,
                          icon: Icon(
                            _copied ? Icons.check : Icons.copy,
                            size: 18,
                          ),
                          label: Text(_copied ? 'Copied!' : 'Copy Code'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor:
                                _copied ? AppColors.success : AppColors.primary,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 13),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(color: AppColors.lightGrey),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.05),
                              blurRadius: 8,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: QrImageView(
                          data: widget.familyCode,
                          version: QrVersions.auto,
                          size: 150,
                          backgroundColor: Colors.white,
                          eyeStyle: const QrEyeStyle(
                            eyeShape: QrEyeShape.square,
                            color: AppColors.secondary,
                          ),
                          dataModuleStyle: const QrDataModuleStyle(
                            dataModuleShape: QrDataModuleShape.square,
                            color: AppColors.primary,
                          ),
                        ),
                      ),
                      const SizedBox(height: 14),
                      SizedBox(
                        width: double.infinity,
                        child: OutlinedButton.icon(
                          onPressed: _showFullScreenQr,
                          icon: const Icon(Icons.fullscreen, size: 18),
                          label: const Text('Full Screen'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.08),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, size: 16, color: Colors.amber),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Member opens app → Join Family → enter code or scan QR',
                      style: TextStyle(
                          fontSize: 11,
                          color: AppColors.textLight,
                          height: 1.4),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ], // <-- FIXED: closes Column's children list
      ), // closes Column(...)
    ); // closes Dialog(...)
  }
}

class _NotificationWrapper extends StatefulWidget {
  final String userId;
  const _NotificationWrapper({required this.userId});
  @override
  State<_NotificationWrapper> createState() => _NotificationWrapperState();
}

class _NotificationWrapperState extends State<_NotificationWrapper> {
  String _familyCode = '';
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  Future<void> _resolve() async {
    final prefs = await SharedPreferences.getInstance();
    var code = prefs.getString('familyCode') ?? '';
    if (code.isEmpty) {
      final account = await FirebaseService.getUserById(widget.userId);
      code = account?['familyCode']?.toString() ?? '';
      if (code.isNotEmpty) await prefs.setString('familyCode', code);
    }
    if (mounted)
      setState(() {
        _familyCode = code;
        _ready = true;
      });
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready)
      return const Center(
          child: CircularProgressIndicator(color: AppColors.primary));
    return NotificationScreen(
      userId: widget.userId,
      familyCode: _familyCode,
      showBackButton: false,
    );
  }
}
