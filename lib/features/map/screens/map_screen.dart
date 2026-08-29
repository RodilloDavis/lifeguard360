// import 'dart:async';
// import 'package:flutter/material.dart';
// import 'package:google_maps_flutter/google_maps_flutter.dart';
// import 'package:shared_preferences/shared_preferences.dart';
// import '../../../core/constants/app_colors.dart';
// import '../../../services/firebase_realtime_database.dart';
// import '../../../services/emergency_report_service.dart';
// import '../../notifications/screens/notification_screen.dart';

// class MapScreen extends StatefulWidget {
//   /// The current logged-in user's ID — used to highlight "You" on the map.
//   final String? userId;

//   /// The current logged-in user's display name.
//   final String? userName;

//   /// Optional — if provided, members are loaded directly from this code
//   /// without any extra lookup. If omitted, the screen looks up the code
//   /// via [userId] from the Accounts node.
//   final String? familyCode;

//   const MapScreen({
//     super.key,
//     this.userId,
//     this.userName,
//     this.familyCode,
//   });

//   @override
//   State<MapScreen> createState() => _MapScreenState();
// }

// class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
//   // ── Map ──────────────────────────────────────────────────────────────────
//   GoogleMapController? _mapController;
//   MapType _mapType = MapType.normal;

//   static const _defaultCamera = CameraPosition(
//     target: LatLng(12.8797, 121.7740),
//     zoom: 6,
//   );

//   // ── Data ─────────────────────────────────────────────────────────────────
//   List<Map<String, dynamic>> _members = [];
//   String _resolvedFamilyCode = '';
//   String _familyName = '';
//   bool _isLoading = true;
//   String? _errorMessage;

//   // ── Map overlays ─────────────────────────────────────────────────────────
//   final Map<String, Marker> _markers = {};
//   final Set<Polyline> _polylines = {};

//   // ── Auto-refresh ──────────────────────────────────────────────────────────
//   Timer? _refreshTimer;
//   static const _refreshInterval = Duration(seconds: 10);

//   // ── UI state ──────────────────────────────────────────────────────────────
//   Map<String, dynamic>? _selectedMember;
//   bool _showMemberList = true;

//   // ── Notification badge ──────────────────────────────────────────────────
//   int _unreadCount = 0;
//   Timer? _unreadTimer;

//   // ── Colours ───────────────────────────────────────────────────────────────
//   static const List<double> _markerHues = [
//     BitmapDescriptor.hueAzure,
//     BitmapDescriptor.hueViolet,
//     BitmapDescriptor.hueOrange,
//     BitmapDescriptor.hueRose,
//     BitmapDescriptor.hueCyan,
//     BitmapDescriptor.hueYellow,
//     BitmapDescriptor.hueMagenta,
//   ];

//   static const List<Color> _chipColors = [
//     AppColors.primary,
//     Colors.purple,
//     Colors.orange,
//     Colors.pink,
//     Colors.teal,
//     Colors.indigo,
//     Colors.deepOrange,
//   ];

//   // ══════════════════════════════════════════════════════════════════════════
//   // Lifecycle
//   // ══════════════════════════════════════════════════════════════════════════

//   @override
//   void initState() {
//     super.initState();
//     WidgetsBinding.instance.addObserver(this);
//     _initialize();
//     _pollUnreadCount();
//   }

//   @override
//   void dispose() {
//     WidgetsBinding.instance.removeObserver(this);
//     _refreshTimer?.cancel();
//     _unreadTimer?.cancel();
//     _mapController?.dispose();
//     super.dispose();
//   }

//   // ══════════════════════════════════════════════════════════════════════════
//   // Notification badge
//   // ══════════════════════════════════════════════════════════════════════════

//   Future<void> _pollUnreadCount() async {
//     await _refreshUnreadCount();
//     _unreadTimer = Timer.periodic(
//       const Duration(seconds: 10),
//       (_) => _refreshUnreadCount(),
//     );
//   }

//   Future<void> _refreshUnreadCount() async {
//     try {
//       final prefs = await SharedPreferences.getInstance();
//       var familyCode = _resolvedFamilyCode;
//       if (familyCode.isEmpty) {
//         final account = await FirebaseService.getUserById(widget.userId ?? '');
//         familyCode = account?['familyCode']?.toString() ?? '';
//         if (familyCode.isNotEmpty && mounted) {
//           setState(() => _resolvedFamilyCode = familyCode);
//         }
//       }
//       if (familyCode.isEmpty) return;

//       final readIds = (prefs.getStringList('notif_read_ids') ?? []).toSet();
//       final deletedIds =
//           (prefs.getStringList('notif_deleted_ids') ?? []).toSet();

//       final reports = await EmergencyReportService.getFamilyReports(familyCode);
//       final unread = reports.where((r) {
//         final id = r['ReportId']?.toString() ?? '';
//         return !deletedIds.contains(id) && !readIds.contains(id);
//       }).length;

//       if (mounted) setState(() => _unreadCount = unread);
//     } catch (_) {}
//   }

//   void _navigateToNotifications() {
//     Navigator.push(
//       context,
//       MaterialPageRoute(
//         builder: (_) => NotificationScreen(
//           userId: widget.userId ?? '',
//           familyCode: _resolvedFamilyCode,
//         ),
//       ),
//     ).then((_) => _refreshUnreadCount());
//   }

//   // ══════════════════════════════════════════════════════════════════════════
//   // Data loading
//   // ══════════════════════════════════════════════════════════════════════════

//   Future<void> _initialize() async {
//     if (!mounted) return;
//     setState(() {
//       _isLoading = true;
//       _errorMessage = null;
//     });

//     try {
//       // ── Resolve the family code ──────────────────────────────────────────
//       String code = widget.familyCode?.trim() ?? '';

//       if (code.isEmpty) {
//         final uid = widget.userId?.trim() ?? '';
//         if (uid.isEmpty) {
//           _setError(
//             'No family code or user ID provided.\n'
//             'Please log in again.',
//           );
//           return;
//         }

//         final account = await FirebaseService.getUserById(uid);
//         if (account == null) {
//           _setError('Account not found. Please log in again.');
//           return;
//         }

//         code = account['familyCode']?.toString().trim() ?? '';
//         if (code.isEmpty) {
//           _setError(
//             'You are not part of a family yet.\n'
//             'Join or create a family from the Dashboard.',
//           );
//           return;
//         }
//       }

//       // ── Load family name ─────────────────────────────────────────────────
//       final family = await FirebaseService.getFamilyByCode(code);
//       if (family == null) {
//         _setError(
//           'Family not found for code "$code".\n'
//           'Please contact your family admin.',
//         );
//         return;
//       }

//       if (mounted) {
//         setState(() {
//           _resolvedFamilyCode = code;
//           _familyName = family['FamilyName']?.toString() ?? '';
//         });
//       }

//       // ── First location fetch ─────────────────────────────────────────────
//       await _refreshLocations();

