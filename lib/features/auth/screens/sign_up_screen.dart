import 'dart:async';
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:math';
import '../../../core/constants/app_colors.dart';
import '../../../core/constants/panabo_barangays.dart';
import '../../../core/utils/responsive_utils.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/auth_logo_badge.dart';
import '../../../shared/widgets/google_button.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../../services/google_auth_service.dart';
import '../../../services/fcm_service.dart';
import '../../../services/background_service.dart';
import 'family_setup_screen.dart';

class SignupScreen extends StatefulWidget {
  const SignupScreen({super.key});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _mobileController = TextEditingController();
  final _emailController = TextEditingController();
  final _zipCodeController = TextEditingController();
  final _passwordController = TextEditingController();
  final _scrollController = ScrollController();

  // GPS-detected barangay (barangay name only)
  String? _detectedBarangay;

  // The coordinates behind _detectedBarangay — captured once here so
  // _handleSignup() can pass them straight to FirebaseService.register()
  // instead of it taking its own separate, unrelated GPS reading seconds
  // later (see register()'s _getCurrentLocation() fallback).
  double? _detectedLat;
  double? _detectedLng;

  // Manual fallback — only used when user taps "Not accurate?"
  String? _manualBarangay;
  bool _showManualDropdown = false;

  // True only when _detectedBarangay came from a live, non-mocked GPS fix
  // that fell within Panabo City — i.e. never true for the manual dropdown,
  // whether that was reached via a GPS failure or the "Not accurate?"
  // override. Stored on the account so a self-declared barangay is never
  // indistinguishable from a GPS-confirmed one.
  bool get _isLocationVerified => !_showManualDropdown && _detectedBarangay != null;

  bool _isLoading = false;
  bool _isDetectingLocation = false;
  String? _locationError;

  // ── Live email availability check ─────────────────────────────────────────
  // Debounced against FirebaseService.validateEmailForSignup so the user
  // sees "already registered" / "available" feedback before ever pressing
  // Sign Up, instead of only finding out after submitting the form.
  Timer? _emailCheckDebounce;
  bool _isCheckingEmail = false;
  // null = not checked yet (empty field or debounce still pending)
  bool? _emailIsAvailable;
  String? _emailStatusMessage;

  // ── Google Sign-Up state ──────────────────────────────────────────────────
  // Once the user authenticates with Google, we lock the email to the
  // verified Google address, hide the password field (Google is the
  // credential), and register the account with a GoogleUid link instead.
  bool _isGoogleLoading = false;
  bool _isGoogleSignup = false;
  String? _googleUid;
  String? _googlePhotoUrl;

  // Returns the active barangay name (without city/province suffix)
  String? get _activeBarangay =>
      _showManualDropdown ? _manualBarangay : _detectedBarangay;

  // Full address built from active barangay
  String? get _activeAddress => _activeBarangay != null
      ? '$_activeBarangay, Panabo City, Davao del Norte'
      : null;

  // ── Official 41 Barangays of Panabo City ─────────────────────────────────
  final List<String> _barangays = kPanaboBarangays;

