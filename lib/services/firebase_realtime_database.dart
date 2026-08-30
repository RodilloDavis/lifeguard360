import 'dart:convert';
import 'dart:async';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../core/utils/cached_http_get.dart';

class FirebaseService {
  static const String dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';
  static const String apiKey = 'AIzaSyCk9_Lc6Osz3Xs1WhYKzF3CfUpTImn1704';

  // ─── Helpers ───────────────────────────────────────────────────────────────

  static String _formatDate(DateTime dt) {
    return '${dt.month}/${dt.day}/${dt.year} '
        '${dt.hour.toString().padLeft(2, '0')} :'
        '${dt.minute.toString().padLeft(2, '0')} :'
        '${dt.second.toString().padLeft(2, '0')}';
  }

  static String _generateFamilyCode() {
    final rand = Random();
    return (100000 + rand.nextInt(900000)).toString();
  }

  // ─── Test Connection ───────────────────────────────────────────────────────

  static Future<void> testConnection() async {
    print('🔵 Testing Firebase connection...');
    try {
      final response = await http.get(Uri.parse('$dbUrl.json'));
      print('🔵 Status: ${response.statusCode}');
      if (response.statusCode == 200) {
        print('✅ Firebase connection successful!');
      } else {
        print('❌ Firebase connection failed: ${response.statusCode}');
      }
    } catch (e) {
      print('❌ Connection test error: $e');
    }
  }

  // ─── GPS Location ──────────────────────────────────────────────────────────

