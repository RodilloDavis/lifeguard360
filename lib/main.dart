// // lib/main.dart
// //
// // ═══════════════════════════════════════════════════════════════════════════════
// // MAIN — Corrected chathead bubble lifecycle integration
// // ═══════════════════════════════════════════════════════════════════════════════
// //
// // CHATHEAD LIFECYCLE FLOW:
// // ──────────────────────────
// //   App launches   → AppLifecycleState.resumed → hide bubble
// //   Home pressed   → AppLifecycleState.paused  → show bubble
// //   App reopened   → AppLifecycleState.resumed  → hide bubble
// //   App killed     → bubble_should_show = true persists in SharedPreferences
// //   Service boots  → reads bubble_should_show → re-opens overlay window
// //
// // The bubble is shown/hidden via ChatheadSosService (which calls the real
// // FlutterOverlayWindow API), and via background service events.
// // ═══════════════════════════════════════════════════════════════════════════════

// import 'dart:async';
// import 'dart:typed_data';

// import 'package:flutter/material.dart';
// import 'package:flutter/foundation.dart' show kIsWeb;
// import 'package:flutter_background_service/flutter_background_service.dart';
// import 'package:firebase_core/firebase_core.dart';
// import 'package:firebase_messaging/firebase_messaging.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// import 'package:shared_preferences/shared_preferences.dart';

// import 'core/constants/app_colors.dart';
// import 'firebase_options.dart';
// import 'services/background_service.dart';
// import 'services/fcm_service.dart';
// import 'services/chathead_sos_service.dart';
// import 'features/auth/screens/login_screen.dart';
// import 'features/dashboard/screens/dashboard_screen.dart';
// import 'features/notifications/screens/shake_sos_alert_screen.dart';
// import 'features/map/screens/family_tracking_screen.dart';

// final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// final FlutterLocalNotificationsPlugin _localNotif =
//     FlutterLocalNotificationsPlugin();

// const String _kFcmChannelId = 'lifeguard_fcm_alerts';
// const String _kFcmChannelName = 'LifeGuard360 Push Alerts';

// final InitializationSettings _initSettings = InitializationSettings(
//   android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
//   iOS: DarwinInitializationSettings(
//     requestAlertPermission: true,
//     requestBadgePermission: true,
//     requestSoundPermission: true,
//   ),
// );

// // ─── FCM Background handler ────────────────────────────────────────────────────

// @pragma('vm:entry-point')
// Future<void> _onBackgroundMessage(RemoteMessage message) async {
//   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
//   await _localNotif.initialize(
//       settings: _initSettings,
//       onDidReceiveNotificationResponse: (NotificationResponse response) {
//         if (response.payload != null) {
//           _storePendingNotification(_decodePayload(response.payload));
//         }
//       });
//   await _showPushNotification(
//     title: message.notification?.title ??
//         message.data['title'] ??
//         '🆘 Emergency Alert',
//     body: message.notification?.body ??
//         message.data['body'] ??
//         'A family member needs help!',
//     payload: _encodePayload(message.data),
//   );
// }

// // ─── Helpers ───────────────────────────────────────────────────────────────────

// Future<void> _storePendingNotification(Map<String, dynamic> data) async {
//   try {
//     final prefs = await SharedPreferences.getInstance();
//     await prefs.setString('pending_notification', _encodePayload(data));
//   } catch (_) {}
// }

// Future<void> _showPushNotification({
//   required String title,
//   required String body,
//   String? payload,
// }) async {
//   await _localNotif.show(
//     id: (DateTime.now().millisecondsSinceEpoch ~/ 1000) & 0x7FFFFFFF,
//     title: title,
//     body: body,
//     notificationDetails: NotificationDetails(
//       android: AndroidNotificationDetails(
//         _kFcmChannelId,
//         _kFcmChannelName,
//         channelDescription: 'Emergency alerts from your family',
//         importance: Importance.max,
//         priority: Priority.max,
//         playSound: true,
//         enableVibration: true,
//         vibrationPattern:
//             Int64List.fromList(const [0, 500, 200, 500, 200, 500]),
//         fullScreenIntent: true,
//         icon: '@mipmap/ic_launcher',
//         color: const Color(0xFFCC0000),
//         visibility: NotificationVisibility.public,
//       ),
//       iOS: const DarwinNotificationDetails(
//         presentAlert: true,
//         presentBadge: true,
//         presentSound: true,
//       ),
//     ),
//     payload: payload,
//   );
// }

// String _encodePayload(Map<String, dynamic> payload) => payload.entries
//     .map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}')
//     .join('&');

// Map<String, dynamic> _decodePayload(String? payload) {
//   if (payload == null || payload.isEmpty) return {};
//   final map = <String, dynamic>{};
//   for (final part in payload.split('&')) {
//     final eq = part.indexOf('=');
//     if (eq > 0) {
//       map[part.substring(0, eq)] = Uri.decodeComponent(part.substring(eq + 1));
//     }
//   }
//   return map;
// }