  // ── GPS centroids [lat, lng] ──────────────────────────────────────────────
  static const Map<String, List<double>> _barangayCentroids = {
    'San Francisco (Poblacion)': [7.3118, 125.6765],
    'New Pandan (Poblacion)': [7.3145, 125.6720],
    'Gredu (Poblacion)': [7.3095, 125.6835],
    'Santo Niño (Poblacion)': [7.3055, 125.6810],
    'A. O. Floirendo': [7.3880, 125.7350],
    'Tagpore': [7.3720, 125.6980],
    'Lower Panaga (Roxas)': [7.3790, 125.6620],
    'Upper Licanan': [7.3650, 125.6480],
    'Waterfall': [7.3820, 125.6350],
    'Kasilak': [7.3550, 125.6830],
    'San Nicolas': [7.3580, 125.7050],
    'New Malitbog': [7.3520, 125.7420],
    'Little Panay': [7.3450, 125.6680],
    'San Pedro': [7.3410, 125.7120],
    'Dapco': [7.3350, 125.7280],
    'New Malaga': [7.3300, 125.7620],
    'J.P. Laurel': [7.3310, 125.6750],
    'San Roque': [7.3230, 125.6910],
    'Kauswagan': [7.3210, 125.7090],
    'Cacao': [7.3180, 125.6450],
    'New Visayas': [7.3140, 125.7020],
    'Nanyo': [7.3090, 125.6260],
    'Consolacion': [7.3050, 125.6680],
    'Mabunao': [7.3020, 125.6580],
    'Sindaton': [7.2980, 125.6380],
    'Katipunan': [7.2990, 125.7210],
    'Cagangohan': [7.2920, 125.6820],
    'San Vicente': [7.2870, 125.6560],
    'Katualan': [7.2850, 125.7420],
    'Maduao': [7.2760, 125.6720],
    'Dalisay': [7.2730, 125.7180],
    'Buenavista': [7.2810, 125.7010],
    'Malativas': [7.2890, 125.6250],
    'Quezon': [7.2720, 125.7580],
    'Salvacion': [7.2940, 125.7620],
    'Datu Abdul Dadia': [7.2620, 125.6460],
    'Kiotoy': [7.2640, 125.7080],
    'Santa Cruz': [7.2610, 125.7310],
    'Southern Davao': [7.2520, 125.6680],
    'Tibungol': [7.2430, 125.7090],
    'Manay': [7.2380, 125.6870],
  };

  // Panabo City bounding box
  static const double _panaboMinLat = 7.20;
  static const double _panaboMaxLat = 7.45;
  static const double _panaboMinLng = 125.55;
  static const double _panaboMaxLng = 125.85;
  static const double _maxDistanceKm = 6.0;

