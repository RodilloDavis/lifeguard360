// lib/services/background_service.dart
//
// ═══════════════════════════════════════════════════════════════════════════════
// BACKGROUND SERVICE — Location tracking, SOS detection, and emergency alerts
// ═══════════════════════════════════════════════════════════════════════════════

import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui';

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_database/firebase_database.dart';
import 'package:flutter_background_service/flutter_background_service.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:permission_handler/permission_handler.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../firebase_options.dart';
import 'emergency_report_service.dart';

// ─── Firebase URL ──────────────────────────────────────────────────────────────
const String _kDbUrl =
    'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

// ─── Notification channel IDs ──────────────────────────────────────────────────
const String _kForegroundChannelId = 'lifeguard_foreground_v2';
const String _kForegroundChannelName = 'LifeGuard360 Running';
const int _kForegroundNotifId = 888;
const String _kAlertChannelId = 'lifeguard_sos_alerts';
const String _kAlertChannelName = 'LifeGuard360 SOS Alerts';
const String _kReportChannelId = 'lifeguard_reports';
const String _kReportChannelName = 'LifeGuard360 Emergency Reports';
const String _kShakeChannelId = 'lifeguard_shake_sos';
const String _kShakeChannelName = 'LifeGuard360 SHAKE SOS';
const String _kReportUpdateChannelId = 'lifeguard_report_resolved';
const String _kReportUpdateChannelName = 'LifeGuard360 Report Updates';

// ─── Shake detection constants ─────────────────────────────────────────────────
const double _kShakeThreshold = 4.5 * 9.81;
const double _kIntenseThreshold = 7.0 * 9.81;
const int _kMinShakeCount = 5;
const int _kShakeWindowMs = 1200;
const int _kCooldownMs = 120000;
const int _kSosCancelWindowSec = 10;

// ─── FCM config ────────────────────────────────────────────────────────────────
const String _kFcmProjectId = 'lifeguard-cefd9';
const String _kFcmClientEmail =
    'firebase-adminsdk-fbsvc@lifeguard-cefd9.iam.gserviceaccount.com';
const String _kFcmPrivateKey = '-----BEGIN PRIVATE KEY-----\n'
    'MIIEvgIBADANBgkqhkiG9w0BAQEFAASCBKgwggSkAgEAAoIBAQDd9ORwnhrcoHi/\n'
    'JX7w3wtiM0//xX+FWDNPXyDbF3EEi4CmruszL1rfVpspbZvvdUOPEl3jrOlF/w5I\n'
    'gU1VAQL0ousQntbreouL3dwYBLZs57GjSwwOTAp7E0cTmzkl81G9VZvuQoLAcId4\n'
    'InaoK0XIDigELp8BilMWdwIJFgSbDpwoR7OrPbpgEZ1sO3G0JTSBIEadNiQydN0l\n'
    'WY5+PnjubyCCjI0eNJyv4OrAGm5Kr1iB7HPgOYHqU5bJHgpbaw3MN3PspXOEWML0\n'
    'ju4t6CQ754cBcs1HebxIkGSQSEzYowP4BAYp+GiFBOMLlLYKiLILtjUOqmfUaIhk\n'
    'QTkR91SRAgMBAAECggEAXhT1leT2pulgdUmMBsbMmPn+IYESPi/2Q+EjWKsVjWMi\n'
    'i8TeTop2nu+jgoqDDBvtIKKc6Kp9EN39rG8em/b7TT4XnKpvmE4QA5/tsMKinwQQ\n'
    '8JIZkJ/b23J+8MkdjsAWOEam+3X23WJ1kc8t87ev8w5JGQi3/pum/4E/fCF4n05m\n'
    'JOAdeI1VxmrfHnWSTMmGy6NBNWVpzDYRR9TGqqsha48l0wn+jotPM5D0AoYY2wqR\n'
    'BRwJ9v2Cn6mFB8Mm7+qVodUo5ngWjGAMWw/YCNoydBLY/qDl87HH1uHxiz6bCq9c\n'
    'jDrE2UPlweXo5wy4AeZBfuvzHJS6NxhgdPlysleD9wKBgQD81tKoKSgysyH5B++j\n'
    'Db5rvO4EoqkjOBHcVf7CKKCw1XTTW2wMcLMauxH/PY48cHEUnsk1JsEgTFZxorYT\n'
    '+cSc5T61iY4g5vMpavQAn4mRzjOYdfPMb+8UUURzvPZvZ4Op5CJwZkGUe6CWN3GX\n'
    'Mo5Ss0seiEIpmJ1UHVDCPYTFgwKBgQDguzvvCkaum797Y6iTmU2ph3iFrbA6XuCr\n'
    'X+qlfMBjrOAinzXUtCRpPwqvmJcHUULeI1mpVAujYad0JF9W7R7xB5r72SLg8o0Y\n'
    'Tv0Vz9okub7s2XgFmKTpGo+9Q27thlUpyIrJ7ZnDOZr6ImcXzCEQe5NfeC9Gc2Tq\n'
    'xYhUCMs1WwKBgA5rylQhFNPfd76Wf0qTjBrlCcZl6LPDjPE+TmuQmam8Yw9zFXSY\n'
    'MP8DUIF4Z1Z3K1v7uoo3jahj8kJE/5GgG2C/ipYcJGkoAxKHsScf8l7InhTCFYfB\n'
    'kqdcA0V+r6enBdF426YBjxgC/SPUQbxX+9ons88oAm4Q8FhN279Yduw1AoGBALiD\n'
    '4nysskYQ6NH1jGbLm0FTUnhnmGcEmXD8CtufJxNv0IN8tyUSV0b2lN6B6Zb/eGiN\n'
    'G8P0lq2ps2SfrIvhmuMJfI3FxWZun7xStmefRhubSpCLKYlmwBgIT/Z0lHJ/NhNd\n'
    'bd7Hr9TjykQP1Rdr6cXvwJvFQQOWIUjFsN5Wbgo7AoGBAMGPUHSOaKdSa8NBOxsw\n'
    '1tf25fV26VKn6XFwBgCUHgOdmHaZ69aiXHnPwyzo63+nx2eBIUU9Rt1WWDOpkkCk\n'
    'S0zGUSlzLL4VqaUEzfaJ+6mzT9yY+xR9r4rKsbe5ma8rrsNlGtBX7ZH8e0Vkj8uI\n'
    'FGHaYXE4NcQuK2ZouQP+RNt0\n'
    '-----END PRIVATE KEY-----';