// void _handleNotificationData(Map<String, dynamic> data) {
//   final type = data['type']?.toString() ?? '';
//   final reporterUserId = data['reporterUserId']?.toString() ?? '';
//   final reporterName = data['reporterName']?.toString() ?? '';
//   final familyCode = data['familyCode']?.toString() ?? '';
//   final location = data['location']?.toString() ?? '';
//   final latitude = double.tryParse(data['latitude']?.toString() ?? '');
//   final longitude = double.tryParse(data['longitude']?.toString() ?? '');
//   final reportId = data['reportId']?.toString() ?? '';
//   final timestamp = data['timestamp']?.toString() ?? '';

//   if (navigatorKey.currentState == null) {
//     _storePendingNotification(data);
//     return;
//   }

//   WidgetsBinding.instance.addPostFrameCallback((_) {
//     if (type == 'shake') {
//       navigatorKey.currentState?.push(MaterialPageRoute(
//         builder: (_) => ShakeSosAlertScreen(
//           reporterName:
//               reporterName.isNotEmpty ? reporterName : 'Family Member',
//           reporterUserId: reporterUserId,
//           familyCode: familyCode,
//           location: location.isNotEmpty ? location : 'Location unavailable',
//           latitude: latitude,
//           longitude: longitude,
//           reportId: reportId,
//           timestamp:
//               timestamp.isNotEmpty ? timestamp : DateTime.now().toString(),
//         ),
//       ));
//     } else if (reporterUserId.isNotEmpty ||
//         (latitude != null && longitude != null)) {
//       _navigateToFamilyTrackingWithReporter(
//         familyCode: familyCode,
//         reporterUserId: reporterUserId,
//         reporterName: reporterName.isNotEmpty ? reporterName : 'Family Member',
//         reporterLat: latitude,
//         reporterLng: longitude,
//         emergencyType: type.isNotEmpty ? type : 'emergency',
//       );
//     } else {
//       _navigateToDashboard();
//     }
//   });
// }

// void _navigateToDashboard() {
//   SharedPreferences.getInstance().then((prefs) {
//     final uid = prefs.getString('userId') ?? '';
//     final name = prefs.getString('userName') ?? '';
//     if (uid.isEmpty) {
//       navigatorKey.currentState?.pushReplacement(
//           MaterialPageRoute(builder: (_) => const LoginScreen()));
//     } else {
//       navigatorKey.currentState?.pushReplacement(MaterialPageRoute(
//           builder: (_) => DashboardScreen(userId: uid, userName: name)));
//     }
//   });
// }

// void _navigateToFamilyTrackingWithReporter({
//   required String familyCode,
//   required String reporterUserId,
//   required String reporterName,
//   double? reporterLat,
//   double? reporterLng,
//   required String emergencyType,
// }) {
//   SharedPreferences.getInstance().then((prefs) {
//     final uid = prefs.getString('userId') ?? '';
//     final name = prefs.getString('userName') ?? '';
//     if (uid.isEmpty) {
//       navigatorKey.currentState?.pushReplacement(
//           MaterialPageRoute(builder: (_) => const LoginScreen()));
//       return;
//     }
//     navigatorKey.currentState?.push(MaterialPageRoute(
//       builder: (_) => FamilyTrackingScreen(
//         currentUserId: uid,
//         currentUserName: name,
//         highlightMemberId: reporterUserId.isNotEmpty ? reporterUserId : null,
//         highlightMemberName: reporterName,
//         initialLat: reporterLat,
//         initialLng: reporterLng,
//         emergencyType: emergencyType,
//       ),
//     ));
//   });
// }

// // ─── Pending notification holders ─────────────────────────────────────────────

// Map<String, dynamic>? _pendingNotificationData;
// String? _pendingLocalNotificationPayload;

// // =============================================================================
// // MAIN
// // =============================================================================

// void main() async {
//   WidgetsFlutterBinding.ensureInitialized();

//   await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

//   await _localNotif.initialize(
//     settings: _initSettings,
//     onDidReceiveNotificationResponse: (NotificationResponse response) {
//       if (response.payload != null) {
//         _handleNotificationData(_decodePayload(response.payload));
//       }
//     },
//   );

//   final androidPlugin = _localNotif.resolvePlatformSpecificImplementation<
//       AndroidFlutterLocalNotificationsPlugin>();
//   await androidPlugin?.createNotificationChannel(AndroidNotificationChannel(
//     _kFcmChannelId,
//     _kFcmChannelName,
//     description: 'Emergency alerts from your family',
//     importance: Importance.max,
//     playSound: true,
//     enableVibration: true,
//     showBadge: true,
//   ));

//   FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

//   if (!kIsWeb) {
//     // ── Initialize background service (registers notification channels,
//     //    configures flutter_background_service) ──────────────────────────
//     await AppBackgroundService.initialize();
//     await AppBackgroundService.start();

