// lib/services/report_history_cache_service.dart
//
// Local cache for ReportHistoryScreen (and, via syncAndGetReports, every
// other screen that needs a family's report list — the notification badge,
// My Reports, the notification screen). Firebase's /FamilyReports/{reportId}
// nodes are only ever appended to or status-patched — nothing is ever
// removed — so once a report is downloaded and its Status is Resolved, it
// never needs to be fetched again. This lets repeat visits skip
// re-downloading everything: the whole family's report history is fetched
// once, cached on-device, and afterwards only two small, cheap requests are
// made — new reports since the last sync and a Status re-check for whatever
// still isn't Resolved. Already-resolved cached reports are never touched
// again.
//
// "New since last sync" is found by existence-diffing, not by a cursor.
// Two cursor designs were tried and both turned out unsafe for this data:
//   - The lexically-greatest ReportId ("{PREFIX}-{millisecondsSinceEpoch}-
//     {suffix}") only sorts correctly WITHIN one prefix (BBL-/SHK-/CRM-/
//     FIR-/...) — across prefixes it compares the letters first, so e.g. a
//     cursor pinned to the newest "SHK-..." report made every later
//     "FIR-..." or "BBL-..." report compare as "already synced" and vanish
//     silently. This is how a family member's fresh report ended up
//     invisible in Notifications despite being unread.
//   - Switching the cursor to each report's Timestamp field (ISO-8601,
//     which DOES sort correctly regardless of type) fixes that, but
//     Firebase Realtime Database rejects `orderBy` on any field besides
//     $key/$value unless the project's security rules declare
//     `".indexOn": "Timestamp"` for this path — which this project's rules
//     don't. The query came back as an HTTP 400 that this code was
//     treating as "nothing new", so no report ever synced at all.
// Firebase's `shallow=true` param needs no such index — it costs one small
// request for every CURRENT report's key (no bodies), diffed client-side
// against the ReportIds already cached to find what's actually new. Full
// bodies are then fetched only for those. Slightly more bytes per poll than
// a perfect cursor would cost (the shallow key list grows with the family's
// total history), but nowhere near what a full-body re-fetch costs, immune
// to any prefix/ordering quirk, and needs no server-side rule changes.

import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'emergency_report_service.dart';

class ReportHistoryCacheService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  static String _reportsKey(String familyCode) =>
      'report_history_cache_$familyCode';

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

  // Three independent screens/services now poll this on their own ~10-12s
  // timers (NotificationCountService, My Reports, the notification screen).
  // Without this guard, overlapping calls would each redo the same shallow
  // diff + reconcile work concurrently. Keying one shared in-flight Future
  // per familyCode means every concurrent caller awaits the SAME sync.
  static final Map<String, Future<List<Map<String, dynamic>>>> _inFlight = {};

  /// Brings the cache up to date and returns the full, current report list.
  ///
  /// - No cache yet → one full download (same as the old behaviour), then
  ///   cached for every visit after this.
  /// - Cache present → only genuinely new reports (existence-diffed via a
  ///   shallow key fetch — see file header) are downloaded in full. Status
  ///   is re-checked for those new reports plus any cached-but-unresolved
  ///   report within [_autoReconcileWindow] — unless [forceFullReconcile]
  ///   is set, in which case every unresolved report is checked regardless
  ///   of age. That reconcile pass runs in the BACKGROUND after this
  ///   returns (see _reconcileInBackground) rather than blocking on it — a
  ///   family with most of its history still open can make that pass fan
  ///   out into dozens of individual status checks and take far longer
  ///   than one poll interval, and new-report visibility must not wait on
  ///   that.
  static Future<List<Map<String, dynamic>>> syncAndGetReports(
    String familyCode, {
    bool forceFullReconcile = false,
  }) {
    if (familyCode.isEmpty) return Future.value(<Map<String, dynamic>>[]);
    final pending = _inFlight[familyCode];
    if (pending != null) return pending;

    final future = _syncAndGetReports(familyCode,
        forceFullReconcile: forceFullReconcile);
    _inFlight[familyCode] = future;
    future.whenComplete(() => _inFlight.remove(familyCode));
    return future;
  }

  static Future<List<Map<String, dynamic>>> _syncAndGetReports(
    String familyCode, {
    bool forceFullReconcile = false,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    final cached = _readCache(prefs, familyCode);

    if (cached == null) {
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

    // ── Only reports Firebase currently has that aren't already cached ────
    final newOnes = await _fetchNewReports(
        '${_dbUrl}Families/$familyCode/FamilyReports', byId.keys.toSet());
    final newIds = <String>{};
    for (final r in newOnes) {
      final id = r['ReportId']?.toString() ?? '';
      if (id.isEmpty) continue;
      byId[id] = r;
      newIds.add(id);
    }

    final quickMerged = byId.values.toList()
      ..sort((a, b) => _parseCreatedAt(b['CreatedAt']?.toString())
          .compareTo(_parseCreatedAt(a['CreatedAt']?.toString())));
    await _writeCache(prefs, familyCode, quickMerged);

    if (!_reconciling.contains(familyCode)) {
      _reconciling.add(familyCode);
      unawaited(_reconcileInBackground(
              familyCode, byId, newIds, forceFullReconcile)
          .whenComplete(() => _reconciling.remove(familyCode)));
    }

    return quickMerged;
  }

  // Guards the background reconcile pass separately from _inFlight (which
  // only covers the fast part above): without this, a slow reconcile still
  // running from one poll would have a fresh one kicked off by every poll
  // after it — the exact pile-up of overlapping heavy work this whole
  // change exists to avoid, just moved one step later.
  static final Set<String> _reconciling = {};

  static Future<void> _reconcileInBackground(
    String familyCode,
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
      await _writeCache(prefs, familyCode, merged);
    } catch (_) {
      // Best-effort — a failed background reconcile just means status
      // changes are caught on a later attempt instead of this one; the
      // report list itself was already returned to the caller above.
    }
  }

  /// Finds reports that exist under [nodeUrl] (no trailing .json) but
  /// aren't in [knownIds], and returns their full bodies.
  ///
  /// Step 1 is a `shallow=true` GET — Firebase returns just
  /// `{reportId: true, ...}` for every child with no need to fetch or order
  /// by anything but $key, so it costs no index and no per-report payload.
  /// Step 2 fetches full bodies only for the id's Step 1 didn't already
  /// have cached, in small concurrent batches (same reasoning as
  /// EmergencyReportService.reconcileStatuses — bounds how many
  /// connections a family with a lot of genuinely new reports opens at
  /// once).
  static Future<List<Map<String, dynamic>>> _fetchNewReports(
      String nodeUrl, Set<String> knownIds) async {
    try {
      final shallowResp = await http
          .get(Uri.parse('$nodeUrl.json').replace(
              queryParameters: {'shallow': 'true'}))
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
  }

  static DateTime _parseCreatedAt(String? s) =>
      EmergencyReportService.parseReportTimestamp(s) ?? DateTime(0);

  /// Drops the cached history for [familyCode] — e.g. on logout, or a
  /// family-code change, where cached reports would belong to the wrong
  /// family entirely.
  static Future<void> clear(String familyCode) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_reportsKey(familyCode));
  }
}