  @override
  void initState() {
    super.initState();
    print('📱 SignupScreen initialized');
    FirebaseService.testConnection();
    _emailController.addListener(_onEmailChanged);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _detectBarangayFromLocation();
    });
  }

  @override
  void dispose() {
    _emailCheckDebounce?.cancel();
    _nameController.dispose();
    _mobileController.dispose();
    _emailController.dispose();
    _zipCodeController.dispose();
    _passwordController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  // ── Live email availability check ─────────────────────────────────────────
  void _onEmailChanged() {
    _emailCheckDebounce?.cancel();
    setState(() {
      _emailIsAvailable = null;
      _emailStatusMessage = null;
      _isCheckingEmail = false;
    });

    final email = _emailController.text.trim();
    if (email.isEmpty || _isGoogleSignup) return;

    _emailCheckDebounce = Timer(const Duration(milliseconds: 600), () {
      _checkEmailAvailability(email);
    });
  }

  Future<void> _checkEmailAvailability(String email) async {
    if (!mounted) return;
    setState(() => _isCheckingEmail = true);

    final result = await FirebaseService.validateEmailForSignup(email);

    // Bail if the user kept typing and this is now a stale result.
    if (!mounted || _emailController.text.trim() != email) return;

    setState(() {
      _isCheckingEmail = false;
      _emailIsAvailable = result['isValid'] == true;
      _emailStatusMessage = result['message']?.toString();
    });
  }

  Widget _buildEmailStatus() {
    if (_isGoogleSignup) return const SizedBox.shrink();
    if (_isCheckingEmail) {
      return const Padding(
        padding: EdgeInsets.only(top: 6, left: 4),
        child: Row(
          children: [
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(strokeWidth: 1.6),
            ),
            SizedBox(width: 8),
            Text(
              'Checking email…',
              style: TextStyle(fontSize: 11.5, color: AppColors.textLight),
            ),
          ],
        ),
      );
    }
    if (_emailIsAvailable == null || _emailStatusMessage == null) {
      return const SizedBox.shrink();
    }
    final bool ok = _emailIsAvailable == true;
    return Padding(
      padding: const EdgeInsets.only(top: 6, left: 4),
      child: Row(
        children: [
          Icon(
            ok ? Icons.check_circle_rounded : Icons.error_rounded,
            size: 13,
            color: ok ? AppColors.success : AppColors.danger,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _emailStatusMessage!,
              style: TextStyle(
                fontSize: 11.5,
                color: ok ? AppColors.success : AppColors.danger,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── Haversine distance (km) ───────────────────────────────────────────────
  double _haversineDistance(
      double lat1, double lng1, double lat2, double lng2) {
    const R = 6371.0;
    final dLat = _toRad(lat2 - lat1);
    final dLng = _toRad(lng2 - lng1);
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(_toRad(lat1)) * cos(_toRad(lat2)) * sin(dLng / 2) * sin(dLng / 2);
    return R * 2 * atan2(sqrt(a), sqrt(1 - a));
  }

  double _toRad(double deg) => deg * pi / 180;

  String? _nearestBarangay(double lat, double lng) {
    String? nearest;
    double minDist = double.infinity;
    _barangayCentroids.forEach((barangay, coords) {
      final dist = _haversineDistance(lat, lng, coords[0], coords[1]);
      if (dist < minDist) {
        minDist = dist;
        nearest = barangay;
      }
    });
    print('📐 Nearest: $nearest (${minDist.toStringAsFixed(2)} km)');
    return minDist <= _maxDistanceKm ? nearest : null;
  }

  // ── Location Detection ────────────────────────────────────────────────────
  Future<void> _detectBarangayFromLocation() async {
    setState(() {
      _isDetectingLocation = true;
      _locationError = null;
      _detectedBarangay = null;
      _detectedLat = null;
      _detectedLng = null;
      _showManualDropdown = false;
      _manualBarangay = null;
    });

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied) {
          // No manual fallback: without GPS we can't verify Panabo City
          // residency, so this stays a hard block (retry stays available —
          // granting permission resolves it, unlike the outside-bounds case).
          setState(() {
            _locationError =
                'Location permission is required to verify you are in Panabo City. Please allow location access and try again.';
            _isDetectingLocation = false;
            _showManualDropdown = false;
          });
          return;
        }
      }
      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _locationError =
              'Location access permanently denied. Enable it in Settings, then tap retry to verify you are in Panabo City.';
          _isDetectingLocation = false;
          _showManualDropdown = false;
        });
        return;
      }

      final Position position = await Geolocator.getCurrentPosition(
        desiredAccuracy: LocationAccuracy.high,
      ).timeout(const Duration(seconds: 15));

      final double lat = position.latitude;
      final double lng = position.longitude;
      print('📍 GPS: $lat, $lng (mocked: ${position.isMocked})');

      // ── STRICT: fake/mock GPS = registration blocked ─────────────────────
      // Checked before the bounding-box test — a spoofed position can just
      // as easily be set inside Panabo City as outside it, so this has to
      // stand on its own rather than only catching out-of-bounds spoofing.
      // No manual-dropdown fallback here, same as the outside-bounds case:
      // this is a deliberate-spoofing signal, not a GPS accuracy problem.
      if (position.isMocked) {
        setState(() {
          _locationError =
              'A fake or simulated location was detected. Please disable mock/fake GPS apps and try again.';
          _isDetectingLocation = false;
          _showManualDropdown = false;
        });
        return;
      }

      // ── STRICT: Outside Panabo City = registration blocked ──────────────
      if (lat < _panaboMinLat ||
          lat > _panaboMaxLat ||
          lng < _panaboMinLng ||
          lng > _panaboMaxLng) {
        setState(() {
          _locationError =
              'Registration is only available for residents of Panabo City, Davao del Norte.';
          _isDetectingLocation = false;
          _showManualDropdown = false; // no fallback — not a Panabo resident
        });
        return;
      }

      final barangay = _nearestBarangay(lat, lng);

      if (barangay != null) {
        setState(() {
          _detectedBarangay = barangay;
          _detectedLat = lat;
          _detectedLng = lng;
          _isDetectingLocation = false;
        });
        _showSnackbar('📍 Detected: $barangay, Panabo City', AppColors.success);
      } else {
        // Inside Panabo bounds but centroid too far — allow manual pick
        setState(() {
          _locationError =
              'Could not pinpoint your barangay. Please select from the list.';
          _isDetectingLocation = false;
          _showManualDropdown = true;
        });
      }
    } catch (e) {
      print('❌ Location error: $e');
      // No manual fallback here either — an unreadable GPS fix means we
      // can't confirm Panabo City residency, same reasoning as denied
      // permission above.
      setState(() {
        _locationError =
            'Could not detect your location. Location access is required to verify you are in Panabo City — please check your GPS/network and tap retry.';
        _isDetectingLocation = false;
        _showManualDropdown = false;
      });
    }
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

  // ── Barangay Widget ───────────────────────────────────────────────────────
  Widget _buildBarangayField() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // ── Panabo-only notice ──────────────────────────────────────────
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          margin: const EdgeInsets.only(bottom: 8),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.07),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
                color: AppColors.primary.withOpacity(0.25), width: 1),
          ),
          child: Row(
            children: const [
              Icon(Icons.info_outline_rounded,
                  size: 14, color: AppColors.primary),
              SizedBox(width: 6),
              Expanded(
                child: Text(
                  'This app is for Panabo City, Davao del Norte residents only.',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),

        // ── GPS read-only field ─────────────────────────────────────────
        _buildGpsField(),

        // ── Manual dropdown (GPS inaccurate / failed inside Panabo) ────
        if (_showManualDropdown) ...[
          const SizedBox(height: 8),
          _buildManualDropdown(),
        ],

        // ── "Not accurate?" link (only when GPS succeeded) ──────────────
        if (!_showManualDropdown && _detectedBarangay != null) ...[
          const SizedBox(height: 6),
          GestureDetector(
            onTap: () => setState(() {
              _showManualDropdown = true;
              _manualBarangay = null;
            }),
            child: Row(
              children: const [
                SizedBox(width: 4),
                Icon(Icons.edit_location_alt_outlined,
                    size: 13, color: AppColors.primary),
                SizedBox(width: 4),
                Text(
                  'Not accurate? Select manually',
                  style: TextStyle(
                    fontSize: 11,
                    color: AppColors.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  // GPS-detected read-only field
  Widget _buildGpsField() {
    final bool hasBarangay = _detectedBarangay != null;
    // Outside-Panabo error is a hard block (no manual dropdown offered)
    final bool isHardBlock = _locationError != null &&
        _locationError!.contains('only available for residents');
    final bool hasError = _locationError != null && !_showManualDropdown;

    final Color borderColor = _isDetectingLocation
        ? AppColors.lightGrey
        : isHardBlock
            ? AppColors.danger
            : hasError
                ? AppColors.danger
                : hasBarangay
                    ? AppColors.success
                    : AppColors.lightGrey;

    final Color iconColor = _isDetectingLocation
        ? AppColors.grey
        : isHardBlock || hasError
            ? AppColors.danger
            : hasBarangay
                ? AppColors.success
                : AppColors.grey;

    final String displayText = _isDetectingLocation
        ? 'Detecting your location...'
        : hasBarangay
            ? '$_detectedBarangay, Panabo City, Davao del Norte'
            : _locationError ?? 'Location not detected';

    final Color textColor = _isDetectingLocation
        ? AppColors.grey
        : hasBarangay
            ? AppColors.secondary
            : (isHardBlock || hasError)
                ? AppColors.danger
                : AppColors.grey;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
      decoration: BoxDecoration(
        color: hasBarangay
            ? AppColors.success.withOpacity(0.04)
            : isHardBlock
                ? AppColors.danger.withOpacity(0.04)
                : AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: 1),
      ),
      child: Row(
        children: [
          _isDetectingLocation
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: AppColors.primary),
                )
              : Icon(
                  isHardBlock
                      ? Icons.location_off_rounded
                      : hasBarangay
                          ? Icons.location_on_rounded
                          : Icons.add_location_alt_outlined,
                  color: iconColor,
                  size: 20,
                ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayText,
              style: TextStyle(
                fontSize: 14,
                color: textColor,
                fontWeight: hasBarangay ? FontWeight.w500 : FontWeight.w400,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          // Hide retry when hard block (outside Panabo)
          if (!isHardBlock)
            GestureDetector(
              onTap: _isDetectingLocation ? null : _detectBarangayFromLocation,
              child: Icon(
                Icons.refresh_rounded,
                color: _isDetectingLocation
                    ? AppColors.lightGrey
                    : AppColors.primary,
                size: 20,
              ),
            ),
        ],
      ),
    );
  }

  // Manual dropdown — only barangays of Panabo City
  Widget _buildManualDropdown() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        DropdownButtonFormField<String>(
          initialValue: _manualBarangay,
          decoration: InputDecoration(
            labelText: 'Select your barangay in Panabo City',
            labelStyle: TextStyle(
              color:
                  _manualBarangay != null ? AppColors.primary : AppColors.grey,
              fontSize: _manualBarangay != null ? 12 : 14,
              fontWeight: FontWeight.w500,
            ),
            prefixIcon: const Icon(Icons.add_location_alt_outlined,
                color: AppColors.grey),
            contentPadding:
                const EdgeInsets.symmetric(vertical: 18, horizontal: 16),
            filled: true,
            fillColor: AppColors.lightGrey,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.lightGrey, width: 1),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide:
                  const BorderSide(color: AppColors.lightGrey, width: 1),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.primary, width: 2),
            ),
            errorBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(color: AppColors.danger, width: 1),
            ),
          ),
          items: _barangays.map((String barangay) {
            return DropdownMenuItem<String>(
              value: barangay,
              child: Text(
                barangay,
                style: TextStyle(
                  fontSize: ResponsiveUtils.getResponsiveFontSize(context, 14),
                ),
                overflow: TextOverflow.ellipsis,
              ),
            );
          }).toList(),
          onChanged: (String? newValue) {
            setState(() => _manualBarangay = newValue);
          },
          validator: (value) {
            if (_showManualDropdown && (value == null || value.isEmpty)) {
              return 'Please select your barangay in Panabo City';
            }
            return null;
          },
          isExpanded: true,
          menuMaxHeight: MediaQuery.of(context).size.height * 0.3,
        ),
        const SizedBox(height: 6),
        GestureDetector(
          onTap: _detectBarangayFromLocation,
          child: Row(
            children: const [
              SizedBox(width: 4),
              Icon(Icons.my_location_rounded,
                  size: 13, color: AppColors.primary),
              SizedBox(width: 4),
              Text(
                'Try auto-detect again',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  // ── Google Sign-Up ────────────────────────────────────────────────────────
  Future<void> _handleGoogleSignup() async {
    setState(() => _isGoogleLoading = true);
    try {
      final googleResult = await GoogleAuthService.signIn();
      if (googleResult == null) {
        // User cancelled the account picker.
        setState(() => _isGoogleLoading = false);
        return;
      }

      final alreadyRegistered =
          await FirebaseService.checkEmailExists(googleResult.email);
      if (alreadyRegistered) {
        await GoogleAuthService.signOut();
        setState(() => _isGoogleLoading = false);
        if (!mounted) return;
        _showSnackbar(
          'This Google account is already registered. Please log in instead.',
          AppColors.danger,
        );
        return;
      }

      setState(() {
        _isGoogleLoading = false;
        _isGoogleSignup = true;
        _googleUid = googleResult.uid;
        _googlePhotoUrl = googleResult.photoUrl;
        _nameController.text = googleResult.displayName;
        _emailController.text = googleResult.email;
      });

      _showSnackbar(
        'Signed in as ${googleResult.email}. Please finish your profile below.',
        AppColors.success,
      );
    } catch (e) {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
        _showSnackbar('Google sign-in failed: $e', AppColors.danger);
      }
    }
  }

  /// Mirrors LoginScreen's post-login session save + navigation, so a Google
  /// sign-up lands the user straight in the app instead of forcing a
  /// separate manual login immediately after.
  Future<void> _completeGoogleSignupSession(
      String userId, String userName) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('userId', userId);
    await prefs.setString('userName', userName);
    await prefs.remove('familyCode');

    await AppBackgroundService.start();
    await FcmService.saveTokenToFirebase(userId);

    if (!mounted) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => FamilySetupScreen(
          userId: userId,
          userName: userName,
          userEmail: _emailController.text.trim(),
          mobile: _mobileController.text.trim(),
          barangay: _activeBarangay ?? '',
          zipCode: _zipCodeController.text.trim(),
        ),
      ),
    );
  }

  // ── Signup Handler ────────────────────────────────────────────────────────
  Future<void> _handleSignup() async {
    // Make sure the debounced email check has actually run (or re-run it
    // synchronously) before validating, so a fast typer-then-submit can't
    // slip past the "already registered" check.
    if (!_isGoogleSignup) {
      final email = _emailController.text.trim();
      if (email.isNotEmpty && RegExp(r'^[\w-\.]+@gmail\.com$').hasMatch(email)) {
        _emailCheckDebounce?.cancel();
        if (_emailIsAvailable == null || _emailController.text.trim() != email) {
          await _checkEmailAvailability(email);
        } else if (_isCheckingEmail) {
          while (_isCheckingEmail && mounted) {
            await Future.delayed(const Duration(milliseconds: 100));
          }
        }
      }
    }
    if (!mounted) return;

    if (!_formKey.currentState!.validate()) return;

    // Guard: must have a confirmed barangay inside Panabo City
    if (_activeBarangay == null) {
      _showSnackbar(
        _locationError != null &&
                _locationError!.contains('only available for residents')
            ? 'Registration is restricted to Panabo City residents only.'
            : _locationError != null
                ? 'Location access is required to verify Panabo City residency before you can sign up.'
                : 'Please wait for location detection or select your barangay.',
        AppColors.danger,
      );
      return;
    }

    setState(() => _isLoading = true);

    try {
      final nameParts = _nameController.text.trim().split(' ');
      final firstName = nameParts.first;
      final lastName =
          nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '';

      final String barangayName = _activeBarangay!;
      final String fullAddress = '$barangayName, Panabo City, Davao del Norte';

      print('📝 Registering: barangay=$barangayName | address=$fullAddress');

      // Pass along the exact coordinates this screen already verified,
      // rather than letting register()/registerWithGoogle() take their own
      // separate, unrelated GPS reading — and record whether the barangay
      // actually came from that verified GPS fix or a manual/self-declared
      // pick, so the two are never indistinguishable on the account record.
      final result = _isGoogleSignup
          ? await FirebaseService.registerWithGoogle(
              googleUid: _googleUid!,
              firstName: firstName,
              lastName: lastName,
              email: _emailController.text.trim(),
              mobileNumber: _mobileController.text.trim(),
              barangay: barangayName,
              zipCode: _zipCodeController.text.trim(),
              photoUrl: _googlePhotoUrl,
              latitude: _detectedLat,
              longitude: _detectedLng,
              locationVerified: _isLocationVerified,
            )
          : await FirebaseService.register(
              firstName: firstName,
              lastName: lastName,
              email: _emailController.text.trim(),
              mobileNumber: _mobileController.text.trim(),
              password: _passwordController.text,
              barangay: barangayName, // clean barangay name
              zipCode: _zipCodeController.text.trim(),
              latitude: _detectedLat,
              longitude: _detectedLng,
              locationVerified: _isLocationVerified,
            );

      if (mounted) {
        setState(() => _isLoading = false);

        if (result['success'] == true) {
          if (_isGoogleSignup) {
            final userId = result['userId']?.toString() ?? '';
            final userName =
                result['userName']?.toString() ?? _nameController.text.trim();
            await _completeGoogleSignupSession(userId, userName);
            return;
          }

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Row(
                children: [
                  Icon(Icons.check_circle, color: Colors.white),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'Account created successfully! Please login.',
                      style: TextStyle(fontWeight: FontWeight.w500),
                    ),
                  ),
                ],
              ),
              backgroundColor: AppColors.success,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10)),
              duration: const Duration(seconds: 2),
            ),
          );
          await Future.delayed(const Duration(milliseconds: 2200));
          if (mounted) Navigator.pop(context);
        } else {
          _showSnackbar(
              result['error'] ?? 'Registration failed', AppColors.danger);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        _showSnackbar('An error occurred: $e', AppColors.danger);
      }
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────
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
          child: Stack(
            children: [
              LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    controller: _scrollController,
                    padding: EdgeInsets.symmetric(
                      horizontal: ResponsiveUtils.isMobile(context) ? 20 : 60,
                      vertical: isKeyboardVisible ? 10 : 20,
                    ),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Logo & title ──────────────────────────────
                          if (!isKeyboardVisible) ...[
                            const SizedBox(height: 44),
                            Center(
                              child: AuthLogoBadge(
                                size: ResponsiveUtils.getScaledSize(
                                    context, 64),
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              'Create your account',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: ResponsiveUtils
                                    .getResponsiveFontSize(context, 22),
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                                letterSpacing: 0.3,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              'Join LifeGuard360 to keep your family safe',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: ResponsiveUtils
                                    .getResponsiveFontSize(context, 12),
                                color: Colors.white.withOpacity(0.85),
                              ),
                            ),
                            const SizedBox(height: 20),
                          ] else
                            const SizedBox(height: 56),

                          // ── Card ────────────────────────────────────────
                          Container(
                            padding: EdgeInsets.all(
                                ResponsiveUtils.isMobile(context) ? 20 : 24),
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
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'Your details',
                                  style: TextStyle(
                                    fontSize: ResponsiveUtils
                                        .getResponsiveFontSize(context, 18),
                                    fontWeight: FontWeight.bold,
                                    color: AppColors.secondary,
                                  ),
                                ),
                                const SizedBox(height: 16),

                                // ── Sign Up with Google ────────────────────
                                if (!_isGoogleSignup) ...[
                                  GoogleButton(
                                    text: 'Sign Up with Google',
                                    isLoading: _isGoogleLoading,
                                    onPressed: _handleGoogleSignup,
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
                                ] else ...[
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 10),
                                    margin: const EdgeInsets.only(bottom: 12),
                                    decoration: BoxDecoration(
                                      color: AppColors.success.withOpacity(0.08),
                                      borderRadius: BorderRadius.circular(8),
                                      border: Border.all(
                                          color: AppColors.success
                                              .withOpacity(0.3)),
                                    ),
                                    child: Row(
                                      children: [
                                        const Icon(Icons.verified_rounded,
                                            size: 16, color: AppColors.success),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Text(
                                            'Verified with Google — finish your profile to link this account.',
                                            style: TextStyle(
                                              fontSize: 11.5,
                                              color: AppColors.secondary,
                                              fontWeight: FontWeight.w500,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ],

                                // ── Full Name ─────────────────────────────
                        CustomTextField(
                          controller: _nameController,
                          labelText: 'Full Name',
                          hintText: 'Full Name',
                          prefixIcon: Icons.person_outline,
                          onChanged: () => setState(() {}),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your full name';
                            }
                            if (value.trim().length < 3) {
                              return 'Name must be at least 3 characters';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: isKeyboardVisible ? 8 : 12),

                        // ── Mobile Number ─────────────────────────────────
                        CustomTextField(
                          controller: _mobileController,
                          labelText: 'Mobile Number',
                          hintText: 'Mobile Number',
                          prefixIcon: Icons.phone_outlined,
                          keyboardType: TextInputType.phone,
                          onChanged: () => setState(() {}),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your mobile number';
                            }
                            if (value.trim().length < 10) {
                              return 'Please enter a valid mobile number';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: isKeyboardVisible ? 8 : 12),

                        // ── Email ─────────────────────────────────────────
                        CustomTextField(
                          controller: _emailController,
                          labelText: 'Email',
                          hintText: 'Email',
                          prefixIcon: Icons.email_outlined,
                          keyboardType: TextInputType.emailAddress,
                          enabled: !_isGoogleSignup,
                          onChanged: () => setState(() {}),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your email';
                            }
                            if (!value.contains('@') || !value.contains('.')) {
                              return 'Please enter a valid email';
                            }
                            if (!_isGoogleSignup &&
                                !value.toLowerCase().endsWith('@gmail.com')) {
                              return 'Please use a Gmail address';
                            }
                            if (!_isGoogleSignup && _emailIsAvailable == false) {
                              return _emailStatusMessage ??
                                  'This email cannot be used.';
                            }
                            return null;
                          },
                        ),
                        _buildEmailStatus(),
                        SizedBox(height: isKeyboardVisible ? 8 : 12),

                        // ── Barangay (GPS first, dropdown fallback) ───────
                        _buildBarangayField(),
                        SizedBox(height: isKeyboardVisible ? 8 : 12),

                        // ── ZipCode ───────────────────────────────────────
                        CustomTextField(
                          controller: _zipCodeController,
                          labelText: 'ZipCode',
                          hintText: 'ZipCode',
                          prefixIcon: Icons.home_outlined,
                          keyboardType: TextInputType.number,
                          onChanged: () => setState(() {}),
                          validator: (value) {
                            if (value == null || value.trim().isEmpty) {
                              return 'Please enter your zipcode';
                            }
                            return null;
                          },
                        ),
                        SizedBox(height: isKeyboardVisible ? 8 : 12),

                        // ── Password (skipped for Google sign-up) ─────────
                        if (!_isGoogleSignup) ...[
                          CustomTextField(
                            controller: _passwordController,
                            labelText: 'Password',
                            hintText: 'Password',
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
                        ],
                                SizedBox(height: isKeyboardVisible ? 16 : 24),

                                // ── Sign Up button ─────────────────────────
                                CustomButton(
                                  text: 'Sign Up',
                                  icon: Icons.person_add_alt_1_rounded,
                                  onPressed: _handleSignup,
                                  isLoading: _isLoading,
                                  height: 54,
                                ),
                                const SizedBox(height: 18),

                                // ── Login link ──────────────────────────────
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      "Already have an account? ",
                                      style: TextStyle(
                                        fontSize: ResponsiveUtils
                                            .getResponsiveFontSize(context, 12),
                                        color: AppColors.textLight,
                                      ),
                                    ),
                                    GestureDetector(
                                      onTap: () => Navigator.pop(context),
                                      child: Text(
                                        'Log In',
                                        style: TextStyle(
                                          fontSize: ResponsiveUtils
                                              .getResponsiveFontSize(
                                                  context, 12),
                                          color: AppColors.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),

              // ── Close button, floating over the gradient ────────────────
              Padding(
                padding: const EdgeInsets.all(12),
                child: _CloseButton(onTap: () => Navigator.pop(context)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Small translucent circular close button used over the gradient header.
class _CloseButton extends StatelessWidget {
  final VoidCallback onTap;
  const _CloseButton({required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.18),
          shape: BoxShape.circle,
        ),
        child: const Icon(Icons.close, color: Colors.white, size: 22),
      ),
    );
  }
}
