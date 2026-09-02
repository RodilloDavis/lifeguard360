// lib/services/user_reports_cache_service.dart
//
// Same incremental-sync strategy as ReportHistoryCacheService, applied to a
// user's OWN report history (/UserEmergencyReports/{userId}) instead of a
// family's. Added because that node was being fully re-downloaded — every
// entry, resolved or not, plus a per-report canonical-status check on every
// still-open one — on every single poll tick by every caller that wanted a
// user's own reports: NotificationCountService (every 10s, running on any
// screen with the bell badge), My Reports (every 12s), and the notification
// screen's dispatcher-update check (every 10s). None of that history ever
// shrinks, so the cost of each of those polls only ever grew with a user's
// tenure in the app. Routing all three through this cache instead means only
// the very first load per install pays for the full history; every poll
// after that transfers just what's new or still unresolved.
//
// See ReportHistoryCacheService for the full rationale — this is the same
// logic, scoped to a userId instead of a familyCode. In particular, "new
// since last sync" is found by existence-diffing a `shallow=true` key list
// against the ReportIds already cached, NOT by a cursor: a ReportId-based
// cursor only sorts correctly within one report-type prefix (BBL-/SHK-/
// CRM-/FIR-/...), and switching to a Timestamp-based cursor instead needs a
// server-side `".indexOn"` rule this project's Firebase rules don't define
// for this path — that combination is what let a family member's fresh
// report sit invisible in Notifications despite being unread.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'emergency_report_service.dart';

