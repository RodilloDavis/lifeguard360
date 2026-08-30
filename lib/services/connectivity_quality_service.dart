// lib/services/connectivity_quality_service.dart
//
// Distinguishes "no network interface at all" from "technically connected,
// but too slow/unreliable to be worth hitting right now" — connectivity_plus
// alone only reports the interface type (wifi/mobile/none), not whether it
// can actually reach the server in reasonable time, which is the far more
// common real case on a weak signal (spotty wifi, 1 bar of mobile data).
// Classifies the connection by timing a small round trip to the app's own
// Firebase project, re-checked periodically and on every interface change.
//
// CachedHttpGet consults [current] to decide whether a URL is worth a real
// network attempt right now, or whether to serve a disk-cached response
// instead without spending any data at all. The moment the connection is
// classified strong again after being weak/offline, every in-memory cache
// entry is invalidated (CachedHttpGet.invalidateAll) so the next scheduled
// poll on any already-open screen — the dashboard's 10s member-status
// timer, My Reports' 12s poll, etc. — picks up fresh data on its very next
// tick instead of waiting out whatever's left of each entry's TTL. That's
// what makes reconnection feel like an automatic sync rather than something
// the user has to notice and pull-to-refresh themselves.

import 'dart:async';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:http/http.dart' as http;
import '../core/utils/cached_http_get.dart';

enum ConnectionQuality { offline, weak, strong }

class ConnectivityQualityService {
  ConnectivityQualityService._();

  // A tiny, cheap Firebase RTDB request used purely to time a round trip —
  // `shallow=true` returns just top-level keys (not their contents) and
  // `timeout=3s` caps how long Firebase itself will hold the request open.
  static const String _probeUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/.json?shallow=true&timeout=3s';

  // A probe slower than this is treated as "weak" even though it eventually
  // succeeded — a multi-second round trip for a few bytes is exactly the
  // kind of connection this service exists to detect and steer routine
  // polling away from.
  static const Duration _strongThreshold = Duration(milliseconds: 1800);
  static const Duration _probeTimeout = Duration(seconds: 4);
  static const Duration _probeInterval = Duration(seconds: 20);

  // Optimistic default: most sessions start on a working connection, and a
  // pessimistic default would make CachedHttpGet skip the very first fetch
  // of anything not already on disk before the first probe even lands.
  static ConnectionQuality _current = ConnectionQuality.strong;
  static ConnectionQuality get current => _current;

  static final StreamController<ConnectionQuality> _controller =
      StreamController<ConnectionQuality>.broadcast();
  static Stream<ConnectionQuality> get stream => _controller.stream;

  static StreamSubscription<List<ConnectivityResult>>? _connSub;
  static Timer? _probeTimer;
  static bool _probing = false;

  /// Starts listening for connectivity changes and periodic quality probes.
  /// Call once at app start (see main.dart); later calls are a no-op.
  static void init() {
    _connSub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.every((r) => r == ConnectivityResult.none)) {
        _setQuality(ConnectionQuality.offline);
      } else {
        _probeNow();
      }
    });
    _probeTimer ??= Timer.periodic(_probeInterval, (_) => _probeNow());
    _probeNow();
  }

  static Future<void> _probeNow() async {
    if (_probing) return;
    _probing = true;
    try {
      final interfaces = await Connectivity().checkConnectivity();
      if (interfaces.every((r) => r == ConnectivityResult.none)) {
        _setQuality(ConnectionQuality.offline);
        return;
      }

      final stopwatch = Stopwatch()..start();
      try {
        final resp =
            await http.get(Uri.parse(_probeUrl)).timeout(_probeTimeout);
        stopwatch.stop();
        final fast = stopwatch.elapsed <= _strongThreshold;
        final reachable = resp.statusCode >= 200 && resp.statusCode < 500;
        _setQuality(
            reachable && fast ? ConnectionQuality.strong : ConnectionQuality.weak);
      } catch (_) {
        // Interface is up but the probe itself failed/timed out — that's
        // the textbook "weak" case (associated to wifi with no real
        // internet, or a mobile connection too slow to complete a request).
        _setQuality(ConnectionQuality.weak);
      }
    } finally {
      _probing = false;
    }
  }

  static void _setQuality(ConnectionQuality quality) {
    final wasBelowStrong = _current != ConnectionQuality.strong;
    final changed = quality != _current;
    _current = quality;
    if (changed) _controller.add(quality);
    if (wasBelowStrong && quality == ConnectionQuality.strong) {
      CachedHttpGet.invalidateAll();
    }
  }
}
