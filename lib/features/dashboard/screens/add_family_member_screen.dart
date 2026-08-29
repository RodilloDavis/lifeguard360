import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/family_service.dart';
import '../../../models/family_model.dart';
import '../../../models/family_member_model.dart';
import '../../../shared/widgets/custom_text_field.dart';

class AddFamilyMemberScreen extends StatefulWidget {
  final String currentFamilyId;

  const AddFamilyMemberScreen({
    super.key,
    required this.currentFamilyId,
  });

  @override
  State<AddFamilyMemberScreen> createState() => _AddFamilyMemberScreenState();
}

class _AddFamilyMemberScreenState extends State<AddFamilyMemberScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _familyCodeController = TextEditingController();
  final _familyCodeFocus = FocusNode(); // ← NEW

  final FamilyService _familyService = FamilyService();

  String _selectedRole = 'Son';
  bool _isVerifying = false;
  bool _isSubmitting = false;
  bool _isFamilyCodeValid = false;
  FamilyModel? _verifiedFamily;

  final List<String> _roles = [
    'Father',
    'Mother',
    'Son',
    'Daughter',
    'Guardian',
    'Grandfather',
    'Grandmother',
    'Uncle',
    'Aunt',
    'Other',
  ];

  @override
  void initState() {
    super.initState();
    _familyCodeFocus
        .addListener(() => setState(() {})); // ← NEW: rebuild on focus change
    _loadCurrentFamilyCode();
  }

  Future<void> _loadCurrentFamilyCode() async {
    print('🔍 Loading family code for: ${widget.currentFamilyId}');
    final code = await _familyService.getFamilyCode(widget.currentFamilyId);
    if (code != null && mounted) {
      print('✅ Family code loaded: $code');
      setState(() {
        _familyCodeController.text = code;
      });
      _verifyFamilyCode();
    } else {
      print('❌ No family code found');
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _emailController.dispose();
    _familyCodeController.dispose();
    _familyCodeFocus.dispose(); // ← NEW
    super.dispose();
  }

  Future<void> _verifyFamilyCode() async {
    if (_familyCodeController.text.trim().isEmpty) {
      setState(() {
        _isFamilyCodeValid = false;
        _verifiedFamily = null;
      });
      return;
    }

    if (_familyCodeController.text.trim().length != 6) {
      _showErrorSnackBar('Family code must be 6 digits');
      return;
    }

    setState(() => _isVerifying = true);

    try {
      print('🔍 Verifying family code: ${_familyCodeController.text.trim()}');
      final family = await _familyService.verifyFamilyCode(
        _familyCodeController.text.trim(),
      );

      if (family != null) {
        print('✅ Family verified: ${family.familyName}');
        setState(() {
          _isFamilyCodeValid = true;
          _verifiedFamily = family;
          _isVerifying = false;
        });

        _showSuccessSnackBar('✓ Connected to ${family.familyName}');
      } else {
        throw Exception('Family not found');
      }
    } catch (e) {
      print('❌ Verification failed: $e');
      setState(() {
        _isFamilyCodeValid = false;
        _verifiedFamily = null;
        _isVerifying = false;
      });
      _showErrorSnackBar('Invalid family code. Please try again.');
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isFamilyCodeValid) {
      _showErrorSnackBar('Please verify the family code first');
      return;
    }

    setState(() => _isSubmitting = true);

    try {
      print('📝 Adding member: ${_nameController.text.trim()}');
      final user = await _familyService.addUserToFamily(
        name: _nameController.text.trim(),
        email: _emailController.text.trim(),
        role: _selectedRole,
        familyCode: _familyCodeController.text.trim(),
      );

      print('✅ Member added successfully: ${user.name}');

      if (mounted) {
        _showSuccessSnackBar('${user.name} added successfully!');
        await Future.delayed(const Duration(seconds: 1));
        if (mounted) {
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      print('❌ Failed to add member: $e');
      setState(() => _isSubmitting = false);
      _showErrorSnackBar('Failed to add member: ${e.toString()}');
    }
  }

  void _showSuccessSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.check_circle, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.success,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.error_outline, color: Colors.white),
            const SizedBox(width: 12),
            Expanded(child: Text(message)),
          ],
        ),
        backgroundColor: AppColors.danger,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Add Family Member',
          style: TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: SingleChildScrollView(
        child: Padding(
          padding: const EdgeInsets.all(20.0),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildHeaderSection(),
                const SizedBox(height: 24),
                _buildFamilyCodeSection(),
                const SizedBox(height: 24),
                _buildMemberDetailsSection(),
                const SizedBox(height: 32),
                _buildPermissionsInfo(),
                const SizedBox(height: 24),
                _buildSubmitButton(),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderSection() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            AppColors.primary.withOpacity(0.1),
            AppColors.primary.withOpacity(0.05)
          ],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Icon(Icons.person_add, color: Colors.white, size: 28),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invite Family Member',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Connect your family for safety tracking',
                  style: TextStyle(
                    fontSize: 12,
                    color: AppColors.textLight,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ─── Family Code Section (keeps centred numeric style, adds floating label) ──
  Widget _buildFamilyCodeSection() {
    final isFocused = _familyCodeFocus.hasFocus;
    final hasValue = _familyCodeController.text.isNotEmpty;
    final labelIsUp = hasValue || isFocused || _isFamilyCodeValid;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: _isFamilyCodeValid
            ? Colors.green.withOpacity(0.05)
            : AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: _isFamilyCodeValid
              ? Colors.green
              : AppColors.grey.withOpacity(0.3),
          width: _isFamilyCodeValid ? 2 : 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                _isFamilyCodeValid ? Icons.check_circle : Icons.family_restroom,
                color: _isFamilyCodeValid ? Colors.green : AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Family Connection Code',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _familyCodeController,
            focusNode: _familyCodeFocus,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              letterSpacing: 4,
            ),
            decoration: InputDecoration(
              labelText: 'Family Code',
              labelStyle: TextStyle(
                color: isFocused
                    ? AppColors.primary
                    : (_isFamilyCodeValid ? Colors.green : AppColors.grey),
                fontSize: labelIsUp ? 12 : 14,
                fontWeight: FontWeight.w500,
              ),
              hintText: labelIsUp ? null : '000000',
              hintStyle: TextStyle(
                color: AppColors.grey.withOpacity(0.5),
                letterSpacing: 4,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.lightGrey,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.primary,
                  width: 2,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.danger,
                  width: 1,
                ),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(
                  color: AppColors.danger,
                  width: 2,
                ),
              ),
              errorStyle: const TextStyle(
                color: AppColors.danger,
                fontSize: 12,
              ),
              prefixIcon: const Icon(Icons.qr_code_2, color: AppColors.primary),
              suffixIcon: _isVerifying
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      ),
                    )
                  : _isFamilyCodeValid
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : IconButton(
                          icon: const Icon(Icons.search,
                              color: AppColors.primary),
                          onPressed: _verifyFamilyCode,
                        ),
              counterText: '',
            ),
            onChanged: (value) {
              setState(() {}); // ← label reacts instantly
              if (value.length == 6) {
                _verifyFamilyCode();
              } else {
                setState(() {
                  _isFamilyCodeValid = false;
                  _verifiedFamily = null;
                });
              }
            },
            validator: (value) {
              if (value == null || value.isEmpty) {
                return 'Please enter family code';
              }
              if (value.length != 6) {
                return 'Family code must be 6 digits';
              }
              return null;
            },
          ),
          if (_verifiedFamily != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.green.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  const Icon(Icons.verified, color: Colors.green, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Verified: ${_verifiedFamily!.familyName}',
                      style: const TextStyle(
                        color: Colors.green,
                        fontWeight: FontWeight.w600,
                        fontSize: 14,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 12),
          const Text(
            'Enter the 6-digit family code to connect this member to your family circle.',
            style: TextStyle(
              fontSize: 12,
              color: AppColors.textLight,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }

  // ─── Member Details (CustomTextField for name & email) ──────────────────────
  Widget _buildMemberDetailsSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Member Information',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 16),
        CustomTextField(
          controller: _nameController,
          labelText: 'Full Name',
          hintText: 'Full Name',
          prefixIcon: Icons.person_outline,
          onChanged: () => setState(() {}),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter full name';
            }
            if (value.length < 3) {
              return 'Name must be at least 3 characters';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        CustomTextField(
          controller: _emailController,
          labelText: 'Email Address',
          hintText: 'Email Address',
          prefixIcon: Icons.email_outlined,
          keyboardType: TextInputType.emailAddress,
          onChanged: () => setState(() {}),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter email address';
            }
            if (!value.contains('@') || !value.contains('.')) {
              return 'Please enter a valid email';
            }
            return null;
          },
        ),
        const SizedBox(height: 16),
        const Text(
          'Family Role',
          style: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 8),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lightGrey),
            borderRadius: BorderRadius.circular(12),
          ),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedRole,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.people_outline),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: _roles.map((role) {
              return DropdownMenuItem(
                value: role,
                child: Text(role),
              );
            }).toList(),
            onChanged: (value) {
              setState(() => _selectedRole = value!);
            },
          ),
        ),
      ],
    );
  }

  Widget _buildPermissionsInfo() {
    final permissions = Permissions.forRole(_selectedRole);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.blue.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.blue.withOpacity(0.2)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const Icon(Icons.security, color: Colors.blue, size: 20),
              const SizedBox(width: 8),
              Text(
                'Permissions for $_selectedRole',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                  color: AppColors.secondary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _buildPermissionItem(
              'View family locations', permissions.viewLocation),
          _buildPermissionItem('Send SOS alerts', permissions.sendSOS),
          _buildPermissionItem(
              'Receive emergency alerts', permissions.receiveAlerts),
          _buildPermissionItem(
              'Manage family members', permissions.manageMembers),
        ],
      ),
    );
  }

  Widget _buildPermissionItem(String label, bool enabled) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8.0),
      child: Row(
        children: [
          Icon(
            enabled ? Icons.check_circle : Icons.cancel,
            size: 16,
            color: enabled ? Colors.green : AppColors.grey,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 12,
                color: enabled ? AppColors.secondary : AppColors.textLight,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmitButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: (_isFamilyCodeValid && !_isSubmitting) ? _submitForm : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.grey.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: _isFamilyCodeValid ? 4 : 0,
        ),
        child: _isSubmitting
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                  color: Colors.white,
                  strokeWidth: 2,
                ),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.person_add, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Add Family Member',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.5,
                    ),
                  ),
                ],
              ),
      ),
    );
  }
}