//       // ── Start periodic refresh ───────────────────────────────────────────
//       _refreshTimer?.cancel();
//       _refreshTimer =
//           Timer.periodic(_refreshInterval, (_) => _refreshLocations());
//     } catch (e) {
//       _setError('Error loading map: $e');
//     }
//   }

//   Future<void> _refreshLocations() async {
//     if (_resolvedFamilyCode.isEmpty || !mounted) return;
//     try {
//       final members = await FirebaseService.getFamilyMembersWithLocations(
//           _resolvedFamilyCode);
//       if (!mounted) return;
//       setState(() {
//         _members = members;
//         _isLoading = false;
//       });
//       await _buildMarkersAndPolylines(members);
//     } catch (e) {
//       if (mounted) setState(() => _isLoading = false);
//       debugPrint('❌ MapScreen refresh error: $e');
//     }
//   }

//   void _setError(String msg) {
//     if (mounted) {
//       setState(() {
//         _errorMessage = msg;
//         _isLoading = false;
//       });
//     }
//   }

//   // ══════════════════════════════════════════════════════════════════════════
//   // Markers & Polylines
//   // ══════════════════════════════════════════════════════════════════════════

//   Future<void> _buildMarkersAndPolylines(
//       List<Map<String, dynamic>> members) async {
//     final newMarkers = <String, Marker>{};
//     final latLngs = <LatLng>[];
//     int colorIdx = 0;

//     for (int i = 0; i < members.length; i++) {
//       final m = members[i];
//       final lat = (m['latitude'] as num?)?.toDouble();
//       final lng = (m['longitude'] as num?)?.toDouble();
//       if (lat == null || lng == null) continue;

//       final pos = LatLng(lat, lng);
//       latLngs.add(pos);

//       final id = m['userId']?.toString() ?? 'member_$i';
//       final name = m['name']?.toString() ?? 'Member';
//       final role = m['role']?.toString() ?? '';
//       final isMe = id == (widget.userId ?? '');

//       final hue = isMe
//           ? BitmapDescriptor.hueGreen
//           : _markerHues[colorIdx % _markerHues.length];
//       if (!isMe) colorIdx++;

//       newMarkers[id] = Marker(
//         markerId: MarkerId(id),
//         position: pos,
//         icon: BitmapDescriptor.defaultMarkerWithHue(hue),
//         infoWindow: InfoWindow(
//           title: isMe ? '$name (You)' : name,
//           snippet: role.isNotEmpty ? role : null,
//         ),
//         onTap: () => _onMarkerTapped(m),
//       );
//     }

//     final polylines = <Polyline>{};
//     if (latLngs.length >= 2) {
//       polylines.add(Polyline(
//         polylineId: const PolylineId('family_link'),
//         points: latLngs,
//         color: AppColors.primary.withOpacity(0.4),
//         width: 2,
//         patterns: [PatternItem.dash(20), PatternItem.gap(10)],
//       ));
//     }

//     if (!mounted) return;
//     setState(() {
//       _markers
//         ..clear()
//         ..addAll(newMarkers);
//       _polylines
//         ..clear()
//         ..addAll(polylines);
//     });

//     _animateCameraToFit(latLngs);
//   }

//   void _animateCameraToFit(List<LatLng> pts) {
//     if (_mapController == null || pts.isEmpty) return;
//     if (pts.length == 1) {
//       _mapController!.animateCamera(
//         CameraUpdate.newCameraPosition(
//             CameraPosition(target: pts.first, zoom: 15)),
//       );
//     } else {
//       _mapController!.animateCamera(
//         CameraUpdate.newLatLngBounds(_boundsFrom(pts), 80),
//       );
//     }
//   }

//   LatLngBounds _boundsFrom(List<LatLng> pts) {
//     double s = pts.first.latitude,
//         n = pts.first.latitude,
//         w = pts.first.longitude,
//         e = pts.first.longitude;
//     for (final p in pts) {
//       if (p.latitude < s) s = p.latitude;
//       if (p.latitude > n) n = p.latitude;
//       if (p.longitude < w) w = p.longitude;
//       if (p.longitude > e) e = p.longitude;
//     }
//     return LatLngBounds(southwest: LatLng(s, w), northeast: LatLng(n, e));
//   }

//   // ══════════════════════════════════════════════════════════════════════════
//   // Interaction
//   // ══════════════════════════════════════════════════════════════════════════

//   void _onMarkerTapped(Map<String, dynamic> m) =>
//       setState(() => _selectedMember = m);

//   void _flyToMember(Map<String, dynamic> m) {
//     final lat = (m['latitude'] as num?)?.toDouble();
//     final lng = (m['longitude'] as num?)?.toDouble();
//     if (lat == null || lng == null || _mapController == null) return;
//     _mapController!.animateCamera(
//       CameraUpdate.newCameraPosition(
//           CameraPosition(target: LatLng(lat, lng), zoom: 16)),
//     );
//     setState(() => _selectedMember = m);
//   }

//   void _fitAllMembers() {
//     final pts = _members
//         .where((m) => m['latitude'] != null && m['longitude'] != null)
//         .map((m) => LatLng(
//               (m['latitude'] as num).toDouble(),
//               (m['longitude'] as num).toDouble(),
//             ))
//         .toList();
//     _animateCameraToFit(pts);
//   }

//   // ══════════════════════════════════════════════════════════════════════════
//   // Build
//   // ══════════════════════════════════════════════════════════════════════════

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.white,
//       body: SafeArea(
//         child: Stack(
//           children: [
//             _buildMap(),
//             _buildTopBar(),
//             if (!_isLoading && _errorMessage == null) ...[
//               _buildFabCluster(),
//               _buildBottomMemberPanel(),
//             ],
//             if (_selectedMember != null) _buildSelectedMemberCard(),
//             if (_isLoading) _buildLoadingOverlay(),
//             if (!_isLoading && _errorMessage != null) _buildErrorOverlay(),
//           ],
//         ),
//       ),
//     );
//   }

//   // ── Google Map ────────────────────────────────────────────────────────────

//   Widget _buildMap() {
//     return GoogleMap(
//       initialCameraPosition: _defaultCamera,
//       mapType: _mapType,
//       markers: Set<Marker>.of(_markers.values),
//       polylines: _polylines,
//       myLocationEnabled: true,
//       myLocationButtonEnabled: false,
//       zoomControlsEnabled: false,
//       compassEnabled: true,
//       mapToolbarEnabled: false,
//       onMapCreated: (c) {
//         _mapController = c;
//         if (_markers.isNotEmpty) _fitAllMembers();
//       },
//       onTap: (_) => setState(() => _selectedMember = null),
//     );
//   }

//   // ── Top Bar ───────────────────────────────────────────────────────────────

//   Widget _buildTopBar() {
//     final locatedCount = _members.where((m) => m['latitude'] != null).length;

