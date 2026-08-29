// lib/features/notifications/screens/shake_sos_alert_screen.dart
//
// Shown when a family member taps the push notification that was triggered
// by another member's shake SOS.
//
// Features:
//   • Displays reporter name, timestamp, and address
//   • Shows coordinates with a Google Maps deep-link button
//   • "Send Location to Police" button — writes to /emergency-high-red/ and
//     pushes FCM to all registered dispatchers
//   • One-shot protection — once sent to police the button is disabled
// ─────────────────────────────────────────────────────────────────────────────

import 'dart:convert';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../services/fcm_service.dart';

class ShakeSosAlertScreen extends StatefulWidget {
  /// Name of the family member who triggered the shake SOS.
  final String reporterName;

  /// UID of the person who shook the device.
  final String reporterUserId;

  /// Family group code — used to read barangay from Firebase if needed.
  final String familyCode;

  /// Human-readable address string returned by reverse-geocoding.
  final String location;

  /// GPS latitude of the shake event (may be null if GPS was unavailable).
  final double? latitude;

  /// GPS longitude of the shake event (may be null if GPS was unavailable).
  final double? longitude;

  /// The report-ID written to Firebase (e.g. "SHK-1712345678-AB12CD").
  final String reportId;

  /// ISO-8601 / formatted timestamp string from the report payload.
  final String timestamp;

  const ShakeSosAlertScreen({
    super.key,
    required this.reporterName,
    required this.reporterUserId,
    required this.familyCode,
    required this.location,
    this.latitude,
    this.longitude,
    required this.reportId,
    required this.timestamp,
  });

  // ── Convenience constructor from FCM notification data map ─────────────────
  factory ShakeSosAlertScreen.fromNotificationData(Map<String, dynamic> data) {
    return ShakeSosAlertScreen(
      reporterName: data['reporterName']?.toString() ?? 'A family member',
      reporterUserId: data['reporterUserId']?.toString() ?? '',
      familyCode: data['familyCode']?.toString() ?? '',
      location: data['location']?.toString() ?? 'Location unavailable',
      latitude: double.tryParse(data['latitude']?.toString() ?? ''),
      longitude: double.tryParse(data['longitude']?.toString() ?? ''),
      reportId: data['reportId']?.toString() ?? '',
      timestamp: data['timestamp']?.toString() ?? '',
    );
  }

  @override
  State<ShakeSosAlertScreen> createState() => _ShakeSosAlertScreenState();
}

