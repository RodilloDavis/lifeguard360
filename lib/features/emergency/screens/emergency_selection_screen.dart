import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import 'accident_emergency_screen.dart';
import 'fire_emergency_screen.dart';
import 'medical_alert_screen.dart';
import 'flood_emergency_screen.dart';
import 'crime_emergency_screen.dart';
import 'other_emergency_screen.dart';

// ═══════════════════════════════════════════════════════════════════════════════
// EmergencySelectionScreen
//
// Entry point for all emergency reports. Requires userId + userName so every
// sub-screen can pass them through to EmergencyConfirmationScreen
// → EmergencyReportService → Firebase.
//
// Usage from DashboardHome / SOS button:
//
//   Navigator.push(
//     context,
//     MaterialPageRoute(
//       builder: (_) => EmergencySelectionScreen(
//         userId: widget.userId,
//         userName: widget.userName,
//       ),
//     ),
//   );
// ═══════════════════════════════════════════════════════════════════════════════

class EmergencySelectionScreen extends StatelessWidget {
  final String userId;
  final String userName;

  const EmergencySelectionScreen({
    super.key,
    required this.userId,
    required this.userName,
  });

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        title: const Text(
          'Select Emergency Type',
          style: TextStyle(
              color: AppColors.secondary, fontWeight: FontWeight.bold),
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.secondary),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(20),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // ── Header banner ────────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    colors: [AppColors.danger, Color(0xFFFF6B6B)],
                  ),
                  borderRadius: BorderRadius.circular(16),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.danger.withOpacity(0.3),
                      blurRadius: 10,
                      offset: const Offset(0, 4),
                    ),
                  ],
                ),
                child: const Row(
                  children: [
                    Icon(Icons.warning_amber_rounded,
                        color: Colors.white, size: 36),
                    SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text('Emergency Alert',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 18,
                                  fontWeight: FontWeight.bold)),
                          SizedBox(height: 4),
                          Text('Select the type of emergency to report',
                              style: TextStyle(
                                  color: Colors.white70, fontSize: 12)),
                        ],
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 28),
              const Text('What is the emergency?',
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: AppColors.secondary)),
              const SizedBox(height: 16),

              // ── Emergency grid ───────────────────────────────────────────
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                crossAxisSpacing: 14,
                mainAxisSpacing: 14,
                childAspectRatio: 1.2,
                children: [
                  _buildCard(
                    context,
                    icon: Icons.local_fire_department,
                    emoji: '🔥',
                    label: 'Fire',
                    subtitle: 'Building, forest, vehicle',
                    color: Colors.deepOrange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FireEmergencyScreen(
                          userId: userId,
                          userName: userName,
                        ),
                      ),
                    ),
                  ),
                  _buildCard(
                    context,
                    icon: Icons.local_hospital,
                    emoji: '🏥',
                    label: 'Medical',
                    subtitle: 'Injury, illness, cardiac',
                    color: Colors.red,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => MedicalAlertScreen(
                          userId: userId,
                          userName: userName,
                        ),
                      ),
                    ),
                  ),
                  _buildCard(
                    context,
                    icon: Icons.gavel,
                    emoji: '👮',
                    label: 'Crime',
                    subtitle: 'Theft, assault, suspicious',
                    color: AppColors.secondary,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => CrimeEmergencyScreen(
                          userId: userId,
                          userName: userName,
                        ),
                      ),
                    ),
                  ),
                  _buildCard(
                    context,
                    icon: Icons.water,
                    emoji: '💧',
                    label: 'Flood',
                    subtitle: 'Rising water, evacuation',
                    color: Colors.blue,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => FloodEmergencyScreen(
                          userId: userId,
                          userName: userName,
                        ),
                      ),
                    ),
                  ),
                  _buildCard(
                    context,
                    icon: Icons.car_crash,
                    emoji: '🚗',
                    label: 'Accident',
                    subtitle: 'Vehicle, workplace, fall',
                    color: Colors.orange,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => AccidentEmergencyScreen(
                          userId: userId,
                          userName: userName,
                        ),
                      ),
                    ),
                  ),
                  _buildCard(
                    context,
                    icon: Icons.warning_amber,
                    emoji: '⚠️',
                    label: 'Other',
                    subtitle: 'Gas leak, missing person',
                    color: Colors.amber.shade700,
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => OtherEmergencyScreen(
                          userId: userId,
                          userName: userName,
                        ),
                      ),
                    ),
                  ),
                ],
              ),

              const SizedBox(height: 24),

              // ── Safety reminder ──────────────────────────────────────────
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: Colors.amber.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.amber.withOpacity(0.3)),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.info_outline, color: Colors.amber, size: 20),
                    SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        'Your report will include your current GPS location '
                        'and be saved to our emergency database. Make sure '
                        'you are in a safe location before reporting.',
                        style: TextStyle(
                            fontSize: 12,
                            color: AppColors.textLight,
                            height: 1.4),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard(
    BuildContext context, {
    required IconData icon,
    required String emoji,
    required String label,
    required String subtitle,
    required Color color,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: color.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: color.withOpacity(0.25), width: 1.5),
          boxShadow: [
            BoxShadow(
                color: color.withOpacity(0.08),
                blurRadius: 8,
                offset: const Offset(0, 2)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, color: color, size: 22),
                ),
                const Spacer(),
                Text(emoji, style: const TextStyle(fontSize: 22)),
              ],
            ),
            const Spacer(),
            Text(label,
                style: TextStyle(
                    fontSize: 15, fontWeight: FontWeight.bold, color: color)),
            const SizedBox(height: 2),
            Text(subtitle,
                style:
                    const TextStyle(fontSize: 10, color: AppColors.textLight),
                maxLines: 1,
                overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