// ─── Top-level notifications plugin ───────────────────────────────────────────
final FlutterLocalNotificationsPlugin _bgFlnp =
    FlutterLocalNotificationsPlugin();

// =============================================================================
// PUBLIC API
// =============================================================================

class AppBackgroundService {
  static Future<void> initialize() async {
    if (kIsWeb) return;

    if (await Permission.notification.isDenied) {
      await Permission.notification.request();
    }

    // Ask to be exempted from battery optimisation / Doze.
    //
    // This is what actually keeps presence and background location working
    // on real devices. Without the exemption, Android (and far more
    // aggressively, Transsion/Xiaomi/Oppo-style OEM battery managers) kills
    // this foreground service shortly after the user swipes the app away.
    // When that happens the Realtime Database socket closes, so the
    // onDisconnect() registered in bgEntryPoint fires and the user is
    // reported Offline — and the plugin's watchdog restart is itself
    // blocked by the same battery manager, so they stay Offline and stop
    // sending location until they next open the app by hand.
    //
    // Requested here rather than at first launch so it's tied to the
    // service actually starting. The permission_handler call is a no-op if
    // the exemption has already been granted.
    try {
      if (await Permission.ignoreBatteryOptimizations.isDenied) {
        await Permission.ignoreBatteryOptimizations.request();
      }
    } catch (e) {
      debugPrint('⚠️ Battery-optimisation exemption request failed: $e');
    }

    final androidPlugin = _bgFlnp.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    for (final channel in _allChannels) {
      await androidPlugin?.createNotificationChannel(channel);
    }

    await _bgFlnp.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true,
        ),
      ),
    );

    await FlutterBackgroundService().configure(
      androidConfiguration: AndroidConfiguration(
        onStart: bgEntryPoint,
        isForegroundMode: true,
        autoStart: true,
        autoStartOnBoot: true,
        notificationChannelId: _kForegroundChannelId,
        initialNotificationTitle: 'LifeGuard360 is running in the background',
        initialNotificationContent:
            'Actively protecting your family • Location tracking ON',
        foregroundServiceNotificationId: _kForegroundNotifId,
        foregroundServiceTypes: const [AndroidForegroundType.location],
      ),
      iosConfiguration: IosConfiguration(
        autoStart: true,
        onForeground: bgEntryPoint,
        onBackground: _iosBackground,
      ),
    );
  }

  static final List<AndroidNotificationChannel> _allChannels = [
    const AndroidNotificationChannel(
      _kForegroundChannelId,
      _kForegroundChannelName,
      importance: Importance.low,
      description: 'Shown while LifeGuard360 tracks your location',
      playSound: false,
      enableVibration: false,
      showBadge: false,
    ),
    const AndroidNotificationChannel(
      _kAlertChannelId,
      _kAlertChannelName,
      importance: Importance.max,
      description: 'SOS and emergency alerts from your family',
      playSound: true,
      enableVibration: true,
    ),
    const AndroidNotificationChannel(
      _kReportChannelId,
      _kReportChannelName,
      importance: Importance.high,
      description: 'New emergency reports from your family circle',
      playSound: true,
      enableVibration: true,
    ),
    const AndroidNotificationChannel(
      _kShakeChannelId,
      _kShakeChannelName,
      importance: Importance.max,
      description: 'Shake SOS emergency alerts',
      playSound: true,
      enableVibration: true,
    ),
    const AndroidNotificationChannel(
      _kReportUpdateChannelId,
      _kReportUpdateChannelName,
      importance: Importance.high,
      description: 'Updates on reports you submitted — when a responder is '
          'assigned, and when the report is resolved',
      playSound: true,
      enableVibration: true,
    ),
  ];

  static Future<void> start() async {
    if (kIsWeb) return;
    final svc = FlutterBackgroundService();
    if (!await svc.isRunning()) {
      await svc.startService();
      debugPrint('🚀 Background service started');
    } else {
      debugPrint('✅ Background service already running');
    }
  }

  static Future<void> stop() async {
    if (kIsWeb) return;
    try {
      FlutterBackgroundService().invoke('stopService');
      debugPrint('🛑 Background service stop requested');
    } catch (e) {
      debugPrint('⚠️ AppBackgroundService.stop() error: $e');
    }
  }

  static Future<bool> isRunning() => FlutterBackgroundService().isRunning();

  static Future<void> ensureRunning() async {
    if (kIsWeb) return;
    final svc = FlutterBackgroundService();
    if (!await svc.isRunning()) {
      debugPrint('⚠️ Background service was dead – restarting');
      await svc.startService();
    }
  }
}

// =============================================================================
// iOS background handler
// =============================================================================

@pragma('vm:entry-point')
Future<bool> _iosBackground(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  try {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('userId') ?? '';
    if (uid.isNotEmpty) await _patchStatus(uid, 'Online');
  } catch (_) {}
  return true;
}

// =============================================================================
// NOTIFICATION HELPERS
// =============================================================================

Future<void> _showSosAlert(String senderName) async {
  await _bgFlnp.show(
    id: DateTime.now().millisecondsSinceEpoch ~/ 1000,
    title: '🚨 SOS Alert!',
    body: '$senderName needs help! Open the app immediately.',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _kAlertChannelId,
        _kAlertChannelName,
        importance: Importance.max,
        priority: Priority.max,
        fullScreenIntent: true,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFFCC0000),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.critical,
      ),
    ),
  );
}

