// lib/features/notifications/screens/notification_screen.dart
//
// ADDED: Back button in AppBar for navigation.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/emergency_report_service.dart';
import '../../map/screens/family_tracking_screen.dart';

const String _kDbUrl =
    'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

class NotificationScreen extends StatefulWidget {
  final String userId;
  final String familyCode;

  /// Whether to show the top-left back button. Set to false when this
  /// screen is embedded as a bottom-nav tab (e.g. inside an IndexedStack)
  /// rather than pushed onto the Navigator — popping in that case would
  /// pop the host screen's own route instead of just switching tabs,
  /// leaving a black screen behind.
  final bool showBackButton;

  const NotificationScreen({
    super.key,
    required this.userId,
    required this.familyCode,
    this.showBackButton = true,
  });

  @override
  State<NotificationScreen> createState() => _NotificationScreenState();
}

class _NotificationScreenState extends State<NotificationScreen>
    with WidgetsBindingObserver {
  // ── Emergency reports state ───────────────────────────────────────────────
  List<Map<String, dynamic>> _reports = [];
  Set<String> _readIds = {};
  Set<String> _deletedIds = {};
  bool _isLoading = true;

  // ── Witness requests state ────────────────────────────────────────────────
  List<Map<String, dynamic>> _witnessRequests = [];
  Set<String> _acknowledgedWitnessIds = {};

  // ── Dispatcher acknowledge-messages state ─────────────────────────────────
  // Reports the user submitted that a dispatcher has acknowledged with a
  // message — surfaced here so the reporter sees it was picked up, not just
  // as a one-off push banner.
  List<Map<String, dynamic>> _dispatcherMessages = [];
  Set<String> _readDispatcherMsgIds = {};
  Set<String> _deletedDispatcherMsgIds = {};

  // ── Resolved-report state ─────────────────────────────────────────────────
  // Reports the user submitted that a responder or administrator has closed
  // out. Kept separate from the family-report feed above: that one is about
  // what other members reported, this one is the outcome of the user's own
  // reports.
  List<Map<String, dynamic>> _resolvedReports = [];
  Set<String> _readResolvedIds = {};
  Set<String> _deletedResolvedIds = {};

  // ── Responder-assignment state ────────────────────────────────────────────
  // Reports the dispatcher has put a responder on ('Acknowledged'), so the
  // reporter knows someone is actually on their way.
  List<Map<String, dynamic>> _assignedReports = [];
  Set<String> _readAssignedIds = {};
  Set<String> _deletedAssignedIds = {};

  // The responder's name and assignment time live only on the canonical
  // /{reportLabel}/{reportId} record, not on the reporter's index entry, so
  // they're fetched once per report and cached rather than re-fetched by
  // every 10s refresh.
  final Map<String, Map<String, dynamic>> _responderDetails = {};

  // ── Offline cache state ───────────────────────────────────────────────────
  // Shows previously-fetched notifications when a live fetch fails (e.g. no
  // internet), instead of an empty/stale screen.
  bool _isOffline = false;

  Timer? _autoRefreshTimer;
  final FlutterLocalNotificationsPlugin _flnp =
      FlutterLocalNotificationsPlugin();

  // `mounted` alone isn't a reliable enough guard for the network calls the
  // 10s auto-refresh timer fires: cancelling the timer in dispose() only
  // stops FUTURE ticks, not a fetch already in flight when the widget is
  // disposed — that request can still resolve afterwards and call setState
  // on a defunct element. Set synchronously in dispose(), before anything
  // else, so every check against it is unambiguous.
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initNotificationListener();
    _loadReadIds()
        .then((_) => _loadDeletedIds())
        .then((_) => _loadAcknowledgedWitnessIds())
        .then((_) => _loadReadDispatcherMsgIds())
        .then((_) => _loadDeletedDispatcherMsgIds())
        .then((_) => _loadReadResolvedIds())
        .then((_) => _loadDeletedResolvedIds())
        .then((_) => _loadReadAssignedIds())
        .then((_) => _loadDeletedAssignedIds())
        .then((_) => _loadCachedNotifications())
        .then((_) {
          // Cached data is already on screen at this point — no need to
          // block it behind a full-screen spinner while we refresh live.
          if (_reports.isNotEmpty || _witnessRequests.isNotEmpty) {
            if (mounted) setState(() => _isLoading = false);
          }
        })
        .then((_) => _loadAll());

    _autoRefreshTimer = Timer.periodic(
        const Duration(seconds: 10), (_) => _loadAll(silent: true));
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _autoRefreshTimer?.cancel();
    super.dispose();
  }

  // This screen's 10-second poll fans out to several network calls
  // (family reports, own reports, witness requests) and rebuilds the whole
  // list. There's no reason to keep paying that behind a backgrounded app,
  // so the timer stops on pause and restarts — with an immediate catch-up
  // fetch — on resume.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _autoRefreshTimer ??= Timer.periodic(
          const Duration(seconds: 10), (_) => _loadAll(silent: true));
      _loadAll(silent: true);
    } else if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.detached ||
        state == AppLifecycleState.hidden) {
      _autoRefreshTimer?.cancel();
      _autoRefreshTimer = null;
    }
  }

  void _initNotificationListener() {
    _flnp
        .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>()
        ?.requestNotificationsPermission();
    _flnp.getNotificationAppLaunchDetails().then((details) {
      if (details?.didNotificationLaunchApp == true) {
        _loadAll(silent: true);
      }
    });
  }

  // ── Persistence helpers ───────────────────────────────────────────────────
  Future<void> _loadReadIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notif_read_ids') ?? [];
    if (mounted) setState(() => _readIds = list.toSet());
  }

  Future<void> _loadDeletedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notif_deleted_ids') ?? [];
    if (mounted) setState(() => _deletedIds = list.toSet());
  }

  Future<void> _loadAcknowledgedWitnessIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('witness_ack_ids') ?? [];
    if (mounted) setState(() => _acknowledgedWitnessIds = list.toSet());
  }

  Future<void> _loadReadDispatcherMsgIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notif_read_dispatcher_ids') ?? [];
    if (mounted) setState(() => _readDispatcherMsgIds = list.toSet());
  }

  Future<void> _markDispatcherMessageRead(String id) async {
    if (_readDispatcherMsgIds.contains(id)) return;
    setState(() => _readDispatcherMsgIds.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'notif_read_dispatcher_ids', _readDispatcherMsgIds.toList());
  }

  Future<void> _loadDeletedDispatcherMsgIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notif_deleted_dispatcher_ids') ?? [];
    if (mounted) setState(() => _deletedDispatcherMsgIds = list.toSet());
  }

  Future<void> _deleteDispatcherMessage(String id) async {
    if (_deletedDispatcherMsgIds.contains(id)) return;
    HapticFeedback.mediumImpact();
    setState(() => _deletedDispatcherMsgIds.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'notif_deleted_dispatcher_ids', _deletedDispatcherMsgIds.toList());
  }

  Future<void> _loadReadResolvedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notif_read_resolved_ids') ?? [];
    if (mounted) setState(() => _readResolvedIds = list.toSet());
  }

  Future<void> _markResolvedRead(String id) async {
    if (id.isEmpty || _readResolvedIds.contains(id)) return;
    setState(() => _readResolvedIds.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'notif_read_resolved_ids', _readResolvedIds.toList());
  }

  Future<void> _loadDeletedResolvedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notif_deleted_resolved_ids') ?? [];
    if (mounted) setState(() => _deletedResolvedIds = list.toSet());
  }

  Future<void> _deleteResolvedNotification(String id) async {
    if (id.isEmpty || _deletedResolvedIds.contains(id)) return;
    HapticFeedback.mediumImpact();
    setState(() => _deletedResolvedIds.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'notif_deleted_resolved_ids', _deletedResolvedIds.toList());
  }

  Future<void> _loadReadAssignedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notif_read_assigned_ids') ?? [];
    if (mounted) setState(() => _readAssignedIds = list.toSet());
  }

  Future<void> _markAssignedRead(String id) async {
    if (id.isEmpty || _readAssignedIds.contains(id)) return;
    setState(() => _readAssignedIds.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'notif_read_assigned_ids', _readAssignedIds.toList());
  }

  Future<void> _loadDeletedAssignedIds() async {
    final prefs = await SharedPreferences.getInstance();
    final list = prefs.getStringList('notif_deleted_assigned_ids') ?? [];
    if (mounted) setState(() => _deletedAssignedIds = list.toSet());
  }

  Future<void> _deleteAssignedNotification(String id) async {
    if (id.isEmpty || _deletedAssignedIds.contains(id)) return;
    HapticFeedback.mediumImpact();
    setState(() => _deletedAssignedIds.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'notif_deleted_assigned_ids', _deletedAssignedIds.toList());
  }

  // ── Offline cache helpers ─────────────────────────────────────────────────
  String get _reportsCacheKey => 'cached_reports_${widget.familyCode}';
  String get _witnessCacheKey => 'cached_witness_requests_${widget.userId}';

  // Loads whatever was cached from the last successful fetch so the screen
  // shows real content immediately, even before the network call resolves
  // (or if it never resolves because there's no internet).
  Future<void> _loadCachedNotifications() async {
    final prefs = await SharedPreferences.getInstance();
    try {
      final reportsJson = prefs.getString(_reportsCacheKey);
      if (reportsJson != null) {
        final list = (json.decode(reportsJson) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (mounted) setState(() => _reports = list);
      }
    } catch (e) {
      debugPrint('❌ Loading cached reports: $e');
    }
    try {
      final witnessJson = prefs.getString(_witnessCacheKey);
      if (witnessJson != null) {
        final list = (json.decode(witnessJson) as List)
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        if (mounted) setState(() => _witnessRequests = list);
      }
    } catch (e) {
      debugPrint('❌ Loading cached witness requests: $e');
    }
  }

  Future<void> _cacheReports(List<Map<String, dynamic>> reports) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_reportsCacheKey, json.encode(reports));
  }

  Future<void> _cacheWitnessRequests(
      List<Map<String, dynamic>> requests) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_witnessCacheKey, json.encode(requests));
  }

  // ── Combined loader ───────────────────────────────────────────────────────
  Future<void> _loadAll({bool silent = false}) async {
    if (_disposed) return;
    await Future.wait([
      _loadReports(silent: silent),
      _loadWitnessRequests(),
      _loadMyReportUpdates(),
    ]);
  }

  // Dispatcher acknowledge-messages and resolutions both live on the user's
  // own report entries, so they come out of a single fetch rather than two
  // identical round-trips every 10s.
  Future<void> _loadMyReportUpdates() async {
    if (widget.userId.isEmpty || _disposed) return;
    try {
      final reports = await EmergencyReportService.getUserReports(widget.userId);
      if (_disposed) return;
      final withMessages = reports
          .where((r) => (r['DispatcherMessage']?.toString() ?? '').isNotEmpty)
          .toList();
      final resolved = reports
          .where((r) =>
              EmergencyReportService.isResolvedStatus(r['Status']?.toString()))
          .toList();
      final assigned = reports
          .where((r) =>
              EmergencyReportService.isAssignedStatus(r['Status']?.toString()))
          .toList();
      final enrichedAssigned = await _withResponderDetails(assigned);
      if (!_disposed && mounted) {
        setState(() {
          _dispatcherMessages = withMessages;
          _resolvedReports = resolved;
          _assignedReports = enrichedAssigned;
        });
      }
    } catch (e) {
      debugPrint('❌ NotificationScreen own-report updates: $e');
    }
  }

  /// Folds the responder's name and assignment time — which live on the
  /// canonical report record rather than the reporter's index entry — into
  /// each assigned report. Fetched once per report and cached; notifications
  /// the user has already read or dismissed are skipped, so a long history
  /// never costs a request.
  Future<List<Map<String, dynamic>>> _withResponderDetails(
      List<Map<String, dynamic>> assigned) async {
    final out = <Map<String, dynamic>>[];
    for (final r in assigned) {
      final id = r['ReportId']?.toString() ?? '';
      final cached = _responderDetails[id];
      if (cached != null) {
        out.add({...r, ...cached});
        continue;
      }
      if (id.isEmpty ||
          _readAssignedIds.contains(id) ||
          _deletedAssignedIds.contains(id)) {
        out.add(r);
        continue;
      }
      try {
        final full = await EmergencyReportService.getReportFromIndex(r);
        if (full == null) {
          out.add(r);
          continue;
        }
        final extra = <String, dynamic>{};
        for (final key in const [
          'DispatcherName',
          'DispatcherId',
          'AcknowledgedAt'
        ]) {
          if (full[key] != null) extra[key] = full[key];
        }
        _responderDetails[id] = extra;
        out.add({...r, ...extra});
      } catch (e) {
        debugPrint('⚠️ Responder details for $id: $e');
        out.add(r);
      }
    }
    return out;
  }

  // EmergencyReportService.getFamilyReports() swallows network errors and
  // returns [] on failure (other screens rely on that). We need to tell a
  // real "zero reports" apart from "fetch failed" so a dropped connection
  // doesn't overwrite good cached data with an empty list, so this screen
  // fetches directly instead of going through that service.
  Future<List<Map<String, dynamic>>> _fetchFamilyReports(
      String familyCode) async {
    if (familyCode.isEmpty) return [];
    final resp = await http
        .get(Uri.parse('$_kDbUrl/Families/$familyCode/FamilyReports.json'))
        .timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) {
      throw Exception('FamilyReports fetch failed: ${resp.statusCode}');
    }
    final raw = resp.body.trim();
    if (raw == 'null' || raw.isEmpty) return [];
    final data = json.decode(raw);
    if (data is! Map) return [];
    final list =
        data.values.map((v) => Map<String, dynamic>.from(v as Map)).toList();
    list.sort((a, b) => (b['CreatedAt'] ?? '')
        .toString()
        .compareTo((a['CreatedAt'] ?? '').toString()));
    // This bypasses EmergencyReportService.getFamilyReports() for the
    // reason above, so it has to reconcile against each report's canonical
    // Status itself — otherwise a family member's report could sit on this
    // screen showing Pending long after the dispatcher resolved it.
    return EmergencyReportService.reconcileStatuses(list);
  }

  Future<void> _loadReports({bool silent = false}) async {
    if (_disposed || !mounted) return;
    // Only block the screen with a spinner when there's truly nothing to
    // show yet — if cached notifications are already visible, refresh
    // quietly behind them instead of hiding them.
    final hasSomethingOnScreen = _reports.isNotEmpty || _witnessRequests.isNotEmpty;
    if (!silent && !hasSomethingOnScreen) setState(() => _isLoading = true);
    try {
      final reports = await _fetchFamilyReports(widget.familyCode);
      if (_disposed) return;
      await _cacheReports(reports);
      if (!_disposed && mounted) {
        setState(() {
          _reports = reports;
          _isLoading = false;
          _isOffline = false;
        });
      }
    } catch (e) {
      debugPrint('❌ NotificationScreen reports: $e');
      if (!_disposed && mounted) setState(() {
        _isLoading = false;
        _isOffline = true;
      });
    }
  }

  Future<void> _loadWitnessRequests() async {
    if (widget.userId.isEmpty || _disposed) return;
    try {
      final resp = await http
          .get(Uri.parse('$_kDbUrl/WitnessRequests/${widget.userId}.json'))
          .timeout(const Duration(seconds: 10));
      if (_disposed) return;

      if (resp.statusCode != 200) {
        if (mounted) setState(() => _isOffline = true);
        return;
      }
      final raw = resp.body.trim();
      if (raw == 'null' || raw.isEmpty) {
        await _cacheWitnessRequests([]);
        if (!_disposed && mounted) setState(() => _witnessRequests = []);
        return;
      }

      final Map<String, dynamic> data =
          Map<String, dynamic>.from(json.decode(raw) as Map);

      final list = data.entries.map((e) {
        final m = Map<String, dynamic>.from(e.value as Map);
        m['RequestId'] = e.key;
        return m;
      }).toList();

      // Newest first
      list.sort((a, b) {
        final tA = DateTime.tryParse(a['Timestamp']?.toString() ?? '') ??
            DateTime(2000);
        final tB = DateTime.tryParse(b['Timestamp']?.toString() ?? '') ??
            DateTime(2000);
        return tB.compareTo(tA);
      });

      await _cacheWitnessRequests(list);
      if (!_disposed && mounted) setState(() => _witnessRequests = list);
    } catch (e) {
      debugPrint('❌ WitnessRequests fetch: $e');
      if (!_disposed && mounted) setState(() => _isOffline = true);
    }
  }

  // ── Report actions ────────────────────────────────────────────────────────
  Future<void> _markAllAsRead() async {
    final all = _reports.map((r) => r['ReportId']?.toString() ?? '').toSet();
    final allDispatcherMsgs = _visibleDispatcherMessages
        .map((r) => r['ReportId']?.toString() ?? '')
        .toSet();
    final allResolved = _visibleResolvedReports
        .map((r) => r['ReportId']?.toString() ?? '')
        .toSet();
    final allAssigned = _visibleAssignedReports
        .map((r) => r['ReportId']?.toString() ?? '')
        .toSet();
    setState(() {
      _readIds = all;
      _readDispatcherMsgIds = allDispatcherMsgs;
      _readResolvedIds = {..._readResolvedIds, ...allResolved};
      _readAssignedIds = {..._readAssignedIds, ...allAssigned};
    });
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notif_read_ids', all.toList());
    await prefs.setStringList(
        'notif_read_dispatcher_ids', allDispatcherMsgs.toList());
    await prefs.setStringList(
        'notif_read_resolved_ids', _readResolvedIds.toList());
    await prefs.setStringList(
        'notif_read_assigned_ids', _readAssignedIds.toList());
  }

  Future<void> _markOneAsRead(String id) async {
    if (_readIds.contains(id)) return;
    setState(() => _readIds.add(id));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notif_read_ids', _readIds.toList());
  }

  Future<void> _persistDeletedIds() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList('notif_deleted_ids', _deletedIds.toList());
  }

  Future<void> _deleteNotification(String id) async {
    if (_deletedIds.contains(id)) return;
    HapticFeedback.mediumImpact();
    setState(() => _deletedIds.add(id));
    await _persistDeletedIds();
  }

  Future<void> _deleteAll() async {
    final all = _visibleReports
        .map((r) => r['ReportId']?.toString() ?? '')
        .where((id) => id.isNotEmpty)
        .toSet();
    if (all.isEmpty) return;
    HapticFeedback.mediumImpact();
    setState(() => _deletedIds = {..._deletedIds, ...all});
    await _persistDeletedIds();
  }

  // ── Witness request actions ───────────────────────────────────────────────
  Future<void> _acknowledgeWitnessRequest(String requestId) async {
    HapticFeedback.selectionClick();
    setState(() => _acknowledgedWitnessIds.add(requestId));
    final prefs = await SharedPreferences.getInstance();
    await prefs.setStringList(
        'witness_ack_ids', _acknowledgedWitnessIds.toList());

    // Update status in RTDB so dispatcher can see it
    try {
      await http
          .patch(
            Uri.parse(
                '$_kDbUrl/WitnessRequests/${widget.userId}/$requestId.json'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({'Status': 'Acknowledged'}),
          )
          .timeout(const Duration(seconds: 10));
    } catch (e) {
      debugPrint('⚠️ witness ack RTDB patch: $e');
    }
  }

  // ─── Navigate to map with reporter info ──────────────────────────────────
  Future<void> _navigateToReporter(Map<String, dynamic> report) async {
    // Mark as read first
    final reportId = report['ReportId']?.toString() ?? '';
    if (reportId.isNotEmpty) {
      await _markOneAsRead(reportId);
    }

    // Extract reporter info
    final reporterUserId = report['UserId']?.toString() ?? '';
    final reporterName =
        (report['UserName']?.toString() ?? '').trim().isEmpty
            ? 'Family Member'
            : report['UserName'].toString().trim();
    final emergencyType = report['EmergencyType']?.toString() ?? 'emergency';

    // Extract location
    final location = report['Location'] as Map<String, dynamic>?;
    double? latitude;
    double? longitude;

    if (location != null) {
      latitude = (location['Latitude'] as num?)?.toDouble();
      longitude = (location['Longitude'] as num?)?.toDouble();
    }

    // Get current user info
    final prefs = await SharedPreferences.getInstance();
    final currentUserId = prefs.getString('userId') ?? widget.userId;
    final currentUserName = prefs.getString('userName') ?? 'User';

    if (currentUserId.isEmpty) {
      debugPrint('❌ Cannot navigate: no current user');
      return;
    }

    // Navigate to FamilyTrackingScreen with reporter highlighted
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => FamilyTrackingScreen(
            currentUserId: currentUserId,
            currentUserName: currentUserName,
            highlightMemberId:
                reporterUserId.isNotEmpty ? reporterUserId : null,
            highlightMemberName: reporterName,
            initialLat: latitude,
            initialLng: longitude,
            emergencyType: emergencyType,
          ),
        ),
      );
    }
  }

  // ── Visibility ────────────────────────────────────────────────────────────
  //
  // This screen is an inbox of things the user hasn't dealt with yet, not an
  // archive: opening a notification marks it read, and a read notification
  // leaves the list. Every section below therefore filters on its own read
  // set as well as its dismissed set. Nothing is lost by disappearing here —
  // the underlying reports remain in My Reports / Report History.
  List<Map<String, dynamic>> get _visibleReports => _reports
      .where((r) => !_deletedIds.contains(r['ReportId']?.toString() ?? ''))
      .where((r) => (r['UserId']?.toString() ?? '') != widget.userId)
      .where((r) => !_readIds.contains(r['ReportId']?.toString() ?? ''))
      .toList();

  // A dispatcher message is written when they acknowledge a report — the same
  // event the "Responder Assigned" card announces, and it's carried inside
  // that card. Reports already covered by an assignment or resolution card are
  // filtered out here so one event doesn't produce two notifications.
  List<Map<String, dynamic>> get _visibleDispatcherMessages {
    final covered = <String>{
      ..._visibleAssignedReports.map((r) => r['ReportId']?.toString() ?? ''),
      ..._visibleResolvedReports.map((r) => r['ReportId']?.toString() ?? ''),
    };
    return _dispatcherMessages
        .where((r) => !_deletedDispatcherMsgIds
            .contains(r['ReportId']?.toString() ?? ''))
        .where((r) =>
            !_readDispatcherMsgIds.contains(r['ReportId']?.toString() ?? ''))
        .where((r) => !covered.contains(r['ReportId']?.toString() ?? ''))
        .toList();
  }

  List<Map<String, dynamic>> get _visibleResolvedReports => _resolvedReports
      .where((r) =>
          !_deletedResolvedIds.contains(r['ReportId']?.toString() ?? ''))
      .where((r) => !_readResolvedIds.contains(r['ReportId']?.toString() ?? ''))
      .toList();

  List<Map<String, dynamic>> get _visibleAssignedReports => _assignedReports
      .where((r) =>
          !_deletedAssignedIds.contains(r['ReportId']?.toString() ?? ''))
      .where((r) => !_readAssignedIds.contains(r['ReportId']?.toString() ?? ''))
      .toList();

  // ─── Build ─────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    // Read notifications are filtered out of these lists entirely, so what's
    // visible IS what's unread — no second read check needed to count them.
    final visible = _visibleReports;
    final visibleDispatcherMsgs = _visibleDispatcherMessages;
    final visibleResolved = _visibleResolvedReports;
    final visibleAssigned = _visibleAssignedReports;
    final pendingWitness = _witnessRequests
        .where((r) =>
            !_acknowledgedWitnessIds.contains(r['RequestId']?.toString() ?? ''))
        .length;

    final totalUnread = visible.length +
        pendingWitness +
        visibleDispatcherMsgs.length +
        visibleResolved.length +
        visibleAssigned.length;

    return Scaffold(
      backgroundColor: AppColors.canvas,
      appBar: AppBar(
        backgroundColor: AppColors.canvas,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        automaticallyImplyLeading: false,
        leading: widget.showBackButton
            ? IconButton(
                icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
                onPressed: () {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                },
                tooltip: 'Back',
              )
            : null,
        titleSpacing: 0,
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Notifications',
              style: TextStyle(
                color: AppColors.secondary,
                fontWeight: FontWeight.bold,
                fontSize: 19,
              ),
            ),
            Text(
              totalUnread > 0 ? '$totalUnread new' : 'All caught up',
              style: TextStyle(
                fontSize: 12.5,
                color: totalUnread > 0 ? AppColors.primary : AppColors.textLight,
                fontWeight: totalUnread > 0 ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
        actions: [
          if (visible.isNotEmpty ||
              visibleDispatcherMsgs.isNotEmpty ||
              visibleResolved.isNotEmpty ||
              visibleAssigned.isNotEmpty)
            TextButton(
              onPressed: _markAllAsRead,
              child: const Text('Mark all read',
                  style: TextStyle(fontSize: 12.5, color: AppColors.primary)),
            ),
          if (visible.isNotEmpty)
            IconButton(
              icon: const Icon(Icons.delete_sweep_outlined,
                  color: AppColors.textLight),
              tooltip: 'Clear all',
              onPressed: () => _confirmDeleteAll(context),
            ),
          const SizedBox(width: 4),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary))
          : Column(
              children: [
                if (_isOffline) _buildOfflineBanner(),
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: _loadAll,
                    color: AppColors.primary,
                    child: (visible.isEmpty &&
                            _witnessRequests.isEmpty &&
                            visibleDispatcherMsgs.isEmpty &&
                            visibleResolved.isEmpty &&
                            visibleAssigned.isEmpty)
                        ? _buildEmptyState()
                        : _buildList(),
                  ),
                ),
              ],
            ),
    );
  }

  Widget _buildOfflineBanner() {
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.12),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.35)),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_rounded, size: 18, color: Colors.orange.shade800),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              "You're offline — showing previously loaded notifications",
              style: TextStyle(
                fontSize: 12.5,
                color: Colors.orange.shade900,
                fontWeight: FontWeight.w600,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildList() {
    // Rows are collected as builders rather than built widgets so ListView
    // .builder can lazily construct only what's on screen — the list runs to
    // 80+ notifications, and building every card up front was wasted work.
    final rows = <Widget Function()>[];

    // ── Responder assignments (shown first — "someone is on their way" is
    // the most time-sensitive update on the user's own reports) ───────
    final visibleAssigned = _visibleAssignedReports;
    if (visibleAssigned.isNotEmpty) {
      rows.add(() => _sectionHeader('🚔 Responder Assigned',
          color: AppColors.primary, count: visibleAssigned.length));
      for (final r in visibleAssigned) {
        rows.add(() => _swipeableAssignedCard(r));
      }
      rows.add(() => const SizedBox(height: 8));
    }

    // ── Resolved reports ─────────────────────────────────────────────
    final visibleResolved = _visibleResolvedReports;
    if (visibleResolved.isNotEmpty) {
      rows.add(() => _sectionHeader('✅ Resolved Reports',
          color: AppColors.success, count: visibleResolved.length));
      for (final r in visibleResolved) {
        rows.add(() => _swipeableResolvedCard(r));
      }
      rows.add(() => const SizedBox(height: 8));
    }

    // ── Dispatcher acknowledge messages (shown first — updates on the
    // user's own reports) ─────────────────────────────────────────────
    final visibleDispatcherMsgs = _visibleDispatcherMessages;
    if (visibleDispatcherMsgs.isNotEmpty) {
      rows.add(() => _sectionHeader('👮 Dispatcher Updates',
          color: AppColors.primary, count: visibleDispatcherMsgs.length));
      for (final r in visibleDispatcherMsgs) {
        rows.add(() => _swipeableDispatcherMessageCard(r));
      }
      rows.add(() => const SizedBox(height: 8));
    }

    // ── Witness Requests (shown at top when present) ─────────────────
    if (_witnessRequests.isNotEmpty) {
      rows.add(() => _sectionHeader('👮 Witness Requests',
          color: const Color(0xFF1565C0), count: _witnessRequests.length));
      for (final r in _witnessRequests) {
        rows.add(() => _witnessRequestCard(r));
      }
      rows.add(() => const SizedBox(height: 8));
    }

    // ── Emergency Reports, grouped by day ────────────────────────────
    for (final entry in _grouped().entries) {
      rows.add(() => _sectionHeader(entry.key, count: entry.value.length));
      for (final r in entry.value) {
        rows.add(() => _swipeableCard(r));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      physics: const AlwaysScrollableScrollPhysics(),
      itemCount: rows.length,
      // Every card here paints a BoxShadow, which is comparatively costly to
      // rasterize. Without a boundary per row, any one card repainting (a
      // swipe-to-dismiss drag, a card entering/leaving) dirties the whole
      // visible list and re-rasterizes every shadow on screen. The boundary
      // caches each row as its own layer so scrolling just moves them.
      itemBuilder: (_, i) => RepaintBoundary(child: rows[i]()),
    );
  }

  // ── RESPONDER-ASSIGNED CARD ───────────────────────────────────────────────
  //
  // Tells the reporter a responder has been assigned to a report THEY filed,
  // and restates which report — type, the date and time it was filed, and
  // where — so it's unambiguous when several are open at once. Stays in the
  // list until it's read; reading removes it.
  Widget _responderAssignedCard(Map<String, dynamic> r) {
    final reportId = r['ReportId']?.toString() ?? '';
    final type = (r['EmergencyType'] ?? 'other').toString();
    final label = EmergencyReportService.getTypeLabel(type);
    final emoji = EmergencyReportService.getTypeEmoji(type);
    final createdAt = r['CreatedAt']?.toString() ?? '';
    final reportedDate = EmergencyReportService.formatReportDate(createdAt);
    final reportedTime = EmergencyReportService.formatReportTime(createdAt);
    final assignedAtRaw = EmergencyReportService.assignedAtOf(r);
    final assignedOn =
        EmergencyReportService.formatReportDateTime(assignedAtRaw);
    final responder = EmergencyReportService.responderNameOf(r);
    final dispatcherMessage = r['DispatcherMessage']?.toString().trim() ?? '';
    final location = _locationFor(r);

    return GestureDetector(
      // Reading it takes it out of the list; the report itself stays in My
      // Reports, so nothing is lost.
      onTap: () => _markAssignedRead(reportId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.primary.withOpacity(0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.primary,
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.local_police, size: 15, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'RESPONDER ASSIGNED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Text(
                    _relativeTime(
                        assignedAtRaw.isNotEmpty ? assignedAtRaw : createdAt),
                    style: const TextStyle(
                        fontSize: 10, color: Colors.white70),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.primary.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.directions_run,
                        color: AppColors.primary, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          responder.isNotEmpty
                              ? '$responder is responding to your $label'
                              : 'A responder has been assigned to your $label',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            height: 1.3,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          assignedOn.isEmpty
                              ? 'Your report is now being acted on.'
                              : 'Assigned $assignedOn',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textLight,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.lightGrey,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _reportDetailRow(
                                  Icons.label_outline, 'Type', '$emoji $label'),
                              if (reportedDate.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _reportDetailRow(Icons.calendar_today_outlined,
                                    'Date reported', reportedDate),
                              ],
                              if (reportedTime.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _reportDetailRow(Icons.access_time,
                                    'Time reported', reportedTime),
                              ],
                              if (location != 'Location unavailable') ...[
                                const SizedBox(height: 6),
                                _reportDetailRow(
                                    Icons.place_outlined, 'Location', location),
                              ],
                              if (reportId.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _reportDetailRow(Icons.tag, 'Report ID',
                                    reportId, monospace: true),
                              ],
                            ],
                          ),
                        ),
                        // The dispatcher's own note, written when they
                        // assigned the responder.
                        if (dispatcherMessage.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.format_quote,
                                  size: 13, color: AppColors.textLight),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  dispatcherMessage,
                                  style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.secondary,
                                    height: 1.4,
                                    fontStyle: FontStyle.italic,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                  color: AppColors.primary,
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 4),
                            const Text('New',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.primary,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Dismiss notification',
                    child: InkResponse(
                      onTap: () => _deleteAssignedNotification(reportId),
                      radius: 22,
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.close_rounded,
                            size: 17, color: AppColors.textLight),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── RESOLVED-REPORT CARD ──────────────────────────────────────────────────
  //
  // Confirms to the reporter that a responder or administrator has closed out
  // a report THEY submitted, and restates which report that was — type, the
  // date and time it was filed, and where — so "resolved" is unambiguous even
  // when several reports are open at once.
  //
  // Only ever rendered while unread — reading one removes it — so it always
  // carries the unread treatment.
  Widget _resolvedReportCard(Map<String, dynamic> r) {
    final reportId = r['ReportId']?.toString() ?? '';
    final type = (r['EmergencyType'] ?? 'other').toString();
    final label = EmergencyReportService.getTypeLabel(type);
    final emoji = EmergencyReportService.getTypeEmoji(type);
    final createdAt = r['CreatedAt']?.toString() ?? '';
    final reportedDate = EmergencyReportService.formatReportDate(createdAt);
    final reportedTime = EmergencyReportService.formatReportTime(createdAt);
    final resolvedAtRaw = EmergencyReportService.resolvedAtOf(r);
    final resolvedOn =
        EmergencyReportService.formatReportDateTime(resolvedAtRaw);
    final resolvedBy = EmergencyReportService.resolvedByOf(r);
    final note = EmergencyReportService.resolutionNoteOf(r);
    final location = _locationFor(r);

    return GestureDetector(
      // Tapping marks it read, which takes it out of the list. The report
      // itself stays in My Reports, so nothing is lost by dismissing it here.
      onTap: () => _markResolvedRead(reportId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: AppColors.success.withOpacity(0.35),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // ── Status banner — the headline claim of the card ───────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: const BoxDecoration(
                color: AppColors.success,
                borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified_rounded,
                      size: 15, color: Colors.white),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'REPORT RESOLVED',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.4,
                      ),
                    ),
                  ),
                  Text(
                    _relativeTime(
                        resolvedAtRaw.isNotEmpty ? resolvedAtRaw : createdAt),
                    style: const TextStyle(
                        fontSize: 10, color: Colors.white70),
                  ),
                ],
              ),
            ),

            Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: AppColors.success.withOpacity(0.12),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(Icons.check_circle,
                        color: AppColors.success, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Your $label has been resolved',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                            height: 1.3,
                            color: AppColors.secondary,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Text(
                          'Closed by $resolvedBy'
                          '${resolvedOn.isEmpty ? '' : ' · $resolvedOn'}',
                          style: const TextStyle(
                            fontSize: 12,
                            color: AppColors.textLight,
                            height: 1.35,
                          ),
                        ),
                        const SizedBox(height: 10),

                        // ── Report details ──────────────────────────────
                        Container(
                          width: double.infinity,
                          padding: const EdgeInsets.all(10),
                          decoration: BoxDecoration(
                            color: AppColors.lightGrey,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _reportDetailRow(
                                  Icons.label_outline, 'Type', '$emoji $label'),
                              if (reportedDate.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _reportDetailRow(Icons.calendar_today_outlined,
                                    'Date reported', reportedDate),
                              ],
                              if (reportedTime.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _reportDetailRow(Icons.access_time,
                                    'Time reported', reportedTime),
                              ],
                              if (location != 'Location unavailable') ...[
                                const SizedBox(height: 6),
                                _reportDetailRow(
                                    Icons.place_outlined, 'Location', location),
                              ],
                              if (reportId.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                _reportDetailRow(Icons.tag, 'Report ID',
                                    reportId, monospace: true),
                              ],
                            ],
                          ),
                        ),

                        if (note.isNotEmpty) ...[
                          const SizedBox(height: 8),
                          Text(
                            note,
                            style: const TextStyle(
                              fontSize: 12.5,
                              color: AppColors.secondary,
                              height: 1.4,
                              fontStyle: FontStyle.italic,
                            ),
                          ),
                        ],

                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                  color: AppColors.success,
                                  shape: BoxShape.circle),
                            ),
                            const SizedBox(width: 4),
                            const Text('New',
                                style: TextStyle(
                                    fontSize: 10,
                                    color: AppColors.success,
                                    fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Semantics(
                    button: true,
                    label: 'Dismiss notification',
                    child: InkResponse(
                      onTap: () => _deleteResolvedNotification(reportId),
                      radius: 22,
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.close_rounded,
                            size: 17, color: AppColors.textLight),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _reportDetailRow(IconData icon, String label, String value,
      {bool monospace = false}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(top: 1),
          child: Icon(icon, size: 13, color: AppColors.textLight),
        ),
        const SizedBox(width: 6),
        SizedBox(
          width: 92,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 11.5,
              color: AppColors.textLight,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 12,
              color: AppColors.secondary,
              fontWeight: FontWeight.w600,
              height: 1.3,
              fontFamily: monospace ? 'monospace' : null,
            ),
          ),
        ),
      ],
    );
  }

  // ── DISPATCHER ACKNOWLEDGE-MESSAGE CARD ───────────────────────────────────
  Widget _dispatcherMessageCard(Map<String, dynamic> r) {
    final reportId = r['ReportId']?.toString() ?? '';
    final isRead = _readDispatcherMsgIds.contains(reportId);
    final message = r['DispatcherMessage']?.toString() ?? '';
    final type = (r['EmergencyType'] ?? 'report').toString();
    final barangay = r['Barangay']?.toString() ?? '';
    final createdAt = r['CreatedAt']?.toString() ?? '';

    return GestureDetector(
      // Tapping a dispatcher update means "seen it" — marking it read is what
      // removes it from the list (see _visibleDispatcherMessages).
      onTap: () => _markDispatcherMessageRead(reportId),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isRead ? Colors.white : AppColors.primary.withOpacity(0.05),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isRead
                ? AppColors.lightGrey
                : AppColors.primary.withOpacity(0.35),
            width: isRead ? 1 : 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                padding: const EdgeInsets.all(9),
                decoration: BoxDecoration(
                  color: AppColors.primary.withOpacity(0.1),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.local_police,
                    color: AppColors.primary, size: 20),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            'Your ${_humanize(type)} report was acknowledged',
                            style: TextStyle(
                              fontWeight:
                                  isRead ? FontWeight.w600 : FontWeight.bold,
                              fontSize: 14,
                              height: 1.3,
                              color: AppColors.secondary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          _relativeTime(createdAt),
                          style: const TextStyle(
                              fontSize: 11, color: AppColors.textLight),
                        ),
                      ],
                    ),
                    if (barangay.isNotEmpty) ...[
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          const Icon(Icons.location_city,
                              size: 12, color: AppColors.textLight),
                          const SizedBox(width: 4),
                          Text('Brgy. $barangay',
                              style: const TextStyle(
                                  fontSize: 12, color: AppColors.textLight)),
                        ],
                      ),
                    ],
                    const SizedBox(height: 10),
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(10),
                      decoration: BoxDecoration(
                        color: AppColors.lightGrey,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text(
                        message,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.secondary,
                          height: 1.4,
                        ),
                      ),
                    ),
                    if (!isRead) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          Container(
                            width: 7,
                            height: 7,
                            decoration: const BoxDecoration(
                                color: AppColors.primary,
                                shape: BoxShape.circle),
                          ),
                          const SizedBox(width: 4),
                          const Text('New',
                              style: TextStyle(
                                  fontSize: 10,
                                  color: AppColors.primary,
                                  fontWeight: FontWeight.bold)),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              Semantics(
                button: true,
                label: 'Dismiss notification',
                child: InkResponse(
                  onTap: () => _deleteDispatcherMessage(reportId),
                  radius: 22,
                  child: const SizedBox(
                    width: 40,
                    height: 40,
                    child: Icon(Icons.close_rounded,
                        size: 17, color: AppColors.textLight),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── WITNESS REQUEST CARD ──────────────────────────────────────────────────
  Widget _witnessRequestCard(Map<String, dynamic> r) {
    final requestId = r['RequestId']?.toString() ?? '';
    final isAcknowledged = _acknowledgedWitnessIds.contains(requestId);
    final dispatcherName = r['DispatcherName']?.toString() ?? 'Dispatcher';
    final dispatcherRank = r['DispatcherRank']?.toString() ?? 'Officer';
    final emergencyType = r['EmergencyType']?.toString() ?? 'Emergency';
    final barangay = r['Barangay']?.toString() ?? '';
    final message = r['Message']?.toString() ??
        'You are requested to appear at the police station as a witness.';
    final timestamp = r['Timestamp']?.toString() ?? '';

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: isAcknowledged
            ? Colors.white
            : const Color(0xFF1565C0).withOpacity(0.04),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAcknowledged
              ? const Color(0xFFE0E4EA)
              : const Color(0xFF1565C0).withOpacity(0.35),
          width: isAcknowledged ? 1 : 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
          if (!isAcknowledged)
            BoxShadow(
              color: const Color(0xFF1565C0).withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 3),
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Top banner ───────────────────────────────────────────────────
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
            decoration: BoxDecoration(
              color: isAcknowledged
                  ? const Color(0xFF1565C0).withOpacity(0.08)
                  : const Color(0xFF1565C0),
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(15)),
            ),
            child: Row(
              children: [
                Icon(Icons.gavel,
                    color:
                        isAcknowledged ? const Color(0xFF1565C0) : Colors.white,
                    size: 15),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    isAcknowledged
                        ? '✅ WITNESS REQUEST  •  Acknowledged'
                        : '👮 WITNESS REQUEST  •  Action Required',
                    style: TextStyle(
                      color: isAcknowledged
                          ? const Color(0xFF1565C0)
                          : Colors.white,
                      fontSize: 11,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.3,
                    ),
                  ),
                ),
                Text(
                  _relativeTime(timestamp),
                  style: TextStyle(
                    fontSize: 10,
                    color: isAcknowledged
                        ? const Color(0xFF1565C0).withOpacity(0.7)
                        : Colors.white70,
                  ),
                ),
              ],
            ),
          ),

          // ── Body ─────────────────────────────────────────────────────────
          Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Dispatcher info row
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(9),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1565C0).withOpacity(0.1),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.local_police,
                          color: Color(0xFF1565C0), size: 20),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            '$dispatcherRank $dispatcherName',
                            style: const TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: AppColors.secondary,
                            ),
                          ),
                          const Text(
                            'Panabo City Police Station',
                            style: TextStyle(
                                fontSize: 12, color: AppColors.textLight),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 12),

                // Incident info pills
                Wrap(
                  spacing: 8,
                  runSpacing: 6,
                  children: [
                    _infoPill(
                      Icons.warning_amber_rounded,
                      emergencyType,
                      const Color(0xFF1565C0),
                    ),
                    if (barangay.isNotEmpty)
                      _infoPill(
                        Icons.location_city,
                        'Brgy. $barangay',
                        AppColors.grey,
                      ),
                  ],
                ),

                const SizedBox(height: 12),

                // Message
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(
                    message,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.secondary,
                      height: 1.5,
                    ),
                  ),
                ),

                const SizedBox(height: 12),

                // Action buttons
                if (!isAcknowledged) ...[
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton.icon(
                          onPressed: () =>
                              _acknowledgeWitnessRequest(requestId),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1565C0),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(10)),
                            elevation: 0,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                          ),
                          icon: const Icon(Icons.check_circle_outline,
                              size: 16, color: Colors.white),
                          label: const Text(
                            'I Acknowledge',
                            style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                                fontSize: 13),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  const Text(
                    '* Please bring a valid ID when visiting the station.',
                    style: TextStyle(
                        fontSize: 10,
                        color: AppColors.textLight,
                        fontStyle: FontStyle.italic),
                  ),
                ] else ...[
                  Row(
                    children: [
                      const Icon(Icons.check_circle,
                          color: AppColors.success, size: 16),
                      const SizedBox(width: 6),
                      const Text(
                        'You have acknowledged this request.',
                        style: TextStyle(
                          fontSize: 12,
                          color: AppColors.success,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _infoPill(IconData icon, String label, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: color.withOpacity(0.08),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withOpacity(0.25)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: color),
          const SizedBox(width: 5),
          Text(label,
              style: TextStyle(
                  fontSize: 11, color: color, fontWeight: FontWeight.w600)),
        ],
      ),
    );
  }

  // ── Group emergency reports by day ────────────────────────────────────────
  Map<String, List<Map<String, dynamic>>> _grouped() {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));

    final thisWeek = today.subtract(const Duration(days: 7));

    final Map<String, List<Map<String, dynamic>>> result = {
      'Today': [],
      'Yesterday': [],
      'This week': [],
      'Earlier': [],
    };

    for (final r in _visibleReports) {
      final ts = _parseTs((r['Timestamp'] ?? r['CreatedAt'] ?? '').toString());
      if (ts == null) {
        result['Earlier']!.add(r);
        continue;
      }
      final d = DateTime(ts.year, ts.month, ts.day);
      if (d == today) {
        result['Today']!.add(r);
      } else if (d == yesterday) {
        result['Yesterday']!.add(r);
      } else if (d.isAfter(thisWeek)) {
        result['This week']!.add(r);
      } else {
        result['Earlier']!.add(r);
      }
    }

    result.removeWhere((_, v) => v.isEmpty);
    return result;
  }

  // ── Swipeable emergency report card ──────────────────────────────────────
  Widget _swipeableCard(Map<String, dynamic> r) {
    final id = r['ReportId']?.toString() ?? '';
    return _SwipeToDeleteCard(
      key: ValueKey(id),
      dismissKey: id,
      onDismissed: () => _deleteNotification(id),
      child: _reportCard(r),
    );
  }

  Widget _swipeableAssignedCard(Map<String, dynamic> r) {
    final id = r['ReportId']?.toString() ?? '';
    return _SwipeToDeleteCard(
      key: ValueKey('assigned_$id'),
      dismissKey: 'assigned_$id',
      onDismissed: () => _deleteAssignedNotification(id),
      child: _responderAssignedCard(r),
    );
  }

  Widget _swipeableResolvedCard(Map<String, dynamic> r) {
    final id = r['ReportId']?.toString() ?? '';
    return _SwipeToDeleteCard(
      key: ValueKey('resolved_$id'),
      dismissKey: 'resolved_$id',
      onDismissed: () => _deleteResolvedNotification(id),
      child: _resolvedReportCard(r),
    );
  }

  Widget _swipeableDispatcherMessageCard(Map<String, dynamic> r) {
    final id = r['ReportId']?.toString() ?? '';
    return _SwipeToDeleteCard(
      key: ValueKey('dispatcher_$id'),
      dismissKey: 'dispatcher_$id',
      onDismissed: () => _deleteDispatcherMessage(id),
      child: _dispatcherMessageCard(r),
    );
  }

  Widget _sectionHeader(String title, {Color? color, int? count}) {
    final c = color ?? AppColors.secondary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
      child: Row(
        children: [
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  letterSpacing: 0.1,
                  color: c)),
          if (count != null) ...[
            const SizedBox(width: 6),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: c.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text('$count',
                  style: TextStyle(
                      fontSize: 11, fontWeight: FontWeight.bold, color: c)),
            ),
          ],
        ],
      ),
    );
  }

  // ── Report card with tap navigation ──────────────────────────────────────
  Widget _reportCard(Map<String, dynamic> r) {
    final id = r['ReportId']?.toString() ?? '';
    final isUnread = !_readIds.contains(id);
    final type = (r['EmergencyType'] ?? 'other').toString();
    final isShake = type == 'shake';
    final isOwn = (r['UserId'] ?? '').toString() == widget.userId;
    // Stored names often carry stray whitespace, which renders as "adrian  reported".
    final reporter = (r['UserName'] ?? '').toString().trim().isEmpty
        ? 'A family member'
        : (r['UserName']).toString().trim();
    final color = _colorFor(type);
    final status = EmergencyReportService.displayStatus(r['Status']?.toString());

    return GestureDetector(
      onTap: () => _navigateToReporter(r),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: isUnread ? color.withOpacity(0.04) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isUnread ? color.withOpacity(0.25) : AppColors.lightGrey,
            width: (isShake && isUnread) ? 2 : 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
            if (isShake)
              BoxShadow(
                  color: AppColors.danger.withOpacity(0.12),
                  blurRadius: 14,
                  offset: const Offset(0, 4)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (isShake)
              Container(
                width: double.infinity,
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
                decoration: const BoxDecoration(
                  color: AppColors.danger,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(15)),
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 14),
                    SizedBox(width: 6),
                    Text('🚨 EMERGENCY-HIGH-RED  •  Shake SOS',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.4)),
                  ],
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                        color: color.withOpacity(0.12), shape: BoxShape.circle),
                    child: Icon(_iconFor(type), color: color, size: 24),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Text(_titleFor(type, reporter, isOwn),
                                  style: TextStyle(
                                      fontWeight: isUnread
                                          ? FontWeight.bold
                                          : FontWeight.w600,
                                      fontSize: 14,
                                      height: 1.3,
                                      color: AppColors.secondary)),
                            ),
                            const SizedBox(width: 8),
                            Padding(
                              padding: const EdgeInsets.only(top: 1),
                              child: Text(
                                _relativeTime(r['Timestamp'] ?? r['CreatedAt']),
                                style: const TextStyle(
                                    fontSize: 11, color: AppColors.textLight),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 5),
                        Text(_subtitleFor(r),
                            style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.textLight,
                                height: 1.35)),
                        const SizedBox(height: 4),
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Padding(
                              padding: EdgeInsets.only(top: 2),
                              child: Icon(Icons.place_outlined,
                                  size: 13, color: AppColors.textLight),
                            ),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                _locationFor(r),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    fontSize: 12.5,
                                    color: AppColors.textLight,
                                    height: 1.35),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            _statusBadge(status),
                            if (isUnread) ...[
                              const SizedBox(width: 8),
                              Container(
                                  width: 7,
                                  height: 7,
                                  decoration: BoxDecoration(
                                      color: color, shape: BoxShape.circle)),
                              const SizedBox(width: 4),
                              Text('New',
                                  style: TextStyle(
                                      fontSize: 10,
                                      color: color,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Secondary affordance to the swipe gesture, so it stays
                  // quiet: neutral grey, but with a full 40dp tap target.
                  Semantics(
                    button: true,
                    label: 'Dismiss notification',
                    child: InkResponse(
                      onTap: () => _deleteNotification(id),
                      radius: 22,
                      child: const SizedBox(
                        width: 40,
                        height: 40,
                        child: Icon(Icons.close_rounded,
                            size: 17, color: AppColors.textLight),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Confirm delete all dialog ─────────────────────────────────────────────
  void _confirmDeleteAll(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Clear all notifications?'),
        content: const Text(
            'This will remove all emergency report notifications from your list. '
            'Witness requests will not be cleared.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(ctx);
              _deleteAll();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('Clear all'),
          ),
        ],
      ),
    );
  }

  // Expects an already-display-mapped status (see
  // EmergencyReportService.displayStatus) — callers pass the raw stored
  // value through that first, so 'Acknowledged' arrives here as 'In
  // Progress' rather than falling into the default Pending-styled case.
  Widget _statusBadge(String status) {
    Color bg;
    Color fg;
    switch (status.toLowerCase()) {
      case 'active':
        bg = AppColors.danger.withOpacity(0.12);
        fg = AppColors.danger;
        break;
      case 'in progress':
        bg = AppColors.primary.withOpacity(0.12);
        fg = AppColors.primary;
        break;
      case 'resolved':
        bg = AppColors.success.withOpacity(0.12);
        fg = AppColors.success;
        break;
      default:
        bg = Colors.orange.withOpacity(0.12);
        fg = Colors.orange;
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration:
          BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Text(status,
          style:
              TextStyle(fontSize: 10, color: fg, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildEmptyState() {
    return LayoutBuilder(
      builder: (context, constraints) {
        return ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.zero,
          children: [
            SizedBox(
              height: constraints.maxHeight,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.notifications_none_rounded,
                        size: 72, color: AppColors.grey.withOpacity(0.35)),
                    const SizedBox(height: 16),
                    Text(
                      _isOffline ? 'Nothing cached yet' : 'No notifications yet',
                      style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _isOffline
                          ? "You're offline and nothing was loaded\nbefore the connection dropped."
                          : 'Emergency reports and witness requests\nwill appear here.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontSize: 14, color: AppColors.textLight, height: 1.4),
                    ),
                    const SizedBox(height: 24),
                    ElevatedButton.icon(
                      onPressed: _loadAll,
                      icon: const Icon(Icons.refresh),
                      label: const Text('Refresh'),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ── Helpers ───────────────────────────────────────────────────────────────
  Color _colorFor(String t) {
    switch (t) {
      case 'shake':
        return AppColors.danger;
      case 'fire':
        return Colors.deepOrange;
      case 'medical':
        return Colors.red;
      case 'flood':
        return Colors.blue;
      case 'crime':
        return AppColors.secondary;
      case 'accident':
        return Colors.orange;
      default:
        return AppColors.grey;
    }
  }

  IconData _iconFor(String t) {
    switch (t) {
      case 'shake':
        return Icons.vibration;
      case 'fire':
        return Icons.local_fire_department;
      case 'medical':
        return Icons.local_hospital;
      case 'flood':
        return Icons.water;
      case 'crime':
        return Icons.gavel;
      case 'accident':
        return Icons.car_crash;
      default:
        return Icons.warning_amber_rounded;
    }
  }

  String _titleFor(String type, String reporter, bool isOwn) {
    final who = isOwn ? 'You' : reporter;
    switch (type) {
      case 'shake':
        return isOwn
            ? '🚨 You triggered a Shake SOS'
            : '🚨 $reporter triggered Shake SOS';
      case 'fire':
        return '$who reported a Fire Emergency';
      case 'medical':
        return '$who reported a Medical Emergency';
      case 'flood':
        return '$who reported a Flood Emergency';
      case 'crime':
        return '$who reported a Crime';
      case 'accident':
        return '$who reported an Accident';
      default:
        return '$who filed an Emergency Report';
    }
  }

  // Values arrive straight from the DB as raw keys like "heart_attack" — turn
  // them into something readable before they hit the UI.
  String _humanize(String raw) {
    final s = raw.replaceAll('_', ' ').trim();
    if (s.isEmpty) return s;
    return s[0].toUpperCase() + s.substring(1);
  }

  // Google Open Location Code token, e.g. "8M6G+MFG" — meaningless to users,
  // so it's stripped out of any address before display.
  static final _plusCodeRe = RegExp(
      r'\b[23456789A-CF-HJ-NP-TV-Z]{4,8}\+[23456789A-CF-HJ-NP-TV-Z]{2,3}\b',
      caseSensitive: false);

  String _stripPlusCode(String s) {
    var out = s.replaceAll(_plusCodeRe, '');
    out = out.replaceAll(RegExp(r',\s*,'), ','); // collapse the gap it leaves
    out = out.replaceAll(RegExp(r'^[,\s]+'), '');
    out = out.replaceAll(RegExp(r'[,\s]+$'), '');
    return out.trim();
  }

  // `Location.Address` is a plus-code reverse-geocode with no barangay info;
  // `Barangay` is stored separately. Join them so the barangay a report
  // happened in is actually visible, not just the city/region.
  String _locationFor(Map<String, dynamic> r) {
    final loc = r['Location'] as Map?;
    final addr = _stripPlusCode((loc?['Address'] ?? '').toString().trim());
    final brgy = (r['Barangay'] ?? '').toString().trim();
    final hasAddr = addr.isNotEmpty &&
        addr.toLowerCase() != 'location unavailable' &&
        addr.toLowerCase() != 'see map for exact location';
    final hasBrgy = brgy.isNotEmpty && brgy.toLowerCase() != 'unknown barangay';

    if (hasBrgy && hasAddr) {
      return addr.toLowerCase().contains(brgy.toLowerCase())
          ? addr
          : 'Brgy. $brgy, $addr';
    }
    if (hasBrgy) return 'Brgy. $brgy';
    if (hasAddr) return addr;
    return 'Location unavailable';
  }

  String _subtitleFor(Map<String, dynamic> r) {
    final type = (r['EmergencyType'] ?? 'other').toString();
    final d = r['Details'] as Map?;

    String detail;
    switch (type) {
      case 'shake':
        detail = 'Automatic SOS via shake gesture';
        break;
      case 'fire':
        final ft = (d?['fireType'] ?? 'fire').toString();
        final trap = d?['peopleTrapped'] == true
            ? ' · ${d?['numberOfPeople'] ?? 1} trapped'
            : '';
        detail = '${_humanize(ft)} fire$trap';
        break;
      case 'medical':
        detail = _humanize((d?['condition'] ?? 'Medical emergency').toString());
        break;
      case 'flood':
        detail = 'Water level: ${_humanize((d?['waterLevel'] ?? 'unknown').toString())}';
        break;
      case 'crime':
        detail = _humanize((d?['crimeType'] ?? 'Crime reported').toString());
        break;
      case 'accident':
        detail = _humanize((d?['accidentType'] ?? 'Accident').toString());
        break;
      default:
        detail = (d?['description'] ?? 'Emergency report').toString();
    }

    return detail;
  }

  static const List<String> _months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  String _relativeTime(dynamic raw) {
    if (raw == null) return '';
    final ts = _parseTs(raw.toString());
    if (ts == null) return raw.toString();
    final now = DateTime.now();
    final diff = now.difference(ts);
    if (diff.inSeconds < 60) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    // Past a week, "132d ago" stops meaning anything — show a real date.
    final month = _months[ts.month - 1];
    return ts.year == now.year
        ? '${ts.day} $month'
        : '${ts.day} $month ${ts.year}';
  }

  DateTime? _parseTs(String raw) {
    final iso = DateTime.tryParse(raw);
    if (iso != null) return iso;
    try {
      final p = raw.split(' ');
      if (p.length == 2) {
        final d = p[0].split('/');
        final t = p[1].split(':');
        if (d.length == 3 && t.length == 3) {
          return DateTime(int.parse(d[2]), int.parse(d[0]), int.parse(d[1]),
              int.parse(t[0]), int.parse(t[1]), int.parse(t[2]));
        }
      }
    } catch (_) {}
    return null;
  }
}

// ── Swipe-to-delete wrapper ─────────────────────────────────────────────────
//
// Fades and shrinks the card in step with the drag so it dissolves toward the
// delete action instead of sliding off fully opaque. Drag progress lives in a
// ValueNotifier rather than setState so each frame repaints only this card,
// not the whole notification list.
class _SwipeToDeleteCard extends StatefulWidget {
  const _SwipeToDeleteCard({
    super.key,
    required this.child,
    required this.dismissKey,
    required this.onDismissed,
  });

  final Widget child;
  final String dismissKey;
  final VoidCallback onDismissed;

  @override
  State<_SwipeToDeleteCard> createState() => _SwipeToDeleteCardState();
}

class _SwipeToDeleteCardState extends State<_SwipeToDeleteCard> {
  final ValueNotifier<double> _progress = ValueNotifier<double>(0);

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Dismissible(
      key: Key(widget.dismissKey),
      direction: DismissDirection.endToStart,
      // Longer than the 200ms/300ms defaults so the card glides out and the
      // row collapses gently rather than snapping shut.
      movementDuration: const Duration(milliseconds: 320),
      resizeDuration: const Duration(milliseconds: 280),
      dismissThresholds: const {DismissDirection.endToStart: 0.35},
      onUpdate: (details) => _progress.value = details.progress,
      // Remove from state only once the slide + collapse has finished. Doing
      // it mid-gesture (the old confirmDismiss) dropped the card from the
      // list immediately, so it blinked away instead of animating out.
      onDismissed: (_) => widget.onDismissed(),
      background: ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (_, progress, __) => _buildDeleteBackground(progress),
      ),
      child: ValueListenableBuilder<double>(
        valueListenable: _progress,
        builder: (_, progress, child) {
          final t = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
          return Opacity(
            opacity: 1 - (t * 0.75),
            child: Transform.scale(scale: 1 - (t * 0.06), child: child),
          );
        },
        child: widget.child,
      ),
    );
  }

  Widget _buildDeleteBackground(double progress) {
    final t = Curves.easeOut.transform(progress.clamp(0.0, 1.0));
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        // Deepens toward full red as the drag approaches the threshold.
        color: Color.lerp(const Color(0xFFFFCDD2), Colors.red, t),
        borderRadius: BorderRadius.circular(16),
      ),
      alignment: Alignment.centerRight,
      padding: const EdgeInsets.only(right: 24),
      child: Opacity(
        opacity: t,
        child: Transform.scale(
          scale: 0.8 + (t * 0.2),
          child: const Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.delete_outline, color: Colors.white, size: 28),
              SizedBox(height: 4),
              Text('Delete',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ],
          ),
        ),
      ),
    );
  }
}
