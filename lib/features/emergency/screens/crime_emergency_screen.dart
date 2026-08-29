import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/form_auto_scroll.dart';
import '../../../shared/widgets/custom_button.dart';
import 'emergency_confirmation_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// CrimeEmergencyScreen
//
// CHANGE vs original:
//  • Requires userId + userName (passed from DashboardHome / EmergencySelectionScreen)
//  • Forwards both to EmergencyConfirmationScreen so the report gets saved
//    under the correct user in Firebase
//  • Replaced "Do you need immediate police assistance?" Yes/No toggle with a
//    3-level color-coded emergency severity selector:
//      Blue  → Low    – No immediate danger, report for records
//      Green → Medium – Situation is escalating, police advised
//      Red   → High   – Immediate threat, police needed urgently
// ═══════════════════════════════════════════════════════════════════════════════

class CrimeEmergencyScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const CrimeEmergencyScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<CrimeEmergencyScreen> createState() => _CrimeEmergencyScreenState();
}

class _CrimeEmergencyScreenState extends State<CrimeEmergencyScreen>
    with AutoScrollForm<CrimeEmergencyScreen> {
  @override
  List<Object> get autoScrollSteps =>
      const ['type', 'ongoing', 'level', 'info', 'send'];

  String? _selectedCrimeType;
  bool _isOngoing = true;
  String? _emergencyLevel; // 'low' | 'medium' | 'high'
  String _additionalInfo = '';

  // ── Emergency level definitions ─────────────────────────────────────────────
  static const _levels = [
    {
      'id': 'low',
      'label': 'Low',
      'sublabel': 'Not High Emergency',
      'description': 'No immediate danger. Reporting for records or awareness.',
      'icon': Icons.info_outline,
      'color': Color(0xFF1565C0), // deep blue
      'bgColor': Color(0xFFE3F2FD),
      'borderColor': Color(0xFF90CAF9),
    },
    {
      'id': 'medium',
      'label': 'Medium',
      'sublabel': 'Moderate Emergency',
      'description': 'Situation is escalating. Police presence recommended.',
      'icon': Icons.warning_amber_outlined,
      'color': Color(0xFF2E7D32), // deep green
      'bgColor': Color(0xFFE8F5E9),
      'borderColor': Color(0xFF81C784),
    },
    {
      'id': 'high',
      'label': 'High',
      'sublabel': 'Urgent — Police Needed Now',
      'description':
          'Immediate threat to life or safety. Fast response required.',
      'icon': Icons.local_police,
      'color': Color(0xFFCC0000), // danger red
      'bgColor': Color(0xFFFFEBEE),
      'borderColor': Color(0xFFEF9A9A),
    },
  ];

  final List<Map<String, dynamic>> _crimeTypes = [
    {'id': 'theft', 'label': 'Theft/Robbery', 'icon': Icons.money_off},
    {'id': 'assault', 'label': 'Assault', 'icon': Icons.person_off},
    {'id': 'burglary', 'label': 'Burglary', 'icon': Icons.door_front_door},
    {'id': 'vandalism', 'label': 'Vandalism', 'icon': Icons.broken_image},
    {
      'id': 'suspicious',
      'label': 'Suspicious Activity',
      'icon': Icons.visibility,
    },
    {'id': 'other', 'label': 'Other Crime', 'icon': Icons.more_horiz},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Crime Emergency',
          style: TextStyle(
              color: AppColors.secondary, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildEmergencyBanner(),
              const SizedBox(height: 24),
              autoScrollStep(
                'type',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('What type of crime?'),
                    const SizedBox(height: 12),
                    _buildCrimeTypeSelection(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'ongoing',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Is this happening now?'),
                    const SizedBox(height: 12),
                    _buildToggleButtons(
                      ['Yes, Ongoing', 'No, Already Happened'],
                      _isOngoing,
                      (value) {
                        setState(() => _isOngoing = value);
                        advanceFrom('ongoing');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'level',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Emergency Level'),
                    const SizedBox(height: 4),
                    const Text(
                      'Select the severity to determine how fast police should respond.',
                      style: TextStyle(fontSize: 12, color: AppColors.textLight),
                    ),
                    const SizedBox(height: 12),
                    _buildEmergencyLevelSelector(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'info',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Additional Information (Optional)'),
                    const SizedBox(height: 12),
                    _buildAdditionalInfoField(),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildSafetyTip(),
              const SizedBox(height: 24),
              autoScrollStep(
                'send',
                CustomButton(
                  text: 'REPORT CRIME',
                  color: AppColors.secondary,
                  onPressed:
                      (_selectedCrimeType != null && _emergencyLevel != null)
                          ? _submitCrimeReport
                          : () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Emergency Level Selector ────────────────────────────────────────────────

  Widget _buildEmergencyLevelSelector() {
    return Column(
      children: _levels.map((level) {
        final isSelected = _emergencyLevel == level['id'];
        final color = level['color'] as Color;
        final bgColor = level['bgColor'] as Color;
        final borderColor = level['borderColor'] as Color;
        final icon = level['icon'] as IconData;

        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: GestureDetector(
            onTap: () {
              setState(() => _emergencyLevel = level['id'] as String);
              advanceFrom('level');
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? color : bgColor,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: isSelected ? color : borderColor,
                  width: isSelected ? 2.5 : 1.5,
                ),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                          color: color.withOpacity(0.30),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  // ── Color badge dot ───────────────────────────────────────
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withOpacity(0.25)
                          : color.withOpacity(0.15),
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      icon,
                      color: isSelected ? Colors.white : color,
                      size: 24,
                    ),
                  ),
                  const SizedBox(width: 14),
                  // ── Labels ────────────────────────────────────────────────
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            // Colored pill badge
                            Container(
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 8, vertical: 3),
                              decoration: BoxDecoration(
                                color: isSelected
                                    ? Colors.white.withOpacity(0.25)
                                    : color.withOpacity(0.15),
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                level['label'] as String,
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected ? Colors.white : color,
                                  letterSpacing: 0.5,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Flexible(
                              child: Text(
                                level['sublabel'] as String,
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                  color: isSelected
                                      ? Colors.white
                                      : AppColors.secondary,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          level['description'] as String,
                          style: TextStyle(
                            fontSize: 11.5,
                            color: isSelected
                                ? Colors.white.withOpacity(0.88)
                                : AppColors.textLight,
                            height: 1.35,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // ── Check icon when selected ──────────────────────────────
                  if (isSelected)
                    const Padding(
                      padding: EdgeInsets.only(left: 8),
                      child: Icon(Icons.check_circle,
                          color: Colors.white, size: 22),
                    ),
                ],
              ),
            ),
          ),
        );
      }).toList(),
    );
  }

  // ── Existing widgets ────────────────────────────────────────────────────────

  Widget _buildEmergencyBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [AppColors.secondary, AppColors.secondary.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.secondary.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.gavel, color: Colors.white, size: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Crime Reporting',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Your safety is our priority',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.secondary));
  }

  Widget _buildCrimeTypeSelection() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _crimeTypes.map((crime) {
        final isSelected = _selectedCrimeType == crime['id'];
        return GestureDetector(
          onTap: () {
            setState(() => _selectedCrimeType = crime['id'] as String);
            advanceFrom('type');
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.secondary : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? AppColors.secondary : AppColors.lightGrey,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: AppColors.secondary.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(crime['icon'] as IconData,
                    color: isSelected ? Colors.white : AppColors.secondary,
                    size: 20),
                const SizedBox(width: 8),
                Text(crime['label'] as String,
                    style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.secondary,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 14)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildToggleButtons(
      List<String> options, bool value, Function(bool) onChanged) {
    return Row(
      children: [
        Expanded(
          child: _buildToggleButton(options[0], value, () => onChanged(true)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: _buildToggleButton(options[1], !value, () => onChanged(false)),
        ),
      ],
    );
  }

  Widget _buildToggleButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? AppColors.secondary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? AppColors.secondary : AppColors.lightGrey,
            width: isSelected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: isSelected ? Colors.white : AppColors.secondary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14)),
      ),
    );
  }

  Widget _buildAdditionalInfoField() {
    return TextField(
      maxLines: 4,
      onChanged: (value) => setState(() => _additionalInfo = value),
      decoration: InputDecoration(
        hintText:
            'Describe what happened, location details, suspect information...',
        hintStyle: const TextStyle(fontSize: 13, color: AppColors.grey),
        filled: true,
        fillColor: AppColors.lightGrey,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        contentPadding: const EdgeInsets.all(16),
      ),
    );
  }

  Widget _buildSafetyTip() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.amber.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.amber.withOpacity(0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lightbulb_outline, color: Colors.amber, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Safety Tip',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary)),
                SizedBox(height: 4),
                Text(
                  'If you\'re in immediate danger, move to a safe location before reporting. Your safety comes first.',
                  style: TextStyle(
                      fontSize: 12, color: AppColors.textLight, height: 1.4),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  void _submitCrimeReport() {
    if (_selectedCrimeType == null || _emergencyLevel == null) return;

    final emergencyData = {
      'type': 'crime',
      'crimeType': _selectedCrimeType,
      'isOngoing': _isOngoing,
      'emergencyLevel': _emergencyLevel, // 'low' | 'medium' | 'high'
      'additionalInfo': _additionalInfo,
      'timestamp': DateTime.now().toIso8601String(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmergencyConfirmationScreen(
          emergencyData: emergencyData,
          emergencyTitle: 'Crime Report',
          emergencyColor: AppColors.secondary,
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }
}