//     return Positioned(
//       top: 12,
//       left: 12,
//       right: 12,
//       child: Container(
//         padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(16),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.12),
//               blurRadius: 12,
//               offset: const Offset(0, 4),
//             ),
//           ],
//         ),
//         child: Row(
//           children: [
//             // ── Back button ────────────────────────────────────────────────
//             GestureDetector(
//               onTap: () => Navigator.pop(context),
//               child: Container(
//                 padding: const EdgeInsets.all(6),
//                 decoration: BoxDecoration(
//                   color: AppColors.lightGrey,
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: const Icon(Icons.arrow_back,
//                     color: AppColors.secondary, size: 20),
//               ),
//             ),
//             const SizedBox(width: 10),
//             Container(
//               padding: const EdgeInsets.all(6),
//               decoration: const BoxDecoration(
//                 color: AppColors.secondary,
//                 shape: BoxShape.circle,
//               ),
//               child: const Icon(Icons.security, color: Colors.white, size: 18),
//             ),
//             const SizedBox(width: 8),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 mainAxisSize: MainAxisSize.min,
//                 children: [
//                   const Text(
//                     'Live Tracking',
//                     style: TextStyle(
//                       fontSize: 15,
//                       fontWeight: FontWeight.bold,
//                       color: AppColors.secondary,
//                     ),
//                   ),
//                   Text(
//                     _familyName.isNotEmpty
//                         ? _familyName
//                         : _resolvedFamilyCode.isNotEmpty
//                             ? 'Code: $_resolvedFamilyCode'
//                             : 'Loading…',
//                     style: const TextStyle(
//                         fontSize: 11, color: AppColors.textLight),
//                   ),
//                 ],
//               ),
//             ),
//             if (_members.isNotEmpty) ...[
//               Container(
//                 padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
//                 decoration: BoxDecoration(
//                   color: Colors.green.withOpacity(0.1),
//                   borderRadius: BorderRadius.circular(10),
//                 ),
//                 child: Row(
//                   mainAxisSize: MainAxisSize.min,
//                   children: [
//                     Container(
//                       width: 6,
//                       height: 6,
//                       decoration: const BoxDecoration(
//                         color: Colors.green,
//                         shape: BoxShape.circle,
//                       ),
//                     ),
//                     const SizedBox(width: 4),
//                     Text(
//                       '$locatedCount/${_members.length}',
//                       style: const TextStyle(
//                         fontSize: 10,
//                         color: Colors.green,
//                         fontWeight: FontWeight.bold,
//                       ),
//                     ),
//                   ],
//                 ),
//               ),
//               const SizedBox(width: 8),
//             ],
//             // ── Notification bell with badge ──────────────────────────────
//             Stack(
//               clipBehavior: Clip.none,
//               children: [
//                 IconButton(
//                   icon: const Icon(
//                     Icons.notifications_outlined,
//                     color: AppColors.secondary,
//                     size: 24,
//                   ),
//                   onPressed: _navigateToNotifications,
//                   padding: EdgeInsets.zero,
//                   constraints: const BoxConstraints(),
//                   tooltip: 'Notifications',
//                 ),
//                 if (_unreadCount > 0)
//                   Positioned(
//                     right: -2,
//                     top: -2,
//                     child: Container(
//                       padding: const EdgeInsets.all(3),
//                       decoration: const BoxDecoration(
//                         color: AppColors.danger,
//                         shape: BoxShape.circle,
//                       ),
//                       constraints:
//                           const BoxConstraints(minWidth: 16, minHeight: 16),
//                       child: Text(
//                         _unreadCount > 99 ? '99+' : '$_unreadCount',
//                         style: const TextStyle(
//                           color: Colors.white,
//                           fontSize: 9,
//                           fontWeight: FontWeight.bold,
//                           height: 1,
//                         ),
//                         textAlign: TextAlign.center,
//                       ),
//                     ),
//                   ),
//               ],
//             ),
//             const SizedBox(width: 4),
//             GestureDetector(
//               onTap: _refreshLocations,
//               child: Container(
//                 padding: const EdgeInsets.all(6),
//                 decoration: BoxDecoration(
//                   color: AppColors.lightGrey,
//                   borderRadius: BorderRadius.circular(8),
//                 ),
//                 child: const Icon(Icons.refresh,
//                     color: AppColors.secondary, size: 18),
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ── FAB Cluster ───────────────────────────────────────────────────────────

//   Widget _buildFabCluster() {
//     return AnimatedPositioned(
//       duration: const Duration(milliseconds: 300),
//       curve: Curves.easeInOut,
//       right: 12,
//       bottom: _showMemberList ? 196 : 24,
//       child: Column(
//         mainAxisSize: MainAxisSize.min,
//         children: [
//           _miniButton(
//             icon: _mapType == MapType.normal
//                 ? Icons.satellite_alt
//                 : Icons.map_outlined,
//             tooltip:
//                 _mapType == MapType.normal ? 'Satellite view' : 'Normal map',
//             onTap: () => setState(() {
//               _mapType = _mapType == MapType.normal
//                   ? MapType.satellite
//                   : MapType.normal;
//             }),
//           ),
//           const SizedBox(height: 8),
//           _miniButton(
//             icon: Icons.fit_screen,
//             tooltip: 'Fit all members',
//             onTap: _fitAllMembers,
//           ),
//           const SizedBox(height: 8),
//           _miniButton(
//             icon: _showMemberList
//                 ? Icons.keyboard_arrow_down
//                 : Icons.people_alt_outlined,
//             tooltip: _showMemberList ? 'Hide panel' : 'Show panel',
//             onTap: () => setState(() => _showMemberList = !_showMemberList),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _miniButton({
//     required IconData icon,
//     required String tooltip,
//     required VoidCallback onTap,
//   }) {
//     return Tooltip(
//       message: tooltip,
//       child: GestureDetector(
//         onTap: onTap,
//         child: Container(
//           width: 40,
//           height: 40,
//           decoration: BoxDecoration(
//             color: Colors.white,
//             shape: BoxShape.circle,
//             boxShadow: [
//               BoxShadow(
//                 color: Colors.black.withOpacity(0.15),
//                 blurRadius: 8,
//                 offset: const Offset(0, 2),
//               ),
//             ],
//           ),
//           child: Icon(icon, color: AppColors.secondary, size: 20),
//         ),
//       ),
//     );
//   }

//   // ── Bottom Member Panel ───────────────────────────────────────────────────

//   Widget _buildBottomMemberPanel() {
//     return AnimatedPositioned(
//       duration: const Duration(milliseconds: 300),
//       curve: Curves.easeInOut,
//       bottom: 0,
//       left: 0,
//       right: 0,
//       height: _showMemberList ? 184 : 0,
//       child: Container(
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.1),
//               blurRadius: 12,
//               offset: const Offset(0, -3),
//             ),
//           ],
//         ),
//         child: Column(
//           children: [
//             Padding(
//               padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
//               child: Row(
//                 children: [
//                   const Icon(Icons.people, color: AppColors.primary, size: 18),
//                   const SizedBox(width: 8),
//                   const Text(
//                     'Family Members',
//                     style: TextStyle(
//                       fontSize: 14,
//                       fontWeight: FontWeight.bold,
//                       color: AppColors.secondary,
//                     ),
//                   ),
//                   const Spacer(),
//                   GestureDetector(
//                     onTap: _fitAllMembers,
//                     child: Container(
//                       padding: const EdgeInsets.symmetric(
//                           horizontal: 10, vertical: 4),
//                       decoration: BoxDecoration(
//                         color: AppColors.primary.withOpacity(0.1),
//                         borderRadius: BorderRadius.circular(10),
//                       ),
//                       child: const Text(
//                         'Show All',
//                         style: TextStyle(
//                           fontSize: 11,
//                           color: AppColors.primary,
//                           fontWeight: FontWeight.w600,
//                         ),
//                       ),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 8),
//             Expanded(
//               child: _members.isEmpty
//                   ? const Center(
//                       child: Text(
//                         'No members with location data',
//                         style:
//                             TextStyle(fontSize: 12, color: AppColors.textLight),
//                       ),
//                     )
//                   : ListView.builder(
//                       scrollDirection: Axis.horizontal,
//                       padding: const EdgeInsets.symmetric(horizontal: 12),
//                       itemCount: _members.length,
//                       itemBuilder: (context, index) =>
//                           _buildMemberChip(_members[index], index),
//                     ),
//             ),
//             const SizedBox(height: 8),
//           ],
//         ),
//       ),
//     );
//   }

