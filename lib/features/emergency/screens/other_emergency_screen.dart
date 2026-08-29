import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/form_auto_scroll.dart';
import '../../../shared/widgets/custom_button.dart';
import 'emergency_confirmation_screen.dart';

class OtherEmergencyScreen extends StatefulWidget {
  final String userId;
  final String userName;

  const OtherEmergencyScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  State<OtherEmergencyScreen> createState() => _OtherEmergencyScreenState();
}

class _OtherEmergencyScreenState extends State<OtherEmergencyScreen>
    with AutoScrollForm<OtherEmergencyScreen> {
  @override
  List<Object> get autoScrollSteps =>
      const ['category', 'description', 'urgent', 'assistance', 'send'];

  String? _selectedCategory;
  String _emergencyDescription = '';
  bool _isUrgent = true;
  bool _needsImmediateHelp = true;

  final List<Map<String, dynamic>> _categories = [
    {'id': 'gas_leak', 'label': 'Gas Leak', 'icon': Icons.gas_meter},
    {'id': 'power_outage', 'label': 'Power Outage', 'icon': Icons.power_off},
    {'id': 'animal', 'label': 'Animal Emergency', 'icon': Icons.pets},
    {
      'id': 'missing_person',
      'label': 'Missing Person',
      'icon': Icons.person_search
    },
    {'id': 'chemical', 'label': 'Chemical Spill', 'icon': Icons.science},
    {
      'id': 'structural',
      'label': 'Structural Damage',
      'icon': Icons.home_repair_service
    },
    {'id': 'other', 'label': 'Other', 'icon': Icons.help_outline},
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Other Emergency',
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
                'category',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Emergency Category'),
                    const SizedBox(height: 12),
                    _buildCategorySelection(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'description',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Describe the Emergency'),
                    const SizedBox(height: 12),
                    _buildDescriptionField(),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'urgent',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Is this urgent?'),
                    const SizedBox(height: 12),
                    _buildToggleButtons(
                      ['Yes, Urgent', 'No, Not Urgent'],
                      _isUrgent,
                      (value) {
                        setState(() => _isUrgent = value);
                        advanceFrom('urgent');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
              autoScrollStep(
                'assistance',
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildSectionTitle('Do you need immediate assistance?'),
                    const SizedBox(height: 12),
                    _buildToggleButtons(
                      ['Yes', 'No'],
                      _needsImmediateHelp,
                      (value) {
                        setState(() => _needsImmediateHelp = value);
                        advanceFrom('assistance');
                      },
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),
              _buildImportantNote(),
              const SizedBox(height: 24),
              autoScrollStep(
                'send',
                CustomButton(
                  text: 'SUBMIT EMERGENCY REPORT',
                  color: AppColors.grey,
                  onPressed: (_selectedCategory != null &&
                          _emergencyDescription.isNotEmpty)
                      ? _submitOtherEmergency
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
          colors: [AppColors.grey, AppColors.grey.withOpacity(0.8)],
        ),
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: AppColors.grey.withOpacity(0.3),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: const Row(
        children: [
          Icon(Icons.more_horiz, color: Colors.white, size: 32),
          SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('General Emergency',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold)),
                SizedBox(height: 4),
                Text('We\'re here to help',
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

  Widget _buildCategorySelection() {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: _categories.map((category) {
        final isSelected = _selectedCategory == category['id'];
        return GestureDetector(
          onTap: () {
            setState(() => _selectedCategory = category['id']);
            advanceFrom('category');
          },
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isSelected ? AppColors.grey : Colors.white,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                  color: isSelected ? AppColors.grey : AppColors.lightGrey,
                  width: isSelected ? 2 : 1),
              boxShadow: isSelected
                  ? [
                      BoxShadow(
                          color: AppColors.grey.withOpacity(0.2),
                          blurRadius: 8,
                          offset: const Offset(0, 2))
                    ]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(category['icon'],
                    color: isSelected ? Colors.white : AppColors.grey,
                    size: 18),
                const SizedBox(width: 8),
                Text(category['label'],
                    style: TextStyle(
                        color: isSelected ? Colors.white : AppColors.grey,
                        fontWeight:
                            isSelected ? FontWeight.bold : FontWeight.w500,
                        fontSize: 13)),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  Widget _buildDescriptionField() {
    return TextField(
      maxLines: 5,
      onChanged: (value) => setState(() => _emergencyDescription = value),
      decoration: InputDecoration(
        hintText: 'Please provide detailed information about the emergency:\n'
            '• What happened?\n'
            '• Where did it happen?\n'
            '• Are there any immediate dangers?\n'
            '• What help do you need?',
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
          color: isSelected ? AppColors.grey : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
              color: isSelected ? AppColors.grey : AppColors.lightGrey,
              width: isSelected ? 2 : 1),
        ),
        alignment: Alignment.center,
        child: Text(label,
            style: TextStyle(
                color: isSelected ? Colors.white : AppColors.grey,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                fontSize: 14)),
      ),
    );
  }

  Widget _buildImportantNote() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.red.withOpacity(0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.red.withOpacity(0.3)),
      ),
      child: const Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.priority_high, color: Colors.red, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Important',
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary)),
                SizedBox(height: 4),
                Text(
                  'For life-threatening emergencies, always call emergency services (911 or local emergency number) immediately.',
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

  void _submitOtherEmergency() {
    if (_selectedCategory == null || _emergencyDescription.isEmpty) return;

    final emergencyData = {
      'type': 'other',
      'category': _selectedCategory,
      'description': _emergencyDescription,
      'isUrgent': _isUrgent,
      'needsImmediateHelp': _needsImmediateHelp,
      'timestamp': DateTime.now().toIso8601String(),
    };

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => EmergencyConfirmationScreen(
          emergencyData: emergencyData,
          emergencyTitle: 'Emergency Report',
          emergencyColor: AppColors.grey,
          userId: widget.userId,
          userName: widget.userName,
        ),
      ),
    );
  }
}