class _ShakeSosAlertScreenState extends State<ShakeSosAlertScreen>
    with SingleTickerProviderStateMixin {
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  bool _isSendingToPolice = false;
  bool _sentToPolice = false;

  late final AnimationController _pulseCtrl;
  late final Animation<double> _pulseAnim;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _pulseAnim = Tween<double>(begin: 1.0, end: 1.08)
        .animate(CurvedAnimation(parent: _pulseCtrl, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _pulseCtrl.dispose();
    super.dispose();
  }

  // ── Open Google Maps at the shake location ─────────────────────────────────
  Future<void> _openInMaps() async {
    if (widget.latitude == null || widget.longitude == null) return;
    final uri = Uri.parse(
      'https://www.google.com/maps/search/?api=1'
      '&query=${widget.latitude},${widget.longitude}',
    );
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  // ── Send the shake location to police / dispatchers ────────────────────────
  Future<void> _sendToPolice() async {
    if (_sentToPolice || _isSendingToPolice) return;
    setState(() => _isSendingToPolice = true);

    try {
      final prefs = await SharedPreferences.getInstance();
      final callerUserId = prefs.getString('userId') ?? '';
      final callerName = prefs.getString('userName') ?? 'Family Member';

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

      final locationPayload = <String, dynamic>{
        'Latitude': widget.latitude,
        'Longitude': widget.longitude,
        'Address': widget.location,
        'LastUpdated': createdAt,
      };

      final payload = <String, dynamic>{
        'ReportId': policeReportId,
        'OriginalShakeReportId': widget.reportId,
        'ReportLabel': 'emergency-high-red',
        'EmergencyType': 'shake',
        'Trigger': 'family_forwarded_to_police',
        'Status': 'Active',
        'Priority': 'critical',
        'AlertLevel': 'emergency-high-red',
        'ForwardedBy': callerName,
        'ForwardedByUserId': callerUserId,
        'ReporterName': widget.reporterName,
        'ReporterUserId': widget.reporterUserId,
        'FamilyCode': widget.familyCode,
        'CreatedAt': createdAt,
        'Timestamp': now.toIso8601String(),
        'Location': locationPayload,
        'Details': {
          'type': 'shake',
          'trigger': 'family_forwarded_to_police',
          'message': '${widget.reporterName} triggered a Shake SOS. '
              'Forwarded to police by $callerName.',
          'alertLevel': 'emergency-high-red',
          'priority': 'critical',
          'originalReportId': widget.reportId,
        },
      };

      // 1. Write to /emergency-high-red/ so dispatcher dashboard picks it up
      await http
          .put(
            Uri.parse('${_dbUrl}emergency-high-red/$policeReportId.json'),
            headers: {'Content-Type': 'application/json'},
            body: json.encode(payload),
          )
          .timeout(const Duration(seconds: 15));

      // 2. Notify all active dispatchers via FCM
      await FcmService.sendNotificationToDispatchers(
        reporterName: widget.reporterName,
        emergencyType: 'shake',
        location: widget.location,
        barangay: _extractBarangay(widget.location),
        reportId: policeReportId,
      );

      if (mounted) {
        setState(() {
          _isSendingToPolice = false;
          _sentToPolice = true;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Row(
              children: [
                Icon(Icons.check_circle, color: Colors.white),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    '✅ Location sent to police / dispatchers.',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            backgroundColor: AppColors.success,
            behavior: SnackBarBehavior.floating,
            duration: Duration(seconds: 4),
          ),
        );
      }
    } catch (e) {
      debugPrint('❌ _sendToPolice error: $e');
      if (mounted) {
        setState(() => _isSendingToPolice = false);
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

  // ── Pull a rough barangay label from the address string ───────────────────
  String _extractBarangay(String address) {
    if (address.isEmpty || address == 'Location unavailable') return 'Unknown';
    final parts = address.split(',');
    return parts.isNotEmpty ? parts.first.trim() : address;
  }

  // ── Build ──────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final hasCoords = widget.latitude != null && widget.longitude != null;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D1A),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D1A),
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          '🚨 Shake SOS Alert',
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            const SizedBox(height: 8),
            _buildPulsingAlert(),
            const SizedBox(height: 28),
            _buildReporterCard(),
            const SizedBox(height: 16),
            _buildLocationCard(hasCoords),
            const SizedBox(height: 24),
            _buildMapButton(hasCoords),
            const SizedBox(height: 16),
            _buildPoliceButton(),
            const SizedBox(height: 32),
            _buildFooterNote(),
          ],
        ),
      ),
    );
  }

  // ── Pulsing SOS icon ───────────────────────────────────────────────────────
  Widget _buildPulsingAlert() {
    return AnimatedBuilder(
      animation: _pulseAnim,
      builder: (_, child) => Transform.scale(
        scale: _pulseAnim.value,
        child: child,
      ),
      child: Container(
        width: 110,
        height: 110,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const RadialGradient(
            colors: [Color(0xFFE53935), Color(0xFF880000)],
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.red.withOpacity(0.5),
              blurRadius: 30,
              spreadRadius: 8,
            ),
          ],
        ),
        child: const Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.vibration, color: Colors.white, size: 36),
              SizedBox(height: 4),
              Text(
                'SOS',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                  letterSpacing: 2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Reporter info card ─────────────────────────────────────────────────────
  Widget _buildReporterCard() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.red.withOpacity(0.4)),
      ),
      child: Row(
        children: [
          Container(
            width: 56,
            height: 56,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.red.withOpacity(0.15),
              border: Border.all(color: Colors.red.shade700, width: 2),
            ),
            child: Center(
              child: Text(
                widget.reporterName.isNotEmpty
                    ? widget.reporterName[0].toUpperCase()
                    : '?',
                style: const TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 22,
                ),
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Emergency from',
                  style: TextStyle(color: Colors.white60, fontSize: 12),
                ),
                const SizedBox(height: 4),
                Text(
                  widget.reporterName,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                if (widget.timestamp.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      const Icon(Icons.access_time,
                          color: Colors.white38, size: 13),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          widget.timestamp,
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 12),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
            decoration: BoxDecoration(
              color: Colors.red.withOpacity(0.2),
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: Colors.red.shade700),
            ),
            child: const Text(
              'SHAKE\nSOS',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.red,
                fontWeight: FontWeight.bold,
                fontSize: 11,
                letterSpacing: 1,
                height: 1.3,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Location card ──────────────────────────────────────────────────────────
  Widget _buildLocationCard(bool hasCoords) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: AppColors.primary.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.location_on, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              const Text(
                'Last Known Location',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Text(
            widget.location,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.5,
            ),
          ),
          if (hasCoords) ...[
            const SizedBox(height: 12),
            const Divider(color: Colors.white12),
            const SizedBox(height: 10),
            Row(
              children: [
                _buildCoordChip('LAT', widget.latitude!.toStringAsFixed(6)),
                const SizedBox(width: 10),
                _buildCoordChip('LNG', widget.longitude!.toStringAsFixed(6)),
              ],
            ),
          ] else ...[
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.orange.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.withOpacity(0.3)),
              ),
              child: const Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.location_off, color: Colors.orange, size: 14),
                  SizedBox(width: 6),
                  Text(
                    'GPS coordinates unavailable',
                    style: TextStyle(color: Colors.orange, fontSize: 12),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCoordChip(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.primary.withOpacity(0.08),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.primary.withOpacity(0.2)),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label,
                style: const TextStyle(
                    color: AppColors.primary,
                    fontSize: 10,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 1)),
            const SizedBox(height: 2),
            Text(value,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      ),
    );
  }

  // ── View on Maps button ────────────────────────────────────────────────────
  Widget _buildMapButton(bool hasCoords) {
    return SizedBox(
      width: double.infinity,
      child: OutlinedButton.icon(
        onPressed: hasCoords ? _openInMaps : null,
        icon: const Icon(Icons.map_outlined),
        label: const Text('View on Google Maps'),
        style: OutlinedButton.styleFrom(
          foregroundColor: hasCoords ? AppColors.primary : Colors.white38,
          side:
              BorderSide(color: hasCoords ? AppColors.primary : Colors.white12),
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
      ),
    );
  }

  // ── Send to Police button ──────────────────────────────────────────────────
  Widget _buildPoliceButton() {
    if (_sentToPolice) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 16),
        decoration: BoxDecoration(
          color: AppColors.success.withOpacity(0.15),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: AppColors.success),
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.check_circle, color: AppColors.success, size: 22),
            SizedBox(width: 10),
            Text(
              'Location Sent to Police ✓',
              style: TextStyle(
                color: AppColors.success,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
          ],
        ),
      );
    }

    return CustomButton(
      text: _isSendingToPolice
          ? 'Notifying Police...'
          : '🚔  Send Location to Police',
      onPressed: _isSendingToPolice ? () {} : _sendToPolice,
      isLoading: _isSendingToPolice,
      fitContent: false,
      color: const Color(0xFF1565C0),
      icon: _isSendingToPolice ? null : Icons.local_police_outlined,
      fontSize: 15,
    );
  }

  // ── Footer note ────────────────────────────────────────────────────────────
  Widget _buildFooterNote() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.07),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.amber.withOpacity(0.25)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.info_outline, color: Colors.amber, size: 16),
          SizedBox(width: 10),
          Expanded(
            child: Text(
              'Tapping "Send to Police" forwards this family member\'s '
              'shake location to the nearest available dispatcher. '
              'Only do this in a real emergency.',
              style: TextStyle(
                color: Colors.amber,
                fontSize: 12,
                height: 1.5,
              ),
            ),
          ),
        ],
      ),
    );
  }
}
