import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/form_auto_scroll.dart';
import '../../../shared/widgets/custom_button.dart';
import 'emergency_confirmation_screen.dart';

class MedicalAlertScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const MedicalAlertScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<MedicalAlertScreen> createState() => _MedicalAlertScreenState();
}

class _MedicalAlertScreenState extends State<MedicalAlertScreen>
    with AutoScrollForm<MedicalAlertScreen> {
  @override
  List<Object> get autoScrollSteps =>
      const ['condition', 'conscious', 'ambulance', 'symptoms', 'send'];

  String? _selectedCondition;
  bool _isConscious = true;
  bool _needsAmbulance = true;
  String _symptoms = '';

  final List<Map<String, dynamic>> _conditions = [
    {
      'id': 'heart_attack',
      'label': 'Heart Attack',
      'icon': Icons.favorite,
      'description': 'Chest pain, breathing difficulty'
    },
    {
      'id': 'stroke',
      'label': 'Stroke',
      'icon': Icons.psychology,
      'description': 'Face drooping, arm weakness, speech difficulty'
    },
    {
      'id': 'breathing',
      'label': 'Breathing Problem',
      'icon': Icons.air,
      'description': 'Severe difficulty breathing'
    },
    {
      'id': 'injury',
      'label': 'Severe Injury',
      'icon': Icons.healing,
      'description': 'Major trauma or bleeding'
    },
    {
      'id': 'seizure',
      'label': 'Seizure',
      'icon': Icons.warning,
      'description': 'Uncontrolled movements'
    },
    {
      'id': 'allergic',
      'label': 'Allergic Reaction',
      'icon': Icons.medication,
      'description': 'Severe allergic response'
    },
    {
      'id': 'poisoning',
      'label': 'Poisoning',
      'icon': Icons.dangerous,
      'description': 'Toxic substance ingestion'
    },
    {
      'id': 'other',
      'label': 'Other Medical',
      'icon': Icons.local_hospital,
      'description': 'Other medical emergency'
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
          'Medical Emergency',
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
              _buildMedicalIDCard(),
              const SizedBox(height: 24),
              autoScrollStep(
                'condition',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('What is the medical condition?'),
                    const SizedBox(height: 12),
                    _buildConditionSelection(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'conscious',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Is the patient conscious?'),
                    const SizedBox(height: 12),
                    _buildToggleButtons(
                      ['Yes, Conscious', 'No, Unconscious'],
                      _isConscious,
                      (value) {
                        setState(() => _isConscious = value);
                        advanceFrom('conscious');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'ambulance',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Is an ambulance needed?'),
                    const SizedBox(height: 12),
                    _buildToggleButtons(
                      ['Yes, Urgent', 'No, Can Transport'],
                      _needsAmbulance,
                      (value) {
                        setState(() => _needsAmbulance = value);
                        advanceFrom('ambulance');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'symptoms',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Symptoms (Optional)'),
                    const SizedBox(height: 12),
                    _buildSymptomsField(),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildMedicalGuidelines(),
              const SizedBox(height: 24),
              autoScrollStep(
                'send',
                CustomButton(
                  text: 'SEND MEDICAL ALERT',
                  color: AppColors.primary,
                  onPressed:
                      _selectedCondition != null ? _submitMedicalAlert : () {},
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
          colors: [AppColors.primary, AppColors.primary.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.primary.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.medical_services, color: Colors.white, size: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Medical Emergency',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('Medical assistance on the way',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMedicalIDCard() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.lightGrey),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.badge, color: AppColors.primary, size: 20),
              const SizedBox(width: 8),
              Text(
                'Medical ID: ${widget.userName}',
                style: const TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary),
              ),
            ],
          ),
          const Divider(height: 20),
          _buildInfoRow('Blood Type', 'O+'),
          const SizedBox(height: 8),
          _buildInfoRow('Allergies', 'None'),
          const SizedBox(height: 8),
          _buildInfoRow('Medications', 'None'),
          const SizedBox(height: 8),
          _buildInfoRow('Emergency Contact', '+63 912 345 6789'),
        ],
      ),
    );
  }

  Widget _buildInfoRow(String label, String value) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(label,
            style: const TextStyle(color: AppColors.textLight, fontSize: 13)),
        Text(value,
            style: const TextStyle(
                fontWeight: FontWeight.w600,
                fontSize: 13,
                color: AppColors.secondary)),
      ],
    );
  }

  Widget _buildSectionTitle(String title) {
    return Text(title,
        style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.secondary));
  }

  Widget _buildConditionSelection() {
    return Column(
      children: _conditions.map((condition) {
        final isSelected = _selectedCondition == condition['id'];
        return Padding(
          padding: const EdgeInsets.only(bottom: 10.0),
          child: GestureDetector(
            onTap: () {
              setState(() => _selectedCondition = condition['id']);
              advanceFrom('condition');
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: isSelected ? AppColors.primary : Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: isSelected ? AppColors.primary : AppColors.lightGrey,
                    width: isSelected ? 2 : 1),
                boxShadow: isSelected
                    ? [
                        BoxShadow(
                            color: AppColors.primary.withOpacity(0.2),
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
                          : AppColors.primary.withOpacity(0.1),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Icon(condition['icon'],
                        color: isSelected ? Colors.white : AppColors.primary,
                        size: 22),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(condition['label'],
                            style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: isSelected
                                    ? Colors.white
                                    : AppColors.secondary)),
                        const SizedBox(height: 2),
                        Text(condition['description'],
                            style: TextStyle(
                                fontSize: 11,
                                color: isSelected
                                    ? Colors.white.withOpacity(0.9)
                                    : AppColors.textLight)),
                      ],
                    ),
                  ),
                  if (isSelected)
                    const Icon(Icons.check_circle,
                        color: Colors.white, size: 22),
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
          color: isSelected ? AppColors.primary : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? AppColors.primary : AppColors.lightGrey,
              width: isSelected ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: isSelected ? Colors.white : AppColors.primary,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14)),
      ),
    );
  }

  Widget _buildSymptomsField() {
    return TextField(
      maxLines: 3,
      onChanged: (value) => setState(() => _symptoms = value),
      decoration: InputDecoration(
        hintText: 'Describe symptoms, pain level, duration...',
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

  Widget _buildMedicalGuidelines() {
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
              Text('While Waiting for Help',
                  style: TextStyle(
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary,
                      fontSize: 15)),
            ],
          ),
          const SizedBox(height: 12),
          _buildGuidelineItem('Keep the patient calm and comfortable'),
          _buildGuidelineItem('Do not give food or water unless instructed'),
          _buildGuidelineItem('Monitor breathing and consciousness'),
          _buildGuidelineItem('Have medical information ready for responders'),
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

  void _submitMedicalAlert() {
    if (_selectedCondition == null) return;

    final emergencyData = {
      'type': 'medical',
      'condition': _selectedCondition,
      'isConscious': _isConscious,
      'needsAmbulance': _needsAmbulance,
      'symptoms': _symptoms,
      'medicalID': {
        'name': widget.userName,
        'bloodType': 'O+',
        'allergies': 'None',
        'medications': 'None',
      },
      'timestamp': DateTime.now().toIso8601String(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmergencyConfirmationScreen(
          emergencyData: emergencyData,
          emergencyTitle: 'Medical Emergency',
          emergencyColor: AppColors.primary,
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }
}