//     // ── Chathead: request SYSTEM_ALERT_WINDOW permission ─────────────────
//     // We request silently on first launch. The user will see the Android
//     // settings screen once. After that, the overlay works permanently.
//     if (!await ChatheadSosService.hasPermission()) {
//       await ChatheadSosService.requestPermission();
//     }

//     // ── Tell background service the app is in the foreground ──────────────
//     // This ensures the bubble is hidden on first launch.
//     AppBackgroundService.notifyAppResumed();

//     // ── Handle pending notifications from terminated state ─────────────────
//     final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
//     if (initialMessage != null) {
//       _pendingNotificationData = initialMessage.data;
//     }

//     final details = await _localNotif.getNotificationAppLaunchDetails();
//     if (details?.didNotificationLaunchApp == true) {
//       _pendingLocalNotificationPayload = details?.notificationResponse?.payload;
//     }

//     final prefs = await SharedPreferences.getInstance();
//     final storedPayload = prefs.getString('pending_notification');
//     if (storedPayload != null && storedPayload.isNotEmpty) {
//       if (_pendingNotificationData == null) {
//         _pendingNotificationData = _decodePayload(storedPayload);
//       }
//       await prefs.remove('pending_notification');
//     }
//   }

//   runApp(const LifeGuard360App());
// }

// // =============================================================================
// // ROOT APP
// // =============================================================================

// class LifeGuard360App extends StatelessWidget {
//   const LifeGuard360App({super.key});

//   @override
//   Widget build(BuildContext context) {
//     return MaterialApp(
//       title: 'LifeGuard360',
//       debugShowCheckedModeBanner: false,
//       navigatorKey: navigatorKey,
//       theme: ThemeData(
//         colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
//         primaryColor: AppColors.primary,
//         scaffoldBackgroundColor: Colors.white,
//         fontFamily: 'Roboto',
//       ),
//       home: _LifecycleWrapper(
//         child: SplashRouter(
//           pendingNotificationData: _pendingNotificationData,
//           pendingLocalNotificationPayload: _pendingLocalNotificationPayload,
//         ),
//       ),
//     );
//   }
// }

// // =============================================================================
// // LIFECYCLE WRAPPER
// //
// // This is the gatekeeper for the chathead bubble. It observes the app's
// // lifecycle and shows/hides the bubble accordingly.
// //
// // Key decisions:
// //   • We only act on the TRANSITION (was/wasn't in foreground), not every event.
// //   • We use a 300ms delay before hiding to avoid a flash when the user
// //     switches between our app screens (which briefly fires paused/resumed).
// //   • 'inactive' on Android usually means a dialog appeared — we don't hide
// //     the bubble for that, only for a true background transition (paused).
// // =============================================================================

// class _LifecycleWrapper extends StatefulWidget {
//   final Widget child;
//   const _LifecycleWrapper({required this.child});

//   @override
//   State<_LifecycleWrapper> createState() => _LifecycleWrapperState();
// }

// class _LifecycleWrapperState extends State<_LifecycleWrapper>
//     with WidgetsBindingObserver {
//   bool _appIsInForeground = true;
//   Timer? _hideDebounce;

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);

//     // FCM foreground message — show local notification.
//     FirebaseMessaging.onMessage.listen((RemoteMessage message) {
//       _showPushNotification(
//         title: message.notification?.title ?? '🆘 Emergency Alert',
//         body: message.notification?.body ?? 'A family member needs help!',
//         payload: _encodePayload(message.data),
//       );
//     });

//     // FCM background tap.
//     FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
//       _handleNotificationData(message.data);
//     });
//   }

//   @override
//   void dispose() {
//     _hideDebounce?.cancel();
//     WidgetsBinding.instance.removeObserver(this);
//     super.dispose();
//   }

//   @override
//   void didChangeAppLifecycleState(AppLifecycleState state) {
//     if (kIsWeb) return;

//     debugPrint('📱 Lifecycle → $state (foreground: $_appIsInForeground)');

//     switch (state) {
//       // ── App going to background ───────────────────────────────────────────
//       case AppLifecycleState.paused:
//         if (_appIsInForeground) {
//           _appIsInForeground = false;
//           _hideDebounce?.cancel();
//           debugPrint('📱 App paused → showing chathead bubble');
//           _showBubble();
//         }
//         break;

//       // ── App coming back to foreground ─────────────────────────────────────
//       case AppLifecycleState.resumed:
//         _hideDebounce?.cancel();
//         if (!_appIsInForeground) {
//           _appIsInForeground = true;
//           debugPrint('📱 App resumed → hiding chathead bubble');
//           _hideBubble();
//           AppBackgroundService.ensureRunning();
//         }
//         break;

