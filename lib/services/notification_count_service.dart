// lib/services/notification_count_service.dart
//
// ═══════════════════════════════════════════════════════════════════════════════
// NOTIFICATION BADGE COUNT
// ═══════════════════════════════════════════════════════════════════════════════
//
// The unread count behind the bell badge, shared by every screen that shows
// one (dashboard, map, alert contacts). Those screens each carried their own
// copy of this arithmetic and had drifted from what the notification screen
// actually displays — most visibly by counting the user's OWN reports, so
// filing a report lit up your own badge for something you just did yourself.
//
// Reports are family-scoped: a report notifies the OTHER members of the
// family, never its author. The author sees it in My Reports instead, and
// hears back only when a responder is assigned or the report is resolved.
//
// The rules here mirror the visibility getters in NotificationScreen
// (_visibleReports, _visibleAssignedReports, _visibleResolvedReports,
// _visibleDispatcherMessages) — change one, change the other, or the badge
// and the list it opens will disagree.

import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart' show debugPrint;
import 'package:shared_preferences/shared_preferences.dart';

import '../core/utils/cached_http_get.dart';
import 'emergency_report_service.dart';
import 'firebase_realtime_database.dart';
import 'report_history_cache_service.dart';
import 'user_reports_cache_service.dart';

class NotificationCountService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  // ═══════════════════════════════════════════════════════════════════════
  // SHARED SINGLETON POLLER
  // ═══════════════════════════════════════════════════════════════════════
  //
  // Every screen that shows the bell badge (dashboard, map, alert contacts)
  // used to run its own independent 10s Timer.periodic calling
  // unreadCount() — and since DashboardScreen's IndexedStack keeps
  // DashboardHome + MapScreen mounted at the same time, opening the
  // dashboard alone already meant 2 concurrent pollers for identical data,
  // before counting any screen pushed on top. This mirrors
  // EmergencyStatusService's proven pattern instead: one timer, one fetch
  // group, any number of listeners.
  static NotificationCountService? _instance;
  static NotificationCountService get instance =>
      _instance ??= NotificationCountService._();
  NotificationCountService._();

  Timer? _pollTimer;
  String? _currentUserId;
  int? _lastCount;
  final List<StreamController<int>> _controllers = [];

  /// Idempotent — a second call with the same [userId] while already
  /// polling is a no-op, so any screen's initState can call this freely
  /// without needing to know whether another screen already started it.
  void startPolling(String userId) {
    if (userId.isEmpty) return;
    if (_currentUserId == userId && _pollTimer != null) return;
    _pollTimer?.cancel();
    _currentUserId = userId;
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetch(userId);
    });
    _fetch(userId); // immediate
  }

  void pause() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void resume() {
    final userId = _currentUserId;
    if (userId == null || userId.isEmpty) return;
    if (_pollTimer != null) return; // already running
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _fetch(userId);
    });
    _fetch(userId); // catch up immediately
  }

  /// [controller] is replayed the last known count immediately on attach
  /// (if one exists) so a newly-mounted screen's badge doesn't flicker to 0
  /// while waiting for the next tick.
  void addListener(StreamController<int> controller) {
    _controllers.add(controller);
    if (_lastCount != null) controller.add(_lastCount!);
  }

  void removeListener(StreamController<int> controller) {
    _controllers.remove(controller);
  }

  /// One-off immediate re-check without touching the timer — for a screen
  /// that wants to catch up right away after an action that likely changed
  /// the count (e.g. returning from the notifications list), even though
  /// polling was never paused so resume() would otherwise no-op.
  void refreshNow() {
    final userId = _currentUserId;
    if (userId != null && userId.isNotEmpty) _fetch(userId);
  }

  Future<void> _fetch(String userId) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      var familyCode = prefs.getString('familyCode') ?? '';
      if (familyCode.isEmpty) {
        final account = await FirebaseService.getUserById(userId);
        familyCode = account?['familyCode']?.toString() ?? '';
      }
      final count = await unreadCount(
        userId: userId,
        familyCode: familyCode,
        throwOnError: true,
      );
      _lastCount = count;
      for (final c in _controllers) {
        if (!c.isClosed) c.add(count);
      }
    } catch (e) {
      debugPrint('⚠️ NotificationCountService polling: $e');
      // Leave _lastCount (and every listener's current badge) as-is, same
      // as each screen's own catch block used to do individually.
    }
  }

  /// Number of unread notifications for [userId], matching what the
  /// notification screen would show them right now. Returns 0 on failure
  /// unless [throwOnError] is set — callers that poll this repeatedly and
  /// keep the previous count on screen should set it, so a dropped request
  /// doesn't read as "0 unread" and silently hide the badge; one-shot
  /// callers that have nothing to protect can leave it at the default.
  ///
  /// New callers that need to POLL this on a timer should use
  /// [NotificationCountService.instance]'s startPolling/addListener instead
  /// of running their own Timer.periodic against this static method — see
  /// the singleton section above for why.
  static Future<int> unreadCount({
    required String userId,
    required String familyCode,
    bool throwOnError = false,
  }) async {
    if (userId.isEmpty) return 0;
    try {
      final prefs = await SharedPreferences.getInstance();

      // Routed through the incremental caches instead of
      // EmergencyReportService.getFamilyReports()/getUserReports() directly:
      // this method is polled every 10s by every screen showing the bell
      // badge, and those two calls used to re-download BOTH histories in
      // full — every past resolved report included — on every single tick,
      // forever. The cache services fetch the full history once and only
      // the delta (new reports + still-unresolved ones) after that, so
      // repeat polls cost a small fraction of what they used to regardless
      // of how long the family's/user's history has grown.
      final results = await Future.wait([
        familyCode.isEmpty
            ? Future.value(<Map<String, dynamic>>[])
            : ReportHistoryCacheService.syncAndGetReports(familyCode),
        UserReportsCacheService.syncAndGetReports(userId),
        _pendingWitnessCount(userId, prefs, throwOnError: true),
      ]);

      final familyReports = results[0] as List<Map<String, dynamic>>;
      final ownReports = results[1] as List<Map<String, dynamic>>;
      final pendingWitness = results[2] as int;

      return _familyReportCount(familyReports, userId, prefs) +
          _ownReportUpdateCount(ownReports, prefs) +
          pendingWitness;
    } catch (e) {
      debugPrint('⚠️ NotificationCountService.unreadCount: $e');
      if (throwOnError) rethrow;
      return 0;
    }
  }

  // Reports filed by OTHER family members. The user's own reports are
  // deliberately excluded — that's the family-scoping rule above.
  static int _familyReportCount(
    List<Map<String, dynamic>> reports,
    String userId,
    SharedPreferences prefs,
  ) {
    final readIds = (prefs.getStringList('notif_read_ids') ?? []).toSet();
    final deletedIds = (prefs.getStringList('notif_deleted_ids') ?? []).toSet();

    return reports.where((r) {
      final id = r['ReportId']?.toString() ?? '';
      if ((r['UserId']?.toString() ?? '') == userId) return false;
      return !deletedIds.contains(id) && !readIds.contains(id);
    }).length;
  }

  // Updates on the user's OWN reports: a responder being assigned, the report
  // being resolved, and any dispatcher message not already carried by one of
  // those two cards.
  static int _ownReportUpdateCount(
    List<Map<String, dynamic>> ownReports,
    SharedPreferences prefs,
  ) {
    final readAssigned =
        (prefs.getStringList('notif_read_assigned_ids') ?? []).toSet();
    final deletedAssigned =
        (prefs.getStringList('notif_deleted_assigned_ids') ?? []).toSet();
    final readResolved =
        (prefs.getStringList('notif_read_resolved_ids') ?? []).toSet();
    final deletedResolved =
        (prefs.getStringList('notif_deleted_resolved_ids') ?? []).toSet();
    final readDispatcher =
        (prefs.getStringList('notif_read_dispatcher_ids') ?? []).toSet();
    final deletedDispatcher =
        (prefs.getStringList('notif_deleted_dispatcher_ids') ?? []).toSet();

    final covered = <String>{};
    var count = 0;

    for (final r in ownReports) {
      final id = r['ReportId']?.toString() ?? '';
      final status = r['Status']?.toString();

      if (EmergencyReportService.isAssignedStatus(status)) {
        if (!readAssigned.contains(id) && !deletedAssigned.contains(id)) {
          covered.add(id);
          count++;
        }
      } else if (EmergencyReportService.isResolvedStatus(status)) {
        if (!readResolved.contains(id) && !deletedResolved.contains(id)) {
          covered.add(id);
          count++;
        }
      }
    }

    for (final r in ownReports) {
      final id = r['ReportId']?.toString() ?? '';
      final message = r['DispatcherMessage']?.toString() ?? '';
      if (message.isEmpty || covered.contains(id)) continue;
      if (!readDispatcher.contains(id) && !deletedDispatcher.contains(id)) {
        count++;
      }
    }

    return count;
  }

  static Future<int> _pendingWitnessCount(
      String userId, SharedPreferences prefs,
      {bool throwOnError = false}) async {
    try {
      final resp = await CachedHttpGet.get(
        Uri.parse('${_dbUrl}WitnessRequests/$userId.json'),
        timeout: const Duration(seconds: 10),
      );
      if (resp.statusCode != 200) {
        if (throwOnError) throw Exception('HTTP ${resp.statusCode}');
        return 0;
      }
      final raw = resp.body.trim();
      if (raw == 'null' || raw.isEmpty) return 0;
      final decoded = json.decode(raw);
      if (decoded is! Map) return 0;

      final acknowledged =
          (prefs.getStringList('witness_ack_ids') ?? []).toSet();
      return decoded.keys.where((k) => !acknowledged.contains('$k')).length;
    } catch (e) {
      debugPrint('⚠️ NotificationCountService witness count: $e');
      if (throwOnError) rethrow;
      return 0;
    }
  }
}
