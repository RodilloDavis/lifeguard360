// import 'package:flutter/material.dart';
// import '../../../core/constants/app_colors.dart';
// import '../../../services/firebase_realtime_database.dart';
// import '../../dashboard/screens/dashboard_screen.dart';

// class FamilySetupScreen extends StatefulWidget {
//   final String userId;
//   final String userName;
//   final String userEmail;
//   final String mobile;
//   final String barangay;
//   final String zipCode;

//   const FamilySetupScreen({
//     super.key,
//     required this.userId,
//     required this.userName,
//     required this.userEmail,
//     this.mobile = '',
//     this.barangay = '',
//     this.zipCode = '',
//   });

//   @override
//   State<FamilySetupScreen> createState() => _FamilySetupScreenState();
// }

// class _FamilySetupScreenState extends State<FamilySetupScreen> {
//   bool _showJoinFamily = true;

//   @override
//   Widget build(BuildContext context) {
//     return Scaffold(
//       backgroundColor: Colors.white,
//       body: SafeArea(
//         child: SingleChildScrollView(
//           child: Padding(
//             padding: const EdgeInsets.all(24.0),
//             child: Column(
//               crossAxisAlignment: CrossAxisAlignment.start,
//               children: [
//                 const SizedBox(height: 20),
//                 _buildHeader(),
//                 const SizedBox(height: 40),
//                 _buildToggleButtons(),
//                 const SizedBox(height: 32),
//                 AnimatedSwitcher(
//                   duration: const Duration(milliseconds: 300),
//                   child: _showJoinFamily
//                       ? JoinFamilyForm(
//                           key: const ValueKey('join'),
//                           userId: widget.userId,
//                           userName: widget.userName,
//                           userEmail: widget.userEmail,
//                           mobile: widget.mobile,
//                           barangay: widget.barangay,
//                           zipCode: widget.zipCode,
//                         )
//                       : CreateFamilyForm(
//                           key: const ValueKey('create'),
//                           userId: widget.userId,
//                           userName: widget.userName,
//                           userEmail: widget.userEmail,
//                           mobile: widget.mobile,
//                           barangay: widget.barangay,
//                           zipCode: widget.zipCode,
//                         ),
//                 ),
//               ],
//             ),
//           ),
//         ),
//       ),
//     );
//   }