//       // ── App detached (being killed) ───────────────────────────────────────
//       // We persist the flag so the background service re-shows the bubble
//       // when it restarts after the kill.
//       case AppLifecycleState.detached:
//         if (_appIsInForeground) {
//           _appIsInForeground = false;
//           _showBubble();
//           debugPrint('📱 App detached → bubble flag set for post-kill restore');
//         }
//         break;

//       // ── Inactive: system dialog, notification shade, etc. ─────────────────
//       // Don't change bubble state for brief inactivity.
//       case AppLifecycleState.inactive:
//       case AppLifecycleState.hidden:
//         break;
//     }
//   }

//   void _showBubble() {
//     // ChatheadSosService.show() calls FlutterOverlayWindow.showOverlay()
//     // which opens the actual system window over all other apps.
//     ChatheadSosService.show();
//     // Also notify background service so it knows the state.
//     AppBackgroundService.notifyAppPaused();
//   }

//   void _hideBubble() {
//     // ChatheadSosService.hide() calls FlutterOverlayWindow.closeOverlay()
//     // which removes the system window entirely.
//     ChatheadSosService.hide();
//     AppBackgroundService.notifyAppResumed();
//   }

//   @override
//   Widget build(BuildContext context) => widget.child;
// }

// // =============================================================================
// // SPLASH / SESSION ROUTER
// // =============================================================================

// class SplashRouter extends StatefulWidget {
//   final Map<String, dynamic>? pendingNotificationData;
//   final String? pendingLocalNotificationPayload;

//   const SplashRouter({
//     super.key,
//     this.pendingNotificationData,
//     this.pendingLocalNotificationPayload,
//   });

//   @override
//   State<SplashRouter> createState() => _SplashRouterState();
// }

// class _SplashRouterState extends State<SplashRouter> {
//   bool _isProcessing = false;

//   @override
//   void initState() {
//     super.initState();
//     _checkSession();
//   }

//   @override
//   void dispose() {
//     _isProcessing = false;
//     super.dispose();
//   }

//   Future<void> _checkSession() async {
//     if (_isProcessing) return;
//     _isProcessing = true;

//     await Future.delayed(const Duration(seconds: 1));
//     if (!mounted) {
//       _isProcessing = false;
//       return;
//     }

//     final prefs = await SharedPreferences.getInstance();
//     final userId = prefs.getString('userId') ?? '';
//     final userName = prefs.getString('userName') ?? '';

//     if (!mounted) {
//       _isProcessing = false;
//       return;
//     }

//     if (userId.isNotEmpty) {
//       if (!kIsWeb) {
//         await AppBackgroundService.start();
//         AppBackgroundService.notifyAppResumed();
//       }
//       await FcmService.saveTokenToFirebase(userId);

//       await Navigator.pushReplacement(
//         context,
//         MaterialPageRoute(
//             builder: (_) =>
//                 DashboardScreen(userId: userId, userName: userName)),
//       );

//       // Handle pending notification after navigation settles.
//       WidgetsBinding.instance.addPostFrameCallback((_) {
//         Future.delayed(const Duration(milliseconds: 500), () {
//           if (widget.pendingNotificationData != null && mounted) {
//             _handleNotificationData(widget.pendingNotificationData!);
//           } else if (widget.pendingLocalNotificationPayload != null &&
//               mounted) {
//             _handleNotificationData(
//                 _decodePayload(widget.pendingLocalNotificationPayload));
//           }
//         });
//       });
//     } else {
//       if (!mounted) {
//         _isProcessing = false;
//         return;
//       }
//       await Navigator.pushReplacement(
//         context,
//         MaterialPageRoute(builder: (_) => const LoginScreen()),
//       );
//     }

//     _isProcessing = false;
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: AppColors.splashBackground,
//       body: Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Container(
//               width: 150,
//               height: 150,
//               decoration: const BoxDecoration(
//                 color: AppColors.secondary,
//                 shape: BoxShape.circle,
//               ),
//               child: const Icon(Icons.security, size: 80, color: Colors.white),
//             ),
//             const SizedBox(height: 20),
//             const Text(
//               'LifeGuard360',
//               style: TextStyle(
//                 fontSize: 32,
//                 fontWeight: FontWeight.bold,
//                 color: AppColors.secondary,
//               ),
//             ),
//             const SizedBox(height: 40),
//             const CircularProgressIndicator(
//               valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
//             ),
//           ],
//         ),
//       ),
//     );
//   }
// }

// lib/main.dart
// lib/main.dart
import 'dart:async';
import 'dart:typed_data';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'core/constants/app_colors.dart';
import 'firebase_options.dart';
import 'services/background_service.dart';
import 'services/connectivity_quality_service.dart';
import 'services/fcm_service.dart';
import 'services/offline_report_queue_service.dart';
import 'features/auth/screens/login_screen.dart';
import 'features/dashboard/screens/dashboard_screen.dart';
import 'features/notifications/screens/shake_sos_alert_screen.dart';
import 'features/map/screens/family_tracking_screen.dart';
import 'features/overlay/screens/sos_bubble_overlay.dart';
import 'services/overlay_service.dart';
import 'package:flutter_overlay_window/flutter_overlay_window.dart'
    hide NotificationVisibility;

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

