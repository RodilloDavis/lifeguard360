// lib/services/emergency_status_service.dart
import 'dart:async';
import 'dart:convert';
import '../core/utils/cached_http_get.dart';

class EmergencyStatusService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  static EmergencyStatusService? _instance;
  static EmergencyStatusService get instance =>
      _instance ??= EmergencyStatusService._();
  EmergencyStatusService._();

  final Map<String, Set<String>> _activeEmergencies =
      {}; // familyCode -> Set<userId>
  final List<StreamController<Map<String, Set<String>>>> _controllers = [];

  Timer? _pollTimer;
  String? _currentFamilyCode;

  void startPolling(String familyCode) {
    print(
        '🔴 EmergencyStatusService.startPolling() called with familyCode: "$familyCode"');

    if (familyCode.isEmpty) {
      print(
          '⚠️ EmergencyStatusService: familyCode is empty, cannot start polling');
      return;
    }

    if (_currentFamilyCode == familyCode) {
      print(
          '🟡 EmergencyStatusService: Already polling for familyCode: $familyCode');
      return;
    }

    _stopPolling();
    _currentFamilyCode = familyCode;
    print(
        '🟢 EmergencyStatusService: Starting polling for familyCode: $familyCode');

    // Runs on the UI isolate (unlike the background service's polling,
    // which has its own isolate) — every tick is a real HTTP round-trip
    // plus JSON decode competing with whatever the user is doing on
    // screen. 5s was needlessly aggressive for "is anyone's SOS still
    // active" — SOS itself reaches the user far faster via FCM push and
    // the background service's own poll; this is a slower-changing
    // fallback/map-pin-freshness layer, so it doesn't need to be this
    // tight, and halving the tick rate meaningfully cuts main-thread load
    // on slower devices.
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _fetchActiveEmergencies(familyCode);
    });
    _fetchActiveEmergencies(familyCode); // immediate fetch
  }

  void _stopPolling() {
    _pollTimer?.cancel();
    _pollTimer = null;
    _currentFamilyCode = null;
  }

  // Suspends the network timer without forgetting which family code we were
  // polling, so the dashboard can pause this while backgrounded (nobody is
  // looking at the screen, so the network round-trip is pure waste) and
  // resume() afterwards without re-resolving the family code. Real SOS
  // delivery is unaffected — that's the background service's job, not this
  // UI-layer poll.
  void pause() {
    _pollTimer?.cancel();
    _pollTimer = null;
  }

  void resume() {
    final familyCode = _currentFamilyCode;
    if (familyCode == null || familyCode.isEmpty) return;
    if (_pollTimer != null) return; // already running
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) async {
      await _fetchActiveEmergencies(familyCode);
    });
    _fetchActiveEmergencies(familyCode); // catch up immediately
  }

  Future<void> _fetchActiveEmergencies(String familyCode) async {
    if (familyCode.isEmpty) return;

    print(
        '🔍 EmergencyStatusService: Fetching active emergencies for familyCode: $familyCode');

    try {
      final Set<String> activeUserIds = {};

      // Check SOS flag - this is the most important for immediate SOS
      final sosResp = await CachedHttpGet.get(
        Uri.parse('${_dbUrl}Families/$familyCode/SOS.json'),
        timeout: const Duration(seconds: 8),
      );

      // NOTE ON LOGGING IN THIS METHOD
      // This runs on a 5-second poll on the UI isolate. print() writes
      // synchronously to the platform log, so logging per SOS entry and per
      // report (80+ lines a tick on a busy family) stalled the main thread
      // often enough to drop frames mid-scroll. Everything here is kept to
      // fixed-size summaries for that reason — do not add logging inside
      // these loops.
      if (sosResp.statusCode == 200) {
        final body = sosResp.body.trim();

        if (body != 'null' && body.isNotEmpty) {
          final sosData = json.decode(body) as Map<String, dynamic>;
          for (final entry in sosData.entries) {
            final data = entry.value as Map?;
            if (data != null && data['active'] == true) {
              activeUserIds.add(entry.key);
            }
          }
        }
      }

      // Also check active emergency reports (not resolved). This used to
      // download the family's ENTIRE report history and filter for
      // Active/Pending client-side — on a 10s poll that keeps re-sending
      // every past resolved report forever as history grows. RTDB's
      // orderBy/equalTo query does that filtering server-side instead, so
      // only the reports we actually care about cross the network. Two
      // requests (one per status) rather than one, since RTDB only
      // supports a single equalTo per query.
      for (final status in const ['Active', 'Pending']) {
        final reportsResp = await CachedHttpGet.get(
          Uri.parse('${_dbUrl}Families/$familyCode/FamilyReports.json')
              .replace(queryParameters: {
            'orderBy': '"Status"',
            'equalTo': '"$status"',
          }),
          timeout: const Duration(seconds: 8),
        );

        if (reportsResp.statusCode != 200) continue;
        final body = reportsResp.body.trim();
        if (body == 'null' || body.isEmpty) continue;

        final reportsData = json.decode(body) as Map<String, dynamic>;
        for (final entry in reportsData.entries) {
          final report = entry.value as Map?;
          final userId = report?['UserId']?.toString();
          if (userId != null && userId.isNotEmpty) {
            activeUserIds.add(userId);
          }
        }
      }

      final previousActive = _activeEmergencies[familyCode] ?? {};
      final changed = !_setsEqual(previousActive, activeUserIds);
      _activeEmergencies[familyCode] = activeUserIds;

      // Only log on an actual transition — a quiet poll stays silent.
      if (changed) {
        print('🔄 Emergency status changed → active users: $activeUserIds');
        _notifyListeners();
      }
    } catch (e) {
      print('⚠️ Error fetching active emergencies: $e');
    }
  }

  bool _setsEqual(Set<String> a, Set<String> b) {
    if (a.length != b.length) return false;
    for (final item in a) {
      if (!b.contains(item)) return false;
    }
    return true;
  }

  Set<String> getActiveEmergencyUserIds(String familyCode) {
    return _activeEmergencies[familyCode] ?? {};
  }

  bool isUserInEmergency(String familyCode, String userId) {
    final result = _activeEmergencies[familyCode]?.contains(userId) ?? false;
    print(
        '🔍 isUserInEmergency: familyCode=$familyCode, userId=$userId, result=$result');
    return result;
  }

  void addListener(StreamController<Map<String, Set<String>>> controller) {
    _controllers.add(controller);
    // Replay whatever this service already knows immediately, rather than
    // leaving a fresh listener waiting for the next STATE CHANGE — which
    // may never come if nothing changes again after this listener attaches.
    // Without this, a screen that mounts after an emergency is already
    // active (or remounts after an earlier screen already polled the same
    // family) never finds out about it.
    if (_activeEmergencies.isNotEmpty) {
      controller.add(Map.unmodifiable(_activeEmergencies));
    }
  }

  void removeListener(StreamController<Map<String, Set<String>>> controller) {
    _controllers.remove(controller);
  }

  void _notifyListeners() {
    for (final controller in _controllers) {
      if (!controller.isClosed) {
        controller.add(Map.unmodifiable(_activeEmergencies));
      }
    }
  }

  void dispose() {
    _stopPolling();
    for (final controller in _controllers) {
      controller.close();
    }
    _controllers.clear();
    _activeEmergencies.clear();
  }
}