//   Widget _buildMemberChip(Map<String, dynamic> member, int index) {
//     final memberId = member['userId']?.toString() ?? '';
//     final name = member['name']?.toString() ?? 'Member';
//     final role = member['role']?.toString() ?? '';
//     final isMe = memberId == (widget.userId ?? '');
//     final hasLoc = member['latitude'] != null && member['longitude'] != null;
//     final isSelected = _selectedMember?['userId'] == memberId;
//     final color = _chipColors[index % _chipColors.length];

//     return GestureDetector(
//       onTap: hasLoc ? () => _flyToMember(member) : null,
//       child: AnimatedContainer(
//         duration: const Duration(milliseconds: 200),
//         width: 108,
//         margin: const EdgeInsets.only(right: 10, bottom: 4, top: 2),
//         padding: const EdgeInsets.all(10),
//         decoration: BoxDecoration(
//           color: isSelected
//               ? AppColors.primary.withOpacity(0.1)
//               : AppColors.lightGrey,
//           borderRadius: BorderRadius.circular(14),
//           border: Border.all(
//             color: isSelected ? AppColors.primary : Colors.transparent,
//             width: 2,
//           ),
//         ),
//         child: Column(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             Row(
//               children: [
//                 CircleAvatar(
//                   radius: 15,
//                   backgroundColor: color.withOpacity(0.2),
//                   child: Text(
//                     name[0].toUpperCase(),
//                     style: TextStyle(
//                         color: color,
//                         fontWeight: FontWeight.bold,
//                         fontSize: 12),
//                   ),
//                 ),
//                 const Spacer(),
//                 Container(
//                   width: 8,
//                   height: 8,
//                   decoration: BoxDecoration(
//                     color: hasLoc ? Colors.green : AppColors.grey,
//                     shape: BoxShape.circle,
//                   ),
//                 ),
//               ],
//             ),
//             const SizedBox(height: 6),
//             Text(
//               isMe ? '$name (You)' : name,
//               style: TextStyle(
//                 fontSize: 11,
//                 fontWeight: FontWeight.bold,
//                 color: isSelected ? AppColors.primary : AppColors.secondary,
//               ),
//               maxLines: 1,
//               overflow: TextOverflow.ellipsis,
//             ),
//             if (role.isNotEmpty)
//               Text(role,
//                   style:
//                       const TextStyle(fontSize: 9, color: AppColors.textLight)),
//             const SizedBox(height: 2),
//             Text(
//               hasLoc ? '📍 Located' : 'No location',
//               style: TextStyle(
//                 fontSize: 9,
//                 color: hasLoc ? Colors.green : AppColors.grey,
//                 fontWeight: hasLoc ? FontWeight.w600 : FontWeight.normal,
//               ),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ── Selected Member Card ──────────────────────────────────────────────────

//   Widget _buildSelectedMemberCard() {
//     final m = _selectedMember!;
//     final name = m['name']?.toString() ?? 'Member';
//     final role = m['role']?.toString() ?? '';
//     final id = m['userId']?.toString() ?? '';
//     final isMe = id == (widget.userId ?? '');
//     final lat = (m['latitude'] as num?)?.toDouble();
//     final lng = (m['longitude'] as num?)?.toDouble();
//     final lastUpdated = m['lastUpdated']?.toString() ?? '';

//     return Positioned(
//       top: 80,
//       left: 12,
//       right: 60,
//       child: Container(
//         padding: const EdgeInsets.all(14),
//         decoration: BoxDecoration(
//           color: Colors.white,
//           borderRadius: BorderRadius.circular(16),
//           boxShadow: [
//             BoxShadow(
//               color: Colors.black.withOpacity(0.15),
//               blurRadius: 12,
//               offset: const Offset(0, 4),
//             ),
//           ],
//         ),
//         child: Row(
//           crossAxisAlignment: CrossAxisAlignment.start,
//           children: [
//             CircleAvatar(
//               radius: 22,
//               backgroundColor: AppColors.primary.withOpacity(0.15),
//               child: Text(
//                 name[0].toUpperCase(),
//                 style: const TextStyle(
//                   color: AppColors.primary,
//                   fontWeight: FontWeight.bold,
//                   fontSize: 18,
//                 ),
//               ),
//             ),
//             const SizedBox(width: 10),
//             Expanded(
//               child: Column(
//                 crossAxisAlignment: CrossAxisAlignment.start,
//                 children: [
//                   Row(children: [
//                     Flexible(
//                       child: Text(
//                         isMe ? '$name (You)' : name,
//                         style: const TextStyle(
//                           fontSize: 14,
//                           fontWeight: FontWeight.bold,
//                           color: AppColors.secondary,
//                         ),
//                         overflow: TextOverflow.ellipsis,
//                       ),
//                     ),
//                     if (role.isNotEmpty) ...[
//                       const SizedBox(width: 6),
//                       Container(
//                         padding: const EdgeInsets.symmetric(
//                             horizontal: 6, vertical: 2),
//                         decoration: BoxDecoration(
//                           color: AppColors.primary.withOpacity(0.1),
//                           borderRadius: BorderRadius.circular(6),
//                         ),
//                         child: Text(role,
//                             style: const TextStyle(
//                                 fontSize: 9,
//                                 color: AppColors.primary,
//                                 fontWeight: FontWeight.bold)),
//                       ),
//                     ],
//                   ]),
//                   const SizedBox(height: 4),
//                   if (lat != null && lng != null)
//                     Text(
//                       'Lat: ${lat.toStringAsFixed(5)}\nLng: ${lng.toStringAsFixed(5)}',
//                       style: const TextStyle(
//                           fontSize: 10, color: AppColors.textLight),
//                     )
//                   else
//                     const Text('Location not available',
//                         style: TextStyle(fontSize: 10, color: AppColors.grey)),
//                   if (lastUpdated.isNotEmpty) ...[
//                     const SizedBox(height: 2),
//                     Text('Updated: $lastUpdated',
//                         style: const TextStyle(
//                             fontSize: 9, color: AppColors.grey)),
//                   ],
//                 ],
//               ),
//             ),
//             GestureDetector(
//               onTap: () => setState(() => _selectedMember = null),
//               child: const Icon(Icons.close, size: 16, color: AppColors.grey),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ── Loading Overlay ───────────────────────────────────────────────────────