Future<void> _showReportAlert(String reporterName, String reportType) async {
  final emoji = {
        'fire': '🔥',
        'medical': '🚑',
        'flood': '🌊',
        'crime': '🚨',
        'accident': '🚗',
        'other': '⚠️',
      }[reportType] ??
      '⚠️';
  final label = {
        'fire': 'Fire Emergency',
        'medical': 'Medical Emergency',
        'flood': 'Flood Emergency',
        'crime': 'Crime Report',
        'accident': 'Accident',
        'other': 'Emergency',
      }[reportType] ??
      'Emergency Report';

  await _bgFlnp.show(
    id: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 1,
    title: '$emoji $label from $reporterName',
    body: 'Tap to view the report and take action.',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _kReportChannelId,
        _kReportChannelName,
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 500, 200, 500, 200, 500]),
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFFCC0000),
        fullScreenIntent: true,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
        interruptionLevel: InterruptionLevel.timeSensitive,
      ),
    ),
  );
}

// Fired when a responder or administrator closes out a report the user
// submitted. Deliberately calmer than the emergency alerts above — this is
// good news, not something demanding immediate action — so it uses its own
// channel, the success green, and no full-screen intent.
Future<void> _showReportResolvedAlert({
  required String reportId,
  required String reportType,
  required String reportedAt,
  required String resolvedAt,
  required String resolvedBy,
  required String location,
}) async {
  final label = EmergencyReportService.getTypeLabel(reportType);
  final reportedOn = EmergencyReportService.formatReportDateTime(reportedAt);
  final resolvedOn = EmergencyReportService.formatReportDateTime(resolvedAt);

  final lines = <String>[
    if (reportedOn.isNotEmpty) 'Reported: $reportedOn',
    if (location.isNotEmpty) 'Location: $location',
    resolvedOn.isNotEmpty
        ? 'Resolved by $resolvedBy on $resolvedOn'
        : 'Resolved by $resolvedBy',
  ];
  final body = lines.join('\n');

  await _bgFlnp.show(
    // Derived from the report ID rather than the clock, so a re-delivery for
    // the same report replaces its tray entry instead of stacking a copy.
    id: reportId.hashCode & 0x7FFFFFFF,
    title: '✅ Your $label has been resolved',
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _kReportUpdateChannelId,
        _kReportUpdateChannelName,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF28A745),
        // The details run past one line — expand them instead of truncating
        // the date/time the user is being told about.
        styleInformation: BigTextStyleInformation(
          body,
          contentTitle: '✅ Your $label has been resolved',
        ),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

// Fired when the dispatcher assigns a responder to a report the user
// submitted — the first sign to the reporter that someone is actually on it.
// Shares the resolved alert's calm treatment: its own channel, no siren, no
// full-screen intent.
Future<void> _showResponderAssignedAlert({
  required String reportId,
  required String reportType,
  required String reportedAt,
  required String assignedAt,
  required String responderName,
  required String location,
}) async {
  final label = EmergencyReportService.getTypeLabel(reportType);
  final reportedOn = EmergencyReportService.formatReportDateTime(reportedAt);
  final assignedOn = EmergencyReportService.formatReportDateTime(assignedAt);

  final title = responderName.isNotEmpty
      ? '🚔 $responderName is responding to your report'
      : '🚔 A responder has been assigned to your report';

  final lines = <String>[
    'Report: $label',
    if (reportedOn.isNotEmpty) 'Reported: $reportedOn',
    if (location.isNotEmpty) 'Location: $location',
    if (assignedOn.isNotEmpty) 'Assigned: $assignedOn',
  ];
  final body = lines.join('\n');

  await _bgFlnp.show(
    // Distinct from the resolved alert's ID for the same report, so the two
    // stages sit side by side in the tray instead of one replacing the other.
    id: ('assigned_$reportId').hashCode & 0x7FFFFFFF,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _kReportUpdateChannelId,
        _kReportUpdateChannelName,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFF0088CC),
        styleInformation:
            BigTextStyleInformation(body, contentTitle: title),
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

Future<void> _showShakeSosSentConfirmation() async {
  await _bgFlnp.show(
    id: (DateTime.now().millisecondsSinceEpoch ~/ 1000) + 3,
    title: '📳 Shake SOS Sent',
    body: 'Your family has been alerted. Help is on the way.',
    notificationDetails: const NotificationDetails(
      android: AndroidNotificationDetails(
        _kShakeChannelId,
        _kShakeChannelName,
        importance: Importance.high,
        priority: Priority.high,
        playSound: true,
        enableVibration: true,
        icon: '@mipmap/ic_launcher',
        color: Color(0xFFCC0000),
      ),
      iOS: DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
  );
}

Future<void> _showShakeSosWarning(int secondsLeft) async {
  // No notification sound here — the siren is a continuous loop driven
  // separately by an AudioPlayer for the whole countdown (see
  // triggerShakeSos), not a one-shot notification chime.
  await _bgFlnp.show(
    id: 9001,
    title: '📳 Shake SOS — Sending in ${secondsLeft}s',
    body: 'Tap CANCEL to stop the SOS from being sent.',
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        _kShakeChannelId,
        _kShakeChannelName,
        importance: Importance.max,
        priority: Priority.max,
        playSound: false,
        enableVibration: true,
        vibrationPattern: Int64List.fromList([0, 200]),
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFFCC0000),
        ongoing: true,
        autoCancel: false,
        actions: const [
          AndroidNotificationAction(
            'cancel_sos',
            'CANCEL SOS',
            showsUserInterface: true,
            cancelNotification: true,
          ),
        ],
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: false,
        presentSound: false,
      ),
    ),
  );
}

Future<void> _dismissShakeSosWarning() async {
  await _bgFlnp.cancel(id: 9001);
}

// =============================================================================
// BACKGROUND ENTRY POINT
// =============================================================================

