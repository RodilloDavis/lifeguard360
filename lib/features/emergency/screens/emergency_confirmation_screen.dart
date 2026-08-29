import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/emergency_report_service.dart';
import 'my_reports_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// EmergencyConfirmationScreen
//
// CHANGES vs original:
//  • Added required userId + userName params
//  • _sendEmergencyAlert() calls EmergencyReportService.saveReport()
//    (saves to labeled collection, e.g. /crime-report/{id})
//  • Shows an error banner + retry if the save fails
//  • Displays the saved Report ID + label on the success screen
//  • "View My Reports" button navigates to MyReportsScreen
// ═══════════════════════════════════════════════════════════════════════════════

class EmergencyConfirmationScreen extends StatefulWidget {
  final Map<String, dynamic> emergencyData;
  final String emergencyTitle;
  final Color emergencyColor;
  final String userId;
  final String userName;

  const EmergencyConfirmationScreen({
    super.key,
    required this.emergencyData,
    required this.emergencyTitle,
    required this.emergencyColor,
    required this.userId,
    required this.userName,
  });

  @override
  State<EmergencyConfirmationScreen> createState() =>
      _EmergencyConfirmationScreenState();
}

class _EmergencyConfirmationScreenState
    extends State<EmergencyConfirmationScreen>
    with SingleTickerProviderStateMixin {
  bool _isSending = false;
  bool _isSuccess = false;
  bool _hasFailed = false;
  String _errorMessage = '';
  String _savedReportId = '';
  String _savedReportLabel = '';

  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulseController.dispose();
    super.dispose();
  }

  // ── Send & save to Firebase ───────────────────────────────────────────────

  Future<void> _sendEmergencyAlert() async {
    setState(() {
      _isSending = true;
      _hasFailed = false;
      _errorMessage = '';
    });

    // Fetch familyCode so the report is written to the family's shared node
    final prefs = await SharedPreferences.getInstance();
    final familyCode = prefs.getString('familyCode') ?? '';

    final result = await EmergencyReportService.saveReport(
      userId: widget.userId,
      userName: widget.userName,
      emergencyData: widget.emergencyData,
      familyCode: familyCode,
    );

    if (!mounted) return;

    if (result['success'] == true) {
      setState(() {
        _isSending = false;
        _isSuccess = true;
        _savedReportId = result['reportId']?.toString() ?? '';
        _savedReportLabel = result['reportLabel']?.toString() ?? '';
      });
    } else {
      setState(() {
        _isSending = false;
        _hasFailed = true;
        _errorMessage =
            result['error']?.toString() ?? 'Unknown error occurred.';
      });
    }
  }

  // ── Root build ────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    if (_isSuccess) return _buildSuccessScreen();
    if (_isSending) return _buildSendingScreen();
    return _buildConfirmScreen();
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Confirm screen
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildConfirmScreen() {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Confirm Emergency',
          style: TextStyle(
              color: AppColors.secondary, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: Padding(
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _buildEmergencyHeader(),
                      const SizedBox(height: 24),
                      _buildLocationInfo(),
                      const SizedBox(height: 16),
                      _buildAdditionalInfo(),
                      if (_hasFailed) ...[
                        const SizedBox(height: 16),
                        _buildErrorBanner(),
                      ],
                      const SizedBox(height: 24),
                      _buildConfirmButton(),
                      const SizedBox(height: 12),
                      _buildCancelButton(),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildEmergencyHeader() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            widget.emergencyColor,
            widget.emergencyColor.withOpacity(0.7)
          ],
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: widget.emergencyColor.withOpacity(0.3),
            blurRadius: 15,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          Text(_getEmergencyIcon(), style: const TextStyle(fontSize: 48)),
          const SizedBox(height: 12),
          Text(
            widget.emergencyTitle,
            style: const TextStyle(
                color: Colors.white, fontSize: 24, fontWeight: FontWeight.bold),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  Widget _buildLocationInfo() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: const Row(
        children: [
          Icon(Icons.location_on, color: AppColors.primary, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your Current Location',
                    style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary)),
                SizedBox(height: 4),
                Text('Your location will be attached as a place name',
                    style: TextStyle(fontSize: 12, color: AppColors.textLight)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildErrorBanner() {
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: AppColors.danger.withOpacity(0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.danger.withOpacity(0.35)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.error_outline, color: AppColors.danger, size: 20),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Failed to send report',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger,
                        fontSize: 13)),
                const SizedBox(height: 2),
                Text(_errorMessage,
                    style: const TextStyle(
                        fontSize: 12, color: AppColors.textLight)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalInfo() {
    final type = widget.emergencyData['type'];
    final List<Widget> infoItems = [];

    switch (type) {
      case 'fire':
        _add(infoItems, 'Fire Type',
            _fireTypeLabel(widget.emergencyData['fireType']));
        if (widget.emergencyData['peopleTrapped'] == true) {
          _add(infoItems, 'People Trapped',
              '${widget.emergencyData['numberOfPeople']} person(s)');
        }
        if (widget.emergencyData['spreadingFast'] != null) {
          _add(
              infoItems,
              'Spreading',
              widget.emergencyData['spreadingFast']
                  ? 'Fast spreading'
                  : 'Contained');
        }
        _addRaw(infoItems, 'Details', widget.emergencyData['additionalInfo']);
        break;

      case 'medical':
        _add(infoItems, 'Condition',
            _medicalLabel(widget.emergencyData['condition']));
        if (widget.emergencyData['isConscious'] != null) {
          _add(
              infoItems,
              'Patient Status',
              widget.emergencyData['isConscious']
                  ? 'Conscious'
                  : 'Unconscious');
        }
        if (widget.emergencyData['needsAmbulance'] != null) {
          _add(
              infoItems,
              'Ambulance',
              widget.emergencyData['needsAmbulance']
                  ? 'Needed urgently'
                  : 'Can transport');
        }
        _addRaw(infoItems, 'Symptoms', widget.emergencyData['symptoms']);
        break;

      case 'crime':
        _add(infoItems, 'Crime Type',
            _crimeLabel(widget.emergencyData['crimeType']));
        if (widget.emergencyData['isOngoing'] != null) {
          _add(
              infoItems,
              'Status',
              widget.emergencyData['isOngoing']
                  ? 'Ongoing now'
                  : 'Already happened');
        }
        if (widget.emergencyData['needsPolice'] != null) {
          _add(infoItems, 'Police Assistance',
              widget.emergencyData['needsPolice'] ? 'Needed' : 'Not needed');
        }
        _addRaw(infoItems, 'Details', widget.emergencyData['additionalInfo']);
        break;

      case 'flood':
        _add(infoItems, 'Water Level',
            _waterLevelLabel(widget.emergencyData['waterLevel']));
        if (widget.emergencyData['peopleTrapped'] == true) {
          _add(infoItems, 'People Trapped',
              '${widget.emergencyData['numberOfPeople']} person(s)');
        }
        if (widget.emergencyData['needsEvacuation'] != null) {
          _add(
              infoItems,
              'Evacuation',
              widget.emergencyData['needsEvacuation']
                  ? 'Needed'
                  : 'Not needed');
        }
        break;

      case 'accident':
        _add(infoItems, 'Accident Type',
            _accidentLabel(widget.emergencyData['accidentType']));
        if (widget.emergencyData['hasInjuries'] == true) {
          _add(infoItems, 'Injuries',
              _injuryLabel(widget.emergencyData['injurySeverity']));
        }
        if (widget.emergencyData['blockingTraffic'] != null) {
          _add(
              infoItems,
              'Traffic',
              widget.emergencyData['blockingTraffic']
                  ? 'Blocking traffic'
                  : 'Not blocking');
        }
        break;

      case 'other':
        _add(infoItems, 'Category',
            _otherCategoryLabel(widget.emergencyData['category']));
        if (widget.emergencyData['isUrgent'] != null) {
          _add(infoItems, 'Urgency',
              widget.emergencyData['isUrgent'] ? 'Urgent' : 'Not urgent');
        }
        if (widget.emergencyData['needsImmediateHelp'] != null) {
          _add(
              infoItems,
              'Help Needed',
              widget.emergencyData['needsImmediateHelp']
                  ? 'Immediate'
                  : 'Can wait');
        }
        _addRaw(infoItems, 'Description', widget.emergencyData['description']);
        break;
    }

    if (infoItems.isEmpty) return const SizedBox.shrink();

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: widget.emergencyColor.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: widget.emergencyColor.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline, color: widget.emergencyColor, size: 20),
              const SizedBox(width: 8),
              const Text('Emergency Details',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary)),
            ],
          ),
          const SizedBox(height: 12),
          ...infoItems,
        ],
      ),
    );
  }

  void _add(List<Widget> list, String label, String? value) {
    if (value == null || value.isEmpty || value == 'Unknown') return;
    list.add(_infoRow(label, value));
  }

  void _addRaw(List<Widget> list, String label, dynamic raw) {
    final s = raw?.toString().trim() ?? '';
    if (s.isNotEmpty) list.add(_infoRow(label, s));
  }

  Widget _infoRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label,
                style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.textLight)),
          ),
          Expanded(
            child: Text(value,
                style: const TextStyle(
                    fontSize: 13,
                    color: AppColors.secondary,
                    fontWeight: FontWeight.w500)),
          ),
        ],
      ),
    );
  }

  Widget _buildConfirmButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: _isSending ? null : _sendEmergencyAlert,
        style: ElevatedButton.styleFrom(
          backgroundColor: widget.emergencyColor,
          disabledBackgroundColor: widget.emergencyColor.withOpacity(0.5),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
        ),
        child: const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.send, size: 24),
            SizedBox(width: 12),
            Text('CONFIRM & SEND ALERT',
                style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.5)),
          ],
        ),
      ),
    );
  }

  Widget _buildCancelButton() {
    return SizedBox(
      width: double.infinity,
      height: 50,
      child: OutlinedButton(
        onPressed: () => Navigator.pop(context),
        style: OutlinedButton.styleFrom(
          side: BorderSide(color: AppColors.grey.withOpacity(0.5)),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        ),
        child: const Text('Cancel',
            style: TextStyle(
                fontSize: 16,
                color: AppColors.grey,
                fontWeight: FontWeight.w600)),
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Sending screen
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildSendingScreen() {
    return Scaffold(
      backgroundColor: widget.emergencyColor,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ScaleTransition(
              scale: Tween<double>(begin: 0.8, end: 1.2).animate(
                CurvedAnimation(
                    parent: _pulseController, curve: Curves.easeInOut),
              ),
              child: Container(
                padding: const EdgeInsets.all(32),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.wifi_tethering,
                    size: 80, color: Colors.white),
              ),
            ),
            const SizedBox(height: 32),
            const Text('Sending Emergency Alert',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 24,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            const Text('Saving to Firebase...',
                style: TextStyle(color: Colors.white70, fontSize: 14)),
            const SizedBox(height: 16),
            _build911Box(),
            const SizedBox(height: 32),
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
              strokeWidth: 3,
            ),
          ],
        ),
      ),
    );
  }

  Widget _build911Box() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 40),
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.2),
              blurRadius: 10,
              offset: const Offset(0, 4)),
        ],
      ),
      child: Column(
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                    color: AppColors.danger,
                    borderRadius: BorderRadius.circular(8)),
                child: const Icon(Icons.phone, color: Colors.white, size: 24),
              ),
              const SizedBox(width: 12),
              const Text('Contacting Emergency Services',
                  style: TextStyle(
                      fontSize: 14,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 20),
            decoration: BoxDecoration(
              color: AppColors.danger.withOpacity(0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('911',
                    style: TextStyle(
                        fontSize: 36,
                        fontWeight: FontWeight.bold,
                        color: AppColors.danger,
                        letterSpacing: 2)),
              ],
            ),
          ),
          const SizedBox(height: 12),
          const Text('Local emergency responders are being notified',
              textAlign: TextAlign.center,
              style: TextStyle(
                  fontSize: 12, color: AppColors.textLight, height: 1.4)),
        ],
      ),
    );
  }

  // ════════════════════════════════════════════════════════════════════════════
  // Success screen
  // ════════════════════════════════════════════════════════════════════════════

  Widget _buildSuccessScreen() {
    return Scaffold(
      backgroundColor: AppColors.success,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.2),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline,
                    size: 100, color: Colors.white),
              ),
              const SizedBox(height: 32),
              const Text('Alert Sent Successfully!',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              const Text(
                'Emergency services have been notified\nHelp is on the way',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16),
              ),

              // ── Report ID + label chip ─────────────────────────────────
              if (_savedReportId.isNotEmpty) ...[
                const SizedBox(height: 12),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.2),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Column(
                    children: [
                      // Label badge
                      if (_savedReportLabel.isNotEmpty)
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 4),
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            _savedReportLabel,
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                letterSpacing: 0.5),
                          ),
                        ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.receipt_long,
                              color: Colors.white70, size: 14),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              'Report ID: $_savedReportId',
                              style: const TextStyle(
                                  color: Colors.white70,
                                  fontSize: 11,
                                  fontFamily: 'monospace'),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],

              const Spacer(),
              _build911SuccessBox(),
              const SizedBox(height: 16),

              // ── View My Reports button ─────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 52,
                child: OutlinedButton.icon(
                  onPressed: () {
                    Navigator.of(context).popUntil((route) =>
                        route.isFirst || route.settings.name == '/dashboard');
                    Future.microtask(() {
                      if (context.mounted) {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MyReportsScreen(
                              userId: widget.userId,
                              userName: widget.userName,
                            ),
                          ),
                        );
                      }
                    });
                  },
                  icon: const Icon(Icons.assignment_outlined,
                      color: Colors.white),
                  label: const Text('View My Reports',
                      style: TextStyle(
                          color: Colors.white,
                          fontSize: 15,
                          fontWeight: FontWeight.w600)),
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white70, width: 1.5),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                  ),
                ),
              ),
              const SizedBox(height: 12),

              // ── Back to Home button ────────────────────────────────────
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: () => Navigator.of(context).popUntil((route) =>
                      route.isFirst || route.settings.name == '/dashboard'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: AppColors.success,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                  ),
                  child: const Text('Back to Home',
                      style:
                          TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _build911SuccessBox() {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.2),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.white.withOpacity(0.3), width: 2),
      ),
      child: Column(
        children: [
          const Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 24),
              SizedBox(width: 8),
              Text('911 Notified',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.white)),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Text('Emergency responders dispatched',
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: AppColors.success)),
          ),
        ],
      ),
    );
  }

  // ── Label helpers ─────────────────────────────────────────────────────────

  String _getEmergencyIcon() {
    const icons = {
      'fire': '🔥',
      'medical': '🏥',
      'crime': '👮',
      'flood': '💧',
      'accident': '🚗',
    };
    return icons[widget.emergencyData['type']] ?? '⚠️';
  }

  String _fireTypeLabel(String? t) =>
      const {
        'residential': 'Residential Fire',
        'industrial': 'Industrial Fire',
        'forest': 'Forest Fire',
        'vehicle': 'Vehicle Fire',
        'electrical': 'Electrical Fire',
        'chemical': 'Chemical Fire',
      }[t] ??
      'Unknown';

  String _medicalLabel(String? c) =>
      const {
        'heart_attack': 'Heart Attack',
        'stroke': 'Stroke',
        'breathing': 'Breathing Problem',
        'injury': 'Severe Injury',
        'seizure': 'Seizure',
        'allergic': 'Allergic Reaction',
        'poisoning': 'Poisoning',
        'other': 'Other Medical',
      }[c] ??
      'Unknown';

  String _crimeLabel(String? t) =>
      const {
        'theft': 'Theft/Robbery',
        'assault': 'Assault',
        'burglary': 'Burglary',
        'vandalism': 'Vandalism',
        'suspicious': 'Suspicious Activity',
        'other': 'Other Crime',
      }[t] ??
      'Unknown';

  String _waterLevelLabel(String? l) =>
      const {
        'ankle': 'Ankle Deep',
        'knee': 'Knee Deep',
        'waist': 'Waist Deep',
        'chest': 'Chest Deep+',
      }[l] ??
      'Unknown';

  String _accidentLabel(String? t) =>
      const {
        'vehicle': 'Vehicle Collision',
        'motorcycle': 'Motorcycle Accident',
        'pedestrian': 'Pedestrian Hit',
        'bicycle': 'Bicycle Accident',
        'workplace': 'Workplace Accident',
        'other': 'Other Accident',
      }[t] ??
      'Unknown';

  String _injuryLabel(String? s) =>
      const {
        'minor': 'Minor Injuries',
        'moderate': 'Moderate Injuries',
        'severe': 'Severe Injuries',
      }[s] ??
      'Unknown';

  String _otherCategoryLabel(String? c) =>
      const {
        'gas_leak': 'Gas Leak',
        'power_outage': 'Power Outage',
        'animal': 'Animal Emergency',
        'missing_person': 'Missing Person',
        'chemical': 'Chemical Spill',
        'structural': 'Structural Damage',
        'other': 'Other',
      }[c] ??
      'Unknown';
}