//   Widget _buildHeader() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         Container(
//           padding: const EdgeInsets.all(16),
//           decoration: BoxDecoration(
//             color: AppColors.primary.withOpacity(0.1),
//             shape: BoxShape.circle,
//           ),
//           child: const Icon(
//             Icons.family_restroom,
//             size: 48,
//             color: AppColors.primary,
//           ),
//         ),
//         const SizedBox(height: 24),
//         Text(
//           'Welcome, ${widget.userName}!',
//           style: const TextStyle(
//             fontSize: 28,
//             fontWeight: FontWeight.bold,
//             color: AppColors.secondary,
//           ),
//         ),
//         const SizedBox(height: 8),
//         const Text(
//           'Let\'s set up your family circle for safety tracking',
//           style: TextStyle(
//             fontSize: 16,
//             color: AppColors.textLight,
//             height: 1.5,
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildToggleButtons() {
//     return Container(
//       decoration: BoxDecoration(
//         color: AppColors.lightGrey,
//         borderRadius: BorderRadius.circular(12),
//       ),
//       padding: const EdgeInsets.all(4),
//       child: Row(
//         children: [
//           Expanded(
//             child: _buildToggleButton(
//               'Join Family',
//               _showJoinFamily,
//               () => setState(() => _showJoinFamily = true),
//             ),
//           ),
//           Expanded(
//             child: _buildToggleButton(
//               'Create Family',
//               !_showJoinFamily,
//               () => setState(() => _showJoinFamily = false),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   Widget _buildToggleButton(String label, bool isSelected, VoidCallback onTap) {
//     return GestureDetector(
//       onTap: onTap,
//       child: AnimatedContainer(
//         duration: const Duration(milliseconds: 200),
//         padding: const EdgeInsets.symmetric(vertical: 14),
//         decoration: BoxDecoration(
//           color: isSelected ? Colors.white : Colors.transparent,
//           borderRadius: BorderRadius.circular(10),
//           boxShadow: isSelected
//               ? [
//                   BoxShadow(
//                     color: Colors.black.withOpacity(0.05),
//                     blurRadius: 8,
//                     offset: const Offset(0, 2),
//                   ),
//                 ]
//               : null,
//         ),
//         alignment: Alignment.center,
//         child: Text(
//           label,
//           style: TextStyle(
//             fontSize: 15,
//             fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
//             color: isSelected ? AppColors.primary : AppColors.textLight,
//           ),
//         ),
//       ),
//     );
//   }
// }

// // ═══════════════════════════════════════════════════════════════════════════
// // JoinFamilyForm — calls FirebaseService.joinFamily() directly
// // Saves to:
// //   /Families/{familyCode}/Members/{userId}
// //   /Accounts/{userId}  →  FamilyId, FamilyCode, FamilyName, FamilyRole
// // ═══════════════════════════════════════════════════════════════════════════
// class JoinFamilyForm extends StatefulWidget {
//   final String userId;
//   final String userName;
//   final String userEmail;
//   final String mobile;
//   final String barangay;
//   final String zipCode;

//   const JoinFamilyForm({
//     super.key,
//     required this.userId,
//     required this.userName,
//     required this.userEmail,
//     this.mobile = '',
//     this.barangay = '',
//     this.zipCode = '',
//   });

//   @override
//   State<JoinFamilyForm> createState() => _JoinFamilyFormState();
// }

// class _JoinFamilyFormState extends State<JoinFamilyForm> {
//   final _formKey = GlobalKey<FormState>();
//   final _familyCodeController = TextEditingController();
//   final _familyCodeFocus = FocusNode();

//   String _selectedRole = 'Son';
//   bool _isVerifying = false;
//   bool _isJoining = false;
//   bool _isFamilyCodeValid = false;
//   Map<String, dynamic>? _verifiedFamily;

//   final List<String> _roles = [
//     'Father',
//     'Mother',
//     'Son',
//     'Daughter',
//     'Guardian',
//     'Grandfather',
//     'Grandmother',
//     'Uncle',
//     'Aunt',
//     'Other',
//   ];

//   @override
//   void initState() {
//     super.initState();
//     _familyCodeFocus.addListener(() => setState(() {}));
//   }

//   @override
//   void dispose() {
//     _familyCodeController.dispose();
//     _familyCodeFocus.dispose();
//     super.dispose();
//   }

//   // ── Verify — reads /Families/{code} ──────────────────────────────────────
//   Future<void> _verifyFamilyCode() async {
//     final code = _familyCodeController.text.trim();
//     if (code.isEmpty) {
//       setState(() {
//         _isFamilyCodeValid = false;
//         _verifiedFamily = null;
//       });
//       return;
//     }
//     if (code.length != 6) {
//       _showErrorSnackBar('Family code must be 6 digits');
//       return;
//     }

//     setState(() => _isVerifying = true);

//     try {
//       print('🔵 Verifying family code: $code');
//       final family = await FirebaseService.getFamilyByCode(code);

//       if (family != null) {
//         print('✅ Family found: ${family['FamilyName']}');
//         setState(() {
//           _isFamilyCodeValid = true;
//           _verifiedFamily = family;
//           _isVerifying = false;
//         });
//         _showSuccessSnackBar('Found: ${family['FamilyName']}');
//       } else {
//         print('❌ No family found for code: $code');
//         setState(() {
//           _isFamilyCodeValid = false;
//           _verifiedFamily = null;
//           _isVerifying = false;
//         });
//         _showErrorSnackBar('Invalid family code. Family not found.');
//       }
//     } catch (e) {
//       print('❌ Verify error: $e');
//       setState(() {
//         _isFamilyCodeValid = false;
//         _verifiedFamily = null;
//         _isVerifying = false;
//       });
//       _showErrorSnackBar('Error verifying code: $e');
//     }
//   }

//   // ── Join — writes to /Families/{code}/Members + /Accounts/{userId} ───────
//   Future<void> _joinFamily() async {
//     if (!_formKey.currentState!.validate()) return;
//     if (!_isFamilyCodeValid) {
//       _showErrorSnackBar('Please verify the family code first');
//       return;
//     }

//     setState(() => _isJoining = true);

//     try {
//       print('🔵 Joining family: ${_familyCodeController.text.trim()}');
//       print('🔵 UserId: ${widget.userId} | Role: $_selectedRole');

//       final result = await FirebaseService.joinFamily(
//         userId: widget.userId,
//         userName: widget.userName,
//         familyCode: _familyCodeController.text.trim(),
//         role: _selectedRole,
//       );

//       print('🔵 Join result: $result');

//       if (mounted) {
//         if (result['success'] == true) {
//           _showSuccessSnackBar(
//               result['message'] ?? 'Successfully joined family!');
//           await Future.delayed(const Duration(seconds: 1));
//           if (mounted) {
//             Navigator.pushReplacement(
//               context,
//               MaterialPageRoute(
//                 builder: (context) => DashboardScreen(
//                   userId: widget.userId,
//                   userName: widget.userName,
//                 ),
//               ),
//             );
//           }
//         } else {
//           setState(() => _isJoining = false);
//           _showErrorSnackBar(result['error'] ?? 'Failed to join family');
//         }
//       }
//     } catch (e) {
//       print('❌ Join family error: $e');
//       if (mounted) {
//         setState(() => _isJoining = false);
//         _showErrorSnackBar('Failed to join family: $e');
//       }
//     }
//   }

//   void _showSuccessSnackBar(String message) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//       content: Row(children: [
//         const Icon(Icons.check_circle, color: Colors.white),
//         const SizedBox(width: 12),
//         Expanded(child: Text(message)),
//       ]),
//       backgroundColor: AppColors.success,
//       behavior: SnackBarBehavior.floating,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//     ));
//   }

//   void _showErrorSnackBar(String message) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//       content: Row(children: [
//         const Icon(Icons.error_outline, color: Colors.white),
//         const SizedBox(width: 12),
//         Expanded(child: Text(message)),
//       ]),
//       backgroundColor: AppColors.danger,
//       behavior: SnackBarBehavior.floating,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//     ));
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Form(
//       key: _formKey,
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Container(
//             padding: const EdgeInsets.all(16),
//             decoration: BoxDecoration(
//               color: AppColors.primary.withOpacity(0.05),
//               borderRadius: BorderRadius.circular(12),
//               border: Border.all(color: AppColors.primary.withOpacity(0.2)),
//             ),
//             child: const Row(
//               children: [
//                 Icon(Icons.info_outline, color: AppColors.primary, size: 24),
//                 SizedBox(width: 12),
//                 Expanded(
//                   child: Text(
//                     'Ask your family admin for the 6-digit family code',
//                     style: TextStyle(
//                         fontSize: 13, color: AppColors.secondary, height: 1.4),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(height: 24),
//           _buildFamilyCodeSection(),
//           const SizedBox(height: 24),
//           _buildRoleSelection(),
//           const SizedBox(height: 32),
//           _buildJoinButton(),
//         ],
//       ),
//     );
//   }

//   Widget _buildFamilyCodeSection() {
//     final isFocused = _familyCodeFocus.hasFocus;
//     final hasValue = _familyCodeController.text.isNotEmpty;
//     final labelIsUp = hasValue || isFocused || _isFamilyCodeValid;

//     return Container(
//       padding: const EdgeInsets.all(16),
//       decoration: BoxDecoration(
//         color: _isFamilyCodeValid
//             ? Colors.green.withOpacity(0.05)
//             : AppColors.lightGrey,
//         borderRadius: BorderRadius.circular(12),
//         border: Border.all(
//           color: _isFamilyCodeValid
//               ? Colors.green
//               : AppColors.grey.withOpacity(0.3),
//           width: _isFamilyCodeValid ? 2 : 1,
//         ),
//       ),
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Row(
//             children: [
//               Icon(
//                 _isFamilyCodeValid ? Icons.check_circle : Icons.qr_code_2,
//                 color: _isFamilyCodeValid ? Colors.green : AppColors.primary,
//                 size: 24,
//               ),
//               const SizedBox(width: 12),
//               const Text('Family Code',
//                   style: TextStyle(
//                       fontSize: 16,
//                       fontWeight: FontWeight.bold,
//                       color: AppColors.secondary)),
//             ],
//           ),
//           const SizedBox(height: 16),
//           TextFormField(
//             controller: _familyCodeController,
//             focusNode: _familyCodeFocus,
//             keyboardType: TextInputType.number,
//             maxLength: 6,
//             style: const TextStyle(
//                 fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
//             textAlign: TextAlign.center,
//             decoration: InputDecoration(
//               labelText: 'Family Code',
//               labelStyle: TextStyle(
//                 color: isFocused
//                     ? AppColors.primary
//                     : (_isFamilyCodeValid ? Colors.green : AppColors.grey),
//                 fontSize: labelIsUp ? 12 : 14,
//                 fontWeight: FontWeight.w500,
//               ),
//               hintText: labelIsUp ? null : '------',
//               hintStyle: TextStyle(
//                   color: AppColors.grey.withOpacity(0.3), letterSpacing: 8),
//               filled: true,
//               fillColor: Colors.white,
//               border: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(12),
//                   borderSide: BorderSide.none),
//               enabledBorder: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(12),
//                   borderSide:
//                       const BorderSide(color: AppColors.lightGrey, width: 1)),
//               focusedBorder: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(12),
//                   borderSide:
//                       const BorderSide(color: AppColors.primary, width: 2)),
//               errorBorder: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(12),
//                   borderSide:
//                       const BorderSide(color: AppColors.danger, width: 1)),
//               focusedErrorBorder: OutlineInputBorder(
//                   borderRadius: BorderRadius.circular(12),
//                   borderSide:
//                       const BorderSide(color: AppColors.danger, width: 2)),
//               errorStyle:
//                   const TextStyle(color: AppColors.danger, fontSize: 12),
//               suffixIcon: _isVerifying
//                   ? const Padding(
//                       padding: EdgeInsets.all(12.0),
//                       child: SizedBox(
//                           width: 20,
//                           height: 20,
//                           child: CircularProgressIndicator(strokeWidth: 2)),
//                     )
//                   : _isFamilyCodeValid
//                       ? const Icon(Icons.check_circle, color: Colors.green)
//                       : null,
//               counterText: '',
//             ),
//             onChanged: (value) {
//               setState(() {});
//               if (value.length == 6) {
//                 _verifyFamilyCode();
//               } else {
//                 setState(() {
//                   _isFamilyCodeValid = false;
//                   _verifiedFamily = null;
//                 });
//               }
//             },
//             validator: (value) {
//               if (value == null || value.isEmpty)
//                 return 'Please enter family code';
//               if (value.length != 6) return 'Family code must be 6 digits';
//               return null;
//             },
//           ),
//           if (_verifiedFamily != null) ...[
//             const SizedBox(height: 12),
//             Container(
//               padding: const EdgeInsets.all(12),
//               decoration: BoxDecoration(
//                 color: Colors.green.withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(8),
//               ),
//               child: Row(
//                 children: [
//                   const Icon(Icons.verified, color: Colors.green, size: 20),
//                   const SizedBox(width: 8),
//                   Expanded(
//                     child: Column(
//                       crossAxisAlignment: CrossAxisAlignment.start,
//                       children: [
//                         const Text('Verified',
//                             style: TextStyle(
//                                 color: Colors.green,
//                                 fontWeight: FontWeight.bold,
//                                 fontSize: 12)),
//                         Text(
//                           _verifiedFamily!['FamilyName'] ?? 'Family',
//                           style: const TextStyle(
//                               color: Colors.green,
//                               fontWeight: FontWeight.w600,
//                               fontSize: 16),
//                         ),
//                         Text(
//                           'Admin: ${_verifiedFamily!['CreatedByName'] ?? 'Unknown'}',
//                           style: const TextStyle(
//                               color: Colors.green, fontSize: 11),
//                         ),
//                       ],
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ],
//       ),
//     );
//   }

//   Widget _buildRoleSelection() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text('Your Role in Family',
//             style: TextStyle(
//                 fontSize: 16,
//                 fontWeight: FontWeight.bold,
//                 color: AppColors.secondary)),
//         const SizedBox(height: 12),
//         Container(
//           decoration: BoxDecoration(
//             border: Border.all(color: AppColors.lightGrey),
//             borderRadius: BorderRadius.circular(12),
//             color: Colors.white,
//           ),
//           child: DropdownButtonFormField<String>(
//             value: _selectedRole,
//             decoration: const InputDecoration(
//               prefixIcon: Icon(Icons.people_outline),
//               border: InputBorder.none,
//               contentPadding:
//                   EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//             ),
//             items: _roles
//                 .map((role) => DropdownMenuItem(value: role, child: Text(role)))
//                 .toList(),
//             onChanged: (value) => setState(() => _selectedRole = value!),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildJoinButton() {
//     return SizedBox(
//       width: double.infinity,
//       height: 56,
//       child: ElevatedButton(
//         onPressed: (_isFamilyCodeValid && !_isJoining) ? _joinFamily : null,
//         style: ElevatedButton.styleFrom(
//           backgroundColor: AppColors.primary,
//           disabledBackgroundColor: AppColors.grey.withOpacity(0.3),
//           shape:
//               RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//           elevation: _isFamilyCodeValid ? 4 : 0,
//         ),
//         child: _isJoining
//             ? const SizedBox(
//                 width: 24,
//                 height: 24,
//                 child: CircularProgressIndicator(
//                     color: Colors.white, strokeWidth: 2))
//             : const Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Icon(Icons.login, size: 24),
//                   SizedBox(width: 12),
//                   Text('Join Family',
//                       style: TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                           letterSpacing: 0.5)),
//                 ],
//               ),
//       ),
//     );
//   }
// }

// // ═══════════════════════════════════════════════════════════════════════════
// // CreateFamilyForm — calls FirebaseService.createFamily() directly
// // Saves to:
// //   /Families/{familyCode}/  (full family node with Members/{userId})
// //   /Accounts/{userId}  →  FamilyId, FamilyCode, FamilyName, FamilyRole
// // ═══════════════════════════════════════════════════════════════════════════
// class CreateFamilyForm extends StatefulWidget {
//   final String userId;
//   final String userName;
//   final String userEmail;
//   final String mobile;
//   final String barangay;
//   final String zipCode;

//   const CreateFamilyForm({
//     super.key,
//     required this.userId,
//     required this.userName,
//     required this.userEmail,
//     this.mobile = '',
//     this.barangay = '',
//     this.zipCode = '',
//   });

//   @override
//   State<CreateFamilyForm> createState() => _CreateFamilyFormState();
// }

// class _CreateFamilyFormState extends State<CreateFamilyForm> {
//   final _formKey = GlobalKey<FormState>();
//   final _familyNameController = TextEditingController();
//   final _familyNameFocus = FocusNode();

//   String _selectedRole = 'Father';
//   bool _isCreating = false;

//   final List<String> _adminRoles = ['Father', 'Mother', 'Guardian'];

//   @override
//   void initState() {
//     super.initState();
//     _familyNameFocus.addListener(() => setState(() {}));
//   }

//   @override
//   void dispose() {
//     _familyNameController.dispose();
//     _familyNameFocus.dispose();
//     super.dispose();
//   }

//   // ── Create — writes /Families/{code} and updates /Accounts/{userId} ───────
//   Future<void> _createFamily() async {
//     if (!_formKey.currentState!.validate()) return;
//     setState(() => _isCreating = true);

//     try {
//       print('🔨 Creating family: ${_familyNameController.text.trim()}');
//       print('🔨 UserId: ${widget.userId} | Role: $_selectedRole');

//       final result = await FirebaseService.createFamily(
//         userId: widget.userId,
//         userName: widget.userName,
//         familyName: _familyNameController.text.trim(),
//       );

//       print('🔨 Create result: $result');

//       if (mounted) {
//         if (result['success'] == true) {
//           print('✅ Family created! Code: ${result['familyCode']}');
//           await _showFamilyCodeDialog(
//             result['familyCode'],
//             result['familyName'],
//           );
//           if (mounted) {
//             Navigator.pushReplacement(
//               context,
//               MaterialPageRoute(
//                 builder: (context) => DashboardScreen(
//                   userId: widget.userId,
//                   userName: widget.userName,
//                 ),
//               ),
//             );
//           }
//         } else {
//           setState(() => _isCreating = false);
//           _showErrorSnackBar(result['error'] ?? 'Failed to create family');
//         }
//       }
//     } catch (e) {
//       print('❌ Create family error: $e');
//       if (mounted) {
//         setState(() => _isCreating = false);
//         _showErrorSnackBar('Failed to create family: $e');
//       }
//     }
//   }

//   Future<void> _showFamilyCodeDialog(
//       String familyCode, String familyName) async {
//     return showDialog(
//       context: context,
//       barrierDismissible: false,
//       builder: (context) => AlertDialog(
//         shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
//         title: Column(
//           children: [
//             Container(
//               padding: const EdgeInsets.all(16),
//               decoration: BoxDecoration(
//                 color: AppColors.success.withOpacity(0.1),
//                 shape: BoxShape.circle,
//               ),
//               child: const Icon(Icons.check_circle,
//                   color: AppColors.success, size: 48),
//             ),
//             const SizedBox(height: 16),
//             const Text('Family Created!',
//                 style: TextStyle(
//                     fontSize: 24,
//                     fontWeight: FontWeight.bold,
//                     color: AppColors.secondary)),
//           ],
//         ),
//         content: Column(
//           mainAxisSize: MainAxisSize.min,
//           children: [
//             Text(
//               '"$familyName" is ready',
//               textAlign: TextAlign.center,
//               style: const TextStyle(
//                   fontSize: 14,
//                   color: AppColors.textLight,
//                   fontWeight: FontWeight.w500),
//             ),
//             const SizedBox(height: 6),
//             const Text('Share this code with your family members',
//                 textAlign: TextAlign.center,
//                 style: TextStyle(fontSize: 13, color: AppColors.textLight)),
//             const SizedBox(height: 24),
//             Container(
//               padding: const EdgeInsets.all(20),
//               decoration: BoxDecoration(
//                 color: AppColors.primary.withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(16),
//                 border: Border.all(color: AppColors.primary, width: 2),
//               ),
//               child: Column(
//                 children: [
//                   const Text('Family Code',
//                       style: TextStyle(
//                           fontSize: 12,
//                           color: AppColors.textLight,
//                           fontWeight: FontWeight.w500)),
//                   const SizedBox(height: 8),
//                   Text(familyCode,
//                       style: const TextStyle(
//                           fontSize: 36,
//                           fontWeight: FontWeight.bold,
//                           letterSpacing: 8,
//                           color: AppColors.primary)),
//                 ],
//               ),
//             ),
//             const SizedBox(height: 16),
//             Container(
//               padding: const EdgeInsets.all(12),
//               decoration: BoxDecoration(
//                 color: Colors.amber.withOpacity(0.1),
//                 borderRadius: BorderRadius.circular(8),
//                 border: Border.all(color: Colors.amber.withOpacity(0.3)),
//               ),
//               child: const Row(
//                 children: [
//                   Icon(Icons.info_outline, color: Colors.amber, size: 20),
//                   SizedBox(width: 8),
//                   Expanded(
//                     child: Text(
//                       'Save this code! You\'ll need it to add members.',
//                       style:
//                           TextStyle(fontSize: 11, color: AppColors.textLight),
//                     ),
//                   ),
//                 ],
//               ),
//             ),
//           ],
//         ),
//         actions: [
//           SizedBox(
//             width: double.infinity,
//             child: ElevatedButton(
//               onPressed: () => Navigator.pop(context),
//               style: ElevatedButton.styleFrom(
//                 backgroundColor: AppColors.primary,
//                 shape: RoundedRectangleBorder(
//                     borderRadius: BorderRadius.circular(12)),
//                 padding: const EdgeInsets.symmetric(vertical: 14),
//               ),
//               child: const Text('Got it!',
//                   style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
//             ),
//           ),
//         ],
//       ),
//     );
//   }

//   void _showErrorSnackBar(String message) {
//     if (!mounted) return;
//     ScaffoldMessenger.of(context).showSnackBar(SnackBar(
//       content: Row(children: [
//         const Icon(Icons.error_outline, color: Colors.white),
//         const SizedBox(width: 12),
//         Expanded(child: Text(message)),
//       ]),
//       backgroundColor: AppColors.danger,
//       behavior: SnackBarBehavior.floating,
//       shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
//     ));
//   }

//   @override
//   Widget build(BuildContext context) {
//     return Form(
//       key: _formKey,
//       child: Column(
//         crossAxisAlignment: CrossAxisAlignment.start,
//         children: [
//           Container(
//             padding: const EdgeInsets.all(16),
//             decoration: BoxDecoration(
//               color: AppColors.success.withOpacity(0.05),
//               borderRadius: BorderRadius.circular(12),
//               border: Border.all(color: AppColors.success.withOpacity(0.2)),
//             ),
//             child: const Row(
//               children: [
//                 Icon(Icons.admin_panel_settings,
//                     color: AppColors.success, size: 24),
//                 SizedBox(width: 12),
//                 Expanded(
//                   child: Text(
//                     'You\'ll be the family admin with full permissions',
//                     style: TextStyle(
//                         fontSize: 13, color: AppColors.secondary, height: 1.4),
//                   ),
//                 ),
//               ],
//             ),
//           ),
//           const SizedBox(height: 24),
//           _buildFamilyNameField(),
//           const SizedBox(height: 24),
//           _buildRoleSelection(),
//           const SizedBox(height: 32),
//           _buildCreateButton(),
//         ],
//       ),
//     );
//   }

//   Widget _buildFamilyNameField() {
//     final isFocused = _familyNameFocus.hasFocus;
//     final hasValue = _familyNameController.text.isNotEmpty;
//     final labelIsUp = hasValue || isFocused;

//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text('Family Name',
//             style: TextStyle(
//                 fontSize: 16,
//                 fontWeight: FontWeight.bold,
//                 color: AppColors.secondary)),
//         const SizedBox(height: 12),
//         TextFormField(
//           controller: _familyNameController,
//           focusNode: _familyNameFocus,
//           decoration: InputDecoration(
//             labelText: 'Family Name',
//             labelStyle: TextStyle(
//               color: isFocused ? AppColors.primary : AppColors.grey,
//               fontSize: labelIsUp ? 12 : 14,
//               fontWeight: FontWeight.w500,
//             ),
//             hintText: labelIsUp ? null : 'e.g., Dumalag Family',
//             hintStyle: const TextStyle(color: AppColors.grey, fontSize: 14),
//             prefixIcon: const Icon(Icons.home),
//             filled: true,
//             fillColor: Colors.white,
//             contentPadding:
//                 const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
//             border: OutlineInputBorder(
//                 borderRadius: BorderRadius.circular(12),
//                 borderSide:
//                     const BorderSide(color: AppColors.lightGrey, width: 1)),
//             enabledBorder: OutlineInputBorder(
//                 borderRadius: BorderRadius.circular(12),
//                 borderSide:
//                     const BorderSide(color: AppColors.lightGrey, width: 1)),
//             focusedBorder: OutlineInputBorder(
//                 borderRadius: BorderRadius.circular(12),
//                 borderSide:
//                     const BorderSide(color: AppColors.primary, width: 2)),
//             errorBorder: OutlineInputBorder(
//                 borderRadius: BorderRadius.circular(12),
//                 borderSide:
//                     const BorderSide(color: AppColors.danger, width: 1)),
//             focusedErrorBorder: OutlineInputBorder(
//                 borderRadius: BorderRadius.circular(12),
//                 borderSide:
//                     const BorderSide(color: AppColors.danger, width: 2)),
//             errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12),
//           ),
//           onChanged: (_) => setState(() {}),
//           validator: (value) {
//             if (value == null || value.isEmpty) {
//               return 'Please enter a family name';
//             }
//             if (value.length < 3) {
//               return 'Family name must be at least 3 characters';
//             }
//             return null;
//           },
//         ),
//       ],
//     );
//   }

//   Widget _buildRoleSelection() {
//     return Column(
//       crossAxisAlignment: CrossAxisAlignment.start,
//       children: [
//         const Text('Your Role',
//             style: TextStyle(
//                 fontSize: 16,
//                 fontWeight: FontWeight.bold,
//                 color: AppColors.secondary)),
//         const SizedBox(height: 12),
//         Container(
//           decoration: BoxDecoration(
//             border: Border.all(color: AppColors.lightGrey),
//             borderRadius: BorderRadius.circular(12),
//             color: Colors.white,
//           ),
//           child: DropdownButtonFormField<String>(
//             value: _selectedRole,
//             decoration: const InputDecoration(
//               prefixIcon: Icon(Icons.person_outline),
//               border: InputBorder.none,
//               contentPadding:
//                   EdgeInsets.symmetric(horizontal: 16, vertical: 12),
//             ),
//             items: _adminRoles
//                 .map((role) => DropdownMenuItem(value: role, child: Text(role)))
//                 .toList(),
//             onChanged: (value) => setState(() => _selectedRole = value!),
//           ),
//         ),
//       ],
//     );
//   }

//   Widget _buildCreateButton() {
//     return SizedBox(
//       width: double.infinity,
//       height: 56,
//       child: ElevatedButton(
//         onPressed: !_isCreating ? _createFamily : null,
//         style: ElevatedButton.styleFrom(
//           backgroundColor: AppColors.success,
//           disabledBackgroundColor: AppColors.grey.withOpacity(0.3),
//           shape:
//               RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
//           elevation: 4,
//         ),
//         child: _isCreating
//             ? const SizedBox(
//                 width: 24,
//                 height: 24,
//                 child: CircularProgressIndicator(
//                     color: Colors.white, strokeWidth: 2))
//             : const Row(
//                 mainAxisAlignment: MainAxisAlignment.center,
//                 children: [
//                   Icon(Icons.add_circle, size: 24),
//                   SizedBox(width: 12),
//                   Text('Create Family',
//                       style: TextStyle(
//                           fontSize: 16,
//                           fontWeight: FontWeight.bold,
//                           letterSpacing: 0.5)),
//                 ],
//               ),
//       ),
//     );
//   }
// }
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../dashboard/screens/dashboard_screen.dart';

class FamilySetupScreen extends StatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final String mobile;
  final String barangay;
  final String zipCode;

  const FamilySetupScreen({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.mobile = '',
    this.barangay = '',
    this.zipCode = '',
  });

  @override
  State<FamilySetupScreen> createState() => _FamilySetupScreenState();
}

class _FamilySetupScreenState extends State<FamilySetupScreen> {
  bool _showJoinFamily = true;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 20),
                _buildHeader(),
                const SizedBox(height: 40),
                _buildToggleButtons(),
                const SizedBox(height: 32),
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 300),
                  child: _showJoinFamily
                      ? JoinFamilyForm(
                          key: const ValueKey('join'),
                          userId: widget.userId,
                          userName: widget.userName,
                          userEmail: widget.userEmail,
                          mobile: widget.mobile,
                          barangay: widget.barangay,
                          zipCode: widget.zipCode,
                        )
                      : CreateFamilyForm(
                          key: const ValueKey('create'),
                          userId: widget.userId,
                          userName: widget.userName,
                          userEmail: widget.userEmail,
                          mobile: widget.mobile,
                          barangay: widget.barangay,
                          zipCode: widget.zipCode,
                        ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: AppColors.primary.withOpacity(0.1),
            shape: BoxShape.circle,
          ),
          child: const Icon(
            Icons.family_restroom,
            size: 48,
            color: AppColors.primary,
          ),
        ),
        const SizedBox(height: 24),
        Text(
          'Welcome, ${widget.userName}!',
          style: const TextStyle(
            fontSize: 28,
            fontWeight: FontWeight.bold,
            color: AppColors.secondary,
          ),
        ),
        const SizedBox(height: 8),
        const Text(
          'Let\'s set up your family circle for safety tracking',
          style: TextStyle(
            fontSize: 16,
            color: AppColors.textLight,
            height: 1.5,
          ),
        ),
      ],
    );
  }

  Widget _buildToggleButtons() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.lightGrey,
        borderRadius: BorderRadius.circular(12),
      ),
      padding: const EdgeInsets.all(4),
      child: Row(
        children: [
          Expanded(
            child: _buildToggleButton(
              'Join Family',
              _showJoinFamily,
              () => setState(() => _showJoinFamily = true),
            ),
          ),
          Expanded(
            child: _buildToggleButton(
              'Create Family',
              !_showJoinFamily,
              () => setState(() => _showJoinFamily = false),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String label, bool isSelected, VoidCallback onTap) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        padding: const EdgeInsets.symmetric(vertical: 14),
        decoration: BoxDecoration(
          color: isSelected ? Colors.white : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(
            fontSize: 15,
            fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
            color: isSelected ? AppColors.primary : AppColors.textLight,
          ),
        ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// JoinFamilyForm
// ═══════════════════════════════════════════════════════════════════════════
class JoinFamilyForm extends StatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final String mobile;
  final String barangay;
  final String zipCode;

  const JoinFamilyForm({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.mobile = '',
    this.barangay = '',
    this.zipCode = '',
  });

  @override
  State<JoinFamilyForm> createState() => _JoinFamilyFormState();
}

class _JoinFamilyFormState extends State<JoinFamilyForm> {
  final _formKey = GlobalKey<FormState>();
  final _familyCodeController = TextEditingController();
  final _familyCodeFocus = FocusNode();

  String _selectedRole = 'Son';
  bool _isVerifying = false;
  bool _isJoining = false;
  bool _isFamilyCodeValid = false;
  Map<String, dynamic>? _verifiedFamily;

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

  Future<void> _joinFamily() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_isFamilyCodeValid) {
      _showErrorSnackBar('Please verify the family code first');
      return;
    }

    setState(() => _isJoining = true);

    try {
      print('🔵 Joining family: ${_familyCodeController.text.trim()}');
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
              result['message'] ?? 'Successfully joined family!');
          await Future.delayed(const Duration(seconds: 1));
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => DashboardScreen(
                  userId: widget.userId,
                  userName: widget.userName,
                ),
              ),
            );
          }
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

  void _showSuccessSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.check_circle, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: AppColors.success,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
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
                        fontSize: 13, color: AppColors.secondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildFamilyCodeSection(),
          const SizedBox(height: 24),
          _buildRoleSelection(),
          const SizedBox(height: 32),
          _buildJoinButton(),
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
              const Text('Family Code',
                  style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary)),
            ],
          ),
          const SizedBox(height: 16),
          TextFormField(
            controller: _familyCodeController,
            focusNode: _familyCodeFocus,
            keyboardType: TextInputType.number,
            maxLength: 6,
            style: const TextStyle(
                fontSize: 24, fontWeight: FontWeight.bold, letterSpacing: 8),
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
                  color: AppColors.grey.withOpacity(0.3), letterSpacing: 8),
              filled: true,
              fillColor: Colors.white,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.lightGrey, width: 1)),
              focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2)),
              errorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.danger, width: 1)),
              focusedErrorBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.danger, width: 2)),
              errorStyle:
                  const TextStyle(color: AppColors.danger, fontSize: 12),
              suffixIcon: _isVerifying
                  ? const Padding(
                      padding: EdgeInsets.all(12.0),
                      child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : _isFamilyCodeValid
                      ? const Icon(Icons.check_circle, color: Colors.green)
                      : null,
              counterText: '',
            ),
            onChanged: (value) {
              setState(() {});
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
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Verified',
                            style: TextStyle(
                                color: Colors.green,
                                fontWeight: FontWeight.bold,
                                fontSize: 12)),
                        Text(
                          _verifiedFamily!['FamilyName'] ?? 'Family',
                          style: const TextStyle(
                              color: Colors.green,
                              fontWeight: FontWeight.w600,
                              fontSize: 16),
                        ),
                        Text(
                          'Admin: ${_verifiedFamily!['CreatedByName'] ?? 'Unknown'}',
                          style: const TextStyle(
                              color: Colors.green, fontSize: 11),
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

  Widget _buildRoleSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your Role in Family',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary)),
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
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.grey.withOpacity(0.3),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: _isFamilyCodeValid ? 4 : 0,
        ),
        child: _isJoining
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.login, size: 24),
                  SizedBox(width: 12),
                  Text('Join Family',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                ],
              ),
      ),
    );
  }
}

