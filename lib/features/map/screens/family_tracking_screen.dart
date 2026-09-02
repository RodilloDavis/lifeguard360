import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:http/http.dart' as http;
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/animated_refresh_button.dart';
import '../../../core/widgets/map_surface_guard.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../../services/fcm_service.dart';
import '../../../services/emergency_report_service.dart';
import 'member_directions_screen.dart';

class FamilyTrackingScreen extends StatefulWidget {
  final String? currentUserId;
  final String? currentUserName;
  final String? highlightMemberId;
  final String? highlightMemberName;
  final double? initialLat;
  final double? initialLng;
  final String? emergencyType;

  const FamilyTrackingScreen({
    super.key,
    this.currentUserId,
    this.currentUserName,
    this.highlightMemberId,
    this.highlightMemberName,
    this.initialLat,
    this.initialLng,
    this.emergencyType,
  });

  @override
  State<FamilyTrackingScreen> createState() => _FamilyTrackingScreenState();
}

class _FamilyTrackingScreenState extends State<FamilyTrackingScreen>
    with WidgetsBindingObserver {
  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  MapType _mapType = MapType.normal;
  final _mapGuard = MapSurfaceGuard();

  static const _defaultCamera = CameraPosition(
    target: LatLng(12.8797, 121.7740),
    zoom: 6,
  );

  // ── Data ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _members = [];
  String _familyCode = '';
  String _familyName = '';
  bool _isLoading = true;
  String? _errorMessage;

  // ── Map overlays ─────────────────────────────────────────────────────────
  final Map<String, Marker> _markers = {};
  final Set<Polyline> _polylines = {};

  // ── Refresh ───────────────────────────────────────────────────────────────
  Timer? _refreshTimer;
  static const _refreshInterval = Duration(seconds: 10);
  // `mounted` alone isn't a reliable enough guard here: cancelling
  // _refreshTimer in dispose() stops FUTURE ticks, but a refresh cycle
  // already in flight (awaiting the network call) when the user navigates
  // away keeps running and can still resolve afterwards. When it does, it
  // was reaching the emergency-highlight path below and re-showing the
  // "X needs help!" SnackBar on whatever screen the user had already moved
  // to. This flag is set synchronously in dispose(), before anything else,
  // so every check against it is unambiguous.
  bool _disposed = false;

  // ── UI state ──────────────────────────────────────────────────────────────
  Map<String, dynamic>? _selectedMember;
  bool _showPanel = true;
  bool _hasHighlightedMember = false;
  // Gates the "fit all members into view" camera move to the very first
  // successful load — without this, the 10s refresh timer would re-fit
  // (and silently override) the zoom/pan the user just set manually.
  bool _hasFitInitialView = false;

  // Reverse-geocoded barangay name for whichever member is selected —
  // shown instead of raw lat/lng, same fix applied to MemberDirectionsScreen.
  String? _selectedMemberAddress;
  bool _isLoadingSelectedAddress = false;

  // ── Marker hues ───────────────────────────────────────────────────────────
  static const List<double> _markerHues = [
    BitmapDescriptor.hueAzure,
    BitmapDescriptor.hueViolet,
    BitmapDescriptor.hueOrange,
    BitmapDescriptor.hueRose,
    BitmapDescriptor.hueCyan,
    BitmapDescriptor.hueYellow,
    BitmapDescriptor.hueMagenta,
  ];

  static const List<Color> _memberColors = [
    AppColors.primary,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.teal,
    Colors.indigo,
    Colors.deepOrange,
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadAndTrack();
  }

  @override
  void dispose() {
    _disposed = true;
    // The "X needs help!" SnackBar is shown via the nearest ScaffoldMessenger,
    // which for a screen reached by Navigator.push resolves to the app-root
    // one — so without this, a SnackBar still mid-countdown when the user
    // navigates away (e.g. straight back to Notifications) keeps floating
    // over whatever screen they land on next instead of staying scoped to
    // this one.
    ScaffoldMessenger.of(context).clearSnackBars();
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused) {
      _mapGuard.onPaused();
    } else if (state == AppLifecycleState.resumed &&
        _mapGuard.onResumedShouldRecreate() &&
        mounted) {
      // Long enough backgrounded that Android may have reclaimed the map's
      // native surface — force a clean rebuild rather than trust it.
      setState(() => _mapController = null);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Data
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _loadAndTrack() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      if (widget.currentUserId == null) {
        _setError('User ID not available.');
        return;
      }

      final account = await FirebaseService.getUserById(widget.currentUserId!);
      if (account == null) {
        _setError('Account not found.');
        return;
      }

      // getUserById returns normalized lowercase keys
      final familyCode = account['familyCode']?.toString() ?? '';
      if (familyCode.isEmpty) {
        _setError(
            'You are not part of a family yet.\nJoin or create one from the Dashboard.');
        return;
      }

      final family = await FirebaseService.getFamilyByCode(familyCode);
      if (family == null) {
        _setError('Family data not found.');
        return;
      }

      if (mounted) {
        setState(() {
          _familyCode = familyCode;
          _familyName = family['FamilyName']?.toString() ?? '';
        });
      }

      await _refresh();

      _refreshTimer?.cancel();
      _refreshTimer = Timer.periodic(_refreshInterval, (_) => _refresh());

      // Handle emergency notification highlight after data is loaded
      _handleEmergencyHighlight();
    } catch (e) {
      _setError('Error: $e');
    }
  }

  Future<void> _handleEmergencyHighlight() async {
    // Guards re-entry here rather than only at each call site: this is
    // called both from _loadAndTrack() (unconditionally, right after the
    // first _refresh()) and from _refresh() itself (conditionally, on
    // every later poll tick) — the first successful call already sets
    // _hasHighlightedMember below, but _loadAndTrack()'s own call never
    // checked it, so the initial load fired this twice back-to-back: two
    // SnackBars, two 800ms-delayed callbacks, and (for a report opened
    // from Notifications, which always carries an emergencyType) two
    // "Emergency Alert" dialogs stacked on screen. Checking once here
    // covers both call sites instead of duplicating the guard at each one.
    if (_hasHighlightedMember) return;
    // If there's a highlight member ID and we have members loaded
    if (widget.highlightMemberId != null &&
        widget.highlightMemberId!.isNotEmpty &&
        _members.isNotEmpty) {
      // Find the highlighted member
      final highlightedMember = _members.firstWhere(
        (member) => member['userId']?.toString() == widget.highlightMemberId,
        orElse: () => {},
      );

      if (highlightedMember.isNotEmpty && !_disposed && mounted) {
        // Show a snackbar with emergency info
        final emergencyType = widget.emergencyType ?? 'emergency';
        final message = widget.highlightMemberName != null
            ? '⚠️ ${widget.highlightMemberName} needs help! (${emergencyType.toUpperCase()})'
            : '⚠️ Emergency alert from family member!';

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            backgroundColor: AppColors.danger,
            duration: const Duration(seconds: 5),
            action: SnackBarAction(
              label: 'LOCATE',
              textColor: Colors.white,
              onPressed: () {
                _selectMember(highlightedMember, preserveZoom: false);
                _flyTo(highlightedMember, preserveZoom: false);
              },
            ),
          ),
        );

        // Automatically select and center on the highlighted member after a short delay
        Future.delayed(const Duration(milliseconds: 800), () {
          if (!_disposed && mounted) {
            _selectMember(highlightedMember, preserveZoom: false);
            _flyTo(highlightedMember, preserveZoom: false);

            // Show a dialog for emergency if needed
            if (widget.emergencyType != null &&
                widget.emergencyType!.isNotEmpty) {
              _showEmergencyDialog(highlightedMember);
            }
          }
        });

        _hasHighlightedMember = true;
      }
    } else if (widget.initialLat != null &&
        widget.initialLng != null &&
        _mapController != null) {
      // If there's initial coordinates but no member ID, center on that location
      Future.delayed(const Duration(milliseconds: 500), () {
        if (!_disposed && mounted && _mapController != null) {
          _mapController!.animateCamera(
            CameraUpdate.newCameraPosition(
              CameraPosition(
                target: LatLng(widget.initialLat!, widget.initialLng!),
                zoom: 15,
              ),
            ),
          );
        }
      });
    }
  }

  void _showEmergencyDialog(Map<String, dynamic> member) {
    final memberName = member['name']?.toString() ??
        widget.highlightMemberName ??
        'Family Member';
    final emergencyType = widget.emergencyType ?? 'Emergency';
    // Captured from the outer (screen) context, not the dialog's — the
    // dialog already restates what the SnackBar said, so once the user has
    // acknowledged it there's no need for the SnackBar to keep counting
    // down underneath.
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: AppColors.danger),
            const SizedBox(width: 8),
            const Text('Emergency Alert'),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '$memberName has triggered a $emergencyType alert!',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            const Text(
              'Their current location is displayed on the map. Please check on them immediately.',
              style: TextStyle(fontSize: 12, color: AppColors.textLight),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              messenger.clearSnackBars();
            },
            child: const Text('OK', style: TextStyle(color: AppColors.primary)),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              messenger.clearSnackBars();
              _sendHelpForMember(member);
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.danger,
              foregroundColor: Colors.white,
            ),
            child: const Text('Send Help'),
          ),
        ],
      ),
    );
  }

  Future<void> _refresh() async {
    if (_familyCode.isEmpty || _disposed) return;
    try {
      // throwOnError so a dropped poll actually reaches the catch block
      // below instead of silently resolving as an empty list — which would
      // otherwise wipe every member's live location off the map on a single
      // network hiccup.
      final members = await FirebaseService.getFamilyMembersWithLocations(
          _familyCode,
          throwOnError: true);
      // The user may have navigated away while that request was in flight —
      // _refreshTimer.cancel() in dispose() only stops FUTURE ticks, not
      // this already-running one, so this check has to happen before
      // touching State at all, including the emergency-highlight re-trigger
      // below (which would otherwise re-show its SnackBar on whatever
      // screen the user has since moved to).
      if (_disposed || !mounted) return;
      setState(() {
        _members = members;
        _isLoading = false;
      });
      await _rebuildMapOverlays(members);
      if (_disposed || !mounted) return;

      // If we haven't highlighted yet and there's a member to highlight, try again
      if (!_hasHighlightedMember &&
          widget.highlightMemberId != null &&
          members.isNotEmpty) {
        await _handleEmergencyHighlight();
      }
    } catch (e) {
      if (!_disposed && mounted) setState(() => _isLoading = false);
      debugPrint('❌ FamilyTracking refresh error: $e');
    }
  }

  void _setError(String msg) {
    if (mounted) {
      setState(() {
        _errorMessage = msg;
        _isLoading = false;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Map overlays
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _rebuildMapOverlays(List<Map<String, dynamic>> members) async {
    final newMarkers = <String, Marker>{};
    final latLngs = <LatLng>[];
    int colorIdx = 0;

    for (int i = 0; i < members.length; i++) {
      final m = members[i];
      final lat = (m['latitude'] as num?)?.toDouble();
      final lng = (m['longitude'] as num?)?.toDouble();
      if (lat == null || lng == null) continue;

      final pos = LatLng(lat, lng);
      latLngs.add(pos);

      final id = m['userId']?.toString() ?? 'member_$i';
      final name = m['name']?.toString() ?? 'Member';
      final role = m['role']?.toString() ?? '';
      final isMe = id == widget.currentUserId;
      final isHighlighted = id == widget.highlightMemberId;

      // Custom marker color for highlighted member
      double hue;
      if (isHighlighted) {
        hue = BitmapDescriptor.hueRed; // Red for emergency
      } else if (isMe) {
        hue = BitmapDescriptor.hueGreen;
      } else {
        hue = _markerHues[colorIdx % _markerHues.length];
      }

      if (!isMe && !isHighlighted) colorIdx++;

      newMarkers[id] = Marker(
        markerId: MarkerId(id),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: isHighlighted
              ? '$name (⚠️ EMERGENCY)'
              : isMe
                  ? '$name (You)'
                  : name,
          snippet: isHighlighted
              ? '${widget.emergencyType?.toUpperCase() ?? 'EMERGENCY'} - Needs immediate assistance!'
              : role.isNotEmpty
                  ? role
                  : null,
        ),
        onTap: () => _selectMember(m),
      );
    }

    final newPolylines = <Polyline>{};
    if (latLngs.length >= 2) {
      newPolylines.add(Polyline(
        polylineId: const PolylineId('family_link'),
        points: latLngs,
        color: AppColors.primary.withOpacity(0.35),
        width: 2,
        patterns: [PatternItem.dash(20), PatternItem.gap(10)],
      ));
    }

    if (!mounted) return;
    setState(() {
      _markers
        ..clear()
        ..addAll(newMarkers);
      _polylines
        ..clear()
        ..addAll(newPolylines);
    });

    if (_mapController == null) return;

    // If there's a highlighted member, center on them immediately
    if (widget.highlightMemberId != null && !_hasHighlightedMember) {
      final highlightedMember = members.firstWhere(
        (m) => m['userId']?.toString() == widget.highlightMemberId,
        orElse: () => {},
      );

      final lat = (highlightedMember['latitude'] as num?)?.toDouble();
      final lng = (highlightedMember['longitude'] as num?)?.toDouble();

      if (lat != null && lng != null) {
        _mapController!.animateCamera(
          CameraUpdate.newCameraPosition(
            CameraPosition(target: LatLng(lat, lng), zoom: 16),
          ),
        );
        return;
      }
    }

    // Only auto-fit the camera the very first time we have something to
    // show it — every subsequent call (e.g. the 10s refresh timer ticking)
    // must leave the user's own pan/zoom alone.
    if (_hasFitInitialView) return;

    if (latLngs.length >= 2) {
      _hasFitInitialView = true;
      _mapController!
          .animateCamera(CameraUpdate.newLatLngBounds(_bounds(latLngs), 80));
    } else if (latLngs.length == 1) {
      _hasFitInitialView = true;
      _mapController!.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: latLngs.first, zoom: 15)));
    } else if (widget.initialLat != null && widget.initialLng != null) {
      _hasFitInitialView = true;
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(widget.initialLat!, widget.initialLng!),
            zoom: 15,
          ),
        ),
      );
    }
  }

  LatLngBounds _bounds(List<LatLng> pts) {
    double s = pts.first.latitude,
        n = pts.first.latitude,
        w = pts.first.longitude,
        e = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < s) s = p.latitude;
      if (p.latitude > n) n = p.latitude;
      if (p.longitude < w) w = p.longitude;
      if (p.longitude > e) e = p.longitude;
    }
    return LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Interaction
  // ══════════════════════════════════════════════════════════════════════════

  // preserveZoom=true (the default, used by every ordinary tap) pans to the
  // member without touching whatever zoom level the user is currently at.
  // preserveZoom=false is reserved for the one-time "jump to an emergency
  // when this screen first opens" framing in _handleEmergencyHighlight —
  // that's initial-load framing, not an automatic zoom while browsing.
  void _selectMember(Map<String, dynamic> m, {bool preserveZoom = true}) {
    _setSelectedMember(m);
    final lat = (m['latitude'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null || _mapController == null) return;
    _mapController!.animateCamera(
      preserveZoom
          ? CameraUpdate.newLatLng(LatLng(lat, lng))
          : CameraUpdate.newCameraPosition(
              CameraPosition(target: LatLng(lat, lng), zoom: 16)),
    );
  }

  void _flyTo(Map<String, dynamic> m, {bool preserveZoom = true}) {
    final lat = (m['latitude'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null || _mapController == null) return;
    _mapController!.animateCamera(
      preserveZoom
          ? CameraUpdate.newLatLng(LatLng(lat, lng))
          : CameraUpdate.newCameraPosition(
              CameraPosition(target: LatLng(lat, lng), zoom: 16)),
    );
    _setSelectedMember(m);
  }

  // Selects a member and resolves their barangay name from lat/lng — used
  // by both _selectMember and _flyTo so the detail card's address is never
  // stale/missing regardless of which path selected them.
  void _setSelectedMember(Map<String, dynamic> m) {
    setState(() {
      _selectedMember = m;
      _selectedMemberAddress = null;
      _isLoadingSelectedAddress = true;
    });

    final lat = (m['latitude'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      setState(() => _isLoadingSelectedAddress = false);
      return;
    }

    EmergencyReportService.reverseGeocodeBarangay(lat, lng).then((address) {
      // Ignore a stale result if the selection changed while this was in flight.
      if (!mounted || _selectedMember?['userId']?.toString() != m['userId']?.toString()) {
        return;
      }
      setState(() {
        _selectedMemberAddress = address;
        _isLoadingSelectedAddress = false;
      });
    });
  }

  void _fitAll() {
    final pts = _members
        .where((m) => m['latitude'] != null && m['longitude'] != null)
        .map((m) => LatLng(
              (m['latitude'] as num).toDouble(),
              (m['longitude'] as num).toDouble(),
            ))
        .toList();
    if (pts.isEmpty || _mapController == null) return;
    if (pts.length == 1) {
      _mapController!.animateCamera(CameraUpdate.newCameraPosition(
          CameraPosition(target: pts.first, zoom: 15)));
    } else {
      _mapController!
          .animateCamera(CameraUpdate.newLatLngBounds(_bounds(pts), 80));
    }
  }

  // Forwards MEMBER's own alert/location to police/dispatchers — not the
  // current viewer's. "Send Help" is responding to someone else's
  // emergency, so it must carry the location of the person who actually
  // needs help (member['latitude']/['longitude'], their last known
  // position from the family map), never wherever the person tapping this
  // button happens to be standing. Mirrors ShakeSosAlertScreen's
  // _sendToPolice(), which does the same for shake-triggered alerts
  // reached via a push notification instead of this in-app dialog.
  Future<void> _sendHelpForMember(Map<String, dynamic> member) async {
    final reporterUserId = member['userId']?.toString() ?? '';
    final reporterName = member['name']?.toString() ??
        widget.highlightMemberName ??
        'Family Member';
    final lat = (member['latitude'] as num?)?.toDouble();
    final lng = (member['longitude'] as num?)?.toDouble();
    final emergencyType = widget.emergencyType ?? 'emergency';
    final locationAddress =
        (lat != null && lng != null) ? 'See map for exact location' : 'Location unavailable';

    final now = DateTime.now();
    final rand = Random();
    final suffix = List.generate(6, (_) => rand.nextInt(36).toRadixString(36))
        .join()
        .toUpperCase();
    final policeReportId = 'POL-${now.millisecondsSinceEpoch}-$suffix';
    final createdAt = '${now.month}/${now.day}/${now.year} '
        '${now.hour.toString().padLeft(2, '0')}:'
        '${now.minute.toString().padLeft(2, '0')}:'
        '${now.second.toString().padLeft(2, '0')}';

    final payload = <String, dynamic>{
      'ReportId': policeReportId,
      'ReportLabel': 'emergency-high-red',
      'EmergencyType': emergencyType,
      'Trigger': 'family_forwarded_to_police',
      'Status': 'Active',
      'Priority': 'critical',
      'AlertLevel': 'emergency-high-red',
      'ForwardedBy': widget.currentUserName ?? '',
      'ForwardedByUserId': widget.currentUserId ?? '',
      'ReporterName': reporterName,
      'ReporterUserId': reporterUserId,
      'FamilyCode': _familyCode,
      'CreatedAt': createdAt,
      'Timestamp': now.toIso8601String(),
      'Location': {
        'Latitude': lat,
        'Longitude': lng,
        'Address': locationAddress,
        'LastUpdated': createdAt,
      },
      'Details': {
        'type': emergencyType,
        'trigger': 'family_forwarded_to_police',
        'message': '$reporterName triggered a $emergencyType alert. '
            'Forwarded to police by ${widget.currentUserName ?? "a family member"}.',
        'alertLevel': 'emergency-high-red',
        'priority': 'critical',
      },
    };

    try {
      await http
          .put(
            Uri.parse('${FirebaseService.dbUrl}emergency-high-red/$policeReportId.json'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 15));

      await FcmService.sendNotificationToDispatchers(
        reporterName: reporterName,
        emergencyType: emergencyType,
        location: locationAddress,
        barangay: '',
        reportId: policeReportId,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("$reporterName's location sent to police / dispatchers."),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Failed to notify police: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  // Opens the full road-following route to whichever member is currently
  // selected — real Directions API polyline, distance/duration, travel
  // mode picker, all already built in MemberDirectionsScreen.
  void _navigateToSelectedMember() {
    final m = _selectedMember;
    if (m == null) return;
    final lat = (m['latitude'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${m['name'] ?? 'This member'} has not shared their location yet.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => MemberDirectionsScreen(
          memberName: m['name']?.toString() ?? 'Member',
          memberRole: m['role']?.toString() ?? '',
          memberLat: lat,
          memberLng: lng,
          locationUpdated: m['lastUpdated']?.toString() ?? '',
          isOnline: m['onlineStatus']?.toString() == 'Online',
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Column(
          children: [
            _buildAppBar(),
            Expanded(
              child: _isLoading
                  ? const Center(
                      child:
                          CircularProgressIndicator(color: AppColors.primary))
                  : _errorMessage != null
                      ? _buildErrorState()
                      : Stack(
                          children: [
                            _buildMap(),
                            if (_selectedMember != null) _buildDetailCard(),
                            _buildFabColumn(),
                          ],
                        ),
            ),
            if (!_isLoading && _errorMessage == null) _buildMembersPanel(),
            _buildNavigateButton(),
          ],
        ),
      ),
    );
  }

  // ── App bar ───────────────────────────────────────────────────────────────

  Widget _buildAppBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 6,
              offset: const Offset(0, 2))
        ],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.pop(context),
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                  color: AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(8)),
              child: const Icon(Icons.arrow_back_ios_new,
                  size: 16, color: AppColors.secondary),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: const BoxDecoration(
                color: AppColors.secondary, shape: BoxShape.circle),
            child: const Icon(Icons.security, color: Colors.white, size: 18),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Family Tracking',
                    style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary)),
                if (_familyName.isNotEmpty)
                  Text(_familyName,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textLight)),
              ],
            ),
          ),
          if (_members.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                      width: 6,
                      height: 6,
                      decoration: const BoxDecoration(
                          color: Colors.green, shape: BoxShape.circle)),
                  const SizedBox(width: 4),
                  Text(
                    '${_members.where((m) => m['latitude'] != null).length}/${_members.length}',
                    style: const TextStyle(
                        fontSize: 11,
                        color: Colors.green,
                        fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          const SizedBox(width: 8),
          AnimatedRefreshButton(
            onRefresh: _refresh,
            color: AppColors.secondary,
            size: 18,
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(8)),
          ),
        ],
      ),
    );
  }

  // ── Google Map ────────────────────────────────────────────────────────────

  Widget _buildMap() {
    return GoogleMap(
      key: ValueKey('map_surface_${_mapGuard.generation}'),
      initialCameraPosition: _defaultCamera,
      mapType: _mapType,
      markers: Set<Marker>.of(_markers.values),
      polylines: _polylines,
      myLocationEnabled: true,
      myLocationButtonEnabled: false,
      zoomControlsEnabled: false,
      compassEnabled: true,
      mapToolbarEnabled: false,
      onMapCreated: (c) {
        _mapController = c;
        if (_markers.isNotEmpty) _fitAll();
      },
      onTap: (_) => setState(() => _selectedMember = null),
    );
  }

  // ── FABs ─────────────────────────────────────────────────────────────────

  Widget _buildFabColumn() {
    return Positioned(
      right: 12,
      top: 12,
      child: Column(
        children: [
          _fab(
            icon: _mapType == MapType.normal
                ? Icons.satellite_alt
                : Icons.map_outlined,
            onTap: () => setState(() {
              _mapType = _mapType == MapType.normal
                  ? MapType.satellite
                  : MapType.normal;
            }),
          ),
          const SizedBox(height: 8),
          _fab(icon: Icons.fit_screen, onTap: _fitAll),
          const SizedBox(height: 8),
          _fab(
            icon: _showPanel ? Icons.keyboard_arrow_down : Icons.people,
            onTap: () => setState(() => _showPanel = !_showPanel),
          ),
        ],
      ),
    );
  }

  Widget _fab({required IconData icon, required VoidCallback onTap}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: Colors.white,
          shape: BoxShape.circle,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2))
          ],
        ),
        child: Icon(icon, color: AppColors.secondary, size: 18),
      ),
    );
  }

  // ── Detail card (tapped member) ───────────────────────────────────────────

  Widget _buildDetailCard() {
    final m = _selectedMember!;
    final name = m['name']?.toString() ?? 'Member';
    final role = m['role']?.toString() ?? '';
    final isMe = m['userId'] == widget.currentUserId;
    final isHighlighted = m['userId']?.toString() == widget.highlightMemberId;
    final lat = (m['latitude'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble();
    final lastUpdated = m['lastUpdated']?.toString() ?? '';

    return Positioned(
      top: 12,
      left: 12,
      right: 60,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color:
              isHighlighted ? AppColors.danger.withOpacity(0.1) : Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isHighlighted
              ? Border.all(color: AppColors.danger, width: 2)
              : null,
          boxShadow: [
            BoxShadow(
                color: Colors.black.withOpacity(0.14),
                blurRadius: 12,
                offset: const Offset(0, 4))
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: isHighlighted
                  ? AppColors.danger.withOpacity(0.2)
                  : AppColors.primary.withOpacity(0.15),
              child: Text(name[0].toUpperCase(),
                  style: TextStyle(
                      color:
                          isHighlighted ? AppColors.danger : AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 18)),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        isHighlighted
                            ? '$name (⚠️ EMERGENCY)'
                            : isMe
                                ? '$name (You)'
                                : name,
                        style: TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                            color: isHighlighted
                                ? AppColors.danger
                                : AppColors.secondary),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (role.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                            color: AppColors.primary.withOpacity(0.1),
                            borderRadius: BorderRadius.circular(6)),
                        child: Text(role,
                            style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold)),
                      ),
                    ]
                  ]),
                  const SizedBox(height: 4),
                  if (isHighlighted && widget.emergencyType != null)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: Text(
                        '${widget.emergencyType!.toUpperCase()} ALERT - Needs immediate assistance!',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.danger,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  if (lat != null && lng != null)
                    Text(
                      _isLoadingSelectedAddress
                          ? 'Locating address…'
                          : (_selectedMemberAddress?.isNotEmpty == true
                              ? _selectedMemberAddress!
                              : 'Address unavailable'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 11, color: AppColors.textLight),
                    )
                  else
                    const Text('No location data',
                        style: TextStyle(fontSize: 10, color: AppColors.grey)),
                  if (lastUpdated.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text('Updated: $lastUpdated',
                        style: const TextStyle(
                            fontSize: 9, color: AppColors.grey)),
                  ],
                ],
              ),
            ),
            GestureDetector(
              onTap: () => setState(() => _selectedMember = null),
              child: const Icon(Icons.close, size: 16, color: AppColors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Members panel ─────────────────────────────────────────────────────────

  Widget _buildMembersPanel() {
    return AnimatedContainer(
      duration: const Duration(milliseconds: 300),
      height: _showPanel ? 172 : 0,
      curve: Curves.easeInOut,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.08),
              blurRadius: 12,
              offset: const Offset(0, -3))
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Text('Member Status',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary)),
                const Spacer(),
                GestureDetector(
                  onTap: _fitAll,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10)),
                    child: const Text('Show All',
                        style: TextStyle(
                            fontSize: 11,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600)),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _members.isEmpty
                ? const Center(
                    child: Text('No members with location data',
                        style: TextStyle(
                            fontSize: 12, color: AppColors.textLight)))
                : ListView.builder(
                    scrollDirection: Axis.horizontal,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    itemCount: _members.length,
                    itemBuilder: (ctx, i) => _memberChip(_members[i], i),
                  ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }

  Widget _memberChip(Map<String, dynamic> m, int index) {
    final id = m['userId']?.toString() ?? '';
    final name = m['name']?.toString() ?? 'Member';
    final role = m['role']?.toString() ?? '';
    final isMe = id == widget.currentUserId;
    final isHighlighted = id == widget.highlightMemberId;
    final hasLoc = m['latitude'] != null && m['longitude'] != null;
    final isOnline = m['onlineStatus']?.toString() == 'Online';
    final isSelected = _selectedMember?['userId'] == id;
    final color = isHighlighted
        ? AppColors.danger
        : _memberColors[index % _memberColors.length];

    return GestureDetector(
      onTap: hasLoc ? () => _flyTo(m) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 104,
        margin: const EdgeInsets.only(right: 10, bottom: 4, top: 2),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isHighlighted
              ? AppColors.danger.withOpacity(0.15)
              : isSelected
                  ? AppColors.primary.withOpacity(0.1)
                  : AppColors.lightGrey,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
              color: isHighlighted
                  ? AppColors.danger
                  : isSelected
                      ? AppColors.primary
                      : Colors.transparent,
              width: isHighlighted ? 2 : 2),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 14,
                  backgroundColor: color.withOpacity(0.2),
                  child: Text(name[0].toUpperCase(),
                      style: TextStyle(
                          color: color,
                          fontWeight: FontWeight.bold,
                          fontSize: 11)),
                ),
                const Spacer(),
                Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(
                        color: isOnline ? Colors.green : AppColors.grey,
                        shape: BoxShape.circle)),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isHighlighted
                  ? '$name (⚠️)'
                  : isMe
                      ? '$name (You)'
                      : name,
              style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                  color: isHighlighted
                      ? AppColors.danger
                      : isSelected
                          ? AppColors.primary
                          : AppColors.secondary),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (role.isNotEmpty)
              Text(role,
                  style:
                      const TextStyle(fontSize: 9, color: AppColors.textLight)),
            const SizedBox(height: 2),
            Text(
                isHighlighted
                    ? '🚨 EMERGENCY'
                    : hasLoc
                        ? '📍 Located'
                        : 'No location',
                style: TextStyle(
                    fontSize: 9,
                    color: isHighlighted
                        ? AppColors.danger
                        : hasLoc
                            ? Colors.green
                            : AppColors.grey,
                    fontWeight: isHighlighted || hasLoc
                        ? FontWeight.bold
                        : FontWeight.normal)),
          ],
        ),
      ),
    );
  }

  // ── Navigate To button ───────────────────────────────────────────────────

  Widget _buildNavigateButton() {
    final selected = _selectedMember;
    final name = selected?['name']?.toString();
    final enabled = selected != null;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      color: Colors.white,
      child: SizedBox(
        width: double.infinity,
        height: 50,
        child: ElevatedButton.icon(
          onPressed: enabled ? _navigateToSelectedMember : null,
          icon: const Icon(Icons.navigation),
          label: Text(
            enabled ? 'Navigate To $name' : 'Select a family member to navigate',
            style: const TextStyle(
                fontSize: 15, fontWeight: FontWeight.bold, letterSpacing: 0.3),
            overflow: TextOverflow.ellipsis,
          ),
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.lightGrey,
            disabledForegroundColor: AppColors.grey,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
            elevation: enabled ? 4 : 0,
          ),
        ),
      ),
    );
  }

  // ── Error state ───────────────────────────────────────────────────────────

  Widget _buildErrorState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.location_off,
                size: 72, color: AppColors.grey.withOpacity(0.35)),
            const SizedBox(height: 20),
            Text(
              _errorMessage ?? 'Unable to load tracking',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14, color: AppColors.textLight, height: 1.6),
            ),
            const SizedBox(height: 28),
            ElevatedButton.icon(
              onPressed: _loadAndTrack,
              icon: const Icon(Icons.refresh, size: 18),
              label: const Text('Retry'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding:
                    const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