final FlutterLocalNotificationsPlugin _localNotif =
    FlutterLocalNotificationsPlugin();

// Bumped to _v2 when the family-alert siren sound was added — Android locks
// a channel's sound in at creation time, so devices that already created the
// old channel would otherwise keep the default sound forever.
const String _kFcmChannelId = 'lifeguard_fcm_alerts_v2';
const String _kFcmChannelName = 'LifeGuard360 Push Alerts';

// Separate id used once the user has granted Do Not Disturb access, for the
// same reason as _kFcmChannelId's own _v2 bump above: bypassDnd is locked in
// at channel-creation time too, so it needs an id Android has never created
// before to actually take — see AppBackgroundService's matching _Dnd ids in
// background_service.dart for the fuller explanation.
const String _kFcmChannelIdDnd = 'lifeguard_fcm_alerts_v2_dnd';

final InitializationSettings _initSettings = InitializationSettings(
  android: const AndroidInitializationSettings('@mipmap/ic_launcher'),
  iOS: DarwinInitializationSettings(
    requestAlertPermission: true,
    requestBadgePermission: true,
    requestSoundPermission: true,
  ),
);

// =============================================================================
// FCM BACKGROUND HANDLER
// =============================================================================

@pragma('vm:entry-point')
Future<void> _onBackgroundMessage(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  await _localNotif.initialize(
    settings: _initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null) {
        _storePendingNotification(_decodePayload(response.payload));
      }
    },
  );
  await _showPushNotification(
    title: message.notification?.title ??
        message.data['title'] ??
        '🆘 Emergency Alert',
    body: message.notification?.body ??
        message.data['body'] ??
        'A family member needs help!',
    payload: _encodePayload(message.data),
  );
}

// =============================================================================
// HELPERS
// =============================================================================

Future<void> _storePendingNotification(Map<String, dynamic> data) async {
  try {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('pending_notification', _encodePayload(data));
  } catch (_) {}
}

Future<void> _showPushNotification({
  required String title,
  required String body,
  String? payload,
}) async {
  final androidPlugin = _localNotif.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  final dndGranted =
      (await androidPlugin?.hasNotificationPolicyAccess()) ?? false;

  // Deterministic ID (derived from the notification's own content/payload,
  // not the delivery time) so a redelivered FCM message replaces the
  // existing tray entry instead of stacking a duplicate.
  await _localNotif.show(
    id: (payload ?? '$title|$body').hashCode & 0x7FFFFFFF,
    title: title,
    body: body,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        dndGranted ? _kFcmChannelIdDnd : _kFcmChannelId,
        _kFcmChannelName,
        channelDescription: 'Emergency alerts from your family',
        importance: Importance.max,
        priority: Priority.max,
        playSound: true,
        sound: const RawResourceAndroidNotificationSound('family_alert_siren'),
        enableVibration: true,
        vibrationPattern:
            Int64List.fromList(const [0, 500, 200, 500, 200, 500]),
        fullScreenIntent: true,
        icon: '@mipmap/ic_launcher',
        color: const Color(0xFFCC0000),
        visibility: NotificationVisibility.public,
        channelBypassDnd: dndGranted,
      ),
      iOS: const DarwinNotificationDetails(
        presentAlert: true,
        presentBadge: true,
        presentSound: true,
      ),
    ),
    payload: payload,
  );
}

/// (Re)creates the FCM push-alert channel, picking the "_dnd" id/bypassDnd
/// once Do Not Disturb access is granted — see _kFcmChannelIdDnd's doc
/// comment. Called once at startup, and again from SettingsScreen right
/// after the user grants access, so this channel doesn't have to wait for
/// the next full app restart the way it otherwise would (Android locks
/// bypassDnd at channel-creation time, same as every other alert channel —
/// see AppBackgroundService.refreshAlertChannels for the fuller version of
/// this same explanation).
Future<void> refreshFcmChannel() async {
  final androidPlugin = _localNotif.resolvePlatformSpecificImplementation<
      AndroidFlutterLocalNotificationsPlugin>();
  final dndGranted =
      (await androidPlugin?.hasNotificationPolicyAccess()) ?? false;
  await androidPlugin?.createNotificationChannel(
    AndroidNotificationChannel(
      dndGranted ? _kFcmChannelIdDnd : _kFcmChannelId,
      _kFcmChannelName,
      description: 'Emergency alerts from your family',
      importance: Importance.max,
      playSound: true,
      sound: const RawResourceAndroidNotificationSound('family_alert_siren'),
      enableVibration: true,
      showBadge: true,
      bypassDnd: dndGranted,
    ),
  );
}

