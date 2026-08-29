import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/animated_refresh_button.dart';
import '../../../core/widgets/map_surface_guard.dart';
import '../../../services/emergency_report_service.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// MemberDirectionsScreen
//
// Opens a full-screen Google Map showing:
//   • The current user's live position (blue "You" marker)
//   • The family member's last known position (red marker)
//   • A real road-route polyline fetched from Google Directions API
//   • A bottom info panel with distance, duration, and action buttons
//
// Usage:
//   Navigator.push(context, MaterialPageRoute(
//     builder: (_) => MemberDirectionsScreen(
//       memberName: 'Maria',
//       memberRole: 'Mother',
//       memberLat:  14.1234,
//       memberLng:  121.4567,
//       locationUpdated: '2/26/2026 10:32:11',
//       isOnline: true,
//     ),
//   ));
// ═══════════════════════════════════════════════════════════════════════════════

class MemberDirectionsScreen extends StatefulWidget {
  final String memberName;
  final String memberRole;
  final double memberLat;
  final double memberLng;
  final String locationUpdated;
  final bool isOnline;

  const MemberDirectionsScreen({
    super.key,
    required this.memberName,
    required this.memberLat,
    required this.memberLng,
    this.memberRole = '',
    this.locationUpdated = '',
    this.isOnline = false,
  });

  @override
  State<MemberDirectionsScreen> createState() => _MemberDirectionsScreenState();
}

