// lib/core/utils/cached_http_get.dart
//
// Several services poll overlapping Firebase REST endpoints on their own
// independent timers (EmergencyStatusService, NotificationCountService,
// EmergencyReportService's status reconciliation, ...). When two of those
// timers land within the same few seconds — which they routinely do, since
// most polling is on ~10s cadences started at slightly different times —
// they were issuing two separate HTTP round-trips for the exact same URL and
// throwing one result away. This wrapper makes `http.get` for the same URL
// within [ttl] return the same in-flight or cached response instead, cutting
// duplicate network usage without any call site needing to know about it.
import 'dart:async';
import 'package:http/http.dart' as http;

class _CacheEntry {
  final http.Response response;
  final DateTime expiresAt;
  _CacheEntry(this.response, this.expiresAt);
}

class CachedHttpGet {
  CachedHttpGet._();

  static final Map<String, _CacheEntry> _cache = {};
  static final Map<String, Future<http.Response>> _inFlight = {};

  /// GETs [uri], reusing a response fetched for the same URL within [ttl]
  /// (default 4s — short enough that no caller ever sees stale data across a
  /// full poll cycle, long enough to collapse near-simultaneous callers).
  /// Concurrent calls for the same URL share one in-flight request rather
  /// than issuing their own.
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

    final future = http.get(uri).timeout(timeout).then((response) {
      _cache[key] = _CacheEntry(response, DateTime.now().add(ttl));
      _inFlight.remove(key);
      return response;
    }).catchError((Object e) {
      _inFlight.remove(key);
      throw e;
    });

    _inFlight[key] = future;
    return future;
  }
}