String _encodePayload(Map<String, dynamic> payload) => payload.entries
    .map((e) => '${e.key}=${Uri.encodeComponent(e.value.toString())}')
    .join('&');

Map<String, dynamic> _decodePayload(String? payload) {
  if (payload == null || payload.isEmpty) return {};
  final map = <String, dynamic>{};
  for (final part in payload.split('&')) {
    final eq = part.indexOf('=');
    if (eq > 0) {
      map[part.substring(0, eq)] = Uri.decodeComponent(part.substring(eq + 1));
    }
  }
  return map;
}

void _handleNotificationData(Map<String, dynamic> data) {
  final type = data['type']?.toString() ?? '';
  final reporterUserId = data['reporterUserId']?.toString() ?? '';
  final reporterName = data['reporterName']?.toString() ?? '';
  final familyCode = data['familyCode']?.toString() ?? '';
  final location = data['location']?.toString() ?? '';
  final latitude = double.tryParse(data['latitude']?.toString() ?? '');
  final longitude = double.tryParse(data['longitude']?.toString() ?? '');
  final reportId = data['reportId']?.toString() ?? '';
  final timestamp = data['timestamp']?.toString() ?? '';

  if (navigatorKey.currentState == null) {
    _storePendingNotification(data);
    return;
  }

  WidgetsBinding.instance.addPostFrameCallback((_) {
    if (type == 'shake') {
      navigatorKey.currentState?.push(MaterialPageRoute(
        builder: (_) => ShakeSosAlertScreen(
          reporterName:
              reporterName.isNotEmpty ? reporterName : 'Family Member',
          reporterUserId: reporterUserId,
          familyCode: familyCode,
          location: location.isNotEmpty ? location : 'Location unavailable',
          latitude: latitude,
          longitude: longitude,
          reportId: reportId,
          timestamp:
              timestamp.isNotEmpty ? timestamp : DateTime.now().toString(),
        ),
      ));
    } else if (reporterUserId.isNotEmpty ||
        (latitude != null && longitude != null)) {
      _navigateToFamilyTrackingWithReporter(
        familyCode: familyCode,
        reporterUserId: reporterUserId,
        reporterName: reporterName.isNotEmpty ? reporterName : 'Family Member',
        reporterLat: latitude,
        reporterLng: longitude,
        emergencyType: type.isNotEmpty ? type : 'emergency',
      );
    } else {
      _navigateToDashboard();
    }
  });
}

void _navigateToDashboard() {
  SharedPreferences.getInstance().then((prefs) {
    final uid = prefs.getString('userId') ?? '';
    final name = prefs.getString('userName') ?? '';
    if (uid.isEmpty) {
      navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()));
    } else {
      navigatorKey.currentState?.pushReplacement(MaterialPageRoute(
          builder: (_) => DashboardScreen(userId: uid, userName: name)));
    }
  });
}

void _navigateToFamilyTrackingWithReporter({
  required String familyCode,
  required String reporterUserId,
  required String reporterName,
  double? reporterLat,
  double? reporterLng,
  required String emergencyType,
}) {
  SharedPreferences.getInstance().then((prefs) {
    final uid = prefs.getString('userId') ?? '';
    final name = prefs.getString('userName') ?? '';
    if (uid.isEmpty) {
      navigatorKey.currentState?.pushReplacement(
          MaterialPageRoute(builder: (_) => const LoginScreen()));
      return;
    }
    navigatorKey.currentState?.push(MaterialPageRoute(
      builder: (_) => FamilyTrackingScreen(
        currentUserId: uid,
        currentUserName: name,
        highlightMemberId: reporterUserId.isNotEmpty ? reporterUserId : null,
        highlightMemberName: reporterName,
        initialLat: reporterLat,
        initialLng: reporterLng,
        emergencyType: emergencyType,
      ),
    ));
  });
}

// =============================================================================
// PENDING NOTIFICATION HOLDERS
// =============================================================================

Map<String, dynamic>? _pendingNotificationData;
String? _pendingLocalNotificationPayload;

