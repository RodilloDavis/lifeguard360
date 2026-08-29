import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/form_auto_scroll.dart';
import '../../../shared/widgets/custom_button.dart';
import 'emergency_confirmation_screen.dart';

class FloodEmergencyScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const FloodEmergencyScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FloodEmergencyScreen> createState() => _FloodEmergencyScreenState();
}

class _FloodEmergencyScreenState extends State<FloodEmergencyScreen>
    with AutoScrollForm<FloodEmergencyScreen> {
  @override
  List<Object> get autoScrollSteps =>
      const ['level', 'trapped', 'count', 'evacuation', 'send'];

  String? _selectedWaterLevel;
  bool _peopleTrapped = false;
  bool _needsEvacuation = false;
  int _numberOfPeople = 1;

  final List<Map<String, dynamic>> _waterLevels = [
    {
      'id': 'ankle',
      'label': 'Ankle Deep',
      'description': 'Water below knee level',
      'color': Colors.blue[300],
    },
    {
      'id': 'knee',
      'label': 'Knee Deep',
      'description': 'Water at knee to waist level',
      'color': Colors.blue[500],
    },
    {
      'id': 'waist',
      'label': 'Waist Deep',
      'description': 'Water at waist to chest level',
      'color': Colors.blue[700],
    },
    {
      'id': 'chest',
      'label': 'Chest Deep+',
      'description': 'Water above chest level',
      'color': Colors.blue[900],
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
          'Flood Emergency',
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
                'level',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Current Water Level'),
                    const SizedBox(height: 12),
                    _buildWaterLevelSelection(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'trapped',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Are there people trapped?'),
                    const SizedBox(height: 12),
                    _buildToggleButtons(
                      ['Yes', 'No'],
                      _peopleTrapped,
                      (value) {
                        setState(() {
                          _peopleTrapped = value;
                          if (!value) _numberOfPeople = 1;
                        });
                        advanceFrom('trapped');
                      },
                    ),
                  ],
                ),
              ),
              if (_peopleTrapped) ...[
                const SizedBox(height: 16),
                autoScrollStep('count', _buildNumberOfPeopleSelector()),
              ],
              const SizedBox(height: 24),
              autoScrollStep(
                'evacuation',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Do you need evacuation assistance?'),
                    const SizedBox(height: 12),
                    _buildToggleButtons(
                      ['Yes', 'No'],
                      _needsEvacuation,
                      (value) {
                        setState(() => _needsEvacuation = value);
                        advanceFrom('evacuation');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildFloodSafetyTips(),
              const SizedBox(height: 24),
              autoScrollStep(
                'send',
                CustomButton(
                  text: 'SEND FLOOD ALERT',
                  color: AppColors.accent,
                  onPressed:
                      _selectedWaterLevel != null ? _submitFloodReport : () {},
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
          colors: [AppColors.accent, AppColors.accent.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.accent.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.water_drop, color: Colors.white, size: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Flood Alert',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Report water emergency',
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

  Widget _buildWaterLevelSelection() {
    return Column(
      children: _waterLevels.map((level) {
        final isSelected = _selectedWaterLevel == level['id'];
        final color = level['color'] as Color;
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedWaterLevel = level['id']);
              advanceFrom('level');
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: isSelected
                          ? Colors.white.withOpacity(0.3)
                          : color.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.waves,
                        color: isSelected ? Colors.white : color, size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(level['label'],
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.secondary)),
                        const SizedBox(height: 2),
                        Text(level['description'],
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
          color: isSelected ? AppColors.accent : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? AppColors.accent : AppColors.lightGrey,
              width: isSelected ? 2 : 1),
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

  Widget _buildNumberOfPeopleSelector() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          const Text('Number of people:',
              style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  color: AppColors.secondary)),
          const Spacer(),
          IconButton(
            onPressed: _numberOfPeople > 1
                ? () => setState(() => _numberOfPeople--)
                : null,
            icon: const Icon(Icons.remove_circle_outline),
            color: AppColors.primary,
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            decoration: BoxDecoration(
                color: Colors.white, borderRadius: BorderRadius.circular(8)),
            child: Text('$_numberOfPeople',
                style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary)),
          ),
          IconButton(
            onPressed: () => setState(() => _numberOfPeople++),
            icon: const Icon(Icons.add_circle_outline),
            color: AppColors.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildFloodSafetyTips() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.orange.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.orange.withOpacity(0.3)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.orange, size: 24),
              SizedBox(width: 12),
              Text('Flood Safety Tips',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          _buildSafetyTipItem('Move to higher ground immediately'),
          _buildSafetyTipItem('Avoid walking or driving through flood waters'),
          _buildSafetyTipItem(
              'Stay away from power lines and electrical wires'),
          _buildSafetyTipItem('Keep emergency supplies ready'),
        ],
      ),
    );
  }

  Widget _buildSafetyTipItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(Icons.check_circle_outline,
              size: 16, color: Colors.orange),
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

  void _submitFloodReport() {
    if (_selectedWaterLevel == null) return;

    final emergencyData = {
      'type': 'flood',
      'waterLevel': _selectedWaterLevel,
      'peopleTrapped': _peopleTrapped,
      'numberOfPeople': _peopleTrapped ? _numberOfPeople : 0,
      'needsEvacuation': _needsEvacuation,
      'timestamp': DateTime.now().toIso8601String(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmergencyConfirmationScreen(
          emergencyData: emergencyData,
          emergencyTitle: 'Flood Alert',
          emergencyColor: AppColors.accent,
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }
}