class _MemberDirectionsScreenState extends State<MemberDirectionsScreen>
    with WidgetsBindingObserver {
  // ── Google Maps ───────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  MapType _mapType = MapType.normal;
  final _mapGuard = MapSurfaceGuard();

  // ── Route data ────────────────────────────────────────────────────────────
  LatLng? _myPosition;
  Set<Marker> _markers = {};
  Set<Polyline> _polylines = {};

  // ── UI state ──────────────────────────────────────────────────────────────
  bool _isLoadingLocation = true;
  bool _isLoadingRoute = false;
  String _distance = '';
  String _duration = '';
  String _statusMessage = 'Getting your location…';
  String _selectedMode = 'driving'; // driving | walking | bicycling

  // Reverse-geocoded place name for widget.memberLat/Lng — shown instead of
  // raw coordinates, same as tapping a pin in Google Maps shows a place
  // name rather than a lat/lng pair.
  String _memberAddress = '';
  bool _isLoadingAddress = true;

  // Google API key (same one used in the project)
  static const String _apiKey = 'AIzaSyCJqRDB6viJn-uCAtIvN1_j4HRsvVs5y5w';

  // ── Icons for travel mode ─────────────────────────────────────────────────
  static const _modes = [
    {'key': 'driving', 'label': 'Drive', 'icon': Icons.directions_car},
    {'key': 'walking', 'label': 'Walk', 'icon': Icons.directions_walk},
    {'key': 'bicycling', 'label': 'Bicycle', 'icon': Icons.directions_bike},
  ];

  // ══════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _start();
    _resolveMemberAddress();
  }

  Future<void> _resolveMemberAddress() async {
    // Panabo City street data is spotty enough that the device's raw
    // reverse geocoder often returns a Plus Code ("7MPP+77X, ...") instead
    // of a real place name — reverseGeocodeBarangay() matches against known
    // barangay centroids instead, same fix already applied to emergency
    // report locations.
    final address = await EmergencyReportService.reverseGeocodeBarangay(
      widget.memberLat,
      widget.memberLng,
    );
    if (!mounted) return;
    setState(() {
      _memberAddress = address;
      _isLoadingAddress = false;
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
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
  // Initialisation
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _start() async {
    // 1. Get current location
    final pos = await _getCurrentPosition();
    if (!mounted) return;

    if (pos == null) {
      setState(() {
        _isLoadingLocation = false;
        _statusMessage = 'Could not get your GPS location.\n'
            'Make sure location permission is granted.';
      });
      _placeMarkers(userPos: null);
      return;
    }

    setState(() {
      _myPosition = pos;
      _isLoadingLocation = false;
      _statusMessage = 'Calculating route…';
    });

    _placeMarkers(userPos: pos);
    _fitCamera();

    // 2. Fetch the driving route
    await _fetchRoute();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // GPS
  // ══════════════════════════════════════════════════════════════════════════

  Future<LatLng?> _getCurrentPosition() async {
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) {
        perm = await Geolocator.requestPermission();
        if (perm == LocationPermission.denied) return null;
      }
      if (perm == LocationPermission.deniedForever) return null;

      final pos = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));

      return LatLng(pos.latitude, pos.longitude);
    } catch (e) {
      debugPrint('❌ GPS error: $e');
      return null;
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Markers
  // ══════════════════════════════════════════════════════════════════════════

  void _placeMarkers({required LatLng? userPos}) {
    final dest = LatLng(widget.memberLat, widget.memberLng);
    final markers = <Marker>{};

    // ── Destination marker (family member) ───────────────────────────────
    markers.add(Marker(
      markerId: const MarkerId('member'),
      position: dest,
      icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueRed),
      infoWindow: InfoWindow(
        title: widget.memberName,
        snippet: widget.memberRole.isNotEmpty ? widget.memberRole : null,
      ),
    ));

    // ── Origin marker (current user) ─────────────────────────────────────
    if (userPos != null) {
      markers.add(Marker(
        markerId: const MarkerId('me'),
        position: userPos,
        icon: BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: const InfoWindow(title: 'You are here'),
      ));
    }

    if (mounted) setState(() => _markers = markers);
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Camera
  // ══════════════════════════════════════════════════════════════════════════

  void _fitCamera() {
    if (_mapController == null) return;
    final dest = LatLng(widget.memberLat, widget.memberLng);

    if (_myPosition == null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(CameraPosition(target: dest, zoom: 15)),
      );
      return;
    }

    // Expand bounds to include both points with 80 px padding
    final bounds = _latLngBounds(_myPosition!, dest);
    _mapController!.animateCamera(
      CameraUpdate.newLatLngBounds(bounds, 80),
    );
  }

  LatLngBounds _latLngBounds(LatLng a, LatLng b) {
    return LatLngBounds(
      southwest:
          LatLng(min(a.latitude, b.latitude), min(a.longitude, b.longitude)),
      northeast:
          LatLng(max(a.latitude, b.latitude), max(a.longitude, b.longitude)),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Google Directions API
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _fetchRoute() async {
    if (_myPosition == null) return;

    if (mounted) {
      setState(() {
        _isLoadingRoute = true;
        _statusMessage = 'Calculating route…';
        _polylines = {};
      });
    }

    final origin = '${_myPosition!.latitude},${_myPosition!.longitude}';
    final destination = '${widget.memberLat},${widget.memberLng}';
    final url = Uri.parse(
      'https://maps.googleapis.com/maps/api/directions/json'
      '?origin=$origin'
      '&destination=$destination'
      '&mode=$_selectedMode'
      '&key=$_apiKey',
    );

    try {
      final resp = await http.get(url).timeout(const Duration(seconds: 15));
      if (!mounted) return;

      if (resp.statusCode == 200) {
        final data = json.decode(resp.body) as Map<String, dynamic>;
        final status = data['status']?.toString() ?? '';

        if (status == 'OK') {
          final routes = data['routes'] as List;
          if (routes.isNotEmpty) {
            final leg = routes[0]['legs'][0];
            final distance = leg['distance']['text']?.toString() ?? '';
            final duration = leg['duration']['text']?.toString() ?? '';
            final encodedPoly =
                routes[0]['overview_polyline']['points']?.toString() ?? '';
            final pts = _decodePolyline(encodedPoly);

            setState(() {
              _distance = distance;
              _duration = duration;
              _statusMessage = '';
              _polylines = {
                Polyline(
                  polylineId: const PolylineId('route'),
                  points: pts,
                  color: AppColors.primary,
                  width: 5,
                  startCap: Cap.roundCap,
                  endCap: Cap.roundCap,
                  jointType: JointType.round,
                ),
              };
              _isLoadingRoute = false;
            });

            // Refit camera to the full route
            if (pts.isNotEmpty) {
              final allPts = [
                _myPosition!,
                ...pts,
                LatLng(widget.memberLat, widget.memberLng)
              ];
              final bounds = _boundsFromList(allPts);
              _mapController
                  ?.animateCamera(CameraUpdate.newLatLngBounds(bounds, 80));
            }
            return;
          }
        }

        // API returned an error status (ZERO_RESULTS, REQUEST_DENIED, etc.)
        setState(() {
          _isLoadingRoute = false;
          _statusMessage = status == 'ZERO_RESULTS'
              ? 'No road route found between these two locations.'
              : 'Directions error: $status';
        });
      } else {
        setState(() {
          _isLoadingRoute = false;
          _statusMessage = 'Server error ${resp.statusCode}. Please retry.';
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _isLoadingRoute = false;
          _statusMessage = 'Could not load route. Check your connection.';
        });
      }
      debugPrint('❌ Directions API error: $e');
    }
  }

  // ── Google Encoded Polyline decoder ───────────────────────────────────────
  // Standard algorithm: https://developers.google.com/maps/documentation/utilities/polylinealgorithm

  List<LatLng> _decodePolyline(String encoded) {
    final result = <LatLng>[];
    int index = 0, lat = 0, lng = 0;

    while (index < encoded.length) {
      int b, shift = 0, result0 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result0 |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLat = ((result0 & 1) != 0 ? ~(result0 >> 1) : (result0 >> 1));
      lat += dLat;

      shift = 0;
      result0 = 0;
      do {
        b = encoded.codeUnitAt(index++) - 63;
        result0 |= (b & 0x1F) << shift;
        shift += 5;
      } while (b >= 0x20);
      final dLng = ((result0 & 1) != 0 ? ~(result0 >> 1) : (result0 >> 1));
      lng += dLng;

      result.add(LatLng(lat / 1e5, lng / 1e5));
    }
    return result;
  }

  LatLngBounds _boundsFromList(List<LatLng> pts) {
    double s = pts.first.latitude, n = pts.first.latitude;
    double w = pts.first.longitude, e = pts.first.longitude;
    for (final p in pts) {
      if (p.latitude < s) s = p.latitude;
      if (p.latitude > n) n = p.latitude;
      if (p.longitude < w) w = p.longitude;
      if (p.longitude > e) e = p.longitude;
    }
    return LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e));
  }

  // ══════════════════════════════════════════════════════════════════════════
  // External maps launchers
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _openGoogleMapsNavigation() async {
    final appUri = Uri.parse(
        'google.navigation:q=${widget.memberLat},${widget.memberLng}&mode=d');
    final webUri = Uri.parse('https://www.google.com/maps/dir/?api=1'
        '&destination=${widget.memberLat},${widget.memberLng}'
        '&travelmode=driving');

    if (await canLaunchUrl(appUri)) {
      await launchUrl(appUri);
    } else if (await canLaunchUrl(webUri)) {
      await launchUrl(webUri, mode: LaunchMode.externalApplication);
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // ── Google Map ─────────────────────────────────────────────────
          GoogleMap(
            key: ValueKey('map_surface_${_mapGuard.generation}'),
            initialCameraPosition: CameraPosition(
              target: LatLng(widget.memberLat, widget.memberLng),
              zoom: 14,
            ),
            mapType: _mapType,
            markers: _markers,
            polylines: _polylines,
            myLocationEnabled: false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled: false,
            compassEnabled: true,
            mapToolbarEnabled: false,
            onMapCreated: (controller) {
              _mapController = controller;
              _fitCamera();
            },
          ),

          // ── Top bar ────────────────────────────────────────────────────
          _buildTopBar(),

          // ── Loading overlay (GPS) ──────────────────────────────────────
          if (_isLoadingLocation)
            _buildLoadingOverlay('Getting your location…'),

          // ── Bottom info panel ──────────────────────────────────────────
          if (!_isLoadingLocation) _buildBottomPanel(),

          // ── Map type FAB ───────────────────────────────────────────────
          _buildMapTypeFab(),
        ],
      ),
    );
  }

  // ── Top bar ────────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.13),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            children: [
              // Back
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  padding: const EdgeInsets.all(6),
                  decoration: BoxDecoration(
                    color: AppColors.lightGrey,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: const Icon(Icons.arrow_back,
                      color: AppColors.secondary, size: 20),
                ),
              ),
              const SizedBox(width: 10),

              // Avatar + name
              CircleAvatar(
                radius: 18,
                backgroundColor: AppColors.primary.withOpacity(0.15),
                child: Text(
                  widget.memberName[0].toUpperCase(),
                  style: const TextStyle(
                      color: AppColors.primary,
                      fontWeight: FontWeight.bold,
                      fontSize: 14),
                ),
              ),
              const SizedBox(width: 10),

              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Directions to ${widget.memberName}',
                      style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Row(
                      children: [
                        Container(
                          width: 7,
                          height: 7,
                          decoration: BoxDecoration(
                            color: widget.isOnline ? Colors.green : Colors.grey,
                            shape: BoxShape.circle,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Text(
                          widget.isOnline
                              ? 'Online now'
                              : 'Last seen: ${widget.locationUpdated}',
                          style: TextStyle(
                              fontSize: 10,
                              color: widget.isOnline
                                  ? Colors.green
                                  : AppColors.grey),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Bottom panel ───────────────────────────────────────────────────────────

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 16,
              offset: const Offset(0, -4),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Drag handle ──────────────────────────────────────────────
            Center(
              child: Container(
                margin: const EdgeInsets.only(top: 10, bottom: 4),
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.lightGrey,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // ── Travel mode selector ─────────────────────────────
                  _buildTravelModeSelector(),
                  const SizedBox(height: 12),

                  // ── Route info ───────────────────────────────────────
                  _buildRouteInfo(),
                  const SizedBox(height: 14),

                  // ── Member location chip ─────────────────────────────
                  _buildLocationChip(),
                  const SizedBox(height: 14),

                  // ── Action buttons ───────────────────────────────────
                  _buildActionButtons(),
                  SizedBox(height: MediaQuery.of(context).padding.bottom + 16),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Travel mode selector ─────────────────────────────────────────────────

  Widget _buildTravelModeSelector() {
    return Row(
      children: _modes.map((mode) {
        final key = mode['key'] as String;
        final label = mode['label'] as String;
        final icon = mode['icon'] as IconData;
        final selected = _selectedMode == key;

        return Expanded(
          child: GestureDetector(
            onTap: () async {
              if (_selectedMode == key) return;
              setState(() => _selectedMode = key);
              await _fetchRoute();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              margin: const EdgeInsets.symmetric(horizontal: 3),
              padding: const EdgeInsets.symmetric(vertical: 8),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.lightGrey,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Column(
                children: [
                  Icon(icon,
                      size: 20,
                      color: selected ? Colors.white : AppColors.grey),
                  const SizedBox(height: 2),
                  Text(
                    label,
                    style: TextStyle(
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        color: selected ? Colors.white : AppColors.grey),
                  ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Route info ─────────────────────────────────────────────────────────────

  Widget _buildRouteInfo() {
    if (_isLoadingRoute) {
      return const Row(
        children: [
          SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  color: AppColors.primary, strokeWidth: 2)),
          SizedBox(width: 10),
          Text('Calculating route…',
              style: TextStyle(fontSize: 13, color: AppColors.textLight)),
        ],
      );
    }

    if (_statusMessage.isNotEmpty && _distance.isEmpty) {
      return Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.orange.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.orange.withOpacity(0.3)),
        ),
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 18),
            const SizedBox(width: 8),
            Expanded(
              child: Text(_statusMessage,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textLight)),
            ),
            AnimatedRefreshButton(
              onRefresh: _fetchRoute,
              color: AppColors.primary,
              size: 20,
            ),
          ],
        ),
      );
    }

    if (_distance.isNotEmpty && _duration.isNotEmpty) {
      return Row(
        children: [
          // Distance
          Expanded(
            child: _infoTile(
              icon: Icons.straighten,
              label: 'Distance',
              value: _distance,
              color: AppColors.primary,
            ),
          ),
          const SizedBox(width: 10),
          // Duration
          Expanded(
            child: _infoTile(
              icon: Icons.access_time,
              label: 'Est. Time',
              value: _duration,
              color: Colors.orange,
            ),
          ),
        ],
      );
    }

    return const SizedBox.shrink();
  }

  Widget _infoTile({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withOpacity(0.07),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          const SizedBox(width: 8),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  style: const TextStyle(fontSize: 10, color: AppColors.grey)),
              Text(value,
                  style: TextStyle(
                      fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            ],
          ),
        ],
      ),
    );
  }

  // ── Location chip ─────────────────────────────────────────────────────────

  Widget _buildLocationChip() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Icon(Icons.location_on, color: AppColors.primary, size: 18),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${widget.memberName}\'s Location',
                  style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary),
                ),
                Text(
                  _isLoadingAddress
                      ? 'Locating address…'
                      : (_memberAddress.isNotEmpty
                          ? _memberAddress
                          : 'Address unavailable'),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 11,
                      color: AppColors.textLight),
                ),
                if (widget.locationUpdated.isNotEmpty)
                  Text(
                    'Updated: ${widget.locationUpdated}',
                    style: const TextStyle(fontSize: 9, color: AppColors.grey),
                  ),
              ],
            ),
          ),
          // Online status dot
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
            decoration: BoxDecoration(
              color: widget.isOnline
                  ? Colors.green.withOpacity(0.1)
                  : Colors.grey.withOpacity(0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: widget.isOnline ? Colors.green : Colors.grey,
                  ),
                ),
                const SizedBox(width: 4),
                Text(
                  widget.isOnline ? 'Online' : 'Offline',
                  style: TextStyle(
                      fontSize: 9,
                      fontWeight: FontWeight.bold,
                      color: widget.isOnline ? Colors.green : AppColors.grey),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Action buttons ────────────────────────────────────────────────────────

  Widget _buildActionButtons() {
    return Row(
      children: [
        // Navigate in Google Maps app
        Expanded(
          flex: 3,
          child: SizedBox(
            height: 50,
            child: ElevatedButton.icon(
              onPressed: _openGoogleMapsNavigation,
              icon: const Icon(Icons.navigation, size: 20),
              label: const Text(
                'Open Navigation',
                style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14)),
                elevation: 2,
              ),
            ),
          ),
        ),
        const SizedBox(width: 10),
        // Refresh route
        SizedBox(
          height: 50,
          width: 50,
          child: AnimatedRefreshButton(
            onRefresh: _start,
            color: AppColors.secondary,
            size: 22,
            decoration: BoxDecoration(
              color: AppColors.lightGrey,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
      ],
    );
  }

  // ── Map type FAB ──────────────────────────────────────────────────────────

  Widget _buildMapTypeFab() {
    return Positioned(
      right: 12,
      bottom: 340,
      child: GestureDetector(
        onTap: () => setState(() {
          _mapType =
              _mapType == MapType.normal ? MapType.satellite : MapType.normal;
        }),
        child: Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: Colors.white,
            shape: BoxShape.circle,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.15),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          child: Icon(
            _mapType == MapType.normal
                ? Icons.satellite_alt
                : Icons.map_outlined,
            color: AppColors.secondary,
            size: 20,
          ),
        ),
      ),
    );
  }

  // ── Loading overlay ───────────────────────────────────────────────────────

  Widget _buildLoadingOverlay(String message) {
    return Container(
      color: Colors.white.withOpacity(0.88),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(color: AppColors.primary),
            const SizedBox(height: 16),
            Text(message,
                style:
                    const TextStyle(fontSize: 14, color: AppColors.textLight)),
          ],
        ),
      ),
    );
  }
}