//   Widget _buildLoadingOverlay() {
//     return Container(
//       color: Colors.white.withOpacity(0.92),
//       child: const Center(
//         child: Column(
//           mainAxisAlignment: MainAxisAlignment.center,
//           children: [
//             CircularProgressIndicator(color: AppColors.primary),
//             SizedBox(height: 16),
//             Text(
//               'Loading family locations…',
//               style: TextStyle(color: AppColors.textLight, fontSize: 14),
//             ),
//           ],
//         ),
//       ),
//     );
//   }

//   // ── Error Overlay ─────────────────────────────────────────────────────────

//   Widget _buildErrorOverlay() {
//     return Container(
//       color: Colors.white,
//       child: Center(
//         child: Padding(
//           padding: const EdgeInsets.all(32),
//           child: Column(
//             mainAxisAlignment: MainAxisAlignment.center,
//             children: [
//               Icon(Icons.location_off,
//                   size: 72, color: AppColors.grey.withOpacity(0.35)),
//               const SizedBox(height: 20),
//               Text(
//                 _errorMessage ?? 'Unable to load map.',
//                 textAlign: TextAlign.center,
//                 style: const TextStyle(
//                   fontSize: 14,
//                   color: AppColors.textLight,
//                   height: 1.6,
//                 ),
//               ),
//               const SizedBox(height: 28),
//               ElevatedButton.icon(
//                 onPressed: _initialize,
//                 icon: const Icon(Icons.refresh, size: 18),
//                 label: const Text('Retry'),
//                 style: ElevatedButton.styleFrom(
//                   backgroundColor: AppColors.primary,
//                   foregroundColor: Colors.white,
//                   shape: RoundedRectangleBorder(
//                       borderRadius: BorderRadius.circular(12)),
//                   padding:
//                       const EdgeInsets.symmetric(horizontal: 28, vertical: 12),
//                 ),
//               ),
//             ],
//           ),
//         ),
//       ),
//     );
//   }
// }

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/widgets/animated_refresh_button.dart';
import '../../../core/widgets/map_surface_guard.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../../services/emergency_report_service.dart';
import '../../../services/notification_count_service.dart';
import '../../notifications/screens/notification_screen.dart';

class MapScreen extends StatefulWidget {
  /// The current logged-in user's ID — used to highlight "You" on the map.
  final String? userId;

  /// The current logged-in user's display name.
  final String? userName;

  /// Optional — if provided, members are loaded directly from this code
  /// without any extra lookup. If omitted, the screen looks up the code
  /// via [userId] from the Accounts node.
  final String? familyCode;

  /// Whether to show the top-left back button. Set to false when this
  /// screen is embedded as a bottom-nav tab (e.g. inside an IndexedStack)
  /// rather than pushed onto the Navigator — popping in that case would
  /// pop the host screen's own route instead of just switching tabs,
  /// leaving a black screen behind.
  final bool showBackButton;

  const MapScreen({
    super.key,
    this.userId,
    this.userName,
    this.familyCode,
    this.showBackButton = true,
  });

  @override
  State<MapScreen> createState() => _MapScreenState();
}

class _MapScreenState extends State<MapScreen> with WidgetsBindingObserver {
  // ── Map ──────────────────────────────────────────────────────────────────
  GoogleMapController? _mapController;
  MapType _mapType = MapType.normal;
  bool _isMapReady = false;
  final _mapGuard = MapSurfaceGuard();

  static const _defaultCamera = CameraPosition(
    target: LatLng(12.8797, 121.7740),
    zoom: 6,
  );

  // ── Data ─────────────────────────────────────────────────────────────────
  List<Map<String, dynamic>> _members = [];
  String _resolvedFamilyCode = '';
  String _familyName = '';
  bool _isLoading = true;
  String? _errorMessage;

  // ── Map overlays ─────────────────────────────────────────────────────────
  final Map<String, Marker> _markers = {};

  // `mounted` alone isn't a reliable enough guard for the async calls below:
  // cancelling a Timer in dispose() only stops FUTURE ticks, not a refresh
  // already in flight (awaiting the network call) when the widget is
  // disposed — that request can still resolve afterwards and call setState
  // on a defunct element (see FamilyTrackingScreen's _refresh() for the
  // same issue, confirmed via a real crash log). This flag is set
  // synchronously in dispose(), before anything else, so every check
  // against it is unambiguous.
  bool _disposed = false;

  // ── Auto-refresh ──────────────────────────────────────────────────────────
  Timer? _refreshTimer;
  static const _refreshInterval = Duration(seconds: 10);

  // ── UI state ──────────────────────────────────────────────────────────────
  Map<String, dynamic>? _selectedMember;
  String? _selectedMemberAddress;
  bool _isResolvingAddress = false;
  bool _showMemberList = true;
  bool _hasInitializedCamera = false; // ← NEW: track if we've centered once

  // ── Notification badge ──────────────────────────────────────────────────
  int _unreadCount = 0;
  Timer? _unreadTimer;

  // ── Colours ───────────────────────────────────────────────────────────────
  static const List<double> _markerHues = [
    BitmapDescriptor.hueAzure,
    BitmapDescriptor.hueViolet,
    BitmapDescriptor.hueOrange,
    BitmapDescriptor.hueRose,
    BitmapDescriptor.hueCyan,
    BitmapDescriptor.hueYellow,
    BitmapDescriptor.hueMagenta,
  ];

  static const List<Color> _chipColors = [
    AppColors.primary,
    Colors.purple,
    Colors.orange,
    Colors.pink,
    Colors.teal,
    Colors.indigo,
    Colors.deepOrange,
  ];

