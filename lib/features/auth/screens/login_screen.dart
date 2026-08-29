import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/auth_logo_badge.dart';
import '../../../shared/widgets/google_button.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../../services/fcm_service.dart';
import '../../../services/google_auth_service.dart';
import 'sign_up_screen.dart';
import 'forgot_password_screen.dart';
import 'family_setup_screen.dart';
import '../../dashboard/screens/dashboard_screen.dart';
import '../../../services/background_service.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _isLoading = false;
  bool _isGoogleLoading = false;

  // Direct Firebase URL — same one used in FirebaseService
  static const String _dbUrl =
      'https://lifeguard-cefd9-default-rtdb.asia-southeast1.firebasedatabase.app/';

  // Subtle entrance for the card so the screen doesn't just snap into place.
  late final AnimationController _entranceController;
  late final Animation<double> _fadeAnim;
  late final Animation<Offset> _slideAnim;

  @override
  void initState() {
    super.initState();
    _entranceController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 550),
    );
    _fadeAnim = CurvedAnimation(
      parent: _entranceController,
      curve: Curves.easeOut,
    );
    _slideAnim = Tween<Offset>(
      begin: const Offset(0, 0.06),
      end: Offset.zero,
    ).animate(
        CurvedAnimation(parent: _entranceController, curve: Curves.easeOutCubic));
    _entranceController.forward();
  }

  @override
  void dispose() {
    _entranceController.dispose();
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  /// Reads /Accounts/{userId}/FamilyCode directly from Firebase REST.
  /// Returns the code string, or empty string if none.
  Future<String> _fetchFamilyCodeDirectly(String userId) async {
    try {
      final url = '${_dbUrl}Accounts/$userId/FamilyCode.json';
      print('🔎 Direct read: $url');
      final response =
          await http.get(Uri.parse(url)).timeout(const Duration(seconds: 10));
      print('🔎 Raw FamilyCode response: ${response.body}');

      if (response.statusCode == 200) {
        final raw = response.body.trim();
        if (raw == 'null' || raw.isEmpty) return '';
        return raw.replaceAll('"', '').trim();
      }
    } catch (e) {
      print('❌ Direct FamilyCode read error: $e');
    }
    return '';
  }

  /// Save user session to SharedPreferences so we can skip login next time.
  Future<void> _saveSession({
    required String userId,
    required String userName,
    String familyCode = '',
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
    await prefs.setString('userName', userName);
    // ── FIX: persist familyCode so EmergencyReportService can read it ──
    if (familyCode.isNotEmpty) {
      await prefs.setString('familyCode', familyCode);
    } else {
      await prefs.remove('familyCode');
    }
    print(
        '💾 Session saved for $userName ($userId) | familyCode: "$familyCode"');
  }

  Future<void> _handleLogin() async {
    if (!_formKey.currentState!.validate()) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Please fill in all fields'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final result = await FirebaseService.login(
        emailOrMobile: _emailController.text.trim(),
        password: _passwordController.text,
      );

      if (mounted) {
        if (result['success'] == true) {
          await _completeLogin(result);
          if (mounted) setState(() => _isLoading = false);
        } else {
          setState(() => _isLoading = false);
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(result['error'] ?? 'Login failed'),
              backgroundColor: AppColors.danger,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('An error occurred: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  /// Shared post-login flow: starts the background service, resolves the
  /// family code, persists the session, and navigates. Used by both
  /// email/password login and Google login since they return the same
  /// result shape.
  Future<void> _completeLogin(Map<String, dynamic> result) async {
    final userId = result['userId']?.toString() ?? '';
    final userName = result['userName']?.toString() ?? 'User';
    final userEmail = result['userEmail']?.toString() ?? '';
    final mobile = result['mobileNumber']?.toString() ?? '';
    final barangay = result['barangay']?.toString() ?? '';
    final zipCode = result['zipCode']?.toString() ?? '';

    print('✅ Login OK | userId: $userId');

    await AppBackgroundService.start();
    print('🚀 Background service started after login');

    final familyCode = await _fetchFamilyCodeDirectly(userId);
    print('🏷️ FamilyCode after direct read: "$familyCode"');

    await _saveSession(
        userId: userId, userName: userName, familyCode: familyCode);

    await FcmService.saveTokenToFirebase(userId);

    if (!mounted) return;

    if (familyCode.isNotEmpty) {
      print('🏠 Has family → Dashboard');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => DashboardScreen(
            userId: userId,
            userName: userName,
          ),
        ),
      );
    } else {
      print('🔧 No family → FamilySetupScreen');
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(
          builder: (_) => FamilySetupScreen(
            userId: userId,
            userName: userName,
            userEmail: userEmail,
            mobile: mobile,
            barangay: barangay,
            zipCode: zipCode,
          ),
        ),
      );
    }
  }

  Future<void> _handleGoogleLogin() async {
    setState(() => _isGoogleLoading = true);
    try {
      final googleResult = await GoogleAuthService.signIn();
      if (googleResult == null) {
        // User cancelled the account picker.
        setState(() => _isGoogleLoading = false);
        return;
      }

      final result =
          await FirebaseService.loginWithGoogle(googleUid: googleResult.uid);

      if (!mounted) return;

      if (result['success'] == true) {
        await _completeLogin(result);
        if (mounted) setState(() => _isGoogleLoading = false);
      } else {
        // No linked account yet — this Google identity hasn't signed up.
        await GoogleAuthService.signOut();
        setState(() => _isGoogleLoading = false);
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ??
                'No account is linked to this Google account. Please sign up first.'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            action: SnackBarAction(
              label: 'Sign Up',
              textColor: Colors.white,
              onPressed: () {
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const SignupScreen()),
                );
              },
            ),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Google sign-in failed: $e'),
            backgroundColor: AppColors.danger,
            behavior: SnackBarBehavior.floating,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    final isKeyboardVisible = keyboardHeight > 0;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [AppColors.secondary, AppColors.primary],
          ),
        ),
        child: SafeArea(
          child: LayoutBuilder(
            builder: (context, constraints) {
              return SingleChildScrollView(
                padding: EdgeInsets.symmetric(
                  horizontal: ResponsiveUtils.getResponsivePadding(context),
                  vertical: 24,
                ),
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    minHeight: constraints.maxHeight - 48,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!isKeyboardVisible) ...[
                        Center(
                          child: AuthLogoBadge(
                            size: ResponsiveUtils.getScaledSize(context, 84),
                          ),
                        ),
                        const SizedBox(height: 20),
                        Text(
                          'LifeGuard360',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize:
                                ResponsiveUtils.getResponsiveFontSize(context, 30),
                            fontWeight: FontWeight.bold,
                            color: Colors.white,
                            letterSpacing: 0.3,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Sign in to keep your family safe',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize:
                                ResponsiveUtils.getResponsiveFontSize(context, 13),
                            color: Colors.white.withOpacity(0.85),
                          ),
                        ),
                        const SizedBox(height: 32),
                      ] else
                        const SizedBox(height: 12),
                      FadeTransition(
                        opacity: _fadeAnim,
                        child: SlideTransition(
                          position: _slideAnim,
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(24, 32, 24, 28),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(28),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withOpacity(0.18),
                                  blurRadius: 30,
                                  offset: const Offset(0, 14),
                                ),
                              ],
                            ),
                            child: Form(
                              key: _formKey,
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    'Welcome back',
                                    style: TextStyle(
                                      fontSize: ResponsiveUtils
                                          .getResponsiveFontSize(context, 20),
                                      fontWeight: FontWeight.bold,
                                      color: AppColors.secondary,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    'Enter your details to continue',
                                    style: TextStyle(
                                      fontSize: ResponsiveUtils
                                          .getResponsiveFontSize(context, 12),
                                      color: AppColors.textLight,
                                    ),
                                  ),
                                  const SizedBox(height: 24),
                                  CustomTextField(
                                    controller: _emailController,
                                    labelText: 'Email / Mobile',
                                    hintText: 'Email / Mobile',
                                    prefixIcon: Icons.person_outline,
                                    keyboardType: TextInputType.emailAddress,
                                    onChanged: () => setState(() {}),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your email or mobile';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 16),
                                  CustomTextField(
                                    controller: _passwordController,
                                    labelText: 'Password',
                                    hintText: 'Password',
                                    prefixIcon: Icons.lock_outline,
                                    isPassword: true,
                                    onChanged: () => setState(() {}),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return 'Please enter your password';
                                      }
                                      return null;
                                    },
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: GestureDetector(
                                      onTap: () => Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                            builder: (_) =>
                                                const ForgotPasswordScreen()),
                                      ),
                                      child: Text(
                                        'Forgot Password?',
                                        style: TextStyle(
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.w600,
                                          fontSize: ResponsiveUtils
                                              .getResponsiveFontSize(
                                                  context, 12.5),
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 18),
                                  CustomButton(
                                    text: 'LOG IN',
                                    icon: Icons.login_rounded,
                                    onPressed: _handleLogin,
                                    isLoading: _isLoading,
                                    height: 54,
                                  ),
                                  const SizedBox(height: 16),
                                  Row(
                                    children: [
                                      Expanded(
                                          child: Divider(
                                              color: AppColors.lightGrey)),
                                      Padding(
                                        padding: const EdgeInsets.symmetric(
                                            horizontal: 10),
                                        child: Text(
                                          'OR',
                                          style: TextStyle(
                                            fontSize: 11,
                                            color: AppColors.textLight,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ),
                                      Expanded(
                                          child: Divider(
                                              color: AppColors.lightGrey)),
                                    ],
                                  ),
                                  const SizedBox(height: 16),
                                  GoogleButton(
                                    text: 'Login with Google',
                                    isLoading: _isGoogleLoading,
                                    onPressed: _handleGoogleLogin,
                                  ),
                                  const SizedBox(height: 20),
                                  Row(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      Text(
                                        "Don't have an account? ",
                                        style: TextStyle(
                                          color: AppColors.textLight,
                                          fontSize: ResponsiveUtils
                                              .getResponsiveFontSize(context, 13),
                                        ),
                                      ),
                                      GestureDetector(
                                        onTap: () => Navigator.push(
                                          context,
                                          MaterialPageRoute(
                                              builder: (_) =>
                                                  const SignupScreen()),
                                        ),
                                        child: Text(
                                          'Sign Up',
                                          style: TextStyle(
                                            color: AppColors.primary,
                                            fontWeight: FontWeight.bold,
                                            fontSize: ResponsiveUtils
                                                .getResponsiveFontSize(
                                                    context, 13),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
