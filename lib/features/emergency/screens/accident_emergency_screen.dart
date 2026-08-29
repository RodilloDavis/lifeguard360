import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/form_auto_scroll.dart';
import '../../../shared/widgets/custom_button.dart';
import 'emergency_confirmation_screen.dart';

class AccidentEmergencyScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const AccidentEmergencyScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<AccidentEmergencyScreen> createState() =>
      _AccidentEmergencyScreenState();
}

class _AccidentEmergencyScreenState extends State<AccidentEmergencyScreen>
    with AutoScrollForm<AccidentEmergencyScreen> {
  @override
  List<Object> get autoScrollSteps =>
      const ['type', 'injuries', 'severity', 'traffic', 'send'];

  String? _selectedAccidentType;
  bool _hasInjuries = false;
  String? _injurySeverity;
  bool _blockingTraffic = false;

  final List<Map<String, dynamic>> _accidentTypes = [
    {
      'id': 'vehicle',
      'label': 'Vehicle Collision',
      'icon': Icons.directions_car
    },
    {
      'id': 'motorcycle',
      'label': 'Motorcycle Accident',
      'icon': Icons.two_wheeler
    },
    {
      'id': 'pedestrian',
      'label': 'Pedestrian Hit',
      'icon': Icons.directions_walk
    },
    {'id': 'bicycle', 'label': 'Bicycle Accident', 'icon': Icons.pedal_bike},
    {
      'id': 'workplace',
      'label': 'Workplace Accident',
      'icon': Icons.construction
    },
    {'id': 'other', 'label': 'Other Accident', 'icon': Icons.more_horiz},
  ];

  final List<Map<String, dynamic>> _injurySeverities = [
    {
      'id': 'minor',
      'label': 'Minor',
      'description': 'Bruises, small cuts',
      'color': Colors.yellow[700],
    },
    {
      'id': 'moderate',
      'label': 'Moderate',
      'description': 'Bleeding, fractures',
      'color': Colors.orange,
    },
    {
      'id': 'severe',
      'label': 'Severe',
      'description': 'Unconscious, major trauma',
      'color': AppColors.danger,
    },
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Accident Emergency',
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
                    _buildSectionTitle('Type of Accident'),
                    const SizedBox(height: 12),
                    _buildAccidentTypeSelection(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'injuries',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Are there any injuries?'),
                    const SizedBox(height: 12),
                    _buildToggleButtons(
                      ['Yes', 'No'],
                      _hasInjuries,
                      (value) {
                        setState(() {
                          _hasInjuries = value;
                          if (!value) _injurySeverity = null;
                        });
                        advanceFrom('injuries');
                      },
                    ),
                  ],
                ),
              ),
              if (_hasInjuries) ...[
                const SizedBox(height: 20),
                autoScrollStep(
                  'severity',
                  Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _buildSectionTitle('Injury Severity'),
                      const SizedBox(height: 12),
                      _buildInjurySeveritySelection(),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              autoScrollStep(
                'traffic',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Is the accident blocking traffic?'),
                    const SizedBox(height: 12),
                    _buildToggleButtons(
                      ['Yes', 'No'],
                      _blockingTraffic,
                      (value) {
                        setState(() => _blockingTraffic = value);
                        advanceFrom('traffic');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildAccidentGuidelines(),
              const SizedBox(height: 24),
              autoScrollStep(
                'send',
                CustomButton(
                  text: 'REPORT ACCIDENT',
                  color: Colors.orange,
                  onPressed: _selectedAccidentType != null
                      ? _submitAccidentReport
                      : () {},
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Widgets ───────────────────────────────────────────────────────────────

  Widget _buildEmergencyBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.orange, Colors.orange.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.directions_car, color: Colors.white, size: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Accident Report',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Help is on the way',
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

  Widget _buildAccidentTypeSelection() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _accidentTypes.map((accident) {
        final isSelected = _selectedAccidentType == accident['id'];
        return GestureDetector(
          onTap: () {
            setState(() => _selectedAccidentType = accident['id']);
            advanceFrom('type');
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: isSelected ? Colors.orange : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: isSelected ? Colors.orange : AppColors.lightGrey,
                width: isSelected ? 2 : 1,
              ),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                        color: Colors.orange.withOpacity(0.2),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      )
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(accident['icon'],
                    color: isSelected ? Colors.white : Colors.orange, size: 20),
                const SizedBox(width: 8),
                Text(accident['label'],
                    style: TextStyle(
                        color: isSelected ? Colors.white : Colors.orange,
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

  Widget _buildInjurySeveritySelection() {
    return Column(
      children: _injurySeverities.map((severity) {
        final isSelected = _injurySeverity == severity['id'];
        final color = severity['color'] as Color;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: GestureDetector(
            onTap: () {
              setState(() => _injurySeverity = severity['id']);
              advanceFrom('severity');
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? color : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isSelected ? color : AppColors.lightGrey,
                    width: isSelected ? 2 : 1),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: color.withOpacity(0.3),
                            blurRadius: 8,
                            offset: const Offset(0, 2))
                      ]
                    : null,
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withOpacity(0.3)
                          : color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(Icons.local_hospital,
                        color: isSelected ? Colors.white : color, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(severity['label'],
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.secondary)),
                        const SizedBox(height: 2),
                        Text(severity['description'],
                            style: TextStyle(
                                fontSize: 12,
                                color: isSelected
                                    ? Colors.white.withOpacity(0.9)
                                    : AppColors.textLight)),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle,
                        color: Colors.white, size: 24),
                ],
              ),
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
            child:
                _buildToggleButton(options[0], value, () => onChanged(true))),
        const SizedBox(width: 12),
        Expanded(
            child:
                _buildToggleButton(options[1], !value, () => onChanged(false))),
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
          color: isSelected ? Colors.orange : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: isSelected ? Colors.orange : AppColors.lightGrey,
            width: isSelected ? 2 : 1,
          ),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: isSelected ? Colors.white : Colors.orange,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14)),
      ),
    );
  }

  Widget _buildAccidentGuidelines() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.info_outline, color: Colors.blue, size: 24),
              SizedBox(width: 12),
              Text('Important Guidelines',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          _buildGuidelineItem(
              'Ensure your safety first, move away from danger'),
          _buildGuidelineItem('Call emergency services if not already done'),
          _buildGuidelineItem('Don\'t move injured persons unless necessary'),
          _buildGuidelineItem(
              'Document the scene with photos if safe to do so'),
        ],
      ),
    );
  }

  Widget _buildGuidelineItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.arrow_right, size: 20, color: Colors.blue),
          const SizedBox(width: 8),
          Expanded(
              child: Text(text,
                  style: const TextStyle(
                      fontSize: 12, color: AppColors.textLight, height: 1.4))),
        ],
      ),
    );
  }

  // ── Submit ────────────────────────────────────────────────────────────────

  void _submitAccidentReport() {
    if (_selectedAccidentType == null) return;

    final emergencyData = {
      'type': 'accident',
      'accidentType': _selectedAccidentType,
      'hasInjuries': _hasInjuries,
      'injurySeverity': _injurySeverity,
      'blockingTraffic': _blockingTraffic,
      'timestamp': DateTime.now().toIso8601String(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmergencyConfirmationScreen(
          emergencyData: emergencyData,
          emergencyTitle: 'Accident Report',
          emergencyColor: Colors.orange,
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }
}
