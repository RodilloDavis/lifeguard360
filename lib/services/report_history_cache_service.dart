// lib/services/report_history_cache_service.dart
//
// Local cache for ReportHistoryScreen. Firebase's /FamilyReports/{reportId}
// nodes are only ever appended to or status-patched — nothing is ever
// removed — so once a report is downloaded and its Status is Resolved, it
// never needs to be fetched again. This lets repeat visits to Report
// History (a screen with a genuinely unbounded, ever-growing history) skip
// re-downloading everything: the whole family's report history is fetched
// once, cached on-device, and afterwards only two small, cheap requests are
// made — new report IDs since the last sync (server-side key-range filter,
// not a full re-fetch) and a Status re-check for whatever's still not
// Resolved. Already-resolved cached reports are never touched again.
//
// Report IDs are generated as "{PREFIX}-{millisecondsSinceEpoch}-{suffix}"
// (see EmergencyReportService._generateReportId), so lexical key order
// tracks creation order — which is what makes the server-side "give me
// every key >= this one" query below work as an incremental cursor.

import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'emergency_report_service.dart';

class ReportHistoryCacheService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  static String _reportsKey(String familyCode) =>
      'report_history_cache_$familyCode';
  static String _cursorKey(String familyCode) =>
      'report_history_cursor_$familyCode';

  /// Reads whatever is cached on-device for [familyCode] with no network
  /// call — lets the screen paint instantly on repeat visits while a sync
  /// happens in the background. Returns null when nothing has been cached
  /// yet (first-ever visit).
  static Future<List<Map<String, dynamic>>?> getCachedReports(
      String familyCode) async {
    if (familyCode.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return _readCache(prefs, familyCode);
  }

  /// Automatic background syncs (screen open, pull-to-refresh) only
  /// status-check cached non-Resolved reports created within this window —
  /// a report that's sat un-resolved for over 2 weeks is rarely still
  /// actively moving, and this is what keeps every visit's network cost
  /// bounded no matter how large the family's total history grows. Pass
  /// `forceFullReconcile: true` (used by the explicit refresh button) to
  /// check every non-Resolved report regardless of age.
  static const Duration _autoReconcileWindow = Duration(days: 14);

  /// Brings the cache up to date and returns the full, current report list.
  ///
  /// - No cache yet → one full download (same as the old behaviour), then
  ///   cached for every visit after this.
  /// - Cache present → only new reports (added since the last sync) are
  ///   downloaded. Status is re-checked for those new reports plus any
  ///   cached-but-unresolved report within [_autoReconcileWindow] — unless
  ///   [forceFullReconcile] is set, in which case every unresolved report
  ///   is checked regardless of age. Either way, checks that do run are
  ///   sent in small batches (see EmergencyReportService.reconcileStatuses)
  ///   so a large history never bursts open a huge number of connections
  ///   at once — the thing that made this screen feel like it needed a
  ///   strong connection in the first place.
  static Future<List<Map<String, dynamic>>> syncAndGetReports(
    String familyCode, {
    bool forceFullReconcile = false,
  }) async {
    if (familyCode.isEmpty) return [];
    final prefs = await SharedPreferences.getInstance();
    final cached = _readCache(prefs, familyCode);
    final cursor = prefs.getString(_cursorKey(familyCode));

    if (cached == null || cursor == null) {
      // First visit for this family (or a corrupted/cleared cache) — only
      // path that pulls the entire history.
      final all = await EmergencyReportService.getFamilyReports(familyCode,
          throwOnError: true);
      await _writeCache(prefs, familyCode, all);
      return all;
    }

    final byId = <String, Map<String, dynamic>>{
      for (final r in cached)
        if ((r['ReportId']?.toString() ?? '').isNotEmpty)
          r['ReportId'].toString(): r,
    };

    // ── 1. Only reports created since the last sync ───────────────────────
    final newOnes = await _fetchReportsSince(familyCode, cursor);
    final newIds = <String>{};
    for (final r in newOnes) {
      final id = r['ReportId']?.toString() ?? '';
      if (id.isEmpty) continue;
      byId[id] = r;
      newIds.add(id);
    }

    // ── 2. Status re-check — every new report, plus recent unresolved ones
    final cutoff = DateTime.now().subtract(_autoReconcileWindow);
    final toReconcile = forceFullReconcile
        ? byId.values.toList()
        : byId.values.where((r) {
            final id = r['ReportId']?.toString() ?? '';
            if (newIds.contains(id)) return true; // always check new reports
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
      ..sort((a, b) =>
          _parseCreatedAt(b['CreatedAt']?.toString())
              .compareTo(_parseCreatedAt(a['CreatedAt']?.toString())));

    await _writeCache(prefs, familyCode, merged);
    return merged;
  }

  /// Server-side key-range fetch: every /FamilyReports child whose key
  /// (=ReportId) sorts at or after [cursor]. Firebase's REST `startAt` is
  /// inclusive, so the cursor's own report — already in the cache — is
  /// filtered back out below rather than re-merged.
  static Future<List<Map<String, dynamic>>> _fetchReportsSince(
      String familyCode, String cursor) async {
    final uri = Uri.parse('${_dbUrl}Families/$familyCode/FamilyReports.json')
        .replace(queryParameters: {
      'orderBy': '"\$key"',
      'startAt': '"$cursor"',
    });

    final resp = await http.get(uri).timeout(const Duration(seconds: 15));
    if (resp.statusCode != 200) return [];

    final data = json.decode(resp.body);
    if (data is! Map) return [];

    final out = <Map<String, dynamic>>[];
    data.forEach((key, value) {
      if (key == cursor) return; // already cached from the previous sync
      if (value is Map) out.add(Map<String, dynamic>.from(value));
    });
    return out;
  }

  static List<Map<String, dynamic>>? _readCache(
      SharedPreferences prefs, String familyCode) {
    final raw = prefs.getString(_reportsKey(familyCode));
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(SharedPreferences prefs, String familyCode,
      List<Map<String, dynamic>> reports) async {
    await prefs.setString(_reportsKey(familyCode), json.encode(reports));
    final cursor = _maxReportId(reports);
    if (cursor != null) {
      await prefs.setString(_cursorKey(familyCode), cursor);
    }
  }

  /// The lexically greatest ReportId — see file header on why key order
  /// tracks creation order and doubles as the incremental-sync cursor.
  static String? _maxReportId(List<Map<String, dynamic>> reports) {
    String? max;
    for (final r in reports) {
      final id = r['ReportId']?.toString() ?? '';
      if (id.isEmpty) continue;
      if (max == null || id.compareTo(max) > 0) max = id;
    }
    return max;
  }

  static DateTime _parseCreatedAt(String? s) =>
      EmergencyReportService.parseReportTimestamp(s) ?? DateTime(0);

  /// Drops the cached history for [familyCode] — e.g. on logout, or a
  /// family-code change, where cached reports would belong to the wrong
  /// family entirely.
  static Future<void> clear(String familyCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_reportsKey(familyCode));
    await prefs.remove(_cursorKey(familyCode));
  }
}