class UserReportsCacheService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  static String _reportsKey(String userId) => 'user_reports_cache_$userId';

  /// No-network read of whatever is cached for [userId]. Null on a
  /// first-ever call (nothing cached yet).
  static Future<List<Map<String, dynamic>>?> getCachedReports(
      String userId) async {
    if (userId.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return _readCache(prefs, userId);
  }

  /// Same age bound as ReportHistoryCacheService — see its doc comment.
  static const Duration _autoReconcileWindow = Duration(days: 14);

  // Same reentrancy guard as ReportHistoryCacheService, for the same
  // reason: NotificationCountService, My Reports, and the notification
  // screen all poll this on their own ~10s timers.
  static final Map<String, Future<List<Map<String, dynamic>>>> _inFlight = {};

  /// Brings the cache up to date and returns the full, current list of the
  /// user's own reports.
  static Future<List<Map<String, dynamic>>> syncAndGetReports(
    String userId, {
    bool forceFullReconcile = false,
  }) {
    if (userId.isEmpty) return Future.value(<Map<String, dynamic>>[]);
    final pending = _inFlight[userId];
    if (pending != null) return pending;

    final future =
        _syncAndGetReports(userId, forceFullReconcile: forceFullReconcile);
    _inFlight[userId] = future;
    future.whenComplete(() => _inFlight.remove(userId));
    return future;
  }

  static Future<List<Map<String, dynamic>>> _syncAndGetReports(
    String userId, {
    bool forceFullReconcile = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _readCache(prefs, userId);

    if (cached == null) {
      final all = await EmergencyReportService.getUserReports(userId,
          throwOnError: true);
      await _writeCache(prefs, userId, all);
      return all;
    }

    final byId = <String, Map<String, dynamic>>{
      for (final r in cached)
        if ((r['ReportId']?.toString() ?? '').isNotEmpty)
          r['ReportId'].toString(): r,
    };

    final newOnes = await _fetchNewReports(
        '${_dbUrl}UserEmergencyReports/$userId', byId.keys.toSet());
    final newIds = <String>{};
    for (final r in newOnes) {
      final id = r['ReportId']?.toString() ?? '';
      if (id.isEmpty) continue;
      byId[id] = r;
      newIds.add(id);
    }

    // New reports are cached and returned right here, without waiting on
    // the status-reconcile pass — see ReportHistoryCacheService for why
    // that step can outlast a poll interval by a wide margin and must not
    // gate a new report's visibility.
    final quickMerged = byId.values.toList()
      ..sort((a, b) => _parseCreatedAt(b['CreatedAt']?.toString())
          .compareTo(_parseCreatedAt(a['CreatedAt']?.toString())));
    await _writeCache(prefs, userId, quickMerged);

    if (!_reconciling.contains(userId)) {
      _reconciling.add(userId);
      unawaited(
          _reconcileInBackground(userId, byId, newIds, forceFullReconcile)
              .whenComplete(() => _reconciling.remove(userId)));
    }

    return quickMerged;
  }

  // Same reasoning as ReportHistoryCacheService's _reconciling set.
  static final Set<String> _reconciling = {};

  static Future<void> _reconcileInBackground(
    String userId,
    Map<String, Map<String, dynamic>> byId,
    Set<String> newIds,
    bool forceFullReconcile,
  ) async {
    try {
      final cutoff = DateTime.now().subtract(_autoReconcileWindow);
      final toReconcile = forceFullReconcile
          ? byId.values.toList()
          : byId.values.where((r) {
              final id = r['ReportId']?.toString() ?? '';
              if (newIds.contains(id)) return true;
              final created = _parseCreatedAt(r['CreatedAt']?.toString());
              return created.isAfter(cutoff);
            }).toList();

      final reconciled =
          await EmergencyReportService.reconcileStatuses(toReconcile);
      for (final r in reconciled) {
        final id = r['ReportId']?.toString() ?? '';
        if (id.isNotEmpty) byId[id] = r;
      }

      final merged = byId.values.toList()
        ..sort((a, b) => _parseCreatedAt(b['CreatedAt']?.toString())
            .compareTo(_parseCreatedAt(a['CreatedAt']?.toString())));

      final prefs = await SharedPreferences.getInstance();
      await _writeCache(prefs, userId, merged);
    } catch (_) {
      // Best-effort — see ReportHistoryCacheService's version of this.
    }
  }

  /// See ReportHistoryCacheService._fetchNewReports — identical strategy.
  static Future<List<Map<String, dynamic>>> _fetchNewReports(
      String nodeUrl, Set<String> knownIds) async {
    try {
      final shallowResp = await http
          .get(Uri.parse('$nodeUrl.json')
              .replace(queryParameters: {'shallow': 'true'}))
          .timeout(const Duration(seconds: 15));
      if (shallowResp.statusCode != 200) return [];

      final shallowData = json.decode(shallowResp.body);
      if (shallowData is! Map) return [];

      final newIds = shallowData.keys
          .map((k) => k.toString())
          .where((id) => !knownIds.contains(id))
          .toList();
      if (newIds.isEmpty) return [];

      final out = <Map<String, dynamic>>[];
      const batchSize = 8;
      for (var i = 0; i < newIds.length; i += batchSize) {
        final batch = newIds.skip(i).take(batchSize);
        final results = await Future.wait(batch.map((id) async {
          try {
            final resp = await http
                .get(Uri.parse('$nodeUrl/$id.json'))
                .timeout(const Duration(seconds: 10));
            if (resp.statusCode != 200) return null;
            final data = json.decode(resp.body);
            return data is Map ? Map<String, dynamic>.from(data) : null;
          } catch (_) {
            return null;
          }
        }));
        out.addAll(results.whereType<Map<String, dynamic>>());
      }
      return out;
    } catch (_) {
      return [];
    }
  }

  static List<Map<String, dynamic>>? _readCache(
      SharedPreferences prefs, String userId) {
    final raw = prefs.getString(_reportsKey(userId));
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(SharedPreferences prefs, String userId,
      List<Map<String, dynamic>> reports) async {
    await prefs.setString(_reportsKey(userId), json.encode(reports));
  }

  static DateTime _parseCreatedAt(String? s) =>
      EmergencyReportService.parseReportTimestamp(s) ?? DateTime(0);

  /// Drops the cached history for [userId] — e.g. on logout.
  static Future<void> clear(String userId) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_reportsKey(userId));
  }
}
