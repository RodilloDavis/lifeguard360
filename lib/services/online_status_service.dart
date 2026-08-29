import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

/// Manages the current user's online/offline presence in Firebase.
///
/// This is the FOREGROUND-side of presence, kept deliberately simple: it
/// just confirms "Online" on login/resume for immediate UI feedback and
/// writes "Offline" on an explicit [logout]. It does NOT try to detect
/// disconnects itself.
///
/// The authoritative presence tracking — including the cases this genuinely
/// can't handle from here (the app being force-killed, deleted while
/// running, or the network dropping while backgrounded) — lives in
/// AppBackgroundService (background_service.dart), via Firebase Realtime
/// Database's connection-state presence system (`.info/connected` +
/// `onDisconnect()`). That's the only mechanism that can report "Offline"
/// for events where no client code gets to run: Firebase's own servers
/// notice the socket close and apply a pre-registered write, which is what
/// makes "the user deleted the app" detectable at all. Duplicating that
/// logic here (e.g. with a second connectivity listener) would race against
/// it: if this foreground isolate's own connection dropped while the
/// background service's connection stayed up, this class would wrongly
/// flip the record to Offline for a few seconds until the background
/// service's next write corrected it.
///
/// Call [initialize] after login and [logout] when the user signs out.
class OnlineStatusService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  static OnlineStatusService? _instance;
  static OnlineStatusService get instance =>
      _instance ??= OnlineStatusService._();
  OnlineStatusService._();

  String? _userId;

  // ── Public API ─────────────────────────────────────────────────────────────

  /// Call once after a successful login.
  Future<void> initialize(String userId) async {
    _userId = userId;
    await goOnline();
  }

  /// Confirms the user as Online. Cheap to call on app resume — the
  /// background service's own presence connection is what actually keeps
  /// this accurate over time.
  Future<void> goOnline() async {
    if (_userId == null) return;
    await _setStatus('Online');
    print('🟢 OnlineStatus → Online for $_userId');
  }

  /// Full sign-out teardown: marks the user Offline. Call this from the
  /// logout flow (alongside stopping AppBackgroundService, which cancels
  /// its own onDisconnect registration and writes Offline too).
  Future<void> logout() async {
    if (_userId != null) {
      await _setStatus('Offline');
      print('🔴 OnlineStatus → Offline (logout) for $_userId');
    }
    _userId = null;
  }

  // ── Internals ──────────────────────────────────────────────────────────────

  Future<void> _setStatus(String status) async {
    if (_userId == null) return;
    try {
      final lastSeen = _formatDate(DateTime.now());
      await http.patch(
        Uri.parse('${_dbUrl}Accounts/$_userId.json'),
        body: json.encode({
          'OnlineStatus': status,
          'LastSeen': lastSeen,
        }),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
    } catch (e) {
      print('⚠️ OnlineStatus patch error: $e');
    }
  }

  static String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')}:'
        '${dt.minute.toString().padLeft(2, '0')}:'
        '${dt.second.toString().padLeft(2, '0')}';
  }
}
