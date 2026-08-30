// lib/services/family_members_cache_service.dart
//
// Local cache for the dashboard's family/member list. Unlike
// ReportHistoryCacheService (which has a genuinely unbounded, ever-growing
// history to page through incrementally), a family's membership is a small,
// flat set — there's no meaningful "delta" to fetch for it the way new
// report IDs can be. So this cache is purely temporal: paint instantly from
// whatever's on disk, always refresh in full in the background, overwrite
// the cache with whatever comes back.
//
// This is also what makes the dashboard load path offline-first: the fetch
// this service does internally (FirebaseService.getFamilyByCode +
// getFamilyMembersWithLocations) is routed entirely through CachedHttpGet,
// which itself consults ConnectivityQualityService — on a weak/offline
// connection those calls serve their own last-known-good disk-cached
// response instead of attempting the network at all. The instant-paint
// cache here just means the SCREEN never has to wait on that round trip
// (successful or not) before showing something.

import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';
import 'firebase_realtime_database.dart';

class FamilyMembersCacheService {
  static String _key(String familyCode) =>
      'family_members_cache_v1_$familyCode';

  /// Reads whatever is cached on-device for [familyCode] with no network
  /// call, so the dashboard can paint instantly on repeat opens while a
  /// refresh happens in the background. Returns null when nothing has been
  /// cached yet (true first-ever load, or after [clear]).
  static Future<Map<String, dynamic>?> getCachedFamily(
      String familyCode) async {
    if (familyCode.isEmpty) return null;
    final prefs = await SharedPreferences.getInstance();
    return _readCache(prefs, familyCode);
  }

  /// Fetches the family + member list fresh, merges it into the cache
  /// shape, persists it, and returns it. On failure: returns null when
  /// [throwOnError] is false (caller keeps whatever's already on screen);
  /// rethrows when true.
  static Future<Map<String, dynamic>?> syncAndGetFamily(
    String familyCode, {
    required String userId,
    bool throwOnError = false,
  }) async {
    if (familyCode.isEmpty) return null;
    try {
      final family = await FirebaseService.getFamilyByCode(familyCode);
      if (family == null) return null;

      final familyName = family['FamilyName']?.toString() ?? '';
      final createdBy = family['CreatedBy']?.toString() ?? '';
      final membersRaw = family['Members'];

      final List<Map<String, dynamic>> members = [];
      if (membersRaw != null && membersRaw is Map) {
        membersRaw.forEach((key, value) {
          if (value is Map) {
            members.add({
              'userId': value['UserId']?.toString() ?? key.toString(),
              'name': value['Name']?.toString() ?? 'Unknown',
              'role': value['Role']?.toString() ?? 'Member',
              'joinedAt': value['JoinedAt']?.toString() ?? '',
              'status': 'Online',
            });
          }
        });
      }

      members.sort((a, b) {
        if (a['userId'] == userId) return -1;
        if (b['userId'] == userId) return 1;
        if (a['role'] == 'Admin') return -1;
        if (b['role'] == 'Admin') return 1;
        return (a['name'] as String).compareTo(b['name'] as String);
      });

      // throwOnError so a dropped fetch here surfaces to the caller instead
      // of silently overwriting every member's real photo/status/location
      // with the 'Offline'/blank defaults — same reasoning as the dashboard
      // screen's own pre-existing call to this method.
      final membersWithLocations = await FirebaseService
          .getFamilyMembersWithLocations(familyCode, throwOnError: true);

      final statusById = {
        for (final m in membersWithLocations) m['userId']?.toString() ?? '': m
      };

      for (final member in members) {
        final id = member['userId']?.toString() ?? '';
        final m = statusById[id];
        member['status'] = m?['onlineStatus']?.toString() ?? 'Offline';
        member['lastSeen'] = m?['lastSeen']?.toString() ?? '';
        member['latitude'] = m?['latitude'];
        member['longitude'] = m?['longitude'];
        member['locationUpdated'] = m?['lastUpdated']?.toString() ?? '';
        member['photoUrl'] = m?['photoUrl']?.toString() ?? '';
      }

      final result = {
        'familyName': familyName,
        'createdBy': createdBy,
        'members': members,
      };

      final prefs = await SharedPreferences.getInstance();
      await _writeCache(prefs, familyCode, result);
      return result;
    } catch (e) {
      if (throwOnError) rethrow;
      return null;
    }
  }

  static Map<String, dynamic>? _readCache(
      SharedPreferences prefs, String familyCode) {
    final raw = prefs.getString(_key(familyCode));
    if (raw == null) return null;
    try {
      final decoded = json.decode(raw) as Map<String, dynamic>;
      final members = (decoded['members'] as List)
          .map((e) => Map<String, dynamic>.from(e as Map))
          .toList();
      return {
        'familyName': decoded['familyName']?.toString() ?? '',
        'createdBy': decoded['createdBy']?.toString() ?? '',
        'members': members,
      };
    } catch (_) {
      return null;
    }
  }

  static Future<void> _writeCache(SharedPreferences prefs, String familyCode,
      Map<String, dynamic> family) async {
    await prefs.setString(_key(familyCode), json.encode(family));
  }

  /// Drops the cached family/member list for [familyCode] — e.g. on
  /// logout, or leaving/switching families, where a cached list would
  /// belong to the wrong family or a different account entirely.
  static Future<void> clear(String familyCode) async {
    if (familyCode.isEmpty) return;
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_key(familyCode));
  }
}
