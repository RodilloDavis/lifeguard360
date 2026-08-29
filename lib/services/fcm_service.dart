// lib/services/fcm_service.dart
//
// Changes vs original:
//   + sendNotificationToDispatchers() — called by EmergencyReportService
//     after every standard (non-shake) report save. Reads all dispatcher FCM
//     tokens from /DispatcherTokens and sends a high-priority push to each.
//   + Added latitude/longitude to family push payload for map navigation.
//
// Everything else is unchanged.
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'package:dart_jsonwebtoken/dart_jsonwebtoken.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

class FcmService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';
  static const String _projectId = 'lifeguard-cefd9';
  static const String _clientEmail =
      'firebase-adminsdk-fbsvc@lifeguard-cefd9.iam.gserviceaccount.com';
  static const String _privateKey = '-----BEGIN PRIVATE KEY-----\n'
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

  // ── Save FCM token to Firebase ────────────────────────────────────────────
  static Future<void> saveTokenToFirebase(String userId) async {
    try {
      final messaging = FirebaseMessaging.instance;
      await messaging.requestPermission(
        alert: true,
        badge: true,
        sound: true,
        criticalAlert: true,
      );

      final token = await messaging.getToken();
      if (token == null || token.isEmpty) {
        print('⚠️ FCM token is null');
        return;
      }

      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('fcmToken', token);

      await http
          .patch(
            Uri.parse('${_dbUrl}Accounts/$userId.json'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode({
              'FcmToken': token,
              'FcmTokenUpdatedAt': DateTime.now().toIso8601String(),
            }),
          )
          .timeout(const Duration(seconds: 10));

      print('✅ FCM token saved for $userId');

      messaging.onTokenRefresh.listen((newToken) async {
        await http.patch(
          Uri.parse('${_dbUrl}Accounts/$userId.json'),
          headers: {'Content-Type': 'application/json'},
          body: json.encode({'FcmToken': newToken}),
        );
        await prefs.setString('fcmToken', newToken);
        print('🔄 FCM token refreshed');
      });
    } catch (e) {
      print('❌ saveTokenToFirebase: $e');
    }
  }

  // ── Get OAuth2 access token via JWT ───────────────────────────────────────
  static Future<String?> _getAccessToken() async {
    try {
      final now = DateTime.now();
      final jwt = JWT(
        {
          'iss': _clientEmail,
          'scope': 'https://www.googleapis.com/auth/firebase.messaging',
          'aud': 'https://oauth2.googleapis.com/token',
          'iat': now.millisecondsSinceEpoch ~/ 1000,
          'exp': (now.millisecondsSinceEpoch ~/ 1000) + 3600,
        },
      );

      final token = jwt.sign(
        RSAPrivateKey(_privateKey),
        algorithm: JWTAlgorithm.RS256,
      );

      final response = await http.post(
        Uri.parse('https://oauth2.googleapis.com/token'),
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        body: {
          'grant_type': 'urn:ietf:params:oauth:grant-type:jwt-bearer',
          'assertion': token,
        },
      ).timeout(const Duration(seconds: 15));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        print('✅ FCM access token obtained');
        return data['access_token'] as String?;
      } else {
        print(
            '❌ Token exchange failed: ${response.statusCode} ${response.body}');
        return null;
      }
    } catch (e) {
      print('❌ _getAccessToken: $e');
      return null;
    }
  }

  // ── Send push to all OTHER family members ─────────────────────────────────
  static Future<void> sendEmergencyNotificationToFamily({
    required String familyCode,
    required String reporterUserId,
    required String reporterName,
    required String emergencyType,
    required String location,
    double? latitude,
    double? longitude,
    String? reportId,
    String? timestamp,
  }) async {
    if (familyCode.isEmpty) return;

    try {
      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        print('❌ No access token — push not sent');
        return;
      }

      final res = await http
          .get(Uri.parse('${_dbUrl}Families/$familyCode/Members.json'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;
      final raw = res.body.trim();
      if (raw == 'null' || raw.isEmpty) return;

      final Map<String, dynamic> members =
          Map<String, dynamic>.from(json.decode(raw) as Map);

      final emoji = {
            'fire': '🔥',
            'medical': '🚑',
            'flood': '🌊',
            'crime': '🚨',
            'accident': '🚗',
            'shake': '📳',
            'bubble': '🆘',
            'other': '⚠️',
          }[emergencyType] ??
          '⚠️';

      final typeLabel = {
            'fire': 'Fire Emergency',
            'medical': 'Medical Emergency',
            'flood': 'Flood Emergency',
            'crime': 'Crime Report',
            'accident': 'Accident',
            'shake': 'SHAKE SOS',
            'bubble': 'SOS BUTTON',
            'other': 'Emergency',
          }[emergencyType] ??
          'Emergency';

      final isSos = emergencyType == 'shake' || emergencyType == 'bubble';

      final title = isSos
          ? '$emoji $reporterName is in danger!'
          : '$emoji $typeLabel reported by $reporterName';

      final body = emergencyType == 'shake'
          ? '$reporterName triggered a Shake SOS.\n📍 $location'
          : emergencyType == 'bubble'
              ? '$reporterName pressed the SOS bubble 5 times.\n📍 $location'
              : '$reporterName filed a $typeLabel report.\n📍 $location\nTap to view their location.';

      final List<String> tokens = [];
      for (final entry in members.entries) {
        final memberId = entry.key;
        if (memberId == reporterUserId) continue;
        try {
          final tokenRes = await http
              .get(Uri.parse('${_dbUrl}Accounts/$memberId/FcmToken.json'))
              .timeout(const Duration(seconds: 5));
          if (tokenRes.statusCode == 200) {
            final t = tokenRes.body.trim().replaceAll('"', '');
            if (t != 'null' && t.isNotEmpty) tokens.add(t);
          }
        } catch (_) {}
      }

      if (tokens.isEmpty) {
        print('⚠️ No FCM tokens found for family');
        return;
      }

      print('📤 Sending to ${tokens.length} family member(s)');
      for (final token in tokens) {
        await _sendFcmMessage(
          accessToken: accessToken,
          token: token,
          title: title,
          body: body,
          data: {
            'type': emergencyType,
            'reporterName': reporterName,
            'reporterUserId': reporterUserId,
            'familyCode': familyCode,
            'location': location,
            'latitude': latitude?.toString() ?? '',
            'longitude': longitude?.toString() ?? '',
            'reportId': reportId ?? '',
            'timestamp': timestamp ?? '',
            'click_action': 'FLUTTER_NOTIFICATION_CLICK',
          },
          channelId: 'lifeguard_fcm_alerts',
          color: '#CC0000',
        );
      }
    } catch (e) {
      print('❌ sendEmergencyNotificationToFamily: $e');
    }
  }

  // ── NEW: Send push to ALL registered dispatchers ──────────────────────────
  static Future<void> sendNotificationToDispatchers({
    required String reporterName,
    required String emergencyType,
    required String location,
    required String barangay,
    required String reportId,
  }) async {
    try {
      final res = await http
          .get(Uri.parse('${_dbUrl}DispatcherTokens.json'))
          .timeout(const Duration(seconds: 10));

      if (res.statusCode != 200) return;
      final raw = res.body.trim();
      if (raw == 'null' || raw.isEmpty) {
        print('⚠️ No dispatcher tokens found — skipping dispatcher push');
        return;
      }

      final Map<String, dynamic> dispatchers =
          Map<String, dynamic>.from(json.decode(raw) as Map);

      final List<String> tokens = [];
      for (final entry in dispatchers.entries) {
        final t = (entry.value as Map?)?['token']?.toString() ?? '';
        if (t.isNotEmpty && t != 'null') tokens.add(t);
      }

      if (tokens.isEmpty) {
        print('⚠️ No active dispatcher tokens');
        return;
      }

      final emoji = {
            'fire': '🔥',
            'medical': '🚑',
            'flood': '🌊',
            'crime': '🚨',
            'accident': '🚗',
            'bubble': '🆘',
            'other': '⚠️',
          }[emergencyType] ??
          '⚠️';

      final typeLabel = {
            'fire': 'Fire Emergency',
            'medical': 'Medical Emergency',
            'flood': 'Flood Emergency',
            'crime': 'Crime Report',
            'accident': 'Accident',
            'bubble': 'CRITICAL SOS',
            'other': 'Emergency',
          }[emergencyType] ??
          'Emergency';

      // The floating SOS bubble is a critical, potentially life-threatening
      // trigger — call that out distinctly instead of the generic "NEW
      // REPORT" framing used for standard report types.
      final title = emergencyType == 'bubble'
          ? '$emoji CRITICAL: $reporterName triggered SOS!'
          : '$emoji NEW REPORT: $typeLabel';
      final body = emergencyType == 'bubble'
          ? '👤 $reporterName pressed the SOS bubble · 📍 Brgy. $barangay\n$location'
          : '👤 $reporterName · 📍 Brgy. $barangay\n$location';

      final accessToken = await _getAccessToken();
      if (accessToken == null) {
        print('❌ No access token — dispatcher push not sent');
        return;
      }

      print(
          '📤 Notifying ${tokens.length} dispatcher(s) of new $emergencyType report');

      for (final token in tokens) {
        await _sendFcmMessage(
          accessToken: accessToken,
          token: token,
          title: title,
          body: body,
          data: {
            'type': emergencyType,
            'reporterName': reporterName,
            'reportId': reportId,
            'barangay': barangay,
            'location': location,
            'source': 'user_report',
          },
          channelId: 'lifeguard_dispatcher_alerts',
          color: '#0088CC',
        );
      }
    } catch (e) {
      print('❌ sendNotificationToDispatchers: $e');
    }
  }

  // ── Shared FCM V1 send helper ─────────────────────────────────────────────
  static Future<void> _sendFcmMessage({
    required String accessToken,
    required String token,
    required String title,
    required String body,
    required Map<String, String> data,
    required String channelId,
    required String color,
  }) async {
    try {
      // Data-only message — deliberately omits the top-level `notification`
      // block. When that block is present, Android auto-displays it via
      // Play Services AND our own background handler calls
      // flutter_local_notifications to show it again, producing two
      // notifications for one event. Sending data-only makes the app's
      // local-notification call the single source of truth for display.
      final response = await http
          .post(
            Uri.parse(
                'https://fcm.googleapis.com/v1/projects/$_projectId/messages:send'),
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer $accessToken',
            },
            body: json.encode({
              'message': {
                'token': token,
                'android': {'priority': 'high'},
                'apns': {
                  'headers': {
                    'apns-priority': '10',
                    'apns-push-type': 'background',
                  },
                  'payload': {
                    'aps': {'content-available': 1},
                  },
                },
                'data': {
                  ...data,
                  'title': title,
                  'body': body,
                  'channel_id': channelId,
                  'color': color,
                },
              },
            }),
          )
          .timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        print('✅ Push sent to ...${token.substring(token.length - 6)}');
      } else {
        print('❌ Push failed ${response.statusCode}: ${response.body}');
      }
    } catch (e) {
      print('❌ _sendFcmMessage error: $e');
    }
  }
}
