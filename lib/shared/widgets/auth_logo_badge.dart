import 'package:flutter/material.dart';
import '../../core/constants/app_colors.dart';

/// Circular shield badge used above the form card on the login and sign-up
/// screens.
class AuthLogoBadge extends StatelessWidget {
  final double size;
  const AuthLogoBadge({super.key, required this.size});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Colors.white, Color(0xFFE6F4FF)],
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.25),
            blurRadius: 24,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Icon(
        Icons.shield_rounded,
        size: size * 0.52,
        color: AppColors.primary,
      ),
    );
  }
}