  static Future<Map<String, double>?> _getCurrentLocation() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return null;
      }
      if (permission == LocationPermission.deniedForever) return null;
      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));
      return {
        'latitude': position.latitude,
        'longitude': position.longitude,
      };
    } catch (e) {
      print('❌ Error getting location: $e');
      return null;
    }
  }

  // ─── Register ──────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> register({
    required String firstName,
    required String lastName,
    required String email,
    required String mobileNumber,
    required String password,
    required String barangay,
    required String zipCode,
    double? latitude,
    double? longitude,
    // True only when [barangay] came from a live, non-mocked GPS fix
    // confirmed inside Panabo City (see SignupScreen._isLocationVerified) —
    // false for a manually self-declared barangay (GPS failed, or the user
    // overrode a real detection), so the two are never indistinguishable
    // on the stored account.
    bool locationVerified = false,
  }) async {
    email = email.trim().toLowerCase();

    print('=================================================');
    print('🔵 REGISTRATION STARTED');
    print('🔵 Email: $email | Name: $firstName $lastName');
    print('=================================================');

    if (!RegExp(r'^[\w-\.]+@gmail\.com$').hasMatch(email)) {
      return {
        'success': false,
        'error': 'Please use a Gmail address (e.g., example@gmail.com)'
      };
    }

    try {
      final emailExists = await checkEmailExists(email);
      if (emailExists) {
        return {
          'success': false,
          'error':
              'This email is already registered. Please use a different email or log in.'
        };
      }

      double? finalLat = latitude;
      double? finalLng = longitude;
      if (finalLat == null || finalLng == null) {
        final loc = await _getCurrentLocation();
        if (loc != null) {
          finalLat = loc['latitude'];
          finalLng = loc['longitude'];
        }
      }

      final now = DateTime.now();
      final dateRegistered = _formatDate(now);

      final accountData = {
        'AccountName': '$firstName $lastName',
        'Email': email,
        'MobileNumber': mobileNumber,
        'Password': password,
        'Barangay': barangay,
        'ZipCode': zipCode,
        'DateRegistered': dateRegistered,
        'FamilyId': null,
        'FamilyCode': null,
        'FamilyName': null,
        'FamilyRole': null,
        'OnlineStatus': 'Offline',
        'LastSeen': dateRegistered,
        'LocationVerified': locationVerified,
        'Location': {
          'Latitude': finalLat,
          'Longitude': finalLng,
          'LastUpdated': dateRegistered,
        },
      };

      final response = await http.post(
        Uri.parse('${dbUrl}Accounts.json'),
        body: json.encode(accountData),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = json.decode(response.body);
        final newUserId = responseData['name'];
        print('✅✅✅ ACCOUNT CREATED! ID: $newUserId');

        // Best-effort: mirror into Firebase Auth so this account can use
        // real password-reset emails later. Never fails registration.
        await _mirrorToFirebaseAuth(
            userId: newUserId, email: email, password: password);

        return {
          'success': true,
          'message': 'Account created successfully!',
          'userId': newUserId,
        };
      } else {
        return {
          'success': false,
          'error':
              'Failed to create account. Server returned ${response.statusCode}'
        };
      }
    } catch (e) {
      print('❌ Registration error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ─── Register with Google ──────────────────────────────────────────────────
  // Same shape as register(), but the identity has already been verified by
  // Google/Firebase Auth: no Password is stored, GoogleUid is the lookup key
  // used by loginWithGoogle, and AuthProvider records how the account signs in.

  static Future<Map<String, dynamic>> registerWithGoogle({
    required String googleUid,
    required String firstName,
    required String lastName,
    required String email,
    required String mobileNumber,
    required String barangay,
    required String zipCode,
    String? photoUrl,
    double? latitude,
    double? longitude,
    // See register()'s locationVerified for what this records.
    bool locationVerified = false,
  }) async {
    email = email.trim().toLowerCase();

    print('=================================================');
    print('🔵 GOOGLE REGISTRATION STARTED');
    print('🔵 Email: $email | Name: $firstName $lastName | GoogleUid: $googleUid');
    print('=================================================');

    try {
      final emailExists = await checkEmailExists(email);
      if (emailExists) {
        return {
          'success': false,
          'error':
              'This email is already registered. Please use Login with Google instead.'
        };
      }

      double? finalLat = latitude;
      double? finalLng = longitude;
      if (finalLat == null || finalLng == null) {
        final loc = await _getCurrentLocation();
        if (loc != null) {
          finalLat = loc['latitude'];
          finalLng = loc['longitude'];
        }
      }

      final now = DateTime.now();
      final dateRegistered = _formatDate(now);

      final accountData = {
        'AccountName': '$firstName $lastName',
        'Email': email,
        'MobileNumber': mobileNumber,
        'Password': null,
        'GoogleUid': googleUid,
        'AuthProvider': 'google',
        'Barangay': barangay,
        'ZipCode': zipCode,
        'DateRegistered': dateRegistered,
        'FamilyId': null,
        'FamilyCode': null,
        'FamilyName': null,
        'FamilyRole': null,
        'PhotoUrl': photoUrl,
        'OnlineStatus': 'Offline',
        'LastSeen': dateRegistered,
        'LocationVerified': locationVerified,
        'Location': {
          'Latitude': finalLat,
          'Longitude': finalLng,
          'LastUpdated': dateRegistered,
        },
      };

      final response = await http.post(
        Uri.parse('${dbUrl}Accounts.json'),
        body: json.encode(accountData),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final responseData = json.decode(response.body);
        final newUserId = responseData['name'];
        print('✅✅✅ GOOGLE ACCOUNT CREATED! ID: $newUserId');
        return {
          'success': true,
          'message': 'Account created successfully!',
          'userId': newUserId,
          'userName': '$firstName $lastName',
        };
      } else {
        return {
          'success': false,
          'error':
              'Failed to create account. Server returned ${response.statusCode}'
        };
      }
    } catch (e) {
      print('❌ Google registration error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ─── Login with Google ─────────────────────────────────────────────────────
  // Looks up an existing account by the GoogleUid stamped on it during
  // registerWithGoogle. Returns the same result shape as login() so callers
  // can share the post-login session/navigation code.

  static Future<Map<String, dynamic>> loginWithGoogle({
    required String googleUid,
  }) async {
    print('=================================================');
    print('🔵 GOOGLE LOGIN STARTED - GoogleUid: $googleUid');
    print('=================================================');

    try {
      final response = await http
          .get(Uri.parse('${dbUrl}Accounts.json'))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return {'success': false, 'error': 'Server error: ${response.statusCode}'};
      }

      final Map<String, dynamic>? accounts = json.decode(response.body);
      if (accounts == null || accounts.isEmpty) {
        return {
          'success': false,
          'error': 'No account is linked to this Google account. Please sign up first.'
        };
      }

      String? matchedUserId;
      Map<String, dynamic>? matchedAccount;

      for (var entry in accounts.entries) {
        final account = entry.value as Map<String, dynamic>;
        if (account['GoogleUid']?.toString() == googleUid) {
          matchedUserId = entry.key;
          matchedAccount = account;
          break;
        }
      }

      if (matchedAccount == null) {
        return {
          'success': false,
          'error': 'No account is linked to this Google account. Please sign up first.'
        };
      }

      if (matchedUserId != null) {
        updateUserLocation(matchedUserId);
        setOnlineStatus(matchedUserId, 'Online');
      }

      print('✅✅✅ GOOGLE LOGIN SUCCESSFUL!');
      print('=================================================');

      final location = matchedAccount['Location'] as Map<String, dynamic>?;

      return {
        'success': true,
        'message': 'Login successful!',
        'userId': matchedUserId,
        'userName': matchedAccount['AccountName'] ?? 'User',
        'userEmail': matchedAccount['Email'] ?? '',
        'mobileNumber': matchedAccount['MobileNumber'] ?? '',
        'barangay': matchedAccount['Barangay'],
        'zipCode': matchedAccount['ZipCode'],
        'familyId': matchedAccount['FamilyId'],
        'familyCode': matchedAccount['FamilyCode'],
        'familyName': matchedAccount['FamilyName'],
        'familyRole': matchedAccount['FamilyRole'],
        'latitude': location?['Latitude'],
        'longitude': location?['Longitude'],
      };
    } catch (e) {
      print('❌ GOOGLE LOGIN EXCEPTION: $e');
      return {'success': false, 'error': 'An error occurred: $e'};
    }
  }

  // ─── Set Online Status ─────────────────────────────────────────────────────

  static Future<void> setOnlineStatus(String userId, String status) async {
    try {
      final lastSeen = _formatDate(DateTime.now());
      await http.patch(
        Uri.parse('${dbUrl}Accounts/$userId.json'),
        body: json.encode({
          'OnlineStatus': status,
          'LastSeen': lastSeen,
        }),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 10));
      print('✅ OnlineStatus → $status for $userId');
    } catch (e) {
      print('❌ setOnlineStatus error: $e');
    }
  }

  // ─── Update User Profile (name, role, photo) ──────────────────────────────

  static Future<Map<String, dynamic>> updateUserProfile({
    required String userId,
    required String newName,
    required String newRole,
    String? newPhotoUrl,
  }) async {
    try {
      final accountPayload = {
        'AccountName': newName,
        'FamilyRole': newRole,
        if (newPhotoUrl != null) 'PhotoUrl': newPhotoUrl,
      };
      final accountResponse = await http.patch(
        Uri.parse('$dbUrl/Accounts/$userId.json'),
        body: json.encode(accountPayload),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (accountResponse.statusCode < 200 ||
          accountResponse.statusCode >= 300) {
        return {
          'success': false,
          'error':
              'Failed to update account. Server error ${accountResponse.statusCode}'
        };
      }

      final familyCodeResp = await http
          .get(Uri.parse('$dbUrl/Accounts/$userId/FamilyCode.json'))
          .timeout(const Duration(seconds: 8));

      if (familyCodeResp.statusCode == 200) {
        final raw = familyCodeResp.body.trim();
        if (raw != 'null' && raw.isNotEmpty) {
          final familyCode = raw.replaceAll('"', '').trim();
          if (familyCode.isNotEmpty) {
            final memberPatch = await http.patch(
              Uri.parse('$dbUrl/Families/$familyCode/Members/$userId.json'),
              body: json.encode({'Name': newName}),
              headers: {'Content-Type': 'application/json'},
            ).timeout(const Duration(seconds: 10));

            if (memberPatch.statusCode >= 200 && memberPatch.statusCode < 300) {
              print('✅ Member name updated in family node for $userId');
            } else {
              print(
                  '⚠️ Could not update member name in family node: ${memberPatch.statusCode}');
            }
          }
        }
      }

      print('✅ Profile fully updated for $userId: $newName, $newRole');
      return {'success': true};
    } catch (e) {
      print('❌ updateUserProfile error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ─── Change Password ──────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> changePassword({
    required String userId,
    required String currentPassword,
    required String newPassword,
  }) async {
    try {
      // 1. First, verify the current password by fetching the user's account
      final response = await http
          .get(Uri.parse('$dbUrl/Accounts/$userId.json'))
          .timeout(const Duration(seconds: 15));

      if (response.statusCode != 200) {
        return {
          'success': false,
          'error': 'Failed to fetch user account. Please try again.',
        };
      }

      final accountData = json.decode(response.body);
      if (accountData == null) {
        return {
          'success': false,
          'error': 'User account not found.',
        };
      }

      // 2. Verify the current password matches
      final storedPassword = accountData['Password']?.toString() ?? '';
      if (storedPassword != currentPassword) {
        return {
          'success': false,
          'error': 'Current password is incorrect.',
        };
      }

      // 3. Update the password
      final updateResponse = await http.patch(
        Uri.parse('$dbUrl/Accounts/$userId.json'),
        body: json.encode({'Password': newPassword}),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 15));

      if (updateResponse.statusCode >= 200 && updateResponse.statusCode < 300) {
        print('✅ Password changed successfully for user: $userId');
        return {
          'success': true,
          'message': 'Password changed successfully!',
        };
      } else {
        return {
          'success': false,
          'error':
              'Failed to update password. Server error ${updateResponse.statusCode}',
        };
      }
    } catch (e) {
      print('❌ changePassword error: $e');
      return {
        'success': false,
        'error': 'An error occurred: $e',
      };
    }
  }

  // ─── Create Family ─────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> createFamily({
    required String userId,
    required String userName,
    required String familyName,
  }) async {
    print('=================================================');
    print('🔵 CREATE FAMILY STARTED');
    print('🔵 UserId: $userId | FamilyName: $familyName');
    print('=================================================');

    try {
      String familyCode = _generateFamilyCode();
      bool codeExists = await _familyCodeExists(familyCode);
      int attempts = 0;
      while (codeExists && attempts < 10) {
        familyCode = _generateFamilyCode();
        codeExists = await _familyCodeExists(familyCode);
        attempts++;
      }
      if (codeExists) {
        return {
          'success': false,
          'error': 'Could not generate a unique family code. Please try again.'
        };
      }

      final now = DateTime.now();
      final createdAt = _formatDate(now);

      final familyData = {
        'FamilyName': familyName,
        'FamilyCode': familyCode,
        'CreatedBy': userId,
        'CreatedByName': userName,
        'CreatedAt': createdAt,
        'Members': {
          userId: {
            'UserId': userId,
            'Name': userName,
            'Role': 'Admin',
            'JoinedAt': createdAt,
          }
        },
      };

      final familyResponse = await http.put(
        Uri.parse('${dbUrl}Families/$familyCode.json'),
        body: json.encode(familyData),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (familyResponse.statusCode >= 200 && familyResponse.statusCode < 300) {
        print('✅ Family saved under /Families/$familyCode');

        await _updateAccountFamilyFields(
          userId: userId,
          familyId: familyCode,
          familyCode: familyCode,
          familyName: familyName,
          familyRole: 'Admin',
        );

        print('✅ Creator account updated with family info');
        print('=================================================');

        return {
          'success': true,
          'familyCode': familyCode,
          'familyId': familyCode,
          'familyName': familyName,
          'message': 'Family "$familyName" created successfully!',
        };
      } else {
        return {
          'success': false,
          'error':
              'Failed to create family. Server error ${familyResponse.statusCode}'
        };
      }
    } catch (e) {
      print('❌ Create family error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ─── Join Family ───────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> joinFamily({
    required String userId,
    required String userName,
    required String familyCode,
    required String role,
  }) async {
    print('=================================================');
    print('🔵 JOIN FAMILY STARTED');
    print('🔵 UserId: $userId | FamilyCode: $familyCode | Role: $role');
    print('=================================================');

    try {
      final family = await getFamilyByCode(familyCode);
      if (family == null) {
        return {
          'success': false,
          'error': 'Invalid family code. No family found with code: $familyCode'
        };
      }

      final familyName = family['FamilyName'] ?? 'Family';

      final alreadyMember = await _isAlreadyMember(familyCode, userId);
      if (alreadyMember) {
        return {
          'success': false,
          'error': 'You are already a member of this family.'
        };
      }

      final now = DateTime.now();
      final joinedAt = _formatDate(now);

      final memberData = {
        'UserId': userId,
        'Name': userName,
        'Role': role,
        'JoinedAt': joinedAt,
      };

      final memberResponse = await http.put(
        Uri.parse('${dbUrl}Families/$familyCode/Members/$userId.json'),
        body: json.encode(memberData),
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 30));

      if (memberResponse.statusCode >= 200 && memberResponse.statusCode < 300) {
        print('✅ Member added under /Families/$familyCode/Members/$userId');

        await _updateAccountFamilyFields(
          userId: userId,
          familyId: familyCode,
          familyCode: familyCode,
          familyName: familyName,
          familyRole: role,
        );

        print('✅ Member account updated with family info');
        print('=================================================');

        return {
          'success': true,
          'familyCode': familyCode,
          'familyId': familyCode,
          'familyName': familyName,
          'message': 'Successfully joined "$familyName"!',
        };
      } else {
        return {
          'success': false,
          'error':
              'Failed to join family. Server error ${memberResponse.statusCode}'
        };
      }
    } catch (e) {
      print('❌ Join family error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ─── Get Family by Code ────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getFamilyByCode(
      String familyCode) async {
    try {
      final response = await http
          .get(Uri.parse('${dbUrl}Families/$familyCode.json'))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null) return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      print('❌ Error getting family by code: $e');
      return null;
    }
  }

  // ─── Get Family Members ────────────────────────────────────────────────────

  static Future<List<Map<String, dynamic>>> getFamilyMembers(
      String familyCode) async {
    try {
      // Routed through CachedHttpGet (rather than a bare http.get) so the
      // member list — which changes rarely — is served from disk on a
      // weak/offline connection instead of blocking or failing outright.
      final response = await CachedHttpGet.get(
        Uri.parse('${dbUrl}Families/$familyCode/Members.json'),
        ttl: const Duration(seconds: 20),
        timeout: const Duration(seconds: 30),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data is Map) {
          return data.values.map((m) => Map<String, dynamic>.from(m)).toList();
        }
      }
      return [];
    } catch (e) {
      print('❌ Error getting family members: $e');
      return [];
    }
  }

  // ─── Get Family Members With Locations ────────────────────────────────────

  // [throwOnError] defaults to false to keep existing callers' behavior. Set
  // it true when the caller needs to tell "fetch genuinely failed, don't
  // touch what's already on screen" apart from "fetched fine, family really
  // has no members" — without it, a transient network failure looks
  // identical to an empty result and callers that just overwrite their
  // state with whatever comes back end up blanking out already-known
  // photos/status/location on a single dropped poll.
  static Future<List<Map<String, dynamic>>> getFamilyMembersWithLocations(
      String familyCode, {bool throwOnError = false}) async {
    if (familyCode.trim().isEmpty) {
      print('⚠️ getFamilyMembersWithLocations: empty familyCode');
      return [];
    }

    try {
      // Same reasoning as getFamilyMembers above — this runs on the
      // dashboard/map's 10s poll, so serving the last-known member list
      // from disk on a weak connection (rather than every poll blocking on
      // a slow request for data that rarely changes) matters here most.
      final membersResp = await CachedHttpGet.get(
        Uri.parse('${dbUrl}Families/$familyCode/Members.json'),
        ttl: const Duration(seconds: 20),
        timeout: const Duration(seconds: 15),
      );

      print(
          '📡 Members response [${membersResp.statusCode}] for code: $familyCode');

      if (membersResp.statusCode != 200) {
        print('❌ Non-200 from Members node: ${membersResp.statusCode}');
        if (throwOnError) throw Exception('HTTP ${membersResp.statusCode}');
        return [];
      }

      final membersData = json.decode(membersResp.body);

      if (membersData == null) {
        print('⚠️ No members found for family code: $familyCode');
        return [];
      }

      if (membersData is! Map) {
        print('❌ Unexpected members data type: ${membersData.runtimeType}');
        if (throwOnError) {
          throw Exception('Unexpected members data type');
        }
        return [];
      }

      final List<Map<String, dynamic>> result = [];

      final futures = (membersData).entries.map((entry) async {
        final memberId = entry.key.toString();
        final memberInfo = Map<String, dynamic>.from(entry.value as Map);

        final record = <String, dynamic>{
          'userId': memberId,
          'name': memberInfo['Name']?.toString() ?? 'Unknown',
          'role': memberInfo['Role']?.toString() ?? 'Member',
          'joinedAt': memberInfo['JoinedAt']?.toString() ?? '',
          'latitude': null,
          'longitude': null,
          'lastUpdated': null,
          'onlineStatus': 'Offline',
          'lastSeen': null,
          'photoUrl': '',
        };

        try {
          // This used to be one GET of the whole Accounts/$memberId node,
          // which re-downloaded that member's full base64-encoded
          // PhotoUrl on every single poll (this runs on a 10s timer per
          // dashboard/map screen) even though photos change essentially
          // never. OnlineStatus/LastSeen/Location genuinely need to be
          // fresh every poll and are each a few bytes, so they're fetched
          // directly rather than through the whole node; PhotoUrl is
          // fetched through CachedHttpGet with a long TTL so the (often
          // tens-of-KB) photo bytes actually cross the network only once
          // every few minutes per member instead of every 10 seconds.
          final results = await Future.wait([
            CachedHttpGet.get(
              Uri.parse('${dbUrl}Accounts/$memberId/OnlineStatus.json'),
              ttl: const Duration(seconds: 4),
              timeout: const Duration(seconds: 10),
            ),
            CachedHttpGet.get(
              Uri.parse('${dbUrl}Accounts/$memberId/LastSeen.json'),
              ttl: const Duration(seconds: 4),
              timeout: const Duration(seconds: 10),
            ),
            CachedHttpGet.get(
              Uri.parse('${dbUrl}Accounts/$memberId/Location.json'),
              ttl: const Duration(seconds: 4),
              timeout: const Duration(seconds: 10),
            ),
            CachedHttpGet.get(
              Uri.parse('${dbUrl}Accounts/$memberId/PhotoUrl.json'),
              ttl: const Duration(minutes: 5),
              timeout: const Duration(seconds: 10),
            ),
          ]);

          final statusResp = results[0];
          final lastSeenResp = results[1];
          final locationResp = results[2];
          final photoResp = results[3];

          String? decodeJsonString(http.Response resp) {
            final body = resp.body.trim();
            if (resp.statusCode != 200 || body == 'null' || body.isEmpty) {
              return null;
            }
            final decoded = json.decode(body);
            return decoded?.toString();
          }

          final rawStatus = decodeJsonString(statusResp) ?? 'Offline';
          final lastSeenStr = decodeJsonString(lastSeenResp);
          record['onlineStatus'] = _resolveOnlineStatus(rawStatus, lastSeenStr);
          record['lastSeen'] = lastSeenStr;
          record['photoUrl'] = decodeJsonString(photoResp) ?? '';

          final locationBody = locationResp.body.trim();
          if (locationResp.statusCode == 200 &&
              locationBody != 'null' &&
              locationBody.isNotEmpty) {
            final locData = json.decode(locationBody) as Map<String, dynamic>;
            final lat = locData['Latitude'] ?? locData['latitude'];
            final lng = locData['Longitude'] ?? locData['longitude'];
            final updated =
                (locData['LastUpdated'] ?? locData['lastUpdated'])?.toString();

            if (lat != null && lng != null) {
              record['latitude'] = (lat as num).toDouble();
              record['longitude'] = (lng as num).toDouble();
              record['lastUpdated'] = updated;
            } else {
              print('⚠️ Null lat/lng for member $memberId');
            }
          } else {
            print('⚠️ No Location node for member $memberId');
          }
        } catch (e) {
          print('⚠️ Could not fetch account for $memberId: $e');
        }

        return record;
      });

      result.addAll(await Future.wait(futures));

      final locatedCount = result.where((m) => m['latitude'] != null).length;
      final onlineCount =
          result.where((m) => m['onlineStatus'] == 'Online').length;
      print(
          '✅ ${result.length} members | $locatedCount located | $onlineCount online');

      return result;
    } catch (e) {
      print('❌ getFamilyMembersWithLocations error: $e');
      if (throwOnError) rethrow;
      return [];
    }
  }

  // ─── Leave Family ──────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> leaveFamily({
    required String userId,
    required String familyCode,
  }) async {
    print('🔵 LEAVE FAMILY: userId=$userId familyCode=$familyCode');
    try {
      final removeResponse = await http
          .delete(
              Uri.parse('${dbUrl}Families/$familyCode/Members/$userId.json'))
          .timeout(const Duration(seconds: 30));

      if (removeResponse.statusCode >= 200 && removeResponse.statusCode < 300) {
        await _clearAccountFamilyFields(userId);
        print('✅ User left family successfully');
        return {'success': true, 'message': 'You have left the family.'};
      } else {
        return {
          'success': false,
          'error':
              'Failed to leave family. Server error ${removeResponse.statusCode}'
        };
      }
    } catch (e) {
      print('❌ Leave family error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ─── Delete Family (Admin only) ────────────────────────────────────────────

  static Future<Map<String, dynamic>> deleteFamily({
    required String userId,
    required String familyCode,
  }) async {
    print('🔵 DELETE FAMILY: familyCode=$familyCode');
    try {
      final members = await getFamilyMembers(familyCode);

      for (final member in members) {
        final memberId = member['UserId']?.toString();
        if (memberId != null) await _clearAccountFamilyFields(memberId);
      }

      final deleteResponse = await http
          .delete(Uri.parse('${dbUrl}Families/$familyCode.json'))
          .timeout(const Duration(seconds: 30));

      if (deleteResponse.statusCode >= 200 && deleteResponse.statusCode < 300) {
        print('✅ Family deleted successfully');
        return {'success': true, 'message': 'Family deleted successfully.'};
      } else {
        return {
          'success': false,
          'error':
              'Failed to delete family. Server error ${deleteResponse.statusCode}'
        };
      }
    } catch (e) {
      print('❌ Delete family error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ─── Transfer Admin ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> transferAdmin({
    required String familyCode,
    required String currentAdminId,
    required String newAdminId,
    required String newAdminName,
  }) async {
    print('🔵 TRANSFER ADMIN: $currentAdminId → $newAdminId');
    try {
      await http.patch(
        Uri.parse('${dbUrl}Families/$familyCode.json'),
        body: json
            .encode({'CreatedBy': newAdminId, 'CreatedByName': newAdminName}),
        headers: {'Content-Type': 'application/json'},
      );

      await http.patch(
        Uri.parse('${dbUrl}Families/$familyCode/Members/$currentAdminId.json'),
        body: json.encode({'Role': 'Member'}),
        headers: {'Content-Type': 'application/json'},
      );
      await _patchAccountField(currentAdminId, 'FamilyRole', 'Member');

      await http.patch(
        Uri.parse('${dbUrl}Families/$familyCode/Members/$newAdminId.json'),
        body: json.encode({'Role': 'Admin'}),
        headers: {'Content-Type': 'application/json'},
      );
      await _patchAccountField(newAdminId, 'FamilyRole', 'Admin');

      print('✅ Admin transferred to $newAdminName');
      return {'success': true, 'message': 'Admin rights transferred.'};
    } catch (e) {
      print('❌ Transfer admin error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ─── Update Member Role ─────────────────────────────────────────────────────
  // Patches both places a member's role is stored — Families/{code}/Members
  // (what the member-list screens actually read) and Accounts/{id}.FamilyRole
  // (kept in sync by transferAdmin above) — so the change is visible
  // immediately in the family list and stays consistent everywhere else.
  static Future<Map<String, dynamic>> updateMemberRole({
    required String familyCode,
    required String userId,
    required String role,
  }) async {
    print('🔵 UPDATE MEMBER ROLE: $userId → $role');
    try {
      await http.patch(
        Uri.parse('${dbUrl}Families/$familyCode/Members/$userId.json'),
        body: json.encode({'Role': role}),
        headers: {'Content-Type': 'application/json'},
      );
      await _patchAccountField(userId, 'FamilyRole', role);
      print('✅ Role updated to $role');
      return {'success': true, 'message': 'Role updated to $role.'};
    } catch (e) {
      print('❌ Update member role error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ─── Login ─────────────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>> login({
    required String emailOrMobile,
    required String password,
  }) async {
    final input = emailOrMobile.trim().toLowerCase();
    print('=================================================');
    print('🔵 LOGIN STARTED - Input: $emailOrMobile');
    print('=================================================');

    try {
      final response = await http
          .get(Uri.parse('${dbUrl}Accounts.json'))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        final Map<String, dynamic>? accounts = json.decode(response.body);

        if (accounts == null || accounts.isEmpty) {
          return {
            'success': false,
            'error': 'No accounts found. Please sign up first.'
          };
        }

        String? matchedUserId;
        Map<String, dynamic>? matchedAccount;

        for (var entry in accounts.entries) {
          final account = entry.value as Map<String, dynamic>;
          final accountEmail = account['Email']?.toString().toLowerCase() ?? '';
          final accountMobile = account['MobileNumber']?.toString() ?? '';
          if (accountEmail == input || accountMobile == emailOrMobile.trim()) {
            matchedUserId = entry.key;
            matchedAccount = account;
            break;
          }
        }

        if (matchedAccount == null) {
          return {
            'success': false,
            'error':
                'Account not found. Please check your credentials or sign up.'
          };
        }

        final accountEmail = matchedAccount['Email']?.toString() ?? '';
        // Either a mirrored password account (AuthUid) or a Google account
        // (GoogleUid) means Firebase Auth already has a user for this email
        // — and a completed password reset can add an email/password
        // credential to a Google-only account, so both count here.
        final authUid = matchedAccount['AuthUid']?.toString() ??
            matchedAccount['GoogleUid']?.toString();

        if (authUid != null && authUid.isNotEmpty) {
          // Migrated/Google account: Firebase Auth is the source of truth
          // for the password, since that's what a completed reset updates.
          try {
            await FirebaseAuth.instance.signInWithEmailAndPassword(
              email: accountEmail,
              password: password,
            );
          } on FirebaseAuthException catch (e) {
            if (e.code == 'wrong-password' ||
                e.code == 'invalid-credential' ||
                e.code == 'invalid-email') {
              return {
                'success': false,
                'error': 'Incorrect password. Please try again.'
              };
            }
            // Unexpected Firebase Auth failure (e.g. network) — fall back
            // to the legacy plaintext check rather than blocking login.
            if (matchedAccount['Password']?.toString() != password) {
              return {
                'success': false,
                'error': 'Incorrect password. Please try again.'
              };
            }
          }
        } else {
          if (matchedAccount['Password']?.toString() != password) {
            return {
              'success': false,
              'error': 'Incorrect password. Please try again.'
            };
          }
          // Legacy account verified via plaintext — opportunistically mirror
          // it into Firebase Auth now, so Forgot Password works for it too.
          if (matchedUserId != null && accountEmail.isNotEmpty) {
            unawaited(_mirrorToFirebaseAuth(
              userId: matchedUserId,
              email: accountEmail,
              password: password,
            ));
          }
        }

        if (matchedUserId != null) {
          updateUserLocation(matchedUserId);
          setOnlineStatus(matchedUserId, 'Online');
        }

        print('✅✅✅ LOGIN SUCCESSFUL!');
        print('=================================================');

        final location = matchedAccount['Location'] as Map<String, dynamic>?;

        return {
          'success': true,
          'message': 'Login successful!',
          'userId': matchedUserId,
          'userName': matchedAccount['AccountName'] ?? 'User',
          'userEmail': matchedAccount['Email'] ?? '',
          'mobileNumber': matchedAccount['MobileNumber'] ?? '',
          'barangay': matchedAccount['Barangay'],
          'zipCode': matchedAccount['ZipCode'],
          'familyId': matchedAccount['FamilyId'],
          'familyCode': matchedAccount['FamilyCode'],
          'familyName': matchedAccount['FamilyName'],
          'familyRole': matchedAccount['FamilyRole'],
          'latitude': location?['Latitude'],
          'longitude': location?['Longitude'],
        };
      } else {
        return {
          'success': false,
          'error': 'Server error: ${response.statusCode}'
        };
      }
    } catch (e) {
      print('❌ LOGIN EXCEPTION: $e');
      return {'success': false, 'error': 'An error occurred: $e'};
    }
  }

  // ─── Forgot Password ────────────────────────────────────────────────────────
  // Sends a real Firebase Auth password-reset email. Legacy accounts (no
  // AuthUid yet, i.e. never mirrored) are migrated on the spot using their
  // known RTDB plaintext password, so this works even for accounts that
  // haven't logged in since the Firebase Auth mirror was introduced.
  static Future<Map<String, dynamic>> requestPasswordReset({
    required String email,
  }) async {
    final normalizedEmail = email.trim().toLowerCase();
    print('🔵 PASSWORD RESET REQUESTED for $normalizedEmail');

    try {
      final response = await http
          .get(Uri.parse('${dbUrl}Accounts.json'))
          .timeout(const Duration(seconds: 30));

      if (response.statusCode != 200) {
        return {'success': false, 'error': 'Server error: ${response.statusCode}'};
      }

      final Map<String, dynamic>? accounts = json.decode(response.body);
      String? matchedUserId;
      Map<String, dynamic>? matchedAccount;

      if (accounts != null) {
        for (var entry in accounts.entries) {
          final account = entry.value as Map<String, dynamic>;
          if ((account['Email']?.toString().toLowerCase() ?? '') ==
              normalizedEmail) {
            matchedUserId = entry.key;
            matchedAccount = account;
            break;
          }
        }
      }

      if (matchedAccount == null) {
        return {
          'success': false,
          'error': 'No account found with that email address.'
        };
      }

      final storedPassword = matchedAccount['Password']?.toString();
      final authUid = matchedAccount['AuthUid']?.toString();
      final googleUid = matchedAccount['GoogleUid']?.toString();
      final hasRealPassword = storedPassword != null && storedPassword.isNotEmpty;

      if ((authUid == null || authUid.isEmpty) && hasRealPassword) {
        // Never mirrored before — migrate now using the known password so
        // Firebase Auth actually has an account to send the reset email to.
        await _mirrorToFirebaseAuth(
          userId: matchedUserId!,
          email: normalizedEmail,
          password: storedPassword,
        );
      } else if ((authUid == null || authUid.isEmpty) && !hasRealPassword) {
        // Google-only account: Firebase Auth has no password credential to
        // reset yet (sendPasswordResetEmail silently does nothing for a
        // federated-only account — there's nothing to reset). They need to
        // link a password credential in-app instead, while authenticated.
        if (googleUid != null && googleUid.isNotEmpty) {
          return {
            'success': false,
            'error':
                "This account doesn't have a password yet. Log in with Google, "
                    "then go to Settings > Set Account Password to add one."
          };
        }
        return {
          'success': false,
          'error': 'This account has no password set yet. Please sign up first.'
        };
      }

      await FirebaseAuth.instance.sendPasswordResetEmail(email: normalizedEmail);
      print('✅ Password reset email sent to $normalizedEmail');
      return {
        'success': true,
        'message': 'Password reset email sent. Please check your inbox.'
      };
    } on FirebaseAuthException catch (e) {
      print('❌ Password reset FirebaseAuthException: ${e.code}');
      if (e.code == 'user-not-found') {
        return {
          'success': false,
          'error': 'No account found with that email address.'
        };
      }
      return {'success': false, 'error': e.message ?? 'Error: ${e.code}'};
    } catch (e) {
      print('❌ Password reset error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ─── Set Account Password (link to an existing Google-only account) ───────
  // A Google-signed-up account has a Firebase Auth user with no password
  // credential — there is nothing for sendPasswordResetEmail to reset. This
  // links an email/password credential onto the CURRENTLY signed-in Firebase
  // Auth user instead, which is the supported way to add a password to a
  // federated-only account. Caller must ensure FirebaseAuth.instance.currentUser
  // is that account (e.g. by having just completed Login/Sign Up with Google).
  static Future<Map<String, dynamic>> linkPasswordToCurrentUser({
    required String newPassword,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) {
      return {
        'success': false,
        'error': 'Please log in with Google first, then try again.'
      };
    }

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: newPassword,
      );
      await user.linkWithCredential(credential);

      // Find the RTDB record by GoogleUid and stamp AuthUid so login() and
      // requestPasswordReset recognize this account now has a real password.
      final response = await http
          .get(Uri.parse('${dbUrl}Accounts.json'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final Map<String, dynamic>? accounts = json.decode(response.body);
        if (accounts != null) {
          for (var entry in accounts.entries) {
            final account = entry.value as Map<String, dynamic>;
            if (account['GoogleUid']?.toString() == user.uid) {
              await _patchAccountField(entry.key, 'AuthUid', user.uid);
              break;
            }
          }
        }
      }

      print('✅ Password linked for ${user.email}');
      return {'success': true, 'message': 'Password set successfully!'};
    } on FirebaseAuthException catch (e) {
      print('❌ linkPasswordToCurrentUser FirebaseAuthException: ${e.code}');
      if (e.code == 'provider-already-linked') {
        return {
          'success': false,
          'error': 'This account already has a password set.'
        };
      }
      if (e.code == 'weak-password') {
        return {'success': false, 'error': 'Please choose a stronger password.'};
      }
      return {'success': false, 'error': e.message ?? 'Error: ${e.code}'};
    } catch (e) {
      print('❌ linkPasswordToCurrentUser error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // Looks up whether an account has a real password on file vs. is
  // Google-only, so the UI can decide whether to offer "Set Account Password".
  static Future<Map<String, dynamic>?> getAccountAuthInfo(String userId) async {
    try {
      final response = await http
          .get(Uri.parse('${dbUrl}Accounts/$userId.json'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null) {
          final storedPassword = data['Password']?.toString();
          final authUid = data['AuthUid']?.toString() ?? '';
          return {
            'email': data['Email']?.toString() ?? '',
            // AuthUid means a real Firebase Auth password credential exists
            // (either mirrored from a legacy plaintext password, or linked
            // via Set Account Password) — that supersedes the raw RTDB field.
            'hasPassword': authUid.isNotEmpty ||
                (storedPassword != null && storedPassword.isNotEmpty),
            'hasGoogle': (data['GoogleUid']?.toString() ?? '').isNotEmpty,
          };
        }
      }
      return null;
    } catch (e) {
      print('❌ getAccountAuthInfo error: $e');
      return null;
    }
  }

  // ─── Update Location ───────────────────────────────────────────────────────

  static Future<void> updateUserLocation(String userId) async {
    try {
      final loc = await _getCurrentLocation();
      if (loc == null) return;
      final lastUpdated = _formatDate(DateTime.now());
      await http.patch(
        Uri.parse('${dbUrl}Accounts/$userId/Location.json'),
        body: json.encode({
          'Latitude': loc['latitude'],
          'Longitude': loc['longitude'],
          'LastUpdated': lastUpdated,
        }),
        headers: {'Content-Type': 'application/json'},
      );
      print('✅ Location updated for user: $userId');
    } catch (e) {
      print('❌ Error updating location: $e');
    }
  }

  // ─── Location Tracking Stream ──────────────────────────────────────────────

  static StreamSubscription<Position>? _locationSubscription;

  static Future<void> startLocationTracking(String userId) async {
    await stopLocationTracking();

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) return;
      }
      if (permission == LocationPermission.deniedForever) return;

      print('🟢 Starting location tracking for $userId');

      _locationSubscription = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((Position position) async {
        final lastUpdated = _formatDate(DateTime.now());
        try {
          await http.patch(
            Uri.parse('${dbUrl}Accounts/$userId/Location.json'),
            body: json.encode({
              'Latitude': position.latitude,
              'Longitude': position.longitude,
              'LastUpdated': lastUpdated,
            }),
            headers: {'Content-Type': 'application/json'},
          );
          print(
              '📍 Location pushed: ${position.latitude}, ${position.longitude}');
        } catch (e) {
          print('❌ Failed to push location: $e');
        }
      });
    } catch (e) {
      print('❌ startLocationTracking error: $e');
    }
  }

  static Future<void> stopLocationTracking() async {
    await _locationSubscription?.cancel();
    _locationSubscription = null;
    print('🔴 Location tracking stopped');
  }

  // ─── Check Email Exists ────────────────────────────────────────────────────

  static Future<bool> checkEmailExists(String email) async {
    email = email.toLowerCase();
    try {
      final response = await http
          .get(Uri.parse('${dbUrl}Accounts.json'))
          .timeout(const Duration(seconds: 30));
      if (response.statusCode == 200) {
        final Map<String, dynamic>? accounts = json.decode(response.body);
        if (accounts != null) {
          return accounts.values.any((account) =>
              (account?['Email']?.toString().toLowerCase() ?? '') == email);
        }
      }
      return false;
    } catch (e) {
      throw Exception('Failed to check email: $e');
    }
  }

  // ─── Validate Email for Signup ─────────────────────────────────────────────

  static Future<Map<String, dynamic>> validateEmailForSignup(
      String email) async {
    email = email.trim().toLowerCase();
    if (!RegExp(r'^[\w-\.]+@gmail\.com$').hasMatch(email)) {
      return {
        'isValid': false,
        'message': 'Please enter a valid Gmail address.'
      };
    }
    try {
      final exists = await checkEmailExists(email);
      if (exists) {
        return {
          'isValid': false,
          'message': 'This email is already registered.'
        };
      }
      return {'isValid': true, 'message': 'Email is available.'};
    } catch (e) {
      return {'isValid': false, 'message': 'Error: $e'};
    }
  }

  // ─── Get User By ID ────────────────────────────────────────────────────────

  static Future<Map<String, dynamic>?> getUserById(String userId) async {
    try {
      final response =
          await http.get(Uri.parse('${dbUrl}Accounts/$userId.json'));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null) {
          final location = data['Location'] as Map<String, dynamic>?;
          return {
            'userId': userId,
            'userName': data['AccountName'],
            'userEmail': data['Email'],
            'mobileNumber': data['MobileNumber'],
            'barangay': data['Barangay'],
            'zipCode': data['ZipCode'],
            'familyId': data['FamilyId'] ?? data['familyId'],
            'familyCode': data['FamilyCode'] ?? data['familyCode'],
            'familyName': data['FamilyName'] ?? data['familyName'],
            'familyRole': data['FamilyRole'] ?? data['familyRole'],
            'photoUrl': data['PhotoUrl'] ?? data['photoUrl'] ?? '',
            'onlineStatus': data['OnlineStatus'] ?? 'Offline',
            'lastSeen': data['LastSeen'],
            'latitude': location?['Latitude'] ?? location?['latitude'],
            'longitude': location?['Longitude'] ?? location?['longitude'],
            'locationLastUpdated':
                location?['LastUpdated'] ?? location?['lastUpdated'],
          };
        }
      }
      return null;
    } catch (e) {
      print('❌ Error getting user: $e');
      return null;
    }
  }

  // ─── Personal Emergency Contacts ───────────────────────────────────────────
  // Stored per-user at Accounts/{userId}/PersonalContacts/{contactId} so they
  // persist across app restarts and logout/login, instead of living only in
  // the Alert Contacts screen's local widget state.

  static Future<List<Map<String, dynamic>>> getPersonalContacts(
      String userId) async {
    try {
      final response = await http
          .get(Uri.parse('${dbUrl}Accounts/$userId/PersonalContacts.json'))
          .timeout(const Duration(seconds: 15));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data != null && data is Map) {
          return data.entries.map((e) {
            final contact = Map<String, dynamic>.from(e.value as Map);
            contact['id'] = e.key;
            return contact;
          }).toList();
        }
      }
      return [];
    } catch (e) {
      print('❌ getPersonalContacts error: $e');
      return [];
    }
  }

  static Future<Map<String, dynamic>> addPersonalContact({
    required String userId,
    required String name,
    required String phone,
  }) async {
    try {
      final response = await http
          .post(
            Uri.parse('${dbUrl}Accounts/$userId/PersonalContacts.json'),
            body: json.encode({'Name': name, 'Phone': phone}),
            headers: {'Content-Type': 'application/json'},
          )
          .timeout(const Duration(seconds: 15));

      if (response.statusCode >= 200 && response.statusCode < 300) {
        final data = json.decode(response.body);
        return {'success': true, 'id': data['name']?.toString() ?? ''};
      }
      return {
        'success': false,
        'error': 'Failed to save contact. Server error ${response.statusCode}'
      };
    } catch (e) {
      print('❌ addPersonalContact error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  static Future<bool> removePersonalContact({
    required String userId,
    required String contactId,
  }) async {
    try {
      final response = await http
          .delete(Uri.parse(
              '${dbUrl}Accounts/$userId/PersonalContacts/$contactId.json'))
          .timeout(const Duration(seconds: 15));
      return response.statusCode >= 200 && response.statusCode < 300;
    } catch (e) {
      print('❌ removePersonalContact error: $e');
      return false;
    }
  }

  // ─── Private Helpers ───────────────────────────────────────────────────────

  static Future<void> _updateAccountFamilyFields({
    required String userId,
    required String familyId,
    required String familyCode,
    required String familyName,
    required String familyRole,
  }) async {
    final payload = json.encode({
      'FamilyId': familyId,
      'FamilyCode': familyCode,
      'FamilyName': familyName,
      'FamilyRole': familyRole,
    });
    print('📝 Patching /Accounts/$userId with FamilyCode: $familyCode');
    for (int attempt = 1; attempt <= 3; attempt++) {
      try {
        final response = await http.patch(
          Uri.parse('${dbUrl}Accounts/$userId.json'),
          body: payload,
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 15));
        print('📝 PATCH attempt $attempt status: ${response.statusCode}');
        if (response.statusCode >= 200 && response.statusCode < 300) {
          await Future.delayed(const Duration(milliseconds: 400));
          final verify = await http
              .get(Uri.parse('${dbUrl}Accounts/$userId/FamilyCode.json'));
          final written = verify.body.replaceAll('"', '').trim();
          print('🔍 DB verify FamilyCode: "$written"');
          if (written.isNotEmpty && written != 'null') {
            print('✅ FamilyCode confirmed written: $written');
            return;
          }
          print('⚠️ FamilyCode not confirmed, retrying ($attempt/3)...');
        }
      } catch (e) {
        print('❌ PATCH attempt $attempt error: $e');
      }
      if (attempt < 3) {
        await Future.delayed(const Duration(milliseconds: 600));
      }
    }
    throw Exception(
        'Could not save family info after 3 attempts. Check your connection.');
  }

  static Future<void> _clearAccountFamilyFields(String userId) async {
    await http.patch(
      Uri.parse('${dbUrl}Accounts/$userId.json'),
      body: json.encode({
        'FamilyId': null,
        'FamilyCode': null,
        'FamilyName': null,
        'FamilyRole': null,
      }),
      headers: {'Content-Type': 'application/json'},
    );
  }

  // Creates a Firebase Auth user mirroring an email/password RTDB account
  // and stamps its uid onto the record as AuthUid. This is what lets
  // requestPasswordReset later use Firebase's real password-reset email —
  // RTDB has no email-sending capability of its own. Best-effort: swallows
  // failures (e.g. the mirror already exists) so it never blocks the
  // caller's real operation (registration or login).
  static Future<void> _mirrorToFirebaseAuth({
    required String userId,
    required String email,
    required String password,
  }) async {
    try {
      final credential =
          await FirebaseAuth.instance.createUserWithEmailAndPassword(
        email: email,
        password: password,
      );
      final authUid = credential.user?.uid;
      if (authUid != null) {
        await _patchAccountField(userId, 'AuthUid', authUid);
        print('✅ Mirrored $email into Firebase Auth: $authUid');
      }
    } on FirebaseAuthException catch (e) {
      // Most common case: this email already has a Firebase Auth user from
      // a previous mirror attempt. Nothing to do.
      print('ℹ️ Firebase Auth mirror skipped for $email: ${e.code}');
    } catch (e) {
      print('⚠️ Firebase Auth mirror error for $email: $e');
    }
  }

  static Future<void> _patchAccountField(
      String userId, String field, dynamic value) async {
    await http.patch(
      Uri.parse('${dbUrl}Accounts/$userId.json'),
      body: json.encode({field: value}),
      headers: {'Content-Type': 'application/json'},
    );
  }

  static Future<bool> _familyCodeExists(String code) async {
    try {
      final response = await http
          .get(Uri.parse('${dbUrl}Families/$code.json'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data != null;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _isAlreadyMember(String familyCode, String userId) async {
    try {
      final response = await http
          .get(Uri.parse('${dbUrl}Families/$familyCode/Members/$userId.json'))
          .timeout(const Duration(seconds: 10));
      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data != null;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  // ─── Online status grace period ────────────────────────────────────────────
  // OEM battery managers frequently kill the presence background service the
  // instant a user swipes the app away, closing its RTDB socket and firing
  // onDisconnect() even though the device still has internet. Rather than
  // trust the raw OnlineStatus flag, treat a member as still online if they
  // were seen within this window - it absorbs that kill/watchdog-restart gap.
  static const Duration _onlineGracePeriod = Duration(seconds: 90);

  static String _resolveOnlineStatus(String rawStatus, String? lastSeenStr) {
    if (rawStatus == 'Online') return 'Online';

    final lastSeen = _parseLastSeen(lastSeenStr);
    if (lastSeen != null &&
        DateTime.now().difference(lastSeen) <= _onlineGracePeriod) {
      return 'Online';
    }
    return rawStatus;
  }

  // Parses the app's custom "M/d/yyyy HH:mm:ss" local-time format (see
  // _fmtDate in background_service.dart) without pulling in intl.
  static DateTime? _parseLastSeen(String? s) {
    if (s == null || s.isEmpty) return null;
    try {
      final parts = s.split(' ');
      if (parts.length != 2) return null;
      final dateParts = parts[0].split('/');
      final timeParts = parts[1].split(':');
      if (dateParts.length != 3 || timeParts.length != 3) return null;
      return DateTime(
        int.parse(dateParts[2]),
        int.parse(dateParts[0]),
        int.parse(dateParts[1]),
        int.parse(timeParts[0]),
        int.parse(timeParts[1]),
        int.parse(timeParts[2]),
      );
    } catch (_) {
      return null;
    }
  }
}