  // ══════════════════════════════════════════════════════════════════════════
  // Lifecycle
  // ══════════════════════════════════════════════════════════════════════════

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initialize();
    _pollUnreadCount();
  }

  @override
  void dispose() {
    _disposed = true;
    WidgetsBinding.instance.removeObserver(this);
    _refreshTimer?.cancel();
    _unreadTimer?.cancel();
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
      setState(() {
        _mapController = null;
        _isMapReady = false;
        _hasInitializedCamera = false;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Notification badge
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _pollUnreadCount() async {
    await _refreshUnreadCount();
    _unreadTimer = Timer.periodic(
      const Duration(seconds: 10),
      (_) => _refreshUnreadCount(),
    );
  }

  Future<void> _refreshUnreadCount() async {
    if (_disposed) return;
    try {
      var familyCode = _resolvedFamilyCode;
      if (familyCode.isEmpty) {
        final account = await FirebaseService.getUserById(widget.userId ?? '');
        if (_disposed) return;
        familyCode = account?['familyCode']?.toString() ?? '';
        if (familyCode.isNotEmpty && mounted) {
          setState(() => _resolvedFamilyCode = familyCode);
        }
      }
      // No early return on an empty familyCode: updates on the user's own
      // reports (responder assigned / resolved) still count without one.

      final unread = await NotificationCountService.unreadCount(
        userId: widget.userId ?? '',
        familyCode: familyCode,
        throwOnError: true,
      );

      if (!_disposed && mounted) setState(() => _unreadCount = unread);
    } catch (_) {
      // Leave _unreadCount as whatever it already was.
    }
  }

  void _navigateToNotifications() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => NotificationScreen(
          userId: widget.userId ?? '',
          familyCode: _resolvedFamilyCode,
        ),
      ),
    ).then((_) => _refreshUnreadCount());
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Data loading
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _initialize() async {
    if (!mounted) return;
    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _hasInitializedCamera = false;
    });

    try {
      // ── Resolve the family code ──────────────────────────────────────────
      String code = widget.familyCode?.trim() ?? '';

      if (code.isEmpty) {
        final uid = widget.userId?.trim() ?? '';
        if (uid.isEmpty) {
          _setError(
            'No family code or user ID provided.\n'
            'Please log in again.',
          );
          return;
        }

        final account = await FirebaseService.getUserById(uid);
        if (account == null) {
          _setError('Account not found. Please log in again.');
          return;
        }

        code = account['familyCode']?.toString().trim() ?? '';
        if (code.isEmpty) {
          _setError(
            'You are not part of a family yet.\n'
            'Join or create a family from the Dashboard.',
          );
          return;
        }
      }

      // ── Load family name ─────────────────────────────────────────────────
      final family = await FirebaseService.getFamilyByCode(code);
      if (family == null) {
        _setError(
          'Family not found for code "$code".\n'
          'Please contact your family admin.',
        );
        return;
      }

      if (mounted) {
        setState(() {
          _resolvedFamilyCode = code;
          _familyName = family['FamilyName']?.toString() ?? '';
        });
      }

      // ── First location fetch ─────────────────────────────────────────────
      await _refreshLocations();

      // ── Start periodic refresh ───────────────────────────────────────────
      _refreshTimer?.cancel();
      _refreshTimer =
          Timer.periodic(_refreshInterval, (_) => _refreshLocations());
    } catch (e) {
      _setError('Error loading map: $e');
    }
  }

  Future<void> _refreshLocations() async {
    if (_resolvedFamilyCode.isEmpty || _disposed) return;
    try {
      // throwOnError so a dropped poll reaches the catch block below instead
      // of silently resolving as an empty list, which would otherwise wipe
      // every member's live location off the map on a single network hiccup.
      final members = await FirebaseService.getFamilyMembersWithLocations(
          _resolvedFamilyCode,
          throwOnError: true);
      if (_disposed || !mounted) return;
      setState(() {
        _members = members;
        _isLoading = false;
      });
      await _buildMarkersAndPolylines(members);
    } catch (e) {
      if (!_disposed && mounted) setState(() => _isLoading = false);
      debugPrint('❌ MapScreen refresh error: $e');
    }
  }

  void _setError(String msg) {
    if (!_disposed && mounted) {
      setState(() {
        _errorMessage = msg;
        _isLoading = false;
      });
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Markers & Polylines
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _buildMarkersAndPolylines(
      List<Map<String, dynamic>> members) async {
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
      final isMe = id == (widget.userId ?? '');

      final hue = isMe
          ? BitmapDescriptor.hueGreen
          : _markerHues[colorIdx % _markerHues.length];
      if (!isMe) colorIdx++;

      newMarkers[id] = Marker(
        markerId: MarkerId(id),
        position: pos,
        icon: BitmapDescriptor.defaultMarkerWithHue(hue),
        infoWindow: InfoWindow(
          title: isMe ? '$name (You)' : name,
          snippet: role.isNotEmpty ? role : null,
        ),
        onTap: () => _onMarkerTapped(m),
      );
    }

    if (!mounted) return;
    setState(() {
      _markers
        ..clear()
        ..addAll(newMarkers);
    });

    // ── Only center the map ONCE on first load ────────────────────────────
    if (!_hasInitializedCamera && latLngs.isNotEmpty && _isMapReady) {
      _hasInitializedCamera = true;
      _animateCameraToFit(latLngs);
    }
  }

  void _animateCameraToFit(List<LatLng> pts) {
    if (_mapController == null || pts.isEmpty) return;
    if (pts.length == 1) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
            CameraPosition(target: pts.first, zoom: 15)),
      );
    } else {
      _mapController!.animateCamera(
        CameraUpdate.newLatLngBounds(_boundsFrom(pts), 80),
      );
    }
  }

  LatLngBounds _boundsFrom(List<LatLng> pts) {
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
  // "My Location" button - manually recenter on user
  // ══════════════════════════════════════════════════════════════════════════

  Future<void> _centerOnMyLocation() async {
    if (_mapController == null) return;

    // Find the current user's location from the members list
    final myLocation = _members.firstWhere(
      (m) => m['userId'] == (widget.userId ?? ''),
      orElse: () => {},
    );

    final lat = myLocation['latitude'] as double?;
    final lng = myLocation['longitude'] as double?;

    if (lat != null && lng != null) {
      _mapController!.animateCamera(
        CameraUpdate.newCameraPosition(
          CameraPosition(
            target: LatLng(lat, lng),
            zoom: 16,
          ),
        ),
      );
      // Select the user's marker
      _selectMember(myLocation);
    } else {
      // If we can't find the user's location, try to fit all members
      _fitAllMembers();
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
              'Your current location is not available. Showing all family members.'),
          backgroundColor: Colors.orange,
          behavior: SnackBarBehavior.floating,
          duration: Duration(seconds: 2),
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Interaction
  // ══════════════════════════════════════════════════════════════════════════

  /// Selects [m] and resolves its lat/lng into a readable place name so the
  /// selected-member card can show a location name instead of raw
  /// coordinates.
  void _selectMember(Map<String, dynamic> m) {
    setState(() {
      _selectedMember = m;
      _selectedMemberAddress = null;
      _isResolvingAddress = false;
    });
    _resolveAddressForSelectedMember(m);
  }

  Future<void> _resolveAddressForSelectedMember(Map<String, dynamic> m) async {
    final lat = (m['latitude'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null) return;

    if (mounted) setState(() => _isResolvingAddress = true);

    final address =
        await EmergencyReportService.reverseGeocodeBarangay(lat, lng);

    // Only apply the result if this member is still the one selected —
    // guards against the user tapping a different member while this was
    // still resolving.
    final currentId = _selectedMember?['userId']?.toString();
    if (mounted && currentId != null && currentId == m['userId']?.toString()) {
      setState(() {
        _selectedMemberAddress = address;
        _isResolvingAddress = false;
      });
    }
  }

  void _onMarkerTapped(Map<String, dynamic> m) => _selectMember(m);

  // Pans to the member without forcing a fixed zoom — the user stays in
  // control of zoom at all times outside of the one-time initial camera fit.
  void _flyToMember(Map<String, dynamic> m) {
    final lat = (m['latitude'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble();
    if (lat == null || lng == null || _mapController == null) return;
    _mapController!.animateCamera(CameraUpdate.newLatLng(LatLng(lat, lng)));
    _selectMember(m);
  }

  void _fitAllMembers() {
    final pts = _members
        .where((m) => m['latitude'] != null && m['longitude'] != null)
        .map((m) => LatLng(
              (m['latitude'] as num).toDouble(),
              (m['longitude'] as num).toDouble(),
            ))
        .toList();
    // Showing everyone again means no single member should stay highlighted,
    // otherwise the other pins would remain faded while zoomed out.
    _clearSelection();
    _animateCameraToFit(pts);
  }

  /// Deselects the current member and clears any resolved place name.
  void _clearSelection() {
    setState(() {
      _selectedMember = null;
      _selectedMemberAddress = null;
      _isResolvingAddress = false;
    });
  }

  /// Returns the markers to render, dimming every pin except the selected
  /// member's so the selected one stands out. Recomputed on every build,
  /// so it stays in sync the instant a member is tapped — no marker
  /// rebuild required.
  Set<Marker> _visibleMarkers() {
    final selectedId = _selectedMember?['userId']?.toString();
    if (selectedId == null) {
      return Set<Marker>.of(_markers.values);
    }
    return _markers.values.map((marker) {
      final isSelected = marker.markerId.value == selectedId;
      return marker.copyWith(alphaParam: isSelected ? 1.0 : 0.35);
    }).toSet();
  }

  // ══════════════════════════════════════════════════════════════════════════
  // Build
  // ══════════════════════════════════════════════════════════════════════════

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: Stack(
          children: [
            _buildMap(),
            _buildTopBar(),
            if (!_isLoading && _errorMessage == null) ...[
              _buildFabCluster(),
              _buildBottomMemberPanel(),
              // ── "My Location" button ──────────────────────────────────────
              _buildMyLocationButton(),
            ],
            if (_selectedMember != null) _buildSelectedMemberCard(),
            if (_isLoading) _buildLoadingOverlay(),
            if (!_isLoading && _errorMessage != null) _buildErrorOverlay(),
          ],
        ),
      ),
    );
  }

  // ── Google Map ────────────────────────────────────────────────────────────

  Widget _buildMap() {
    return GoogleMap(
      key: ValueKey('map_surface_${_mapGuard.generation}'),
      initialCameraPosition: _defaultCamera,
      mapType: _mapType,
      markers: _visibleMarkers(),
      myLocationEnabled: true,
      myLocationButtonEnabled: false, // We use our own button
      zoomControlsEnabled: false,
      compassEnabled: true,
      mapToolbarEnabled: false,
      onMapCreated: (c) {
        _mapController = c;
        _isMapReady = true;
        // If we already have markers and haven't initialized camera yet
        if (_markers.isNotEmpty && !_hasInitializedCamera) {
          _hasInitializedCamera = true;
          _fitAllMembers();
        }
      },
      onTap: (_) => _clearSelection(),
      // ── NEW: Track when user drags the map ──────────────────────────────
      onCameraMoveStarted: () {
        // User is dragging the map — we DO NOT auto-center
        // This is handled by the flag _hasInitializedCamera
      },
    );
  }

  // ── My Location Button ───────────────────────────────────────────────────

  Widget _buildMyLocationButton() {
    return Positioned(
      right: 12,
      bottom: _showMemberList ? 196 : 24,
      child: GestureDetector(
        onTap: _centerOnMyLocation,
        child: Container(
          width: 48,
          height: 48,
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
          child: const Icon(
            Icons.my_location,
            color: AppColors.primary,
            size: 28,
          ),
        ),
      ),
    );
  }

  // ── Top Bar ───────────────────────────────────────────────────────────────

  Widget _buildTopBar() {
    final locatedCount = _members.where((m) => m['latitude'] != null).length;

    return Positioned(
      top: 12,
      left: 12,
      right: 12,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.12),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          children: [
            // ── Back button (only when pushed, not when embedded as a tab) ──
            if (widget.showBackButton) ...[
              GestureDetector(
                onTap: () {
                  if (Navigator.canPop(context)) Navigator.pop(context);
                },
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
            ],
            Container(
              padding: const EdgeInsets.all(6),
              decoration: const BoxDecoration(
                color: AppColors.secondary,
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.security, color: Colors.white, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'Live Tracking',
                    style: TextStyle(
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                    ),
                  ),
                  Text(
                    _familyName.isNotEmpty
                        ? _familyName
                        : _resolvedFamilyCode.isNotEmpty
                            ? 'Code: $_resolvedFamilyCode'
                            : 'Loading…',
                    style: const TextStyle(
                        fontSize: 11, color: AppColors.textLight),
                  ),
                ],
              ),
            ),
            if (_members.isNotEmpty) ...[
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
                        color: Colors.green,
                        shape: BoxShape.circle,
                      ),
                    ),
                    const SizedBox(width: 4),
                    Text(
                      '$locatedCount/${_members.length}',
                      style: const TextStyle(
                        fontSize: 10,
                        color: Colors.green,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
            ],
            // ── Notification bell with badge ──────────────────────────────
            Stack(
              clipBehavior: Clip.none,
              children: [
                IconButton(
                  icon: const Icon(
                    Icons.notifications_outlined,
                    color: AppColors.secondary,
                    size: 24,
                  ),
                  onPressed: _navigateToNotifications,
                  padding: EdgeInsets.zero,
                  constraints: const BoxConstraints(),
                  tooltip: 'Notifications',
                ),
                if (_unreadCount > 0)
                  Positioned(
                    right: -2,
                    top: -2,
                    child: Container(
                      padding: const EdgeInsets.all(3),
                      decoration: const BoxDecoration(
                        color: AppColors.danger,
                        shape: BoxShape.circle,
                      ),
                      constraints:
                          const BoxConstraints(minWidth: 16, minHeight: 16),
                      child: Text(
                        _unreadCount > 99 ? '99+' : '$_unreadCount',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 9,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(width: 4),
            AnimatedRefreshButton(
              onRefresh: _refreshLocations,
              color: AppColors.secondary,
              size: 18,
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: AppColors.lightGrey,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── FAB Cluster ───────────────────────────────────────────────────────────

  Widget _buildFabCluster() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      right: 12,
      bottom:
          _showMemberList ? 252 : 80, // Moved up to make room for My Location
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _miniButton(
            icon: _mapType == MapType.normal
                ? Icons.satellite_alt
                : Icons.map_outlined,
            tooltip:
                _mapType == MapType.normal ? 'Satellite view' : 'Normal map',
            onTap: () => setState(() {
              _mapType = _mapType == MapType.normal
                  ? MapType.satellite
                  : MapType.normal;
            }),
          ),
          const SizedBox(height: 8),
          _miniButton(
            icon: Icons.fit_screen,
            tooltip: 'Fit all members',
            onTap: _fitAllMembers,
          ),
          const SizedBox(height: 8),
          _miniButton(
            icon: _showMemberList
                ? Icons.keyboard_arrow_down
                : Icons.people_alt_outlined,
            tooltip: _showMemberList ? 'Hide panel' : 'Show panel',
            onTap: () => setState(() => _showMemberList = !_showMemberList),
          ),
        ],
      ),
    );
  }

  Widget _miniButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onTap,
  }) {
    return Tooltip(
      message: tooltip,
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          width: 40,
          height: 40,
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
          child: Icon(icon, color: AppColors.secondary, size: 20),
        ),
      ),
    );
  }

  // ── Bottom Member Panel ───────────────────────────────────────────────────

  Widget _buildBottomMemberPanel() {
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeInOut,
      bottom: 0,
      left: 0,
      right: 0,
      height: _showMemberList ? 184 : 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.1),
              blurRadius: 12,
              offset: const Offset(0, -3),
            ),
          ],
        ),
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              child: Row(
                children: [
                  const Icon(Icons.people, color: AppColors.primary, size: 18),
                  const SizedBox(width: 8),
                  const Text(
                    'Family Members',
                    style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: _fitAllMembers,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: AppColors.primary.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: const Text(
                        'Show All',
                        style: TextStyle(
                          fontSize: 11,
                          color: AppColors.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: _members.isEmpty
                  ? const Center(
                      child: Text(
                        'No members with location data',
                        style:
                            TextStyle(fontSize: 12, color: AppColors.textLight),
                      ),
                    )
                  : ListView.builder(
                      scrollDirection: Axis.horizontal,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      itemCount: _members.length,
                      itemBuilder: (context, index) =>
                          _buildMemberChip(_members[index], index),
                    ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberChip(Map<String, dynamic> member, int index) {
    final memberId = member['userId']?.toString() ?? '';
    final name = member['name']?.toString() ?? 'Member';
    final role = member['role']?.toString() ?? '';
    final isMe = memberId == (widget.userId ?? '');
    final hasLoc = member['latitude'] != null && member['longitude'] != null;
    final isSelected = _selectedMember?['userId'] == memberId;
    final color = _chipColors[index % _chipColors.length];

    return GestureDetector(
      onTap: hasLoc ? () => _flyToMember(member) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 108,
        margin: const EdgeInsets.only(right: 10, bottom: 4, top: 2),
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: isSelected
              ? AppColors.primary.withOpacity(0.1)
              : AppColors.lightGrey,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: isSelected ? AppColors.primary : Colors.transparent,
            width: 2,
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                CircleAvatar(
                  radius: 15,
                  backgroundColor: color.withOpacity(0.2),
                  child: Text(
                    name[0].toUpperCase(),
                    style: TextStyle(
                        color: color,
                        fontWeight: FontWeight.bold,
                        fontSize: 12),
                  ),
                ),
                const Spacer(),
                Container(
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(
                    color: hasLoc ? Colors.green : AppColors.grey,
                    shape: BoxShape.circle,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              isMe ? '$name (You)' : name,
              style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.bold,
                color: isSelected ? AppColors.primary : AppColors.secondary,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            if (role.isNotEmpty)
              Text(role,
                  style:
                      const TextStyle(fontSize: 9, color: AppColors.textLight)),
            const SizedBox(height: 2),
            Text(
              hasLoc ? '📍 Located' : 'No location',
              style: TextStyle(
                fontSize: 9,
                color: hasLoc ? Colors.green : AppColors.grey,
                fontWeight: hasLoc ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── Selected Member Card ──────────────────────────────────────────────────

  Widget _buildSelectedMemberCard() {
    final m = _selectedMember!;
    final name = m['name']?.toString() ?? 'Member';
    final role = m['role']?.toString() ?? '';
    final id = m['userId']?.toString() ?? '';
    final isMe = id == (widget.userId ?? '');
    final lat = (m['latitude'] as num?)?.toDouble();
    final lng = (m['longitude'] as num?)?.toDouble();
    final isOnline = (m['onlineStatus']?.toString() ?? 'Offline') == 'Online';
    final lastSeen = m['lastSeen']?.toString() ?? '';

    return Positioned(
      top: 80,
      left: 12,
      right: 60,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.15),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: AppColors.primary.withOpacity(0.15),
              child: Text(
                name[0].toUpperCase(),
                style: const TextStyle(
                  color: AppColors.primary,
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    Flexible(
                      child: Text(
                        isMe ? '$name (You)' : name,
                        style: const TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.bold,
                          color: AppColors.secondary,
                        ),
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
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(role,
                            style: const TextStyle(
                                fontSize: 9,
                                color: AppColors.primary,
                                fontWeight: FontWeight.bold)),
                      ),
                    ],
                  ]),
                  const SizedBox(height: 4),
                  if (lat == null || lng == null)
                    const Text('Location not available',
                        style: TextStyle(fontSize: 10, color: AppColors.grey))
                  else if (_isResolvingAddress)
                    const Row(
                      children: [
                        SizedBox(
                          width: 10,
                          height: 10,
                          child: CircularProgressIndicator(
                            strokeWidth: 1.5,
                            color: AppColors.primary,
                          ),
                        ),
                        SizedBox(width: 6),
                        Text('Locating...',
                            style: TextStyle(
                                fontSize: 10, color: AppColors.textLight)),
                      ],
                    )
                  else
                    Text(
                      _selectedMemberAddress ?? 'Location unavailable',
                      style: const TextStyle(
                          fontSize: 10, color: AppColors.textLight),
                    ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          color: isOnline ? Colors.green : AppColors.grey,
                          shape: BoxShape.circle,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          isOnline
                              ? 'Online'
                              : (lastSeen.isNotEmpty
                                  ? 'Offline · Logged out: $lastSeen'
                                  : 'Offline'),
                          style: TextStyle(
                            fontSize: 9,
                            color: isOnline ? Colors.green : AppColors.grey,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            GestureDetector(
              onTap: _clearSelection,
              child: const Icon(Icons.close, size: 16, color: AppColors.grey),
            ),
          ],
        ),
      ),
    );
  }

  // ── Loading Overlay ───────────────────────────────────────────────────────

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.white.withOpacity(0.92),
      child: const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(color: AppColors.primary),
            SizedBox(height: 16),
            Text(
              'Loading family locations…',
              style: TextStyle(color: AppColors.textLight, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }

  // ── Error Overlay ─────────────────────────────────────────────────────────

  Widget _buildErrorOverlay() {
    return Container(
      color: Colors.white,
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off,
                  size: 72, color: AppColors.grey.withOpacity(0.35)),
              const SizedBox(height: 20),
              Text(
                _errorMessage ?? 'Unable to load map.',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textLight,
                  height: 1.6,
                ),
              ),
              const SizedBox(height: 28),
              ElevatedButton.icon(
                onPressed: _initialize,
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
      ),
    );
  }
}