// ═══════════════════════════════════════════════════════════════════════════
// CreateFamilyForm
// ═══════════════════════════════════════════════════════════════════════════
class CreateFamilyForm extends StatefulWidget {
  final String userId;
  final String userName;
  final String userEmail;
  final String mobile;
  final String barangay;
  final String zipCode;

  const CreateFamilyForm({
    super.key,
    required this.userId,
    required this.userName,
    required this.userEmail,
    this.mobile = '',
    this.barangay = '',
    this.zipCode = '',
  });

  @override
  State<CreateFamilyForm> createState() => _CreateFamilyFormState();
}

class _CreateFamilyFormState extends State<CreateFamilyForm> {
  final _formKey = GlobalKey<FormState>();
  final _familyNameController = TextEditingController();
  final _familyNameFocus = FocusNode();

  String _selectedRole = 'Father';
  bool _isCreating = false;

  final List<String> _adminRoles = ['Father', 'Mother', 'Guardian'];

  @override
  void initState() {
    super.initState();
    _familyNameFocus.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _familyNameController.dispose();
    _familyNameFocus.dispose();
    super.dispose();
  }

  Future<void> _createFamily() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isCreating = true);

    try {
      print('🔨 Creating family: ${_familyNameController.text.trim()}');
      print('🔨 UserId: ${widget.userId} | Role: $_selectedRole');

      final result = await FirebaseService.createFamily(
        userId: widget.userId,
        userName: widget.userName,
        familyName: _familyNameController.text.trim(),
      );

      print('🔨 Create result: $result');

      if (mounted) {
        if (result['success'] == true) {
          print('✅ Family created! Code: ${result['familyCode']}');
          await _showFamilyCodeDialog(
            result['familyCode'],
            result['familyName'],
          );
          if (mounted) {
            Navigator.pushReplacement(
              context,
              MaterialPageRoute(
                builder: (context) => DashboardScreen(
                  userId: widget.userId,
                  userName: widget.userName,
                ),
              ),
            );
          }
        } else {
          setState(() => _isCreating = false);
          _showErrorSnackBar(result['error'] ?? 'Failed to create family');
        }
      }
    } catch (e) {
      print('❌ Create family error: $e');
      if (mounted) {
        setState(() => _isCreating = false);
        _showErrorSnackBar('Failed to create family: $e');
      }
    }
  }

  Future<void> _showFamilyCodeDialog(
      String familyCode, String familyName) async {
    return showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: AppColors.success.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle,
                  color: AppColors.success, size: 48),
            ),
            const SizedBox(height: 16),
            const Text('Family Created!',
                style: TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '"$familyName" is ready',
              textAlign: TextAlign.center,
              style: const TextStyle(
                  fontSize: 14,
                  color: AppColors.textLight,
                  fontWeight: FontWeight.w500),
            ),
            const SizedBox(height: 6),
            const Text('Share this code with your family members',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 13, color: AppColors.textLight)),
            const SizedBox(height: 24),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: AppColors.primary.withOpacity(0.1),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.primary, width: 2),
              ),
              child: Column(
                children: [
                  const Text('Family Code',
                      style: TextStyle(
                          fontSize: 12,
                          color: AppColors.textLight,
                          fontWeight: FontWeight.w500)),
                  const SizedBox(height: 8),
                  Text(familyCode,
                      style: const TextStyle(
                          fontSize: 36,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 8,
                          color: AppColors.primary)),
                ],
              ),
            ),
            const SizedBox(height: 16),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.amber.withOpacity(0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.amber.withOpacity(0.3)),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.amber, size: 20),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Save this code! You\'ll need it to add members.',
                      style:
                          TextStyle(fontSize: 11, color: AppColors.textLight),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                padding: const EdgeInsets.symmetric(vertical: 14),
              ),
              child: const Text('Got it!',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ),
          ),
        ],
      ),
    );
  }

  void _showErrorSnackBar(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Row(children: [
        const Icon(Icons.error_outline, color: Colors.white),
        const SizedBox(width: 12),
        Expanded(child: Text(message)),
      ]),
      backgroundColor: AppColors.danger,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Form(
      key: _formKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: AppColors.success.withOpacity(0.05),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.success.withOpacity(0.2)),
            ),
            child: const Row(
              children: [
                Icon(Icons.admin_panel_settings,
                    color: AppColors.success, size: 24),
                SizedBox(width: 12),
                Expanded(
                  child: Text(
                    'You\'ll be the family admin with full permissions',
                    style: TextStyle(
                        fontSize: 13, color: AppColors.secondary, height: 1.4),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 24),
          _buildFamilyNameField(),
          const SizedBox(height: 24),
          _buildRoleSelection(),
          const SizedBox(height: 32),
          _buildCreateButton(),
        ],
      ),
    );
  }

  Widget _buildFamilyNameField() {
    final isFocused = _familyNameFocus.hasFocus;
    final hasValue = _familyNameController.text.isNotEmpty;
    final labelIsUp = hasValue || isFocused;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Family Name',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary)),
        const SizedBox(height: 12),
        TextFormField(
          controller: _familyNameController,
          focusNode: _familyNameFocus,
          decoration: InputDecoration(
            labelText: 'Family Name',
            labelStyle: TextStyle(
              color: isFocused ? AppColors.primary : AppColors.grey,
              fontSize: labelIsUp ? 12 : 14,
              fontWeight: FontWeight.w500,
            ),
            hintText: labelIsUp ? null : 'e.g., Dumalag Family',
            hintStyle: const TextStyle(color: AppColors.grey, fontSize: 14),
            prefixIcon: const Icon(Icons.home),
            filled: true,
            fillColor: Colors.white,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 18),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.lightGrey, width: 1)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.lightGrey, width: 1)),
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.primary, width: 2)),
            errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.danger, width: 1)),
            focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide:
                    const BorderSide(color: AppColors.danger, width: 2)),
            errorStyle: const TextStyle(color: AppColors.danger, fontSize: 12),
          ),
          onChanged: (_) => setState(() {}),
          validator: (value) {
            if (value == null || value.isEmpty) {
              return 'Please enter a family name';
            }
            if (value.length < 3) {
              return 'Family name must be at least 3 characters';
            }
            return null;
          },
        ),
      ],
    );
  }

  Widget _buildRoleSelection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Your Role',
            style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary)),
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
              prefixIcon: Icon(Icons.person_outline),
              border: InputBorder.none,
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            ),
            items: _adminRoles
                .map((role) => DropdownMenuItem(value: role, child: Text(role)))
                .toList(),
            onChanged: (value) => setState(() => _selectedRole = value!),
          ),
        ),
      ],
    );
  }

  Widget _buildCreateButton() {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: !_isCreating ? _createFamily : null,
        style: ElevatedButton.styleFrom(
          backgroundColor: AppColors.success,
          foregroundColor: Colors.white,
          disabledBackgroundColor: AppColors.grey.withOpacity(0.3),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          elevation: 4,
        ),
        child: _isCreating
            ? const SizedBox(
                width: 24,
                height: 24,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2))
            : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.add_circle, size: 24),
                  SizedBox(width: 12),
                  Text('Create Family',
                      style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 0.5)),
                ],
              ),
      ),
    );
  }
}