// =============================================================================
// MAIN
// =============================================================================

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  // Sends uncaught exceptions to the Firebase Crashlytics console instead of
  // only being visible in adb logcat / a locally-running `flutter run`
  // session. FlutterError.onError catches framework-level errors (widget
  // build/layout/paint); PlatformDispatcher.instance.onError additionally
  // catches errors from async code outside the Flutter framework's own
  // error zone — e.g. a Future that resolves after its screen has already
  // been disposed, which is exactly the class of bug this covers.
  FlutterError.onError = FirebaseCrashlytics.instance.recordFlutterFatalError;
  PlatformDispatcher.instance.onError = (error, stack) {
    FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
    return true;
  };

  await _localNotif.initialize(
    settings: _initSettings,
    onDidReceiveNotificationResponse: (NotificationResponse response) {
      if (response.payload != null) {
        _handleNotificationData(_decodePayload(response.payload));
      }
    },
  );

  await refreshFcmChannel();

  FirebaseMessaging.onBackgroundMessage(_onBackgroundMessage);

  if (!kIsWeb) {
    // Handle cold-start notifications. SplashRouter reads the two module
    // variables below as constructor params in LifeGuard360App.build(),
    // which runs synchronously as part of runApp() — so this has to
    // resolve before runApp() is called, or a cold start from tapping a
    // notification would silently lose its target screen.
    final initialMessage = await FirebaseMessaging.instance.getInitialMessage();
    if (initialMessage != null) {
      _pendingNotificationData = initialMessage.data;
    }

    final details = await _localNotif.getNotificationAppLaunchDetails();
    if (details?.didNotificationLaunchApp == true) {
      _pendingLocalNotificationPayload = details?.notificationResponse?.payload;
    }

    final prefs = await SharedPreferences.getInstance();
    final storedPayload = prefs.getString('pending_notification');
    if (storedPayload != null && storedPayload.isNotEmpty) {
      _pendingNotificationData ??= _decodePayload(storedPayload);
      await prefs.remove('pending_notification');
    }
  }

  runApp(const LifeGuard360App());

  // ── Deferred to AFTER the first frame ──────────────────────────────────
  //
  // Everything below used to run BEFORE runApp(), so nothing painted at all
  // until it finished — and AppBackgroundService.initialize() requests two
  // native permission dialogs (notifications, then battery-optimization
  // exemption), which block on a human tapping something. On a slower
  // device that stalled the very first frame for seconds, sometimes far
  // longer if the OS's own battery-manager prompt piled on top (observed
  // on this Transsion/Infinix device). None of it is needed to paint the
  // splash screen, so it now runs after the UI is already up — the
  // permission prompts appear a beat later instead of gating launch, and
  // the background service/overlay finish initializing while the user is
  // already looking at something.
  if (!kIsWeb) {
    unawaited(() async {
      // Tear down any bubble left over from a previous session (e.g. the
      // app was force-killed while backgrounded with the bubble still on
      // screen). _LifecycleWrapper's didChangeAppLifecycleState only fires
      // on lifecycle TRANSITIONS, never for the app's initial state, so
      // without this a stray overlay would keep floating over the splash/
      // login screen on cold start even though the app is in the
      // foreground. Fired before anything else in this block so it clears
      // as fast as possible.
      await OverlayService.hide();

      // Starts the connection-quality probe that CachedHttpGet uses to
      // decide when to serve cached data instead of hitting the network,
      // and when to invalidate its cache so already-open screens resync
      // automatically the moment a weak/dropped connection recovers.
      ConnectivityQualityService.init();

      // Starts the connectivity listener and makes a best-effort attempt
      // to send anything left over in the offline report queue from a
      // previous session (e.g. the app was killed before it ever
      // reconnected). Deferred here like everything else in this block —
      // it doesn't gate the first frame.
      OfflineReportQueueService.init();

      await AppBackgroundService.initialize();
      await AppBackgroundService.start();

      // Messages sent from the overlay engine via
      // FlutterOverlayWindow.shareData
      FlutterOverlayWindow.overlayListener.listen((event) {
        try {
          if (event is Map) {
            final name = event['event']?.toString() ?? '';
            if (name == 'overlay_sos_sent') {
              debugPrint('Overlay SOS sent -> reportId: ${event['reportId']}');
            } else if (name == 'overlay_sos_failed') {
              debugPrint('Overlay SOS FAILED -> ${event['error']}');
            } else if (name == 'overlay_dismissed') {
              debugPrint('Overlay bubble dismissed by drag-to-close');
              OverlayService.markDismissedByDrag();
            }
          }
        } catch (e) {
          debugPrint('Overlay listener error: $e');
        }
      });

      // Re-show the bubble if the user had it switched on, then hand it the
      // current session so an SOS never depends on SharedPreferences
      // working inside the overlay's own Flutter engine.
      await OverlayService.restoreIfEnabled();
      await OverlayService.pushSession();
    }());
  }
}

// =============================================================================
// FLOATING SOS BUBBLE - OVERLAY ENGINE ENTRY POINT
// =============================================================================
//
// Android starts a SECOND Flutter engine for the system overlay window and
// calls this entry point instead of main(). It must stay top-level and keep
// the @pragma annotation, or the AOT compiler will tree-shake it away and the
// bubble will fail to launch in release builds.
//
// Everything the bubble needs (SharedPreferences, http, Geolocator) is reached
// through EmergencyReportService, so no Firebase initialisation is required
// here - reports are written over the REST API.

@pragma('vm:entry-point')
void overlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const SosBubbleOverlay());
}

// =============================================================================
// ROOT APP
// =============================================================================

