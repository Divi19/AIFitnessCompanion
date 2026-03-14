import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../workout/injury_profile_screen.dart';
import '../workout/workout_plan_screen.dart';

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
            return const Center(child: CircularProgressIndicator(color: Color(0xFFB9FF2B)));
          }

          if (!snapshot.hasData || !snapshot.data!.exists) {
             return const Center(child: Text('Profile not found', style: TextStyle(color: Colors.white)));
          }

          final data      = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final bodyStats = data['body_stats']  as Map<String, dynamic>? ?? {};
          final goal      = data['fitness_goal'] ?? 'Not set';

          return SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // ── User Header ──────────────────────────────────────────
                Center(
                  child: CircleAvatar(
                    radius: 40,
                    backgroundColor: const Color(0xFF1A1A1A),
                    child: Text(
                      (data['name'] ?? 'U').toString().substring(0, 1).toUpperCase(),
                      style: const TextStyle(
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFFB9FF2B)),
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Text(data['name'] ?? 'User',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.bold,
                        color: Colors.white)),
                Text(user.email ?? '',
                    textAlign: TextAlign.center,
                    style: const TextStyle(fontSize: 14, color: Colors.grey)),

                const SizedBox(height: 40),

                // ── Info Cards ────────────────────────────────────────────
                // Added .toString() to prevent type mismatch crashes
                _buildInfoSection('Current Goal', goal.toString(), Icons.flag),
                const SizedBox(height: 16),
                _buildInfoSection('Weight', bodyStats['weight']?.toString() ?? '-', Icons.monitor_weight),
                const SizedBox(height: 16),
                _buildInfoSection('Height', bodyStats['height']?.toString() ?? '-', Icons.height),

                const SizedBox(height: 32),

                // ── Active Workout Plan ───────────────────────────────────
                _buildActivePlanSection(context, user.uid),

                const SizedBox(height: 32),

                // ── Action Buttons ────────────────────────────────────────
                ElevatedButton.icon(
                  onPressed: () => Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => const InjuryProfileScreen()),
                  ),
                  icon: const Icon(Icons.medical_information),
                  label: const Text('Update Stats & Injuries',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1A1A1A),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 18),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                      side: const BorderSide(color: Colors.white10),
                    ),
                  ),
                ),

                const SizedBox(height: 16),

                TextButton.icon(
                  onPressed: () => _signOut(context),
                  icon: const Icon(Icons.logout, color: Colors.redAccent),
                  label: const Text('Sign Out',
                      style: TextStyle(color: Colors.redAccent, fontSize: 16)),
                  style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16)),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // ── ACTIVE PLAN SECTION ───────────────────────────────────────────────────
  Widget _buildActivePlanSection(BuildContext context, String uid) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .collection('workout_plans')
          .orderBy('createdAt', descending: true)
          .limit(1)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SizedBox(
            height: 80,
            child: Center(
                child: CircularProgressIndicator(
                    color: Color(0xFFFF5E00), strokeWidth: 2)),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: Colors.white.withOpacity(0.05),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: const Icon(Icons.fitness_center,
                    color: Colors.white24, size: 22),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                  Text('No Active Plan',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.w700,
                          fontSize: 15)),
                  SizedBox(height: 3),
                  Text('Generate your first plan to get started',
                      style: TextStyle(color: Colors.white38, fontSize: 12)),
                ]),
              ),
            ]),
          );
        }

        final doc        = snapshot.data!.docs.first;
        final plan       = doc.data() as Map<String, dynamic>;
        final planId     = doc.id;
        final goal       = plan['goal']        as String? ?? 'Workout Plan';
        final days       = plan['daysPerWeek'];
        final duration   = plan['duration']    as String? ?? '';
        final level      = plan['fitnessLevel'] as String? ?? '';
        final weeks      = plan['planWeeks'];
        final createdAt  = plan['createdAt']   as Timestamp?;
        final expiresAt  = plan['expiresAt']   as Timestamp?;

        String expiryLabel = '';
        bool   isExpired   = false;
        if (expiresAt != null) {
          final diff = expiresAt.toDate().difference(DateTime.now());
          if (diff.isNegative) {
            isExpired   = true;
            expiryLabel = 'Expired';
          } else if (diff.inDays == 0) {
            expiryLabel = 'Expires today';
          } else {
            expiryLabel = 'Expires in ${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'}';
          }
        } else if (createdAt != null) {
          expiryLabel = _formatDate(createdAt.toDate());
        }

        return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Container(
              width: 3, height: 18,
              decoration: BoxDecoration(
                color: const Color(0xFFFF5E00),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(width: 10),
            const Text('Active Workout Plan',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.w800)),
          ]),
          const SizedBox(height: 14),

          GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => WorkoutPlanScreen(
                  plan:   plan['plan'] as String? ?? '',
                  planId: planId,
                  uid:    uid,
                ),
              ),
            ),
            child: Container(
              padding: const EdgeInsets.all(18),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: isExpired
                      ? Colors.red.withOpacity(0.4)
                      : const Color(0xFFFF5E00).withOpacity(0.4),
                ),
              ),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                Row(children: [
                  Container(
                    padding: const EdgeInsets.all(9),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFF5E00).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(Icons.fitness_center,
                        color: Color(0xFFFF5E00), size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(goal,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 15),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis),
                  ),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: isExpired
                          ? Colors.red.withOpacity(0.15)
                          : const Color(0xFFB9FF2B).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      isExpired ? 'Expired' : 'Active',
                      style: TextStyle(
                          color: isExpired
                              ? Colors.redAccent
                              : const Color(0xFFB9FF2B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700),
                    ),
                  ),
                ]),

                const SizedBox(height: 14),
                const Divider(color: Colors.white10, height: 1),
                const SizedBox(height: 14),

                Row(children: [
                  _planStat(Icons.calendar_today_outlined, '${days ?? '?'} days/wk'),
                  const SizedBox(width: 20),
                  _planStat(Icons.timer_outlined, duration),
                  const SizedBox(width: 20),
                  _planStat(Icons.bar_chart, level),
                ]),

                const SizedBox(height: 12),

                if (expiryLabel.isNotEmpty)
                  Row(children: [
                    Icon(
                      isExpired ? Icons.warning_amber_rounded : Icons.access_time_outlined,
                      color: isExpired ? Colors.redAccent : Colors.white38,
                      size: 14,
                    ),
                    const SizedBox(width: 6),
                    Text(expiryLabel,
                        style: TextStyle(
                            color: isExpired ? Colors.redAccent : Colors.white38,
                            fontSize: 12)),
                    const Spacer(),
                    const Text('Tap to view →',
                        style: TextStyle(color: Color(0xFFFF5E00), fontSize: 12, fontWeight: FontWeight.w600)),
                  ]),
              ]),
            ),
          ),
        ]);
      },
    );
  }

  Widget _planStat(IconData icon, String label) {
    return Row(children: [
      Icon(icon, color: Colors.white38, size: 14),
      const SizedBox(width: 4),
      Text(label, style: const TextStyle(color: Colors.white54, fontSize: 12)),
    ]);
  }

  Widget _buildInfoSection(String title, String value, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Icon(icon, color: const Color(0xFFB9FF2B), size: 24),
        const SizedBox(width: 16),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: const TextStyle(color: Colors.grey, fontSize: 12)),
            const SizedBox(height: 2),
            Text(value,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold)),
          ]),
        ),
      ]),
    );
  }

  String _formatDate(DateTime date) {
    final now  = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Generated today';
    if (diff.inDays == 1) return 'Generated yesterday';
    if (diff.inDays < 7)  return 'Generated ${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}