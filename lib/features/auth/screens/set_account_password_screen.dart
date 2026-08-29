import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/google_button.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../../services/google_auth_service.dart';

/// Lets a Google-signed-up account (no password on file) add a password
/// credential, so it can log in either with Google or with email/password
/// afterward. Requires re-confirming the linked Google account first, since
/// linking a password credential must happen while Firebase Auth's
/// currentUser is that same account.
class SetAccountPasswordScreen extends StatefulWidget {
  final String accountEmail;

  const SetAccountPasswordScreen({super.key, required this.accountEmail});

  @override
  State<SetAccountPasswordScreen> createState() =>
      _SetAccountPasswordScreenState();
}

class _SetAccountPasswordScreenState extends State<SetAccountPasswordScreen> {
  final _formKey = GlobalKey<FormState>();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  bool _isVerifying = false;
  bool _isVerified = false;
  bool _isSaving = false;

  @override
  void dispose() {
    _passwordController.dispose();
    _confirmController.dispose();
    super.dispose();
  }

  void _showSnackbar(String message, Color color) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: color,
        behavior: SnackBarBehavior.floating,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
      ),
    );
  }

  Future<void> _handleVerifyGoogle() async {
    setState(() => _isVerifying = true);
    try {
      final result = await GoogleAuthService.signIn();
      if (result == null) {
        setState(() => _isVerifying = false);
        return;
      }

      if (result.email.toLowerCase() != widget.accountEmail.toLowerCase()) {
        await GoogleAuthService.signOut();
        setState(() => _isVerifying = false);
        if (!mounted) return;
        _showSnackbar(
          'That Google account (${result.email}) doesn\'t match this profile\'s email (${widget.accountEmail}).',
          AppColors.danger,
        );
        return;
      }

      setState(() {
        _isVerifying = false;
        _isVerified = true;
      });
    } catch (e) {
      if (mounted) {
        setState(() => _isVerifying = false);
        _showSnackbar('Google verification failed: $e', AppColors.danger);
      }
    }
  }

  Future<void> _handleSetPassword() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSaving = true);

    final result = await FirebaseService.linkPasswordToCurrentUser(
      newPassword: _passwordController.text,
    );

    if (!mounted) return;
    setState(() => _isSaving = false);

    if (result['success'] == true) {
      _showSnackbar('Password set! You can now log in with email/password too.',
          AppColors.success);
      await Future.delayed(const Duration(milliseconds: 1400));
      if (mounted) Navigator.pop(context);
    } else {
      _showSnackbar(result['error'] ?? 'Failed to set password', AppColors.danger);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Set Account Password'),
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'This account (${widget.accountEmail}) signed up with Google and '
              'has no password yet. Confirm it\'s you, then choose a password.',
              style: const TextStyle(fontSize: 13, color: AppColors.textLight),
            ),
            const SizedBox(height: 24),
            if (!_isVerified) ...[
              GoogleButton(
                text: 'Confirm with Google',
                isLoading: _isVerifying,
                onPressed: _handleVerifyGoogle,
              ),
            ] else ...[
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                decoration: BoxDecoration(
                  color: AppColors.success.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.success.withOpacity(0.3)),
                ),
                child: Row(
                  children: [
                    const Icon(Icons.verified_rounded,
                        size: 16, color: AppColors.success),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        'Verified as ${widget.accountEmail}',
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.secondary,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              Form(
                key: _formKey,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    CustomTextField(
                      controller: _passwordController,
                      labelText: 'New Password',
                      hintText: 'New Password',
                      prefixIcon: Icons.lock_outline,
                      isPassword: true,
                      onChanged: () => setState(() {}),
                      validator: (value) {
                        if (value == null || value.isEmpty) {
                          return 'Please enter a password';
                        }
                        if (value.length < 6) {
                          return 'Password must be at least 6 characters';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 16),
                    CustomTextField(
                      controller: _confirmController,
                      labelText: 'Confirm Password',
                      hintText: 'Confirm Password',
                      prefixIcon: Icons.lock_outline,
                      isPassword: true,
                      onChanged: () => setState(() {}),
                      validator: (value) {
                        if (value != _passwordController.text) {
                          return 'Passwords do not match';
                        }
                        return null;
                      },
                    ),
                    const SizedBox(height: 24),
                    CustomButton(
                      text: 'SET PASSWORD',
                      icon: Icons.check_rounded,
                      onPressed: _handleSetPassword,
                      isLoading: _isSaving,
                      height: 54,
                    ),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