class LifeGuard360App extends StatelessWidget {
  const LifeGuard360App({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'LifeGuard360',
      debugShowCheckedModeBanner: false,
      navigatorKey: navigatorKey,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.primary),
        primaryColor: AppColors.primary,
        scaffoldBackgroundColor: Colors.white,
        fontFamily: 'Roboto',
      ),
      // _LifecycleWrapper MUST live here, not as `home:`. `home:` becomes the
      // content of the Navigator's INITIAL route, and SplashRouter replaces
      // that very route (Navigator.pushReplacement to the dashboard) about a
      // second after every launch — which disposes anything rooted inside
      // it, observer and all. `builder` wraps the Navigator itself, so it
      // persists across every push/pushReplacement for the life of the app.
      // Without this, didChangeAppLifecycleState silently stops firing the
      // moment the splash screen hands off, and the floating bubble never
      // shows or hides on any later background/foreground transition.
      builder: (context, child) => _LifecycleWrapper(child: child!),
      home: SplashRouter(
        pendingNotificationData: _pendingNotificationData,
        pendingLocalNotificationPayload: _pendingLocalNotificationPayload,
      ),
    );
  }
}

// =============================================================================
// LIFECYCLE WRAPPER
// =============================================================================

class _LifecycleWrapper extends StatefulWidget {
  final Widget child;
  const _LifecycleWrapper({required this.child});

  @override
  State<_LifecycleWrapper> createState() => _LifecycleWrapperState();
}

class _LifecycleWrapperState extends State<_LifecycleWrapper>
    with WidgetsBindingObserver {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);

    // Show local notification for foreground FCM messages
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      _showPushNotification(
        title: message.notification?.title ??
            message.data['title'] ??
            '🆘 Emergency Alert',
        body: message.notification?.body ??
            message.data['body'] ??
            'A family member needs help!',
        payload: _encodePayload(message.data),
      );
    });

    // Handle notification tap while app is in background (not terminated)
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      _handleNotificationData(message.data);
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (kIsWeb) return;
    debugPrint('📱 Lifecycle → $state');

    switch (state) {
      case AppLifecycleState.resumed:
        // The app itself is on screen — the floating bubble would just
        // duplicate the SOS control the app UI already has, so hide it
        // until the user actually leaves.
        AppBackgroundService.ensureRunning();
        OverlayService.hide();
        break;

      case AppLifecycleState.paused:
      case AppLifecycleState.detached:
        // App backgrounded (home button, app switch) or being closed — bring
        // the bubble up, if the user has it turned on, so SOS is still one
        // tap away. No-ops silently if the permission was revoked; it must
        // never trigger the permission-request flow here (see
        // showIfEnabledAndPermitted).
        OverlayService.showIfEnabledAndPermitted();
        break;

      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
        // Transient — a system dialog, the notification shade, an app
        // switcher preview. Don't flicker the bubble for these.
        break;
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

// =============================================================================
// SPLASH / SESSION ROUTER
// =============================================================================

class SplashRouter extends StatefulWidget {
  final Map<String, dynamic>? pendingNotificationData;
  final String? pendingLocalNotificationPayload;

  const SplashRouter({
    super.key,
    this.pendingNotificationData,
    this.pendingLocalNotificationPayload,
  });

  @override
  State<SplashRouter> createState() => _SplashRouterState();
}

class _SplashRouterState extends State<SplashRouter> {
  bool _isProcessing = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  @override
  void dispose() {
    _isProcessing = false;
    super.dispose();
  }

  Future<void> _checkSession() async {
    if (_isProcessing) return;
    _isProcessing = true;

    await Future.delayed(const Duration(seconds: 1));
    if (!mounted) {
      _isProcessing = false;
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final userId = prefs.getString('userId') ?? '';
    final userName = prefs.getString('userName') ?? '';

    if (!mounted) {
      _isProcessing = false;
      return;
    }

    if (userId.isNotEmpty) {
      if (!kIsWeb) {
        await AppBackgroundService.start();
      }
      await FcmService.saveTokenToFirebase(userId);

      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(userId: userId, userName: userName),
        ),
      );

      WidgetsBinding.instance.addPostFrameCallback((_) {
        Future.delayed(const Duration(milliseconds: 500), () {
          if (widget.pendingNotificationData != null && mounted) {
            _handleNotificationData(widget.pendingNotificationData!);
          } else if (widget.pendingLocalNotificationPayload != null &&
              mounted) {
            _handleNotificationData(
                _decodePayload(widget.pendingLocalNotificationPayload));
          }
        });
      });
    } else {
      if (!mounted) {
        _isProcessing = false;
        return;
      }
      await Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }

    _isProcessing = false;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 150,
              height: 150,
              decoration: const BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.security,
                size: 80,
                color: Colors.white,
              ),
            ),
            const SizedBox(height: 20),
            const Text(
              'LifeGuard360',
              style: TextStyle(
                fontSize: 32,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 40),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(AppColors.primary),
            ),
          ],
        ),
      ),
    );
  }
}