@pragma('vm:entry-point')
void bgEntryPoint(ServiceInstance service) async {
  WidgetsFlutterBinding.ensureInitialized();
  DartPluginRegistrant.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  if (service is AndroidServiceInstance) {
    await service.setAsForegroundService();
    service.setForegroundNotificationInfo(
      title: 'LifeGuard360 is running in the background',
      content: 'Actively protecting your family • Location tracking ON',
    );
  }

  await _bgFlnp.initialize(
    settings: const InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      iOS: DarwinInitializationSettings(),
    ),
  );

  void updateForeground(String content) {
    if (service is AndroidServiceInstance) {
      service.setForegroundNotificationInfo(
        title: 'LifeGuard360 is running in the background',
        content: content,
      );
    }
  }

  // ── Presence (Online/Offline) ────────────────────────────────────────────
  //
  // Backed by Firebase Realtime Database's connection-state presence
  // system instead of a REST heartbeat + guesswork, because it's the only
  // mechanism that can correctly report "Offline" for events no client code
  // can ever run for: the app being force-killed, uninstalled while
  // running, crashing, or the OS abruptly cutting the connection. Firebase's
  // OWN servers notice the socket close and apply the pre-registered
  // onDisconnect() write — no code on the device has to be alive for that
  // to happen, which is what makes it work for "the user deleted the app".
  //
  // Merely closing/backgrounding the app does NOT trigger this: the
  // connection this service holds stays open (that's the entire point of
  // running as a foreground service), so onDisconnect never fires just from
  // backgrounding — satisfying "still online while the app is closed".
  DatabaseReference? presenceRef;
  String presenceSetupForUserId = '';

  void setupPresenceIfNeeded(String uid) {
    if (uid.isEmpty || uid == presenceSetupForUserId) return;
    presenceSetupForUserId = uid;

    final connectedRef = FirebaseDatabase.instance.ref('.info/connected');
    final statusRef = FirebaseDatabase.instance.ref('Accounts/$uid');
    presenceRef = statusRef;

    connectedRef.onValue.listen((event) async {
      if (event.snapshot.value != true) return;
      try {
        // Register FIRST what the server should write if this exact
        // connection drops, THEN confirm Online — that order matters: if a
        // disconnect happened between these two calls it would just mean
        // an extra correct "Offline" write, whereas the reverse order could
        // leave the record wrongly stuck on the connection's last "Online".
        await statusRef.onDisconnect().update({'OnlineStatus': 'Offline'});
        await statusRef.update({
          'OnlineStatus': 'Online',
          'LastSeen': _fmtDate(DateTime.now()),
        });
      } catch (e) {
        debugPrint('⚠️ Presence setup error: $e');
      }
    });
  }

  // ── App foreground/background tracking ──────────────────────────────────
  //
  // Lets shake-SOS (TASK 6 below) know whether the main app currently has a
  // live UI to show an in-app cancel dialog in, or whether it must rely on
  // the notification-based countdown because the app is closed/backgrounded.
  bool isAppForeground = false;
  service.on('appForeground').listen((event) {
    isAppForeground = event?['foreground'] == true;
  });

  // ── Stop command ──────────────────────────────────────────────────────────

  service.on('stopService').listen((_) async {
    final prefs = await SharedPreferences.getInstance();
    final uid = prefs.getString('userId') ?? '';
    // Cancel the pending onDisconnect write first — this is a deliberate,
    // graceful sign-out, not the abrupt disconnect that write is for, so
    // let the explicit PATCH below own it instead of leaving a stale
    // onDisconnect registration behind.
    try {
      await presenceRef?.onDisconnect().cancel();
    } catch (_) {}
    if (uid.isNotEmpty) await _patchStatus(uid, 'Offline');
    service.stopSelf();
    debugPrint('🛑 Background service stopped cleanly');
  });

  // ── Session ───────────────────────────────────────────────────────────────

  String userId = '';
  String familyCode = '';
  String lastKnownReportId = '';
  String lastKnownShakeId = '';

  Future<void> refreshSession() async {
    final prefs = await SharedPreferences.getInstance();
    userId = prefs.getString('userId') ?? '';
    familyCode = prefs.getString('familyCode') ?? '';
    lastKnownReportId = prefs.getString('lastKnownReportId') ?? '';
    lastKnownShakeId = prefs.getString('lastKnownShakeId') ?? '';

    if (userId.isNotEmpty && familyCode.isEmpty) {
      final code = await _fetchFamilyCode(userId);
      if (code.isNotEmpty) {
        familyCode = code;
        await prefs.setString('familyCode', familyCode);
        debugPrint('🏷️ BG resolved familyCode: $familyCode');
      }
    }

    setupPresenceIfNeeded(userId);
  }

  await refreshSession();

  Timer.periodic(const Duration(seconds: 10), (_) => refreshSession());

  // ============================================================================
  // TASK 1 – GPS → Firebase every 30s
  // ============================================================================
  Timer.periodic(const Duration(seconds: 30), (_) async {
    if (userId.isEmpty) return;
    try {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) return;

      final pos = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 10),
        ),
      );
      final now = DateTime.now();

      await http
          .patch(
            Uri.parse('${_kDbUrl}Accounts/$userId.json'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'Location': {
                'latitude': pos.latitude,
                'longitude': pos.longitude,
                'accuracy': pos.accuracy,
                'timestamp': now.toIso8601String(),
              },
              'OnlineStatus': 'Online',
              'LastSeen': _fmtDate(now),
            }),
          )
          .timeout(const Duration(seconds: 10));

      updateForeground(
        'LifeGuard360 is running • Last update ${now.hour}:${now.minute.toString().padLeft(2, '0')}',
      );
    } catch (e) {
      debugPrint('📍 BG location error: $e');
    }
  });

  // ============================================================================
  // TASK 2 – Online-status heartbeat every 30s
  // ============================================================================
  //
  // Belt-and-suspenders alongside the Realtime Database presence system set
  // up above: this keeps LastSeen fresh and re-affirms Online via the plain
  // REST path this file already uses everywhere else. Actually detecting a
  // genuine disconnect (network loss, force-kill, app deletion) is handled
  // by the onDisconnect() registration in setupPresenceIfNeeded(), not here
  // — a failed PATCH in this timer is just silently dropped, same as before.
  Timer.periodic(const Duration(seconds: 30), (_) async {
    if (userId.isEmpty) return;
    await _patchStatus(userId, 'Online');
  });

  // ============================================================================
  // TASK 3 – SOS flag poll every 15s
  // ============================================================================
  final Map<String, bool> notifiedSos = {};

  Timer.periodic(const Duration(seconds: 15), (_) async {
    if (userId.isEmpty || familyCode.isEmpty) return;
    try {
      final res = await http
          .get(Uri.parse('${_kDbUrl}Families/$familyCode/SOS.json'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;
      final raw = res.body.trim();
      if (raw == 'null' || raw.isEmpty) return;

      final sosMap = Map<String, dynamic>.from(json.decode(raw) as Map);

      for (final entry in sosMap.entries) {
        final triggerId = entry.key;
        final data = entry.value as Map?;
        if (data == null) continue;

        final active = data['active'] == true;
        final sender = data['userName']?.toString() ?? 'A family member';

        if (triggerId == userId) continue;

        if (!active) {
          notifiedSos.remove(triggerId);
          continue;
        }
        if (notifiedSos[triggerId] == true) continue;

        notifiedSos[triggerId] = true;

        final sosType = data['type']?.toString() ?? '';
        if (sosType == 'shake') {
          updateForeground('🚨 SOS from $sender!');
          continue;
        }

        await _showSosAlert(sender);
        updateForeground('🚨 SOS from $sender!');
      }
    } catch (e) {
      debugPrint('🚨 BG SOS poll error: $e');
    }
  });

  // ============================================================================
  // TASK 4 – Emergency report poll every 20s
  // ============================================================================
  Timer.periodic(const Duration(seconds: 20), (_) async {
    if (userId.isEmpty || familyCode.isEmpty) return;
    try {
      final res = await http
          .get(Uri.parse(
              '${_kDbUrl}Families/$familyCode/FamilyReports.json?orderBy="\$key"&limitToLast=1'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;
      final raw = res.body.trim();
      if (raw == 'null' || raw.isEmpty) return;

      final reportsMap = Map<String, dynamic>.from(json.decode(raw) as Map);
      final latestId = reportsMap.keys.first;
      final latestData = reportsMap[latestId] as Map?;
      if (latestData == null) return;
      if (latestId == lastKnownReportId) return;

      final eType = latestData['EmergencyType']?.toString() ?? '';
      if (eType == 'shake') {
        lastKnownReportId = latestId;
        return;
      }

      if (latestData['UserId']?.toString() == userId) {
        lastKnownReportId = latestId;
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('lastKnownReportId', latestId);
        return;
      }

      lastKnownReportId = latestId;
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('lastKnownReportId', latestId);

      final reporter = latestData['UserName']?.toString() ?? 'A member';
      final reportType = latestData['EmergencyType']?.toString() ?? 'emergency';
      await _showReportAlert(reporter, reportType);
      updateForeground('📋 New report from $reporter');
    } catch (e) {
      debugPrint('📋 BG report poll error: $e');
    }
  });

  // ============================================================================
  // TASK 5 – Watchdog every 60s (prevents Android from killing the service)
  // ============================================================================
  Timer.periodic(const Duration(seconds: 60), (_) async {
    if (service is AndroidServiceInstance) {
      await service.setAsForegroundService();
    }
  });

  // ============================================================================
  // TASK 6 – Shake SOS detection
  // ============================================================================
  int bgShakeCount = 0;
  DateTime bgShakeWindowStart = DateTime.now();
  DateTime bgShakeLastFired = DateTime(2000);
  bool bgCancelPending = false;
  // Loops for the whole cancel countdown once a normal (non-intense) shake
  // is detected, and stops the instant the user cancels OR the report is
  // sent — never a fixed duration on its own.
  final AudioPlayer shakeSirenPlayer = AudioPlayer();

  Future<void> triggerShakeSos(bool isIntense) async {
    if (userId.isEmpty) return;

    if (isIntense) {
      debugPrint('📳 BG INTENSE SHAKE → instant SOS');
      updateForeground('🚨 INTENSE SHAKE SOS! Alerting family NOW');
      try {
        final result = await _saveBgShakeReport(userId, familyCode);
        if (result['success'] == true) {
          await _showShakeSosSentConfirmation();
          updateForeground('🚨 Shake SOS sent — family alerted');
        }
      } catch (e) {
        debugPrint('❌ BG intense shake error: $e');
      }
    } else {
      if (bgCancelPending) return;
      bgCancelPending = true;

      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool('shakeSosCancelled', false);

      try {
        await shakeSirenPlayer.setReleaseMode(ReleaseMode.loop);
        await shakeSirenPlayer.play(AssetSource('sounds/shake_siren.mp3'));
      } catch (e) {
        debugPrint('⚠️ Could not start shake siren: $e');
      }

      // Lets the main app show an in-app cancel dialog in sync with this
      // same countdown when it's open — a purely cosmetic mirror of this
      // notification. Both write to the same 'shakeSosCancelled' flag below,
      // so there is exactly one authoritative cancel/confirm decision no
      // matter which UI the user actually interacts with.
      if (isAppForeground) {
        service.invoke('shakeCountdownStarted', {
          'seconds': _kSosCancelWindowSec,
        });
      }

      for (int i = _kSosCancelWindowSec; i > 0; i--) {
        // The in-app dialog covers this role while the app is open — showing
        // the notification too would just be a redundant second prompt for
        // the same countdown.
        if (!isAppForeground) {
          await _showShakeSosWarning(i);
        }
        await Future.delayed(const Duration(seconds: 1));
        if (await _isSosCancelled()) {
          await shakeSirenPlayer.stop();
          await _dismissShakeSosWarning();
          service.invoke('shakeCountdownEnded', {'cancelled': true});
          bgCancelPending = false;
          updateForeground('✋ Shake SOS cancelled');
          return;
        }
      }

      await shakeSirenPlayer.stop();
      await _dismissShakeSosWarning();
      service.invoke('shakeCountdownEnded', {'cancelled': false});
      bgCancelPending = false;

      updateForeground('📳 SHAKE SOS triggered! Alerting family');
      try {
        final result = await _saveBgShakeReport(userId, familyCode);
        if (result['success'] == true) {
          await _showShakeSosSentConfirmation();
          updateForeground('📳 Shake SOS sent — family alerted');
        }
      } catch (e) {
        debugPrint('❌ BG normal shake error: $e');
      }
    }
  }

  accelerometerEventStream(
    samplingPeriod: SensorInterval.gameInterval,
  ).listen((AccelerometerEvent event) async {
    if (userId.isEmpty) return;
    // Shake SOS only triggers while the app is open — ignore accelerometer
    // events entirely while backgrounded/closed, rather than falling back
    // to the notification-based countdown.
    if (!isAppForeground) return;

    final gForce =
        sqrt(event.x * event.x + event.y * event.y + event.z * event.z);
    if (gForce < _kShakeThreshold) return;

    final now = DateTime.now();
    if (now.difference(bgShakeLastFired).inMilliseconds < _kCooldownMs) return;

    if (gForce >= _kIntenseThreshold) {
      bgShakeCount = 0;
      bgShakeWindowStart = now;
      bgShakeLastFired = now;
      await triggerShakeSos(true);
      return;
    }

    if (now.difference(bgShakeWindowStart).inMilliseconds > _kShakeWindowMs) {
      bgShakeCount = 0;
      bgShakeWindowStart = now;
    }

    bgShakeCount++;
    if (bgShakeCount >= _kMinShakeCount) {
      bgShakeCount = 0;
      bgShakeWindowStart = now;
      bgShakeLastFired = now;
      await triggerShakeSos(false);
    }
  }, onError: (e) {
    debugPrint('⚠️ Accelerometer error: $e');
  });

  // ============================================================================
  // TASK 7 – Poll FamilyReports for shake events every 20s
  // ============================================================================
  final Map<String, bool> notifiedShake = {};

  Timer.periodic(const Duration(seconds: 20), (_) async {
    if (userId.isEmpty || familyCode.isEmpty) return;
    try {
      final res = await http
          .get(Uri.parse('${_kDbUrl}Families/$familyCode/FamilyReports.json'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;
      final raw = res.body.trim();
      if (raw == 'null' || raw.isEmpty) return;

      final allReports = Map<String, dynamic>.from(json.decode(raw) as Map);

      for (final entry in allReports.entries) {
        final reportId = entry.key;
        final data = entry.value as Map?;
        if (data == null) continue;
        if (data['EmergencyType']?.toString() != 'shake') continue;
        if (data['UserId']?.toString() == userId) continue;
        if (notifiedShake[reportId] == true) continue;

        notifiedShake[reportId] = true;
        final prefs = await SharedPreferences.getInstance();
        lastKnownShakeId = reportId;
        await prefs.setString('lastKnownShakeId', reportId);

        final senderName = data['UserName']?.toString() ?? 'A family member';
        updateForeground('🚨 SHAKE SOS from $senderName!');
      }
    } catch (e) {
      debugPrint('🚨 BG shake poll error: $e');
    }
  });

  // ============================================================================
  // TASK 8 – Own-report status watcher every 30s
  // ============================================================================
  //
  // Watches the user's OWN reports (/UserEmergencyReports/{userId}) for the
  // two dispatcher-side transitions the reporter cares about:
  //
  //   Pending → Acknowledged : a responder has been assigned to the report
  //   any     → Resolved     : a responder or administrator closed it out
  //
  // Without this, either only surfaced if the user happened to reopen My
  // Reports and notice the badge had changed.
  //
  // The last status announced per report is persisted per user, so a service
  // restart doesn't re-announce, each report can raise both alerts in turn as
  // it progresses, and switching accounts on one device starts clean.
  Timer.periodic(const Duration(seconds: 30), (_) async {
    if (userId.isEmpty) return;
    try {
      final res = await http
          .get(Uri.parse('${_kDbUrl}UserEmergencyReports/$userId.json'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;
      final raw = res.body.trim();
      if (raw == 'null' || raw.isEmpty) return;

      final decoded = json.decode(raw);
      if (decoded is! Map) return;
      final reports = Map<String, dynamic>.from(decoded);

      final prefs = await SharedPreferences.getInstance();
      final prefsKey = 'notifiedReportStatus_$userId';
      final storedRaw = prefs.getString(prefsKey);
      final isFirstRun = storedRaw == null;

      final announced = <String, String>{};
      if (storedRaw != null) {
        try {
          final m = json.decode(storedRaw);
          if (m is Map) {
            m.forEach((k, v) => announced['$k'] = '$v');
          }
        } catch (_) {}
      }

      final current = <String, String>{};
      final pending = <Map<String, dynamic>>[];

      for (final entry in reports.entries) {
        final data = entry.value;
        if (data is! Map) continue;
        final report = Map<String, dynamic>.from(data);
        final status = report['Status']?.toString() ?? '';

        // Only the two transitions above are announced; Pending and the live
        // 'Active' SOS state are not news to the person who filed them.
        final isAssigned = EmergencyReportService.isAssignedStatus(status);
        final isResolved = EmergencyReportService.isResolvedStatus(status);
        if (!isAssigned && !isResolved) continue;

        final reportId = report['ReportId']?.toString() ?? entry.key;
        // Normalised so the dispatcher writing 'acknowledged' one day and
        // 'Acknowledged' the next doesn't read as a fresh transition.
        final stage = isResolved ? 'resolved' : 'assigned';
        current[reportId] = stage;
        if (!isFirstRun && announced[reportId] != stage) {
          pending.add(report);
        }
      }

      // First run for this user: whatever state reports are already in is
      // history, not news — record it silently rather than burying the user
      // in alerts for reports handled weeks ago.
      if (isFirstRun) {
        await prefs.setString(prefsKey, json.encode(current));
        // Superseded by the map above, which tracks both transitions.
        await prefs.remove('notifiedResolvedReportIds_$userId');
        debugPrint(
            '📄 Own-report watcher seeded with ${current.length} report(s)');
        return;
      }

      for (final report in pending) {
        final type = report['EmergencyType']?.toString() ?? 'other';
        final reportId = report['ReportId']?.toString() ?? '';
        final label = EmergencyReportService.getTypeLabel(type);
        final location = _ownReportLocation(report);

        // The responder's name and the assignment time live on the canonical
        // /{reportLabel}/{reportId} record — the reporter's index entry only
        // carries Status — so the full record is read for the one report that
        // just changed, rather than on every poll.
        final full = await EmergencyReportService.getReportFromIndex(report) ??
            const <String, dynamic>{};
        final merged = <String, dynamic>{...report, ...full};

        if (current[reportId] == 'resolved') {
          await _showReportResolvedAlert(
            reportId: reportId,
            reportType: type,
            reportedAt: report['CreatedAt']?.toString() ?? '',
            resolvedAt: EmergencyReportService.resolvedAtOf(merged),
            resolvedBy: EmergencyReportService.resolvedByOf(merged),
            location: location,
          );
          updateForeground('✅ Your $label was resolved');
          debugPrint('✅ Notified resolution of $reportId ($type)');
        } else {
          await _showResponderAssignedAlert(
            reportId: reportId,
            reportType: type,
            reportedAt: report['CreatedAt']?.toString() ?? '',
            assignedAt: EmergencyReportService.assignedAtOf(merged),
            responderName: EmergencyReportService.responderNameOf(merged),
            location: location,
          );
          updateForeground('🚔 A responder was assigned to your $label');
          debugPrint('🚔 Notified responder assignment on $reportId ($type)');
        }
      }

      await prefs.setString(prefsKey, json.encode(current));
    } catch (e) {
      debugPrint('📄 BG own-report status poll error: $e');
    }
  });

  updateForeground('LifeGuard360 is running • Location tracking ON');
  debugPrint('✅ Background service entry point initialised');
}

// Barangay is stored separately from the reverse-geocoded address, so the
// two are joined here the same way the report screens display them — skipping
// the placeholder values written when GPS was unavailable.
String _ownReportLocation(Map<String, dynamic> report) {
  final loc = report['Location'];
  final addr = (loc is Map ? loc['Address']?.toString() ?? '' : '').trim();
  final brgy = (report['Barangay']?.toString() ?? '').trim();
  final hasAddr = addr.isNotEmpty &&
      addr.toLowerCase() != 'location unavailable' &&
      addr.toLowerCase() != 'see map for exact location';
  final hasBrgy = brgy.isNotEmpty && brgy.toLowerCase() != 'unknown barangay';

  if (hasBrgy && hasAddr) {
    return addr.toLowerCase().contains(brgy.toLowerCase())
        ? addr
        : 'Brgy. $brgy, $addr';
  }
  if (hasBrgy) return 'Brgy. $brgy';
  if (hasAddr) return addr;
  return '';
}

// =============================================================================
// SHAKE SOS REPORT WRITER
// =============================================================================

Future<Map<String, dynamic>> _saveBgShakeReport(
    String userId, String familyCode) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    final userName = prefs.getString('userName') ?? 'Unknown';

    Map<String, dynamic> location = {
      'Latitude': null,
      'Longitude': null,
      'Address': 'Location unavailable',
      'LastUpdated': _fmtDate(DateTime.now()),
    };
    Map<String, double>? gpsPos;

    try {
      final perm = await Geolocator.checkPermission();
      if (perm != LocationPermission.denied &&
          perm != LocationPermission.deniedForever) {
        final pos = await Geolocator.getCurrentPosition(
          locationSettings: const LocationSettings(
            accuracy: LocationAccuracy.high,
            timeLimit: Duration(seconds: 8),
          ),
        );
        gpsPos = {'latitude': pos.latitude, 'longitude': pos.longitude};
        location = {
          'Latitude': pos.latitude,
          'Longitude': pos.longitude,
          'Address': 'See map for exact location',
          'LastUpdated': _fmtDate(DateTime.now()),
        };
      }
    } catch (_) {}

    // Resolved from THIS shake's actual GPS fix (nearest Panabo barangay
    // centroid), not the static home barangay on the account — same
    // resolution EmergencyReportService.saveReport() uses for other report
    // types, so a shake SOS away from home reflects where the user is now.
    final barangay =
        await EmergencyReportService.resolveReportBarangay(gpsPos, userId);

    final now = DateTime.now();
    final rand = Random();
    final suffix = List.generate(6, (_) => rand.nextInt(36).toRadixString(36))
        .join()
        .toUpperCase();
    final reportId = 'SHK-${now.millisecondsSinceEpoch}-$suffix';
    final createdAt = _fmtDate(now);

    final payload = {
      'ReportId': reportId,
      'ReportLabel': 'family-shake-sos',
      'UserId': userId,
      'UserName': userName,
      'EmergencyType': 'shake',
      'Status': 'Active',
      'CreatedAt': createdAt,
      'Timestamp': now.toIso8601String(),
      'Location': location,
      'Barangay': barangay.isNotEmpty ? barangay : 'Unknown Barangay',
      'Priority': 'critical',
      'AlertLevel': 'family-sos',
      'Details': {
        'type': 'shake',
        'trigger': 'shake_gesture',
        'message': 'Automatic SOS triggered by shake gesture',
        'alertLevel': 'family-sos',
        'priority': 'critical',
      },
    };

    await http.put(
      Uri.parse('${_kDbUrl}UserEmergencyReports/$userId/$reportId.json'),
      body: json.encode({
        'ReportId': reportId,
        'ReportLabel': 'family-shake-sos',
        'EmergencyType': 'shake',
        'Status': 'Active',
        'CreatedAt': createdAt,
        'Location': location,
        'Barangay': barangay.isNotEmpty ? barangay : 'Unknown Barangay',
        'Priority': 'critical',
        'AlertLevel': 'family-sos',
      }),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 10));

    if (familyCode.isNotEmpty) {
      await http.put(
        Uri.parse(
            '${_kDbUrl}Families/$familyCode/FamilyReports/$reportId.json'),
        body: json.encode(payload),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      await http.put(
        Uri.parse('${_kDbUrl}Families/$familyCode/SOS/$userId.json'),
        body: json.encode({
          'active': true,
          'userName': userName,
          'timestamp': now.toIso8601String(),
          'type': 'shake',
          'location': location['Address'],
        }),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));

      _sendShakeFcmToFamily(
        familyCode: familyCode,
        senderUserId: userId,
        senderName: userName,
        address: location['Address']?.toString() ?? 'Location unavailable',
      ).catchError((e) {
        debugPrint('⚠️ Shake FCM failed: $e');
      });
    }

    return {'success': true, 'reportId': reportId};
  } catch (e) {
    debugPrint('❌ _saveBgShakeReport error: $e');
    return {'success': false, 'error': '$e'};
  }
}

// =============================================================================
// FCM PUSH HELPER
// =============================================================================

Future<void> _sendShakeFcmToFamily({
  required String familyCode,
  required String senderUserId,
  required String senderName,
  required String address,
}) async {
  try {
    final accessToken = await _getFcmAccessToken();
    if (accessToken == null) return;

    final res = await http
        .get(Uri.parse('${_kDbUrl}Families/$familyCode/Members.json'))
        .timeout(const Duration(seconds: 10));

    if (res.statusCode != 200) return;
    final raw = res.body.trim();
    if (raw == 'null' || raw.isEmpty) return;

    final members = Map<String, dynamic>.from(json.decode(raw) as Map);
    final title = '🚨 SHAKE SOS — $senderName';
    final body = '📍 $address\nTap to open LifeGuard360 and check on them.';

    for (final entry in members.entries) {
      final memberId = entry.key;
      if (memberId == senderUserId) continue;
      try {
        final tokenRes = await http
            .get(Uri.parse('${_kDbUrl}Accounts/$memberId/FcmToken.json'))
            .timeout(const Duration(seconds: 5));
        if (tokenRes.statusCode != 200) continue;
        final token = tokenRes.body.trim().replaceAll('"', '');
        if (token == 'null' || token.isEmpty) continue;

        final response = await http
            .post(
              Uri.parse(
                  'https://fcm.googleapis.com/v1/projects/$_kFcmProjectId/messages:send'),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer $accessToken',
              },
              body: json.encode({
                'message': {
                  'token': token,
                  'notification': {'title': title, 'body': body},
                  'android': {
                    'priority': 'high',
                    'notification': {
                      'channel_id': 'lifeguard_shake_sos',
                      'notification_priority': 'PRIORITY_MAX',
                      'default_sound': true,
                      'default_vibrate_timings': false,
                      'vibrate_timings': [
                        '0s',
                        '0.5s',
                        '0.2s',
                        '0.5s',
                        '0.2s',
                        '0.5s'
                      ],
                      'visibility': 'PUBLIC',
                      'color': '#CC0000',
                      'icon': 'ic_launcher',
                    },
                  },
                  'apns': {
                    'headers': {'apns-priority': '10'},
                    'payload': {
                      'aps': {
                        'alert': {'title': title, 'body': body},
                        'sound': 'default',
                        'badge': 1,
                        'interruption-level': 'critical',
                      },
                    },
                  },
                  'data': {
                    'type': 'shake',
                    'senderName': senderName,
                    'familyCode': familyCode,
                    'location': address,
                  },
                },
              }),
            )
            .timeout(const Duration(seconds: 10));

        if (response.statusCode == 200) {
          debugPrint(
              '✅ Shake FCM sent to ...${token.substring(token.length - 6)}');
        } else {
          debugPrint('❌ Shake FCM ${response.statusCode}');
        }
      } catch (e) {
        debugPrint('⚠️ Shake FCM member error: $e');
      }
    }
  } catch (e) {
    debugPrint('❌ _sendShakeFcmToFamily: $e');
  }
}

Future<String?> _getFcmAccessToken() async {
  try {
    final now = DateTime.now();
    final header = base64Url
        .encode(utf8.encode(json.encode({'alg': 'RS256', 'typ': 'JWT'})))
        .replaceAll('=', '');
    final claims = base64Url
        .encode(utf8.encode(json.encode({
          'iss': _kFcmClientEmail,
          'scope': 'https://www.googleapis.com/auth/firebase.messaging',
          'aud': 'https://oauth2.googleapis.com/token',
          'iat': now.millisecondsSinceEpoch ~/ 1000,
          'exp': (now.millisecondsSinceEpoch ~/ 1000) + 3600,
        })))
        .replaceAll('=', '');

    final assertion = '$header.$claims';

    final response = await http.post(
      Uri.parse('https://oauth2.googleapis.com/token'),
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: {
        'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
        'assertion': assertion,
      },
    ).timeout(const Duration(seconds: 15));

    if (response.statusCode == 200) {
      return json.decode(response.body)['access_token'] as String?;
    }
    return null;
  } catch (e) {
    debugPrint('❌ _getFcmAccessToken: $e');
    return null;
  }
}

// =============================================================================
// SHARED HELPERS
// =============================================================================

Future<void> _patchStatus(String userId, String status) async {
  try {
    await http
        .patch(
          Uri.parse('${_kDbUrl}Accounts/$userId.json'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({
            'OnlineStatus': status,
            'LastSeen': _fmtDate(DateTime.now()),
          }),
        )
        .timeout(const Duration(seconds: 8));
  } catch (_) {}
}

Future<String> _fetchFamilyCode(String userId) async {
  try {
    final res = await http
        .get(Uri.parse('${_kDbUrl}Accounts/$userId/FamilyCode.json'))
        .timeout(const Duration(seconds: 8));
    if (res.statusCode == 200) {
      final v = res.body.trim();
      if (v != 'null' && v.isNotEmpty) return v.replaceAll('"', '').trim();
    }
  } catch (_) {}
  return '';
}

String _fmtDate(DateTime dt) => '${dt.month}/${dt.day}/${dt.year} '
    '${dt.hour.toString().padLeft(2, '0')}:'
    '${dt.minute.toString().padLeft(2, '0')}:'
    '${dt.second.toString().padLeft(2, '0')}';

Future<bool> _isSosCancelled() async {
  final prefs = await SharedPreferences.getInstance();
  // The cancel flag is written from the MAIN app's isolate (the shake
  // dialog), while this reads from the background service's isolate —
  // SharedPreferences caches its values per-isolate, so without reload()
  // this would keep reading its own stale cached copy and never see the
  // cancel at all (same cross-isolate gotcha saveOverlaySosReport() already
  // works around elsewhere in this codebase).
  await prefs.reload();
  final cancelled = prefs.getBool('shakeSosCancelled') ?? false;
  if (cancelled) await prefs.setBool('shakeSosCancelled', false);
  return cancelled;
}
