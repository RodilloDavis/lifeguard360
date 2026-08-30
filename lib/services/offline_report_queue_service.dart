// lib/services/offline_report_queue_service.dart
//
// Local queue for emergency reports that couldn't reach the server because
// the device had no usable connectivity at the moment the user hit
// "Confirm & Send Alert". Each queued entry is a full snapshot of what
// EmergencyReportService.saveReport() had already resolved — GPS, address,
// barangay, ReportId, timestamp — captured at the moment of the incident,
// not whenever the device happens to reconnect. The queue is flushed
// automatically (oldest first) whenever connectivity comes back, and once
// more on app start in case a report was still waiting from a previous
// session.
//
// Persisted to SharedPreferences as a single JSON-encoded list — the same
// approach report_history_cache_service.dart uses for its own local cache
// — rather than a new local DB dependency, since a handful of queued
// reports at a time is the expected case, not hundreds.

import 'dart:async';
import 'dart:convert';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'emergency_report_service.dart';

class OfflineReportQueueService {
  OfflineReportQueueService._();

  static const String _prefsKey = 'offline_report_queue_v1';

  static StreamSubscription<List<ConnectivityResult>>? _connSub;
  static bool _flushing = false;

  // A connectivity event (or another caller) can ask for a flush while one
  // is already running — rather than let two flushes race on the same
  // SharedPreferences key, that request is remembered and re-run once the
  // in-flight flush finishes.
  static bool _flushRequestedAgain = false;

  static final StreamController<int> _countController =
      StreamController<int>.broadcast();

  /// Emits the number of reports still waiting to be sent — once on
  /// subscribe (loaded from disk) and again every time the queue changes.
  /// UI (e.g. a "1 report queued — will send automatically" banner) should
  /// listen to this rather than polling [pendingCount].
  static Stream<int> get pendingCountStream async* {
    yield await pendingCount();
    yield* _countController.stream;
  }

  static Future<int> pendingCount() async => (await _loadQueue()).length;

  /// Starts listening for connectivity changes and makes a best-effort
  /// attempt to flush anything already queued from a previous session.
  /// Call once at app start (see main.dart); later calls are a no-op.
  static void init() {
    _connSub ??= Connectivity().onConnectivityChanged.listen((results) {
      if (results.any((r) => r != ConnectivityResult.none)) {
        flushQueue();
      }
    });
    flushQueue();
  }

  static Future<bool> hasConnectivity() async {
    try {
      final result = await Connectivity().checkConnectivity();
      return result.any((r) => r != ConnectivityResult.none);
    } catch (_) {
      // Can't tell — assume online so a broken connectivity check never
      // permanently strands a report in the queue instead of just trying
      // and finding out.
      return true;
    }
  }

  static Future<void> enqueue({
    required String type,
    required String reportId,
    required String reportLabel,
    required bool isFamilySos,
    required String userId,
    required String userName,
    required String familyCode,
    required Map<String, dynamic> reportPayload,
    required Map<String, dynamic> location,
    required String barangay,
    required Map<String, double>? gpsPos,
    required DateTime now,
    required String createdAt,
    required Map<String, dynamic> emergencyData,
  }) async {
    final queue = await _loadQueue();
    queue.add({
      'type': type,
      'reportId': reportId,
      'reportLabel': reportLabel,
      'isFamilySos': isFamilySos,
      'userId': userId,
      'userName': userName,
      'familyCode': familyCode,
      'reportPayload': reportPayload,
      'location': location,
      'barangay': barangay,
      'gpsLat': gpsPos?['latitude'],
      'gpsLng': gpsPos?['longitude'],
      'nowIso': now.toIso8601String(),
      'createdAt': createdAt,
      'emergencyData': emergencyData,
      'queuedAt': DateTime.now().toIso8601String(),
    });
    await _saveQueue(queue);
    _countController.add(queue.length);
  }

  static Future<List<Map<String, dynamic>>> _loadQueue() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(_prefsKey);
      if (raw == null || raw.isEmpty) return [];
      final decoded = json.decode(raw) as List;
      return decoded.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    } catch (_) {
      return [];
    }
  }

  static Future<void> _saveQueue(List<Map<String, dynamic>> queue) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_prefsKey, json.encode(queue));
  }

  /// Attempts to send every queued report, oldest first, via
  /// EmergencyReportService.persistQueuedReport — which replays each one
  /// exactly as it was captured (same ReportId/timestamp/location) rather
  /// than resolving any of that fresh. Stops at the first report that
  /// still fails, leaving it and everything behind it queued for the next
  /// trigger, so a family's reports can never arrive out of order.
  static Future<void> flushQueue() async {
    if (_flushing) {
      _flushRequestedAgain = true;
      return;
    }
    _flushing = true;
    try {
      do {
        _flushRequestedAgain = false;
        final queue = await _loadQueue();
        if (queue.isEmpty) return;
        if (!await hasConnectivity()) return;

        var sentCount = 0;
        for (final ctx in queue) {
          final result = await EmergencyReportService.persistQueuedReport(ctx);
          if (result['success'] != true) break;
          sentCount++;
        }
        if (sentCount > 0) {
          final remaining = queue.skip(sentCount).toList();
          await _saveQueue(remaining);
          _countController.add(remaining.length);
        }
      } while (_flushRequestedAgain);
    } finally {
      _flushing = false;
    }
  }
}
