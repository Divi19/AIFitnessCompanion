import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../workout/injury_profile_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
    // Navigate back to login/auth wrapper to avoid null user crashes
    if (context.mounted) {
      Navigator.of(context).popUntil((route) => route.isFirst);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Check if user is null to prevent '!' operator crashes
    final user = FirebaseAuth.instance.currentUser;

    if (user == null) {
      return const Scaffold(
        backgroundColor: Color(0xFF0D0D0D),
        body: Center(child: Text('Not logged in', style: TextStyle(color: Colors.white))),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text('My Profile', style: TextStyle(fontWeight: FontWeight.bold, color: Colors.white)),
        backgroundColor: Colors.transparent,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFC5F135)));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
             return const Center(child: Text('Profile not found', style: TextStyle(color: Colors.white)));
          }

          final data      = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final bodyStats = data['body_stats']  as Map<String, dynamic>? ?? {};
          final goal      = data['fitness_goal'] ?? 'Not set';

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── User Header ──────────────────────────────────────────
                Center(
                  child: Column(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          border: Border.all(color: const Color(0xFFC5F135), width: 3),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFC5F135).withOpacity(0.15),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            )
                          ]
                        ),
                        child: const CircleAvatar(
                          radius: 46,
                          backgroundImage: NetworkImage('https://images.unsplash.com/photo-1534528741775-53994a69daeb?w=200&q=80&fit=crop'),
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        data['name'] ?? 'Sarah James',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 26,
                          fontWeight: FontWeight.w800,
                          color: Colors.white,
                          letterSpacing: -0.5,
                        )
                      ),
                      const SizedBox(height: 4),
                      Text(
                        user.email ?? 'sarah.j@fitcore.ai',
                        textAlign: TextAlign.center,
                        style: const TextStyle(
                          fontSize: 13,
                          color: Color(0xFF6B6B8A),
                          fontWeight: FontWeight.w500,
                        )
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 40),

                // ── 3-Column Info Grid ───────────────────────────────────
                Row(
                  children: [
                    Expanded(
                      child: _buildMiniStatCard(
                        icon: Icons.flag,
                        iconColor: const Color(0xFF9B8FFF),
                        title: 'GOAL',
                        value: goal.toString().split(' ').first, // Try to make it fit in box
                      )
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMiniStatCard(
                        icon: Icons.monitor_weight,
                        iconColor: const Color(0xFFC5F135),
                        title: 'WEIGHT',
                        value: bodyStats['weight']?.toString() ?? '-',
                      )
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: _buildMiniStatCard(
                        icon: Icons.height,
                        iconColor: const Color(0xFFFF7B6B),
                        title: 'HEIGHT',
                        value: bodyStats['height']?.toString() ?? '-',
                      )
                    ),
                  ],
                ),

                const SizedBox(height: 32),

                // ── Action Buttons ────────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InjuryProfileScreen()),
                  ),
                  icon: const Icon(Icons.medical_information, color: Color(0xFF9B8FFF)),
                  label: const Text('Update Stats & Injuries',
                      style: TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A2E), // Match dark cards
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    elevation: 0,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                      side: const BorderSide(color: Colors.white10),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                TextButton(
                  onPressed: () => _signOut(context),
                  style: TextButton.styleFrom(
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
                  ),
                  child: const Text('Sign Out',
                      style: TextStyle(
                        color: Color(0xFFFF7B6B),
                        fontSize: 14,
                        fontWeight: FontWeight.bold
                      )),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildMiniStatCard({required IconData icon, required Color iconColor, required String title, required String value}) {
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A2E),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: Colors.white10)
      ),
      child: Column(
        children: [
          Icon(icon, color: iconColor, size: 24),
          const SizedBox(height: 8),
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFF6B6B8A),
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.0,
            )
          ),
          const SizedBox(height: 4),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.w800,
            )
          )
        ],
      ),
    );
  }
}