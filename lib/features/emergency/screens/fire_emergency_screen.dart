import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/form_auto_scroll.dart';
import '../../../shared/widgets/custom_button.dart';
import 'emergency_confirmation_screen.dart';

class FireEmergencyScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const FireEmergencyScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<FireEmergencyScreen> createState() => _FireEmergencyScreenState();
}

class _FireEmergencyScreenState extends State<FireEmergencyScreen>
    with AutoScrollForm<FireEmergencyScreen> {
  @override
  List<Object> get autoScrollSteps =>
      const ['type', 'trapped', 'count', 'spreading', 'info', 'send'];

  String? _selectedFireType;
  bool _peopleTrapped = false;
  int _numberOfPeople = 1;
  bool _spreadingFast = false;
  String _additionalInfo = '';

  final List<Map<String, dynamic>> _fireTypes = [
    {
      'id': 'residential',
      'label': 'Residential',
      'icon': Icons.home,
      'description': 'House or apartment fire'
    },
    {
      'id': 'industrial',
      'label': 'Industrial',
      'icon': Icons.factory,
      'description': 'Factory or warehouse fire'
    },
    {
      'id': 'forest',
      'label': 'Forest',
      'icon': Icons.forest,
      'description': 'Wildfire or forest fire'
    },
    {
      'id': 'vehicle',
      'label': 'Vehicle',
      'icon': Icons.directions_car,
      'description': 'Car or vehicle fire'
    },
    {
      'id': 'electrical',
      'label': 'Electrical',
      'icon': Icons.electric_bolt,
      'description': 'Electrical fire'
    },
    {
      'id': 'chemical',
      'label': 'Chemical',
      'icon': Icons.science,
      'description': 'Chemical or hazardous fire'
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
          'Fire Emergency',
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
                    _buildSectionTitle('What is the fire type?'),
                    const SizedBox(height: 12),
                    _buildFireTypeSelection(),
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
                'spreading',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Is the fire spreading rapidly?'),
                    const SizedBox(height: 12),
                    _buildToggleButtons(
                      ['Yes, Fast Spreading', 'No, Contained'],
                      _spreadingFast,
                      (value) {
                        setState(() => _spreadingFast = value);
                        advanceFrom('spreading');
                      },
                    ),
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
              _buildFireSafetyTips(),
              const SizedBox(height: 24),
              autoScrollStep(
                'send',
                CustomButton(
                  text: 'SEND FIRE ALERT',
                  color: AppColors.danger,
                  onPressed:
                      _selectedFireType != null ? _submitFireReport : () {},
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
          colors: [AppColors.danger, AppColors.danger.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.danger.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.local_fire_department, color: Colors.white, size: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Fire Emergency',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Immediate response activated',
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

  Widget _buildFireTypeSelection() {
    return Column(
      children: _fireTypes.map((fireType) {
        final isSelected = _selectedFireType == fireType['id'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 12.0),
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedFireType = fireType['id']);
              advanceFrom('type');
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.danger : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isSelected ? AppColors.danger : AppColors.lightGrey,
                    width: isSelected ? 2 : 1),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: AppColors.danger.withOpacity(0.2),
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
                          : AppColors.danger.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(fireType['icon'],
                        color: isSelected ? Colors.white : AppColors.danger,
                        size: 24),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(fireType['label'],
                            style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.secondary)),
                        const SizedBox(height: 2),
                        Text(fireType['description'],
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
          color: isSelected ? AppColors.danger : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? AppColors.danger : AppColors.lightGrey,
              width: isSelected ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: isSelected ? Colors.white : AppColors.danger,
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
            color: AppColors.danger,
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
            color: AppColors.danger,
          ),
        ],
      ),
    );
  }

  Widget _buildAdditionalInfoField() {
    return TextField(
      maxLines: 4,
      onChanged: (value) => setState(() => _additionalInfo = value),
      decoration: InputDecoration(
        hintText: 'Location details, fire size, any hazards present...',
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

  Widget _buildFireSafetyTips() {
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
              Text('Fire Safety Reminders',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          _buildSafetyTipItem('Get out and stay out - never go back inside'),
          _buildSafetyTipItem('Close doors behind you as you leave'),
          _buildSafetyTipItem('Crawl low under smoke to your exit'),
          _buildSafetyTipItem('Call 911 once you are safely outside'),
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

  void _submitFireReport() {
    if (_selectedFireType == null) return;

    final emergencyData = {
      'type': 'fire',
      'fireType': _selectedFireType,
      'peopleTrapped': _peopleTrapped,
      'numberOfPeople': _peopleTrapped ? _numberOfPeople : 0,
      'spreadingFast': _spreadingFast,
      'additionalInfo': _additionalInfo,
      'timestamp': DateTime.now().toIso8601String(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmergencyConfirmationScreen(
          emergencyData: emergencyData,
          emergencyTitle: 'Fire Emergency',
          emergencyColor: AppColors.danger,
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }
}
