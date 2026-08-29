// lib/services/emergency_report_service.dart
//
// CHANGE: Shake SOS now notifies FAMILY MEMBERS ONLY.
//   ✅ Saves to  /Families/{familyCode}/FamilyReports/{reportId}
//   ✅ Saves to  /Families/{familyCode}/SOS/{userId}   ← instant flag
//   ✅ Saves to  /UserEmergencyReports/{userId}/{reportId}
//   ✅ Sends FCM push to all other family members
//   ❌ No longer saves to /emergency-high-red/          ← removed (police/dispatcher)
//   ❌ No longer saves to Firestore /reports/           ← removed (dispatcher dashboard)
//
// NEW: Standard reports now also push FCM to all registered dispatchers.
//   ✅ Sends FCM push to /DispatcherTokens after every non-shake report save.

import 'dart:convert';
import 'dart:math';
import 'package:http/http.dart' as http;
import 'package:geolocator/geolocator.dart';
import 'package:geocoding/geocoding.dart' as geocoding;
import 'package:shared_preferences/shared_preferences.dart';
import 'fcm_service.dart';
import '../core/utils/cached_http_get.dart';

class EmergencyReportService {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  static const String _firestoreUrl =
      'https://firestore.googleapis.com/v1/projects/lifeguard-cefd9/databases/(default)/documents/reports/';

  static const Map<String, String> _reportLabels = {
    'crime': 'crime-report',
    'medical': 'medical-report',
    'fire': 'fire-report',
    'flood': 'flood-report',
    'accident': 'accident-report',
    'other': 'other-report',
    'shake': 'family-shake-sos',
    'bubble': 'family-bubble-sos',
  };

  static String getReportLabel(String type) =>
      _reportLabels[type] ?? 'other-report';

  // ── SOS from the floating bubble, with an explicitly supplied session ─────
  //
  // Preferred entry point for the overlay. The bubble receives userId /
  // userName / familyCode from the main isolate via
  // OverlayService.pushSession(), so it never has to touch SharedPreferences
  // from inside the overlay engine — where that plugin may not be registered.
  //
  // Type 'bubble' takes the family-SOS branch in saveReport(), so family
  // members get the same SOS flag, FamilyReports entry and FCM push that a
  // shake-triggered SOS produces.
  static Future<Map<String, dynamic>> saveBubbleSosReport({
    required String userId,
    required String userName,
    required String familyCode,
  }) async {
    if (userId.isEmpty) {
      return {'success': false, 'error': 'No active session'};
    }

    final emergencyData = {
      'type': 'bubble',
      'trigger': 'overlay_bubble',
      'message': 'Emergency SOS triggered from the floating SOS bubble',
      'timestamp': DateTime.now().toIso8601String(),
    };

    return saveReport(
      userId: userId,
      userName: userName,
      emergencyData: emergencyData,
      familyCode: familyCode,
    );
  }

  // ── Convenience: SOS triggered from the floating bubble overlay ───────────
  //
  // Called from the overlay's own Flutter engine, so SharedPreferences is
  // reloaded first — that isolate holds its own cache and may not have seen
  // writes made by the main app (e.g. a login that happened after the bubble
  // was shown).
  //
  // Routes through the same family-SOS path as saveBubbleSosReport(), so
  // family members receive the identical SOS flag, FamilyReports entry and
  // FCM push. The trigger is tagged 'overlay_bubble' so the source stays
  // distinguishable.
  static Future<Map<String, dynamic>> saveOverlaySosReport() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.reload();

    final userId = prefs.getString('userId') ?? '';
    final userName = prefs.getString('userName') ?? 'Unknown';
    final familyCode = prefs.getString('familyCode') ?? '';

    if (userId.isEmpty) {
      return {'success': false, 'error': 'No active session'};
    }

    final emergencyData = {
      'type': 'bubble',
      'trigger': 'overlay_bubble',
      'message': 'Emergency SOS triggered from the floating SOS bubble',
      'timestamp': DateTime.now().toIso8601String(),
    };

