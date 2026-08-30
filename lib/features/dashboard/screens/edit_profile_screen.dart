import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text_field.dart';
import '../../../shared/widgets/photo_avatar.dart';
import '../../../models/user_model.dart';
import '../../../services/cloudinary_service.dart';
import '../../../services/firebase_realtime_database.dart';
import '../../../services/family_service.dart';
import '../../dashboard/screens/dashboard_screen.dart';

class EditProfileScreen extends StatefulWidget {
  final String userId;
  final UserModel currentUser;
  final bool isAdmin;

  const EditProfileScreen({
    super.key,
    required this.userId,
    required this.currentUser,
    required this.isAdmin,
  });

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  late TextEditingController _nameController;
  String _selectedRole = 'Member';
  bool _hasChanges = false;
  bool _isSaving = false;
  bool _isUploadingPhoto = false;

  // Local preview of a newly picked photo, not yet uploaded.
  File? _pickedPhotoFile;
  // True once the user explicitly chooses "Remove" — clears the photo on save.
  bool _removePhoto = false;

  final List<String> _roles = [
    'Admin',
    'Father',
    'Mother',
    'Son',
    'Daughter',
    'Brother',
    'Sister',
    'Grandfather',
    'Grandmother',
    'Uncle',
    'Aunt',
    'Member',
  ];

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.currentUser.name);
    _selectedRole = _roles.contains(widget.currentUser.role)
        ? widget.currentUser.role
        : 'Member';
  }

  @override
  void dispose() {
    _nameController.dispose();
    super.dispose();
  }

  void _checkForChanges() {
    setState(() {
      _hasChanges = _nameController.text.trim() != widget.currentUser.name ||
          _selectedRole != widget.currentUser.role ||
          _pickedPhotoFile != null ||
          _removePhoto;
    });
  }

  Future<void> _saveChanges() async {
    final newName = _nameController.text.trim();
    if (newName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Name cannot be empty'),
          backgroundColor: AppColors.danger,
        ),
      );
      return;
    }

    if (!_hasChanges) {
      Navigator.pop(context, null);
      return;
    }

    setState(() => _isSaving = true);

    try {
      // Upload the new photo to Cloudinary first (if any) so we have a URL
      // to save — instead of embedding it as base64 text directly in the
      // account's JSON node (see CloudinaryService for why: smaller
      // upload, and every future view fetches a small optimized variant
      // instead of the original). If this fails, the profile fields below
      // are left untouched.
      String? newPhotoUrl;
      if (_pickedPhotoFile != null) {
        setState(() => _isUploadingPhoto = true);
        try {
          newPhotoUrl = await CloudinaryService.uploadImage(_pickedPhotoFile!);
        } catch (e) {
          if (!mounted) return;
          setState(() {
            _isSaving = false;
            _isUploadingPhoto = false;
          });
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Failed to upload photo: $e'),
              backgroundColor: AppColors.danger,
            ),
          );
          return;
        }
        if (!mounted) return;
        setState(() => _isUploadingPhoto = false);
      } else if (_removePhoto) {
        newPhotoUrl = '';
      }

      final result = await FirebaseService.updateUserProfile(
        userId: widget.userId,
        newName: newName,
        newRole: _selectedRole,
        newPhotoUrl: newPhotoUrl,
      );

      if (!mounted) return;

      setState(() => _isSaving = false);

      if (result['success'] == true) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.setString('userName', newName);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Profile updated successfully'),
            backgroundColor: AppColors.success,
          ),
        );
        Navigator.pop(context, {
          'name': newName,
          'role': _selectedRole,
          if (newPhotoUrl != null) 'photoUrl': newPhotoUrl,
        });
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['error'] ?? 'Failed to update profile'),
            backgroundColor: AppColors.danger,
          ),
        );
      }
    } catch (e) {
      setState(() {
        _isSaving = false;
        _isUploadingPhoto = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('An error occurred: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  // ── Build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.splashBackground,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text(
          'Edit Profile',
          style: TextStyle(
            color: AppColors.secondary,
            fontWeight: FontWeight.bold,
          ),
        ),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        child: Column(
          children: [
            const SizedBox(height: 20),
            _buildProfilePhoto(),
            const SizedBox(height: 30),
            _buildNameSection(),
            const SizedBox(height: 16),
            _buildRoleSection(),
            const SizedBox(height: 30),
            _buildSaveButton(),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildProfilePhoto() {
    return Column(
      children: [
        Stack(
          children: [
            Container(
              width: 120,
              height: 120,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.primary.withOpacity(0.2),
                border: Border.all(
                  color: AppColors.primary,
                  width: 3,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: _buildAvatarContent(),
            ),
            if (_isUploadingPhoto)
              const Positioned.fill(
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                ),
              ),
            Positioned(
              right: 0,
              bottom: 0,
              child: GestureDetector(
                onTap: _isSaving ? null : _changeProfilePhoto,
                child: Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: AppColors.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                  child: const Icon(
                    Icons.camera_alt,
                    color: Colors.white,
                    size: 20,
                  ),
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        TextButton.icon(
          onPressed: _isSaving ? null : _changeProfilePhoto,
          icon: const Icon(Icons.edit, size: 18),
          label: const Text('Change Photo'),
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
          ),
        ),
      ],
    );
  }

  /// Picks between: a freshly-picked local file (preview before upload),
  /// the existing remote photo, "removed" (falls back to initials), or the
  /// initials placeholder when there was never a photo.
  Widget _buildAvatarContent() {
    if (_pickedPhotoFile != null) {
      return Image.file(
        _pickedPhotoFile!,
        width: 120,
        height: 120,
        fit: BoxFit.cover,
      );
    }

    final existingPhoto = widget.currentUser.photoUrl;
    if (!_removePhoto && existingPhoto.isNotEmpty) {
      return PhotoAvatar(
        photoUrl: existingPhoto,
        size: 120,
        initials: _buildInitialsAvatar(),
      );
    }

    return _buildInitialsAvatar();
  }

  Widget _buildInitialsAvatar() {
    return Center(
      child: Text(
        widget.currentUser.name.isNotEmpty
            ? widget.currentUser.name[0].toUpperCase()
            : '?',
        style: const TextStyle(
          fontSize: 48,
          fontWeight: FontWeight.bold,
          color: AppColors.primary,
        ),
      ),
    );
  }

  Widget _buildNameSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Padding(
            padding: EdgeInsets.all(16),
            child: Text(
              'Full Name',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: TextField(
              controller: _nameController,
              onChanged: (_) => _checkForChanges(),
              decoration: InputDecoration(
                hintText: 'Enter your full name',
                prefixIcon: const Icon(Icons.person, color: AppColors.primary),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: AppColors.lightGrey),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide:
                      const BorderSide(color: AppColors.primary, width: 2),
                ),
                filled: true,
                fillColor: AppColors.lightGrey.withOpacity(0.3),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  Widget _buildRoleSection() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                const Text(
                  'Family Role',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                    color: AppColors.secondary,
                  ),
                ),
                if (!widget.isAdmin)
                  Container(
                    margin: const EdgeInsets.only(left: 8),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.danger.withOpacity(0.2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Admin approval required',
                      style: TextStyle(
                        fontSize: 10,
                        color: AppColors.danger,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: AppColors.lightGrey.withOpacity(0.3),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.lightGrey),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedRole,
                  isExpanded: true,
                  icon: const Icon(Icons.arrow_drop_down,
                      color: AppColors.primary),
                  items: _roles.map((String role) {
                    return DropdownMenuItem<String>(
                      value: role,
                      child: Text(
                        role,
                        style: const TextStyle(
                          fontSize: 15,
                          color: AppColors.secondary,
                        ),
                      ),
                    );
                  }).toList(),
                  onChanged: (String? newValue) {
                    if (newValue != null) {
                      setState(() {
                        _selectedRole = newValue;
                        _checkForChanges();
                      });
                    }
                  },
                ),
              ),
            ),
          ),
          const SizedBox(height: 16),
        ],
      ),
    );
  }

  // ── Helper Methods ──────────────────────────────────────────────────────

  Widget _buildSaveButton() {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      child: CustomButton(
        text: _isSaving ? 'Saving...' : 'Save Changes',
        onPressed: (_hasChanges && !_isSaving) ? _saveChanges : () {},
        fitContent: false,
        isLoading: _isSaving,
      ),
    );
  }

  Future<void> _pickPhoto(ImageSource source) async {
    try {
      final picker = ImagePicker();
      // Cloudinary generates the actual delivery-size variants on demand
      // (see CloudinaryService.deliveryUrl), so this only needs to cap the
      // one-time upload at a reasonable source resolution — not the tiny
      // 320px this was kept at back when the photo itself was embedded as
      // base64 text in the database record.
      final pickedFile = await picker.pickImage(
        source: source,
        maxWidth: 800,
        maxHeight: 800,
        imageQuality: 80,
      );

      // User cancelled the picker — leave the current photo untouched.
      if (pickedFile == null) return;
      if (!mounted) return;

      setState(() {
        _pickedPhotoFile = File(pickedFile.path);
        _removePhoto = false;
        _checkForChanges();
      });
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not select photo: $e'),
          backgroundColor: AppColors.danger,
        ),
      );
    }
  }

  void _changeProfilePhoto() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) => Container(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Change Profile Photo',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: AppColors.secondary,
              ),
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                _buildPhotoOption(
                  icon: Icons.camera_alt,
                  label: 'Camera',
                  onTap: () {
                    Navigator.pop(context);
                    _pickPhoto(ImageSource.camera);
                  },
                ),
                _buildPhotoOption(
                  icon: Icons.photo_library,
                  label: 'Gallery',
                  onTap: () {
                    Navigator.pop(context);
                    _pickPhoto(ImageSource.gallery);
                  },
                ),
                if (_pickedPhotoFile != null ||
                    (widget.currentUser.photoUrl.isNotEmpty && !_removePhoto))
                  _buildPhotoOption(
                    icon: Icons.delete,
                    label: 'Remove',
                    color: AppColors.danger,
                    onTap: () {
                      Navigator.pop(context);
                      setState(() {
                        _pickedPhotoFile = null;
                        _removePhoto = true;
                        _checkForChanges();
                      });
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content: Text(
                            'Photo will be removed when you save changes',
                          ),
                          backgroundColor: AppColors.danger,
                        ),
                      );
                    },
                  ),
              ],
            ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildPhotoOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    Color? color,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: (color ?? AppColors.primary).withOpacity(0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(
              icon,
              color: color ?? AppColors.primary,
              size: 32,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            label,
            style: TextStyle(
              fontSize: 14,
              color: color ?? AppColors.secondary,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }
}
