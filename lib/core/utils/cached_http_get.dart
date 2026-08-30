// lib/core/utils/cached_http_get.dart
//
// Several services poll overlapping Firebase REST endpoints on their own
// independent timers (EmergencyStatusService, NotificationCountService,
// EmergencyReportService's status reconciliation, the dashboard's per-member
// status poll, ...). When two of those timers land within the same few
// seconds — which they routinely do, since most polling is on ~10s cadences
// started at slightly different times — they were issuing two separate HTTP
// round-trips for the exact same URL and throwing one result away. This
// wrapper makes `http.get` for the same URL within [ttl] return the same
// in-flight or cached response instead, cutting duplicate network usage
// without any call site needing to know about it.
//
// OFFLINE/WEAK-CONNECTION BEHAVIOR: on top of the short in-memory TTL above,
// every successful response is also written to a disk-backed cache
// (SharedPreferences). When the connection is classified weak or offline
// (see ConnectivityQualityService), a call for a URL that's been fetched
// before returns that disk-cached response immediately — no network attempt
// at all — instead of hanging on a slow request or surfacing a hard
// failure. The moment the connection is strong again,
// ConnectivityQualityService clears the in-memory TTL cache (see
// invalidateAll below), so the very next call for any URL goes to the
// network and refreshes both tiers — every screen already polling on its
// own timer picks this up automatically on its next tick, with no
// screen-specific "sync" code needed.
import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../services/connectivity_quality_service.dart';

class _CacheEntry {
  final http.Response response;
  final DateTime expiresAt;
  _CacheEntry(this.response, this.expiresAt);
}

class CachedHttpGet {
  CachedHttpGet._();

  static final Map<String, _CacheEntry> _cache = {};
  static final Map<String, Future<http.Response>> _inFlight = {};

  static const String _diskPrefix = 'http_cache_v1_';

  /// GETs [uri], reusing a response fetched for the same URL within [ttl]
  /// (default 4s — short enough that no caller ever sees stale data across a
  /// full poll cycle on a good connection, long enough to collapse
  /// near-simultaneous callers). Concurrent calls for the same URL share one
  /// in-flight request rather than issuing their own.
  ///
  /// On a weak/offline connection (see ConnectivityQualityService), a URL
  /// that's been fetched successfully before is served from disk instead of
  /// attempting the network at all — see the file header.
  static Future<http.Response> get(
    Uri uri, {
    Duration ttl = const Duration(seconds: 4),
    Duration timeout = const Duration(seconds: 10),
  }) {
    final key = uri.toString();

    final cached = _cache[key];
    if (cached != null && cached.expiresAt.isAfter(DateTime.now())) {
      return Future.value(cached.response);
    }

    final pending = _inFlight[key];
    if (pending != null) return pending;

    final future = _fetch(key, uri, ttl, timeout);
    _inFlight[key] = future;
    return future;
  }

  static Future<http.Response> _fetch(
      String key, Uri uri, Duration ttl, Duration timeout) async {
    try {
      if (ConnectivityQualityService.current != ConnectionQuality.strong) {
        final disk = await _readDisk(key);
        if (disk != null) {
          _cache[key] = _CacheEntry(disk, DateTime.now().add(ttl));
          _inFlight.remove(key);
          return disk;
        }
        // Nothing cached for this URL yet — still worth one real attempt,
        // since a disk-cache miss means there's nothing else to show.
      }

      final response = await http.get(uri).timeout(timeout);
      _cache[key] = _CacheEntry(response, DateTime.now().add(ttl));
      _inFlight.remove(key);
      if (response.statusCode == 200) {
        unawaited(_writeDisk(key, response));
      }
      return response;
    } catch (e) {
      _inFlight.remove(key);
      // The network attempt itself failed (timeout, no route, etc.) — fall
      // back to whatever's on disk rather than surfacing the failure
      // straight to the caller, which is exactly the weak-connection case
      // ConnectivityQualityService's own probe might not have caught yet.
      final disk = await _readDisk(key);
      if (disk != null) return disk;
      rethrow;
    }
  }

  static Future<http.Response?> _readDisk(String key) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_diskKey(key));
      if (raw == null) return null;
      final decoded = json.decode(raw) as Map<String, dynamic>;
      return http.Response(
        decoded['body'] as String,
        decoded['statusCode'] as int,
      );
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeDisk(String key, http.Response response) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(
        _diskKey(key),
        json.encode({
          'body': response.body,
          'statusCode': response.statusCode,
        }),
      );
    } catch (_) {
      // Best-effort — losing a disk-cache write just means the next
      // weak-connection load for this URL falls through to a real network
      // attempt instead of an instant cached one.
    }
  }

  static String _diskKey(String urlKey) => '$_diskPrefix${urlKey.hashCode}';

  /// Drops every in-memory (short-TTL) entry so the next call for any URL
  /// goes to the network instead of returning a still-fresh-by-TTL cached
  /// response. Called by ConnectivityQualityService the moment the
  /// connection goes from weak/offline back to strong, so already-open
  /// screens' next scheduled poll picks up live data immediately instead of
  /// waiting out whatever's left of each entry's TTL.
  static void invalidateAll() {
    _cache.clear();
  }
}