    return saveReport(
      userId: userId,
      userName: userName,
      emergencyData: emergencyData,
      familyCode: familyCode,
    );
  }

  // ── Core save method ──────────────────────────────────────────────────────
  static Future<Map<String, dynamic>> saveReport({
    required String userId,
    required String userName,
    required Map<String, dynamic> emergencyData,
    String familyCode = '',
    // Set when the reporter picked "this happened somewhere else" and chose
    // a barangay manually — e.g. they're reporting a fire they passed on
    // the way home, after already leaving. When present, this barangay is
    // used for the report's location/routing instead of the reporter's own
    // GPS fix, which would otherwise wrongly pin the incident to wherever
    // they are right now. The reporter's actual GPS is still captured into
    // `Location` either way, so dispatchers can still see where to reach
    // the reporter themselves if they need to follow up.
    String? manualBarangay,
  }) async {
    try {
      final type = emergencyData['type']?.toString() ?? 'other';
      final reportLabel = getReportLabel(type);
      final isFamilySos = type == 'shake' || type == 'bubble';

      print(
          '🔵 Saving report → type: $type | label: $reportLabel | userId: $userId');

      // ── GPS ─────────────────────────────────────────────────────────────
      Map<String, dynamic> location = {
        'Latitude': null,
        'Longitude': null,
        'Address': 'Location unavailable',
        'LastUpdated': _formatDate(DateTime.now()),
      };
      Map<String, double>? gpsPos;

      try {
        gpsPos = await _getCurrentLocation();
        if (gpsPos != null) {
          final address = await reverseGeocode(
            gpsPos['latitude']!,
            gpsPos['longitude']!,
          );
          location = {
            'Latitude': gpsPos['latitude'],
            'Longitude': gpsPos['longitude'],
            'Address': address,
            'LastUpdated': _formatDate(DateTime.now()),
          };
        }
      } catch (e) {
        print('⚠️ Could not get GPS for report: $e');
      }

      // Resolved from THIS report's actual GPS fix (gpsPos above), not the
      // static home barangay saved on the user's account — a report made
      // while out and about must reflect where the user actually is.
      // Unless the reporter explicitly said this happened somewhere else
      // (manualBarangay), in which case that overrides the GPS guess —
      // `location` above still reflects their real GPS regardless, so it's
      // never lost, just no longer used to tag WHERE the incident is.
      final hasManualBarangay =
          manualBarangay != null && manualBarangay.trim().isNotEmpty;
      final barangay = hasManualBarangay
          ? manualBarangay.trim()
          : await resolveReportBarangay(gpsPos, userId);
      final now = DateTime.now();
      final createdAt = _formatDate(now);
      final reportId = _generateReportId(type);

      final reportPayload = <String, dynamic>{
        'ReportId': reportId,
        'ReportLabel': reportLabel,
        'UserId': userId,
        'UserName': userName,
        'EmergencyType': type,
        'Status': isFamilySos ? 'Active' : 'Pending',
        'CreatedAt': createdAt,
        'Timestamp': now.toIso8601String(),
        'Location': location,
        'Barangay': barangay.isNotEmpty ? barangay : 'Unknown Barangay',
        'LocationSource': hasManualBarangay ? 'manual' : 'reporter_gps',
        'Details': _buildDetails(emergencyData),
        if (isFamilySos) 'Priority': 'critical',
        if (isFamilySos) 'AlertLevel': 'family-sos',
      };

      if (isFamilySos) {
        // ══════════════════════════════════════════════════════════════════
        // SHAKE SOS → FAMILY ONLY
        // ══════════════════════════════════════════════════════════════════

        // 1. User's own report history
        await http.put(
          Uri.parse('${_dbUrl}UserEmergencyReports/$userId/$reportId.json'),
          body: json.encode({
            'ReportId': reportId,
            'ReportLabel': reportLabel,
            'EmergencyType': type,
            'Status': 'Active',
            'CreatedAt': createdAt,
            'Location': location,
            'Barangay': barangay.isNotEmpty ? barangay : 'Unknown Barangay',
            'Priority': 'critical',
            'AlertLevel': 'family-sos',
          }),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 10));

        print('✅ User index saved at /UserEmergencyReports/$userId/$reportId');

        if (familyCode.isNotEmpty) {
          // 2. FamilyReports
          await http.put(
            Uri.parse(
                '${_dbUrl}Families/$familyCode/FamilyReports/$reportId.json'),
            body: json.encode(reportPayload),
            headers: {'Content-Type': 'application/json'},
          ).timeout(const Duration(seconds: 15));

          print(
              '✅ FamilyReports saved at /Families/$familyCode/FamilyReports/$reportId');

          // 3. SOS flag
          await http.put(
            Uri.parse('${_dbUrl}Families/$familyCode/SOS/$userId.json'),
            body: json.encode({
              'active': true,
              'userName': userName,
              'timestamp': now.toIso8601String(),
              'type': type,
              'location': location['Address'],
            }),
            headers: {'Content-Type': 'application/json'},
          ).timeout(const Duration(seconds: 10));

          print('✅ SOS flag set at /Families/$familyCode/SOS/$userId');

          // 4. FCM push to all other family members
          FcmService.sendEmergencyNotificationToFamily(
            familyCode: familyCode,
            reporterUserId: userId,
            reporterName: userName,
            emergencyType: type,
            location: location['Address']?.toString() ?? 'Location unavailable',
            latitude: gpsPos?['latitude'],
            longitude: gpsPos?['longitude'],
            reportId: reportId,
            timestamp: createdAt,
          ).catchError((e) {
            print('⚠️ FCM notification failed (non-fatal): $e');
          });
        }

        // 5. Floating SOS bubble is treated exactly like a standard report
        // from the dispatcher's point of view — not just a notification —
        // so it actually shows up as an actionable report they can
        // acknowledge/resolve, same as a crime or accident report. Shake
        // SOS stays family-only per the original design.
        if (type == 'bubble') {
          try {
            final dispatcherPayload = <String, dynamic>{
              ...reportPayload,
              // The dispatcher pipeline (Pending → Acknowledged → Resolved)
              // expects 'Pending', not the family-side 'Active' status.
              'Status': 'Pending',
            };

            await http.put(
              Uri.parse('${_dbUrl}$reportLabel/$reportId.json'),
              body: json.encode(dispatcherPayload),
              headers: {'Content-Type': 'application/json'},
            ).timeout(const Duration(seconds: 15));

            print('✅ Dispatcher-visible SOS report saved at /$reportLabel/$reportId');

            FcmService.sendNotificationToDispatchers(
              reporterName: userName,
              emergencyType: type,
              location: location['Address']?.toString() ?? 'Location unavailable',
              barangay: barangay.isNotEmpty ? barangay : 'Unknown Barangay',
              reportId: reportId,
            ).catchError((e) {
              print('⚠️ Dispatcher FCM notification failed (non-fatal): $e');
            });
          } catch (e) {
            print('⚠️ Dispatcher-visible SOS report write failed (non-fatal): $e');
          }
        }
      } else {
        // ══════════════════════════════════════════════════════════════════
        // STANDARD REPORT TYPES (fire, flood, medical, crime, accident, other)
        // ══════════════════════════════════════════════════════════════════

        // 1. Write to /{reportLabel}/{reportId}
        final reportResp = await http.put(
          Uri.parse('${_dbUrl}$reportLabel/$reportId.json'),
          body: json.encode(reportPayload),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 15));

        if (reportResp.statusCode < 200 || reportResp.statusCode >= 300) {
          print('❌ Firebase RTDB PUT failed: ${reportResp.statusCode}');
          return {
            'success': false,
            'error': 'Server error: ${reportResp.statusCode}',
          };
        }

        print('✅ RTDB report saved at /$reportLabel/$reportId');

        // 2. User index
        await http.put(
          Uri.parse('${_dbUrl}UserEmergencyReports/$userId/$reportId.json'),
          body: json.encode({
            'ReportId': reportId,
            'ReportLabel': reportLabel,
            'EmergencyType': type,
            'Status': 'Pending',
            'CreatedAt': createdAt,
            'Location': location,
            'Barangay': barangay.isNotEmpty ? barangay : 'Unknown Barangay',
          }),
          headers: {'Content-Type': 'application/json'},
        ).timeout(const Duration(seconds: 10));

        print(
            '✅ RTDB user index saved at /UserEmergencyReports/$userId/$reportId');

        // ── NEW: Notify all active dispatchers ───────────────────────────────
        FcmService.sendNotificationToDispatchers(
          reporterName: userName,
          emergencyType: type,
          location: location['Address']?.toString() ?? 'Location unavailable',
          barangay: barangay.isNotEmpty ? barangay : 'Unknown Barangay',
          reportId: reportId,
        ).catchError((e) {
          print('⚠️ Dispatcher FCM notification failed (non-fatal): $e');
        });

        // 3. FamilyReports (so family can see it in notifications)
        if (familyCode.isNotEmpty) {
          try {
            await http.put(
              Uri.parse(
                  '${_dbUrl}Families/$familyCode/FamilyReports/$reportId.json'),
              body: json.encode(reportPayload),
              headers: {'Content-Type': 'application/json'},
            ).timeout(const Duration(seconds: 15));

            print(
                '✅ FamilyReports written at /Families/$familyCode/FamilyReports/$reportId');

            final address =
                location['Address']?.toString() ?? 'Location unavailable';
            FcmService.sendEmergencyNotificationToFamily(
              familyCode: familyCode,
              reporterUserId: userId,
              reporterName: userName,
              emergencyType: type,
              location: address,
            ).catchError((e) {
              print('⚠️ FCM notification failed (non-fatal): $e');
            });
          } catch (e) {
            print('⚠️ FamilyReports write failed (non-fatal): $e');
          }
        }

        // 4. Firestore (emergency dispatcher dashboard)
        _saveToFirestore(
          reportId: reportId,
          reportLabel: reportLabel,
          userId: userId,
          userName: userName,
          type: type,
          barangay: barangay,
          gpsPos: gpsPos,
          createdAt: now,
          emergencyData: emergencyData,
        ).catchError((e) {
          print('⚠️ Firestore write failed (non-fatal): $e');
        });
      }

      return {
        'success': true,
        'reportId': reportId,
        'reportLabel': reportLabel,
      };
    } catch (e) {
      print('❌ saveReport error: $e');
      return {'success': false, 'error': 'Error: $e'};
    }
  }

  // ── Read helpers ──────────────────────────────────────────────────────────

  // Both list readers below reconcile against each report's canonical
  // Status before returning (see reconcileStatuses) — otherwise every
  // screen that lists reports (My Reports, Family tab, Report History,
  // Notifications) would keep showing whatever status the index/family
  // feed happened to be written with, even after the dispatcher moves the
  // report on and only patches the canonical record.
  // [throwOnError] defaults to false so existing callers that just want a
  // best-effort list (badge counts, reconciliation) keep degrading quietly
  // to an empty list on failure rather than crashing. Screens that need to
  // tell "no reports" apart from "fetch failed, don't touch what's already
  // on screen" — see MyReportsScreen's offline handling — should pass true
  // so a network failure actually reaches their catch block instead of
  // silently resolving as an empty (and indistinguishable) result.
  static Future<List<Map<String, dynamic>>> getFamilyReports(
      String familyCode, {bool throwOnError = false}) async {
    if (familyCode.isEmpty) return [];
    try {
      final resp = await CachedHttpGet.get(
        Uri.parse('${_dbUrl}Families/$familyCode/FamilyReports.json'),
        timeout: const Duration(seconds: 15),
      );

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data != null && data is Map) {
          final list = data.values
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
          list.sort((a, b) => _parseCreatedAt(b['CreatedAt']?.toString())
              .compareTo(_parseCreatedAt(a['CreatedAt']?.toString())));
          return reconcileStatuses(list);
        }
        return [];
      }
      if (throwOnError) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      return [];
    } catch (e) {
      print('❌ getFamilyReports error: $e');
      if (throwOnError) rethrow;
      return [];
    }
  }

  static Future<List<Map<String, dynamic>>> getUserReports(
      String userId, {bool throwOnError = false}) async {
    try {
      final resp = await CachedHttpGet.get(
        Uri.parse('${_dbUrl}UserEmergencyReports/$userId.json'),
        timeout: const Duration(seconds: 15),
      );

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data != null && data is Map) {
          final list = data.values
              .map((v) => Map<String, dynamic>.from(v as Map))
              .toList();
          list.sort((a, b) => _parseCreatedAt(b['CreatedAt']?.toString())
              .compareTo(_parseCreatedAt(a['CreatedAt']?.toString())));
          return reconcileStatuses(list);
        }
        return [];
      }
      if (throwOnError) {
        throw Exception('HTTP ${resp.statusCode}');
      }
      return [];
    } catch (e) {
      print('❌ getUserReports error: $e');
      if (throwOnError) rethrow;
      return [];
    }
  }

  static Future<Map<String, dynamic>?> getReportById({
    required String reportLabel,
    required String reportId,
  }) async {
    try {
      final resp = await CachedHttpGet.get(
        Uri.parse('${_dbUrl}$reportLabel/$reportId.json'),
        timeout: const Duration(seconds: 10),
      );
      if (resp.statusCode == 200) {
        final data = json.decode(resp.body);
        if (data != null) return Map<String, dynamic>.from(data);
      }
      return null;
    } catch (e) {
      print('❌ getReportById error: $e');
      return null;
    }
  }

  static Future<Map<String, dynamic>?> getReportFromIndex(
      Map<String, dynamic> indexEntry) async {
    final label = indexEntry['ReportLabel']?.toString() ?? '';
    final id = indexEntry['ReportId']?.toString() ?? '';
    if (label.isEmpty || id.isEmpty) return null;
    return getReportById(reportLabel: label, reportId: id);
  }

  /// Just the Status leaf of a report's canonical dispatcher-visible record
  /// — a single small value, not the whole report — for reconciling list
  /// entries that might be lagging behind it. Returns null when the value
  /// is missing (including reports with no canonical record at all, e.g. a
  /// family-only Shake SOS — see saveReport) or the request fails; either
  /// way the caller just keeps what it already had.
  static Future<String?> _fetchCanonicalStatus({
    required String reportLabel,
    required String reportId,
  }) async {
    try {
      // Same report's Status is frequently re-checked within the same
      // couple of seconds by concurrent callers (dashboard unread poll,
      // notification screen, my-reports screen) — CachedHttpGet collapses
      // those into one request.
      final resp = await CachedHttpGet.get(
        Uri.parse('${_dbUrl}$reportLabel/$reportId/Status.json'),
        timeout: const Duration(seconds: 8),
      );
      if (resp.statusCode != 200) return null;
      final raw = resp.body.trim();
      if (raw == 'null' || raw.isEmpty) return null;
      return raw.replaceAll('"', '');
    } catch (_) {
      return null;
    }
  }

  /// Reconciles a LIST of reports — as read from a reporter's index or a
  /// family's report feed — against each one's canonical dispatcher-visible
  /// Status, the same way [mergeReportSources] reconciles a single report's
  /// detail view. The dispatcher app and this one write to different nodes
  /// for the same report and don't always keep both in lockstep, so a list
  /// built purely from the index/family feed can show a status that's
  /// stale in either direction — stuck on Pending after the dispatcher has
  /// already resolved it, or (less commonly) showing a stage that hasn't
  /// actually landed on the canonical record yet.
  ///
  /// Only reports NOT already at the furthest pipeline stage are checked —
  /// a report already showing Resolved can't become "more resolved" — which
  /// keeps this to a handful of small, parallel requests per screen load
  /// rather than one per report in what can be a long history.
  static Future<List<Map<String, dynamic>>> reconcileStatuses(
      List<Map<String, dynamic>> reports) async {
    final toCheck = reports
        .where((r) => !isResolvedStatus(r['Status']?.toString()))
        .where((r) =>
            (r['ReportLabel']?.toString() ?? '').isNotEmpty &&
            (r['ReportId']?.toString() ?? '').isNotEmpty)
        .toList();
    if (toCheck.isEmpty) return reports;

    // Checked in small concurrent batches rather than one giant Future.wait
    // over the whole list — a long history (Report History in particular
    // can run into the hundreds) would otherwise open one HTTP connection
    // per report all at once, which is exactly the kind of burst that
    // chokes or times out on a slow/unstable connection. Batching bounds
    // the concurrent connection count regardless of how large the list is.
    const batchSize = 8;
    final found = <MapEntry<String, String?>?>[];
    for (var i = 0; i < toCheck.length; i += batchSize) {
      final batch = toCheck.skip(i).take(batchSize);
      final batchResults = await Future.wait(batch.map((r) async {
        final label = r['ReportLabel'].toString();
        final id = r['ReportId'].toString();
        final canonical =
            await _fetchCanonicalStatus(reportLabel: label, reportId: id);
        if (canonical == null) return null;
        final resolved = moreAdvancedStatus(r['Status']?.toString(), canonical);
        return resolved == r['Status']?.toString()
            ? null
            : MapEntry(id, resolved);
      }));
      found.addAll(batchResults);
    }

    final changes = <String, String?>{
      for (final e in found)
        if (e != null) e.key: e.value,
    };
    if (changes.isEmpty) return reports;

    return reports.map((r) {
      final id = r['ReportId']?.toString() ?? '';
      return changes.containsKey(id) ? {...r, 'Status': changes[id]} : r;
    }).toList();
  }

  // ── Resolution helpers ────────────────────────────────────────────────────
  //
  // A report is "resolved" once a responder or administrator closes it out on
  // the dispatcher side (ploiceguard360), which patches Status on both
  // /{reportLabel}/{reportId} and the reporter's own
  // /UserEmergencyReports/{userId}/{reportId} index entry. These helpers are
  // shared by everything that has to recognise and describe that transition —
  // the notification screen's "Resolved Reports" section and the background
  // watcher that pushes the resolved alert.

  static const Map<String, String> _typeLabels = {
    'crime': 'Crime Report',
    'medical': 'Medical Emergency',
    'fire': 'Fire Emergency',
    'flood': 'Flood Emergency',
    'accident': 'Accident',
    'other': 'Emergency Report',
    'shake': 'Shake SOS',
    'bubble': 'SOS Button',
  };

  static const Map<String, String> _typeEmojis = {
    'crime': '🚨',
    'medical': '🚑',
    'fire': '🔥',
    'flood': '🌊',
    'accident': '🚗',
    'other': '⚠️',
    'shake': '📳',
    'bubble': '🆘',
  };

  static String getTypeLabel(String type) =>
      _typeLabels[type] ?? 'Emergency Report';

  static String getTypeEmoji(String type) => _typeEmojis[type] ?? '⚠️';

  /// True when [status] is the dispatcher's terminal "closed out" state.
  /// Compared case-insensitively because the value is written by a separate
  /// app and has appeared as both 'Resolved' and 'resolved'.
  static bool isResolvedStatus(String? status) =>
      (status ?? '').trim().toLowerCase() == 'resolved';

  /// True once the dispatcher has assigned a responder to the report. That
  /// side writes 'Acknowledged' for it (alongside AcknowledgedAt and the
  /// responder's DispatcherName); 'Assigned'/'In Progress' are accepted too
  /// so a later vocabulary change there doesn't silently stop the alert.
  static bool isAssignedStatus(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'acknowledged':
      case 'assigned':
      case 'in progress':
        return true;
      default:
        return false;
    }
  }

  /// Normalises the dispatcher's status vocabulary into the labels the
  /// reporter-facing UI shows: 'Pending', 'In Progress', 'Resolved', or
  /// 'Active' for a still-live SOS (a separate concept — see
  /// isAssignedStatus). The dispatcher app writes 'Acknowledged' for what
  /// the reporter sees as 'In Progress'; screens that displayed the raw
  /// value unmapped showed a report with a responder already assigned to it
  /// still labelled 'Acknowledged', styled like an untouched Pending report.
  /// Every screen that shows a status badge should route through this
  /// rather than displaying the stored value directly.
  static String displayStatus(String? raw) {
    final s = raw?.trim() ?? '';
    if (s.isEmpty) return 'Pending';
    return isAssignedStatus(s) ? 'In Progress' : s;
  }

  /// Ranks a status by how far along the Pending → In Progress → Resolved
  /// pipeline it is, so two copies of the same report — e.g. the reporter's
  /// own /UserEmergencyReports index entry and the canonical
  /// /{reportLabel}/{reportId} record the dispatcher writes to — can be
  /// reconciled when they disagree. The two are written by different apps
  /// through different paths and can fall out of sync (most commonly the
  /// canonical record lagging after only the index gets patched); resolving
  /// by rank means the merged view always reflects whichever side has seen
  /// the most recent real transition, and can never regress a report the
  /// user has already seen marked Resolved back to Pending.
  ///
  /// 'Active' (a live, ongoing SOS) sits outside the review pipeline
  /// entirely — it's a different concept, not "behind" Pending — so it
  /// ranks just above Pending: further along than an unactioned report, but
  /// never wins over an explicit Acknowledged/Resolved verdict.
  static int _statusRank(String? status) {
    switch ((status ?? '').trim().toLowerCase()) {
      case 'resolved':
        return 3;
      case 'acknowledged':
      case 'assigned':
      case 'in progress':
        return 2;
      case 'active':
        return 1;
      case 'pending':
        return 0;
      default:
        return -1; // unrecognised/empty — never preferred over a known status
    }
  }

  /// The more advanced of two status values for the SAME report. Ties (and
  /// two unrecognised values) keep [a].
  static String? moreAdvancedStatus(String? a, String? b) =>
      _statusRank(b) > _statusRank(a) ? b : a;

  /// Merges a report's reporter-facing index entry with its canonical
  /// dispatcher-visible record (fetched via [getReportFromIndex]). Every
  /// field from [canonical] wins — it carries richer detail the index never
  /// had (DispatcherName, ResolvedAt, Details, ...) — EXCEPT Status, where
  /// [moreAdvancedStatus] decides, so a canonical record that never got
  /// patched to match a resolution already reflected in the index can't
  /// make an already-resolved report look Pending again.
  static Map<String, dynamic> mergeReportSources(
    Map<String, dynamic> indexEntry,
    Map<String, dynamic>? canonical,
  ) {
    if (canonical == null) return indexEntry;
    final merged = <String, dynamic>{...indexEntry, ...canonical};
    merged['Status'] = moreAdvancedStatus(
      indexEntry['Status']?.toString(),
      canonical['Status']?.toString(),
    );
    return merged;
  }

  /// When the responder was assigned, as recorded by the dispatcher side.
  static String assignedAtOf(Map<String, dynamic> report) => _firstNonEmpty(
      report, const ['AcknowledgedAt', 'acknowledgedAt', 'AssignedAt']);

  /// The responder assigned to the report, or '' when the dispatcher recorded
  /// no name. Note this only lives on the canonical /{reportLabel}/{reportId}
  /// record — the reporter's own /UserEmergencyReports index entry carries
  /// just Status, so callers wanting the name have to read the full report
  /// (see getReportFromIndex).
  static String responderNameOf(Map<String, dynamic> report) => _firstNonEmpty(
      report, const [
    'DispatcherName',
    'dispatcherName',
    'AssignedResponder',
    'ResponderName',
    'AssignedTo',
  ]);

  /// The moment a report was resolved, as written by the dispatcher side.
  /// That app has used more than one field name for it, so the first
  /// populated one wins; returns '' when it recorded no timestamp at all.
  static String resolvedAtOf(Map<String, dynamic> report) => _firstNonEmpty(
      report, const ['ResolvedAt', 'resolvedAt', 'ResolvedOn', 'UpdatedAt']);

  /// Who closed the report out — a responder or an administrator. The
  /// dispatcher app records the acting officer as DispatcherName rather than
  /// a dedicated resolver field, so that's the practical source; falls back
  /// to a neutral phrase when no name was recorded at all.
  static String resolvedByOf(Map<String, dynamic> report) {
    final name = _firstNonEmpty(report, const [
      'ResolvedBy',
      'resolvedBy',
      'ResolvedByName',
      'ResolverName',
      'DispatcherName',
    ]);
    return name.isNotEmpty ? name : 'a responder';
  }

  /// Optional closing remark left by whoever resolved the report.
  static String resolutionNoteOf(Map<String, dynamic> report) => _firstNonEmpty(
      report,
      const ['ResolutionNote', 'ResolvedNote', 'ResolutionMessage']);

  static String _firstNonEmpty(Map<String, dynamic> map, List<String> keys) {
    for (final k in keys) {
      final v = map[k]?.toString().trim() ?? '';
      if (v.isNotEmpty && v != 'null') return v;
    }
    return '';
  }

  /// Parses either an ISO-8601 string or the app's custom
  /// "M/d/yyyy HH:mm:ss" local-time format (see _formatDate below). Returns
  /// null when [raw] is neither.
  static DateTime? parseReportTimestamp(String? raw) {
    if (raw == null || raw.trim().isEmpty) return null;
    final s = raw.trim();
    final iso = DateTime.tryParse(s);
    if (iso != null) return iso;
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

  static const List<String> _monthNames = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  /// "Aug 15, 2026" — empty string when [raw] can't be parsed.
  static String formatReportDate(String? raw) {
    final dt = parseReportTimestamp(raw);
    if (dt == null) return '';
    return '${_monthNames[dt.month - 1]} ${dt.day}, ${dt.year}';
  }

  /// "2:04 PM" — 12-hour clock, matching how dates read elsewhere in the app.
  /// Empty string when [raw] can't be parsed.
  static String formatReportTime(String? raw) {
    final dt = parseReportTimestamp(raw);
    if (dt == null) return '';
    final hour12 = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    return '$hour12:$minute ${dt.hour < 12 ? 'AM' : 'PM'}';
  }

  /// "Aug 15, 2026 at 2:04 PM". Falls back to the raw string when it can't be
  /// parsed, so a value in an unexpected format is still shown rather than
  /// silently disappearing from the notification.
  static String formatReportDateTime(String? raw) {
    final date = formatReportDate(raw);
    if (date.isEmpty) return raw?.trim() ?? '';
    return '$date at ${formatReportTime(raw)}';
  }

  // Sorting key for the app's custom "M/d/yyyy HH:mm:ss" format — month/day
  // are NOT zero-padded, so plain string comparison sorts entries wrong
  // (e.g. "8/9/2026" > "8/14/2026"). DateTime(0) for unparseable values keeps
  // them at the bottom of a newest-first list.
  static DateTime _parseCreatedAt(String? s) =>
      parseReportTimestamp(s) ?? DateTime(0);

  // ── Private helpers ───────────────────────────────────────────────────────

  static Future<void> _saveToFirestore({
    required String reportId,
    required String reportLabel,
    required String userId,
    required String userName,
    required String type,
    required String barangay,
    required Map<String, double>? gpsPos,
    required DateTime createdAt,
    required Map<String, dynamic> emergencyData,
  }) async {
    final description = _buildDescription(type, emergencyData);
    final priority = _derivePriority(type, emergencyData);

    final url = Uri.parse('$_firestoreUrl$reportId');

    final fields = <String, dynamic>{
      'rtdbReportId': {'stringValue': reportId},
      'rtdbReportLabel': {'stringValue': reportLabel},
      'reporterId': {'stringValue': userId},
      'reporterName': {'stringValue': userName},
      'barangay': {'stringValue': barangay.isNotEmpty ? barangay : 'Unknown'},
      'type': {'stringValue': type},
      'description': {'stringValue': description},
      'status': {'stringValue': 'pending'},
      'priority': {'stringValue': priority},
      'dateReported': {
        'timestampValue': createdAt.toUtc().toIso8601String(),
      },
    };

    if (gpsPos != null) {
      fields['location'] = {
        'geoPointValue': {
          'latitude': gpsPos['latitude'],
          'longitude': gpsPos['longitude'],
        },
      };
    } else {
      fields['location'] = {
        'geoPointValue': {'latitude': 7.3103, 'longitude': 125.6839},
      };
    }

    final resp = await http.patch(
      url,
      body: json.encode({'fields': fields}),
      headers: {'Content-Type': 'application/json'},
    ).timeout(const Duration(seconds: 15));

    if (resp.statusCode >= 200 && resp.statusCode < 300) {
      print('✅ Firestore report saved at /reports/$reportId');
    } else {
      throw Exception('Firestore error ${resp.statusCode}');
    }
  }

  /// Resolves the barangay to store on a report from the GPS fix captured
  /// for THAT report — same nearest-centroid matching reverseGeocodeBarangay
  /// uses, but returning a bare barangay name (no "Brgy."/city prefix) so it
  /// fits the plain 'Barangay' field the UI already formats separately.
  /// Falls back to the account's saved barangay only when no GPS fix was
  /// available at all (permission denied, GPS off, etc.).
  ///
  /// Public so background_service.dart's own shake-SOS save path (which
  /// can't reuse saveReport() directly — it runs in a separate isolate with
  /// its own session handling) can resolve the same way instead of always
  /// falling back to the account's static home barangay.
  static Future<String> resolveReportBarangay(
    Map<String, double>? gpsPos,
    String userId,
  ) async {
    if (gpsPos != null) {
      final lat = gpsPos['latitude']!;
      final lng = gpsPos['longitude']!;

      if (_isWithinPanaboCity(lat, lng)) {
        final nearest = _nearestPanaboBarangay(lat, lng);
        if (nearest != null) return nearest;
      }

      try {
        final placemarks = await geocoding.placemarkFromCoordinates(lat, lng);
        if (placemarks.isNotEmpty) {
          final subLocality = placemarks.first.subLocality?.trim();
          if (subLocality != null && subLocality.isNotEmpty) {
            return subLocality;
          }
        }
      } catch (e) {
        print('⚠️ Could not reverse-geocode barangay for report: $e');
      }
    }

    // No usable GPS fix — better to show the user's home barangay than
    // nothing at all.
    return _fetchUserBarangay(userId);
  }

  static Future<String> _fetchUserBarangay(String userId) async {
    try {
      final resp = await http
          .get(Uri.parse('${_dbUrl}Accounts/$userId/Barangay.json'))
          .timeout(const Duration(seconds: 5));
      if (resp.statusCode == 200) {
        final raw = resp.body.trim();
        if (raw != 'null' && raw.isNotEmpty) {
          return raw.replaceAll('"', '').trim();
        }
      }
    } catch (_) {}
    return '';
  }

  static Map<String, dynamic> _buildDetails(Map<String, dynamic> data) {
    final type = data['type']?.toString() ?? 'unknown';
    final d = <String, dynamic>{'type': type};

    switch (type) {
      case 'shake':
        d['trigger'] = data['trigger'] ?? 'shake_gesture';
        d['message'] =
            data['message'] ?? 'Automatic SOS triggered by shake gesture';
        d['alertLevel'] = 'family-sos';
        d['priority'] = 'critical';
        break;
      case 'bubble':
        d['trigger'] = data['trigger'] ?? 'overlay_bubble';
        d['message'] = data['message'] ??
            'Emergency SOS triggered from the floating SOS bubble';
        d['alertLevel'] = 'family-sos';
        d['priority'] = 'critical';
        break;
      case 'fire':
        d['fireType'] = data['fireType'];
        d['peopleTrapped'] = data['peopleTrapped'];
        d['numberOfPeople'] = data['numberOfPeople'];
        d['spreadingFast'] = data['spreadingFast'];
        d['additionalInfo'] = data['additionalInfo'];
        break;
      case 'medical':
        d['condition'] = data['condition'];
        d['isConscious'] = data['isConscious'];
        d['needsAmbulance'] = data['needsAmbulance'];
        d['symptoms'] = data['symptoms'];
        d['additionalInfo'] = data['additionalInfo'];
        break;
      case 'crime':
        d['crimeType'] = data['crimeType'];
        d['isOngoing'] = data['isOngoing'];
        d['needsPolice'] = data['needsPolice'];
        d['additionalInfo'] = data['additionalInfo'];
        break;
      case 'flood':
        d['waterLevel'] = data['waterLevel'];
        d['peopleTrapped'] = data['peopleTrapped'];
        d['numberOfPeople'] = data['numberOfPeople'];
        d['needsEvacuation'] = data['needsEvacuation'];
        d['additionalInfo'] = data['additionalInfo'];
        break;
      case 'accident':
        d['accidentType'] = data['accidentType'];
        d['hasInjuries'] = data['hasInjuries'];
        d['injurySeverity'] = data['injurySeverity'];
        d['blockingTraffic'] = data['blockingTraffic'];
        d['additionalInfo'] = data['additionalInfo'];
        break;
      case 'other':
        d['category'] = data['category'];
        d['isUrgent'] = data['isUrgent'];
        d['needsImmediateHelp'] = data['needsImmediateHelp'];
        d['description'] = data['description'];
        break;
      default:
        data.forEach((k, v) {
          if (k != 'type' && k != 'timestamp') d[k] = v;
        });
    }
    return d;
  }

  static String _buildDescription(String type, Map<String, dynamic> data) {
    switch (type) {
      case 'shake':
        return '🚨 SHAKE SOS — Automatic emergency triggered by device shake';
      case 'bubble':
        return '🚨 BUBBLE SOS — Emergency triggered from the floating SOS bubble';
      case 'fire':
        final ft = data['fireType'] ?? 'fire';
        final trapped = data['peopleTrapped'] == true
            ? ', ${data['numberOfPeople']} people trapped'
            : '';
        return '$ft fire emergency$trapped';
      case 'medical':
        final cond = data['condition'] ?? 'medical emergency';
        final amb = data['needsAmbulance'] == true ? ', ambulance needed' : '';
        return '$cond$amb';
      case 'crime':
        final ct = data['crimeType'] ?? 'crime';
        final ongoing = data['isOngoing'] == true ? ' (ongoing)' : '';
        return '$ct report$ongoing';
      case 'flood':
        final wl = data['waterLevel'] ?? 'unknown level';
        final evac =
            data['needsEvacuation'] == true ? ', needs evacuation' : '';
        return 'Flood — $wl water$evac';
      case 'accident':
        final at = data['accidentType'] ?? 'accident';
        final inj = data['hasInjuries'] == true
            ? ', injuries reported (${data['injurySeverity'] ?? 'unknown'})'
            : '';
        return '$at$inj';
      case 'other':
        final cat = data['category'] ?? 'other';
        final desc = data['description']?.toString() ?? '';
        return desc.isNotEmpty
            ? '$cat: ${desc.substring(0, desc.length.clamp(0, 80))}'
            : cat;
      default:
        return 'Emergency report';
    }
  }

  static String _derivePriority(String type, Map<String, dynamic> data) {
    if (type == 'shake' || type == 'bubble') return 'critical';
    if (type == 'medical') {
      return data['needsAmbulance'] == true ? 'high' : 'medium';
    }
    if (type == 'fire') {
      return data['spreadingFast'] == true || data['peopleTrapped'] == true
          ? 'high'
          : 'medium';
    }
    if (type == 'crime') return data['isOngoing'] == true ? 'high' : 'medium';
    if (type == 'flood') {
      final wl = data['waterLevel']?.toString() ?? '';
      return (wl == 'chest' || wl == 'waist') ? 'high' : 'medium';
    }
    if (type == 'accident') {
      return data['hasInjuries'] == true ? 'high' : 'medium';
    }
    return data['isUrgent'] == true ? 'high' : 'low';
  }

  // ── Panabo City barangay centroids (same dataset used at sign-up) ─────────
  // The device's OS-level reverse geocoder frequently returns an empty or
  // unreliable `subLocality` for barangay-level detail in this region, so
  // for coordinates that fall near a known Panabo City barangay we resolve
  // the barangay by nearest-centroid match instead — the same approach
  // Google Maps effectively performs when you tap a location.
  static const Map<String, List<double>> _panaboBarangayCentroids = {
    'San Francisco (Poblacion)': [7.3118, 125.6765],
    'New Pandan (Poblacion)': [7.3145, 125.6720],
    'Gredu (Poblacion)': [7.3095, 125.6835],
    'Santo Niño (Poblacion)': [7.3055, 125.6810],
    'A. O. Floirendo': [7.3880, 125.7350],
    'Tagpore': [7.3720, 125.6980],
    'Lower Panaga (Roxas)': [7.3790, 125.6620],
    'Upper Licanan': [7.3650, 125.6480],
    'Waterfall': [7.3820, 125.6350],
    'Kasilak': [7.3550, 125.6830],
    'San Nicolas': [7.3580, 125.7050],
    'New Malitbog': [7.3520, 125.7420],
    'Little Panay': [7.3450, 125.6680],
    'San Pedro': [7.3410, 125.7120],
    'Dapco': [7.3350, 125.7280],
    'New Malaga': [7.3300, 125.7620],
    'J.P. Laurel': [7.3310, 125.6750],
    'San Roque': [7.3230, 125.6910],
    'Kauswagan': [7.3210, 125.7090],
    'Cacao': [7.3180, 125.6450],
    'New Visayas': [7.3140, 125.7020],
    'Nanyo': [7.3090, 125.6260],
    'Consolacion': [7.3050, 125.6680],
    'Mabunao': [7.3020, 125.6580],
    'Sindaton': [7.2980, 125.6380],
    'Katipunan': [7.2990, 125.7210],
    'Cagangohan': [7.2920, 125.6820],
    'San Vicente': [7.2870, 125.6560],
    'Katualan': [7.2850, 125.7420],
    'Maduao': [7.2760, 125.6720],
    'Dalisay': [7.2730, 125.7180],
    'Buenavista': [7.2810, 125.7010],
    'Malativas': [7.2890, 125.6250],
    'Quezon': [7.2720, 125.7580],
    'Salvacion': [7.2940, 125.7620],
    'Datu Abdul Dadia': [7.2620, 125.6460],
    'Kiotoy': [7.2640, 125.7080],
    'Santa Cruz': [7.2610, 125.7310],
    'Southern Davao': [7.2520, 125.6680],
    'Tibungol': [7.2430, 125.7090],
    'Manay': [7.2380, 125.6870],
  };

  // Barangays vary widely in size, so the match radius is generous enough
  // to cover the largest barangays while still bounding results to Panabo
  // City (~15km covers the full city extent from any centroid).
  static const double _maxBarangayMatchKm = 15.0;

  // Approximate Panabo City boundary (same box used at sign-up). Any
  // coordinate outside this box is treated as outside the city, regardless
  // of how close it is to a barangay centroid.
  static const double _panaboMinLat = 7.20;
  static const double _panaboMaxLat = 7.45;
  static const double _panaboMinLng = 125.55;
  static const double _panaboMaxLng = 125.85;

  static bool _isWithinPanaboCity(double lat, double lng) {
    return lat >= _panaboMinLat &&
        lat <= _panaboMaxLat &&
        lng >= _panaboMinLng &&
        lng <= _panaboMaxLng;
  }

  static double _toRad(double deg) => deg * pi / 180;

  static double _haversineKm(
      double lat1, double lng1, double lat2, double lng2) {
    const r = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return r * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  /// Returns the nearest known Panabo City barangay to [lat]/[lng], or null
  /// if the nearest centroid is farther than [_maxBarangayMatchKm] away.
  static String? _nearestPanaboBarangay(double lat, double lng) {
    String? nearest;
    double minDist = double.infinity;
    _panaboBarangayCentroids.forEach((barangay, coords) {
      final dist = _haversineKm(lat, lng, coords[0], coords[1]);
      if (dist < minDist) {
        minDist = dist;
        nearest = barangay;
      }
    });
    return minDist <= _maxBarangayMatchKm ? nearest : null;
  }

  static Future<String> reverseGeocode(double lat, double lng) async {
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;
        final parts = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim());

        final address = parts.join(', ');
        if (address.isNotEmpty) return address;
      }
    } catch (e) {
      print('⚠️ Reverse geocode error: $e');
    }
    return 'Panabo City, Davao del Norte';
  }

  /// Reverse-geocodes [lat]/[lng] into a barangay-focused location string,
  /// e.g. "Brgy. New Visayas, Panabo City" — instead of the full street
  /// address that [reverseGeocode] returns.
  ///
  /// Uses the device's own OS-level geocoder (Android/iOS) via the
  /// `geocoding` package, so no Google Maps API key or billing is required.
  static Future<String> reverseGeocodeBarangay(double lat, double lng) async {
    // 1. Outside the Panabo City boundary entirely — label it as such
    //    instead of guessing a barangay or falling through to a generic
    //    device-geocoded address.
    if (!_isWithinPanaboCity(lat, lng)) {
      return 'Outside Panabo City';
    }

    // 2. Within the city — resolve the nearest known barangay centroid.
    //    This is the primary, most reliable source for barangay-level
    //    detail in this region — mirrors tapping a pin on Google Maps and
    //    immediately seeing the barangay it falls within.
    final nearestBarangay = _nearestPanaboBarangay(lat, lng);
    if (nearestBarangay != null) {
      return 'Brgy. $nearestBarangay, Panabo City';
    }

    // 3. Fall back to the device's OS-level geocoder — should rarely be
    //    reached since step 1 already confirms the point is in the city.
    try {
      final placemarks = await geocoding.placemarkFromCoordinates(lat, lng);
      if (placemarks.isNotEmpty) {
        final p = placemarks.first;

        // On Philippine addresses, subLocality is the barangay.
        // subAdministrativeArea/locality is the city/municipality.
        final barangay = p.subLocality?.trim();
        final city = ((p.locality?.trim().isNotEmpty ?? false)
                ? p.locality
                : p.subAdministrativeArea)
            ?.trim();

        if (barangay != null && barangay.isNotEmpty) {
          return (city != null && city.isNotEmpty)
              ? 'Brgy. $barangay, $city'
              : 'Brgy. $barangay';
        }

        if (city != null && city.isNotEmpty) return city;

        // No barangay/city field populated — fall back to whatever we do
        // have, most specific first.
        final parts = [
          p.street,
          p.subLocality,
          p.locality,
          p.administrativeArea,
        ].where((s) => s != null && s.trim().isNotEmpty).map((s) => s!.trim());
        final address = parts.join(', ');
        if (address.isNotEmpty) return address;
      }
    } catch (e) {
      print('⚠️ Reverse geocode (barangay) error: $e');
    }

    // 4. Final fallback.
    return 'Panabo City, Davao del Norte';
  }

  static Future<Map<String, double>?> _getCurrentLocation() async {
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) return null;
    }
    if (perm == LocationPermission.deniedForever) return null;

    final pos = await Geolocator.getCurrentPosition(
      desiredAccuracy: LocationAccuracy.high,
    ).timeout(const Duration(seconds: 10));

    return {'latitude': pos.latitude, 'longitude': pos.longitude};
  }

  static String _generateReportId(String type) {
    const prefix = {
      'crime': 'CRM',
      'medical': 'MED',
      'fire': 'FIR',
      'flood': 'FLD',
      'accident': 'ACC',
      'other': 'OTH',
      'shake': 'SHK',
      'bubble': 'BBL',
    };
    final rand = Random();
    final ms = DateTime.now().millisecondsSinceEpoch;
    final suffix = List.generate(6, (_) => rand.nextInt(36).toRadixString(36))
        .join()
        .toUpperCase();
    return '${prefix[type] ?? 'RPT'}-$ms-$suffix';
  }

  static String _formatDate(DateTime dt) => '${dt.month}/${dt.day}/${dt.year} '
      '${dt.hour.toString().padLeft(2, '0')}:'
      '${dt.minute.toString().padLeft(2, '0')}:'
      '${dt.second.toString().padLeft(2, '0')}';
}
