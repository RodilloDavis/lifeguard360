import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/firebase_realtime_database.dart';

class JoinFamilyScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final String mobile;
  final String barangay;
  final String zipCode;

  const JoinFamilyScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.mobile = '',
    this.barangay = '',
    this.zipCode = '',
  });

  @override
  State<JoinFamilyScreen> createState() => _JoinFamilyScreenState();
}

class _JoinFamilyScreenState extends State<JoinFamilyScreen> {
  final _formKey = GlobalKey<FormState>();
  final _familyCodeController = TextEditingController();
  final _familyCodeFocus = FocusNode();

  String _selectedRole = 'Son';
  bool _isVerifying = false;
  bool _isJoining = false;
  bool _isFamilyCodeValid = false;
  Map<String, dynamic>? _verifiedFamily; // raw map from FirebaseService

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
    _familyCodeFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _familyCodeController.dispose();
    _familyCodeFocus.dispose();
    super.dispose();
  }

  // ─── QR Scanner ──────────────────────────────────────────────────────────────

  void _showQrScanner() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _QrScannerSheet(
        onCodeScanned: (code) {
          Navigator.pop(context);
          _familyCodeController.text = code;
          setState(() {
            _isFamilyCodeValid = false;
            _verifiedFamily = null;
          });
          _verifyFamilyCode();
        },
      ),
    );
  }

  // ─── Verify Family Code ───────────────────────────────────────────────────
  // Calls FirebaseService.getFamilyByCode() → checks /Families/{code}

  Future<void> _verifyFamilyCode() async {
    final code = _familyCodeController.text.trim();

    if (code.isEmpty) {
      setState(() {
        _isFamilyCodeValid = false;
        _verifiedFamily = null;
      });
      return;
    }

    if (code.length != 6) {
      _showErrorSnackBar('Family code must be 6 digits');
      return;
    }

    setState(() => _isVerifying = true);

    try {
      print('🔵 Verifying family code: $code');
      final family = await FirebaseService.getFamilyByCode(code);

      if (family != null) {
        print('✅ Family found: ${family['FamilyName']}');
        setState(() {
          _isFamilyCodeValid = true;
          _verifiedFamily = family;
          _isVerifying = false;
        });
        _showSuccessSnackBar('Found: ${family['FamilyName']}');
      } else {
        print('❌ No family found for code: $code');
        setState(() {
          _isFamilyCodeValid = false;
          _verifiedFamily = null;
          _isVerifying = false;
        });
        _showErrorSnackBar('Invalid family code. Family not found.');
      }
    } catch (e) {
      print('❌ Verify error: $e');
      setState(() {
        _isFamilyCodeValid = false;
        _verifiedFamily = null;
        _isVerifying = false;
      });
      _showErrorSnackBar('Error verifying code: $e');
    }
  }

  // ─── Join Family ──────────────────────────────────────────────────────────
  // Calls FirebaseService.joinFamily() →
  //   saves member under /Families/{code}/Members/{userId}
  //   updates account fields: FamilyId, FamilyCode, FamilyName, FamilyRole

  Future<void> _joinFamily() async {
    if (!_formKey.currentState!.validate()) return;

    if (!_isFamilyCodeValid) {
      _showErrorSnackBar('Please verify the family code first');
      return;
    }

    setState(() => _isJoining = true);

    try {
      print(
          '🔵 Joining family with code: ${_familyCodeController.text.trim()}');
      print('🔵 UserId: ${widget.userId} | Role: $_selectedRole');

      final result = await FirebaseService.joinFamily(
        userId: widget.userId,
        userName: widget.userName,
        familyCode: _familyCodeController.text.trim(),
        role: _selectedRole,
      );

      print('🔵 Join result: $result');

      if (mounted) {
        if (result['success'] == true) {
          _showSuccessSnackBar(
            result['message'] ?? 'Successfully joined family!',
          );
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) Navigator.pop(context, true);
        } else {
          setState(() => _isJoining = false);
          _showErrorSnackBar(result['error'] ?? 'Failed to join family');
        }
      }
    } catch (e) {
      print('❌ Join family error: $e');
      if (mounted) {
        setState(() => _isJoining = false);
        _showErrorSnackBar('Failed to join family: $e');
      }
    }
  }

  // ─── Snackbars ────────────────────────────────────────────────────────────

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
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
    if (!mounted) return;
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

  // ─── Build ────────────────────────────────────────────────────────────────

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
          'Join Family',
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
                _buildInfoBanner(),
                const SizedBox(height: 24),
                _buildFamilyCodeSection(),
                const SizedBox(height: 16),
                _buildOrDivider(),
                const SizedBox(height: 16),
                _buildScanQrButton(),
                const SizedBox(height: 24),
                _buildRoleSelection(),
                const SizedBox(height: 32),
                _buildJoinButton(),
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
            AppColors.primary.withOpacity(0.05),
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
            child: const Icon(
              Icons.family_restroom,
              color: Colors.white,
              size: 28,
            ),
          ),
          const SizedBox(width: 16),
          const Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Join Family Circle',
                  style: TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary,
                  ),
                ),
                SizedBox(height: 4),
                Text(
                  'Connect with your family for safety',
                  style: TextStyle(fontSize: 12, color: AppColors.textLight),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoBanner() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: AppColors.primary.withOpacity(0.05),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.primary.withOpacity(0.2)),
      ),
      child: const Row(
        children: [
          Icon(Icons.info_outline, color: AppColors.primary, size: 24),
          SizedBox(width: 12),
          Expanded(
            child: Text(
              'Ask your family admin for the 6-digit family code',
              style: TextStyle(
                fontSize: 13,
                color: AppColors.secondary,
                height: 1.4,
              ),
            ),
          ),
        ],
      ),
    );
  }

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
                _isFamilyCodeValid ? Icons.check_circle : Icons.qr_code_2,
                color: _isFamilyCodeValid ? Colors.green : AppColors.primary,
                size: 24,
              ),
              const SizedBox(width: 12),
              const Text(
                'Family Code',
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
              fontSize: 24,
              fontWeight: FontWeight.bold,
              letterSpacing: 8,
            ),
            textAlign: TextAlign.center,
            decoration: InputDecoration(
              labelText: 'Family Code',
              labelStyle: TextStyle(
                color: isFocused
                    ? AppColors.primary
                    : (_isFamilyCodeValid ? Colors.green : AppColors.grey),
                fontSize: labelIsUp ? 12 : 14,
                fontWeight: FontWeight.w500,
              ),
              hintText: labelIsUp ? null : '------',
              hintStyle: TextStyle(
                color: AppColors.grey.withOpacity(0.3),
                letterSpacing: 8,
              ),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.lightGrey, width: 1),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.danger, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: const BorderSide(color: AppColors.danger, width: 2),
              ),
              errorStyle:
                  const TextStyle(color: AppColors.danger, fontSize: 12),
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
                      : null,
              counterText: '',
            ),
            onChanged: (value) {
              setState(() {}); // label reacts instantly
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
              if (value.length != 6) return 'Family code must be 6 digits';
              return null;
            },
          ),

          // Verified family banner
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Verified',
                          style: TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.bold,
                            fontSize: 12,
                          ),
                        ),
                        Text(
                          _verifiedFamily!['FamilyName'] ?? 'Family',
                          style: const TextStyle(
                            color: Colors.green,
                            fontWeight: FontWeight.w600,
                            fontSize: 16,
                          ),
                        ),
                        Text(
                          'Admin: ${_verifiedFamily!['CreatedByName'] ?? 'Unknown'}',
                          style: const TextStyle(
                            color: Colors.green,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildOrDivider() {
    return Row(
      children: [
        const Expanded(child: Divider(color: AppColors.lightGrey)),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'OR',
            style: TextStyle(
              color: AppColors.grey,
              fontSize: 13,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        const Expanded(child: Divider(color: AppColors.lightGrey)),
      ],
    );
  }

  Widget _buildScanQrButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: OutlinedButton.icon(
        onPressed: _showQrScanner,
        icon: const Icon(Icons.qr_code_scanner, size: 24),
        label: const Text(
          'Scan QR Code',
          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
        ),
        style: OutlinedButton.styleFrom(
          foregroundColor: AppColors.primary,
          side: const BorderSide(color: AppColors.primary, width: 2),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
        ),
      ),
    );
  }

  Widget _buildRoleSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text(
          'Your Role in Family',
          style: TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 12),
        Container(
          decoration: BoxDecoration(
            border: Border.all(color: AppColors.lightGrey),
            borderRadius: BorderRadius.circular(12),
            color: Colors.white,
          ),
          child: DropdownButtonFormField<String>(
            initialValue: _selectedRole,
            decoration: const InputDecoration(
              prefixIcon: Icon(Icons.people_outline),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: _roles
                .map((role) => DropdownMenuItem(value: role, child: Text(role)))
                .toList(),
            onChanged: (value) => setState(() => _selectedRole = value!),
          ),
        ),
      ],
    );
  }

  Widget _buildJoinButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: (_isFamilyCodeValid && !_isJoining) ? _joinFamily : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.primary,
          disabledBackgroundColor: AppColors.grey.withOpacity(0.3),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
          ),
          elevation: _isFamilyCodeValid ? 4 : 0,
        ),
        child: _isJoining
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login, size: 24),
                  SizedBox(width: 12),
                  Text(
                    'Join Family',
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

// ═══════════════════════════════════════════════════════════════════════════════
// QR Scanner Bottom Sheet
// Uses mobile_scanner to read the family code from a QR generated by InviteScreen
// ═══════════════════════════════════════════════════════════════════════════════

class _QrScannerSheet extends StatefulWidget {
  final void Function(String code) onCodeScanned;

  const _QrScannerSheet({required this.onCodeScanned});

  @override
  State<_QrScannerSheet> createState() => _QrScannerSheetState();
}

class _QrScannerSheetState extends State<_QrScannerSheet> {
  final MobileScannerController _controller = MobileScannerController();
  bool _hasScanned = false;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      height: MediaQuery.of(context).size.height * 0.75,
      decoration: const BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      child: Column(
        children: [
          // Handle bar
          Container(
            margin: const EdgeInsets.only(top: 12, bottom: 8),
            width: 40,
            height: 4,
            decoration: BoxDecoration(
              color: Colors.white38,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
          // Title
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 12),
            child: Text(
              'Scan Family QR Code',
              style: TextStyle(
                color: Colors.white,
                fontSize: 18,
                fontWeight: FontWeight.bold,
              ),
            ),
          ),
          // Scanner viewport
          Expanded(
            child: Stack(
              children: [
                MobileScanner(
                  controller: _controller,
                  onDetect: (capture) {
                    if (_hasScanned) return;
                    final barcodes = capture.barcodes;
                    for (final barcode in barcodes) {
                      final raw = barcode.rawValue;
                      if (raw != null && raw.isNotEmpty) {
                        // Validate: must be 6 digits
                        final code = raw.trim();
                        if (RegExp(r'^\d{6}\$').hasMatch(code)) {
                          _hasScanned = true;
                          widget.onCodeScanned(code);
                          return;
                        }
                      }
                    }
                  },
                ),
                // Scan frame overlay
                Center(
                  child: Container(
                    width: 220,
                    height: 220,
                    decoration: BoxDecoration(
                      border: Border.all(color: AppColors.primary, width: 3),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: Stack(
                      children: [
                        // Corner decorations
                        Positioned(top: 0, left: 0, child: _corner()),
                        Positioned(
                            top: 0,
                            right: 0,
                            child: Transform.rotate(
                                angle: 1.5708, child: _corner())),
                        Positioned(
                            bottom: 0,
                            left: 0,
                            child: Transform.rotate(
                                angle: -1.5708, child: _corner())),
                        Positioned(
                            bottom: 0,
                            right: 0,
                            child: Transform.rotate(
                                angle: 3.1416, child: _corner())),
                      ],
                    ),
                  ),
                ),
                // Hint text
                Positioned(
                  bottom: 40,
                  left: 0,
                  right: 0,
                  child: Center(
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 20, vertical: 8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Text(
                        'Point camera at the QR code',
                        style: TextStyle(color: Colors.white, fontSize: 13),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          // Controls
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  onPressed: () => _controller.toggleTorch(),
                  icon: const Icon(Icons.flashlight_on,
                      color: Colors.white, size: 28),
                  tooltip: 'Toggle flashlight',
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel',
                      style: TextStyle(color: Colors.white70, fontSize: 15)),
                ),
                IconButton(
                  onPressed: () => _controller.switchCamera(),
                  icon: const Icon(Icons.flip_camera_ios,
                      color: Colors.white, size: 28),
                  tooltip: 'Switch camera',
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _corner() {
    return Container(
      width: 24,
      height: 24,
      decoration: const BoxDecoration(
        border: Border(
          top: BorderSide(color: AppColors.primary, width: 4),
          left: BorderSide(color: AppColors.primary, width: 4),
        ),
      ),
    );
  }
}
