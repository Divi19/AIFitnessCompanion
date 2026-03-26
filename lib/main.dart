import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'firebase_options.dart';
import 'core/constants.dart';
import 'features/auth/auth_screen.dart';
import 'features/nutrition/nutrition_assistant.dart';
import 'features/workout/injury_profile_screen.dart';
import 'features/workout/workout_builder_screen.dart';
import 'features/workout/workout_plan_screen.dart';
import 'features/profile/profile_screen.dart';
import 'screens/workout_tracker_screen.dart';
import 'screens/meal_tracker_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Limit Flutter image cache to prevent memory crashes
  PaintingBinding.instance.imageCache.maximumSize = 50;
  PaintingBinding.instance.imageCache.maximumSizeBytes = 30 << 20; // 30 MB

  AppConstants.assertKeysLoaded();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Fitness Companion',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D),
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFC5F135),
          secondary: Color(0xFF9B8FFF),
          surface: Color(0xFF1A1A2E),
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

// ── AUTH GATE ────────────────────────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: Color(0xFFC5F135)),
            ),
          );
        }
        if (!snapshot.hasData || snapshot.data == null) return const AuthScreen();

        final user = snapshot.data!;
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance
              .collection('users')
              .doc(user.uid)
              .snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(color: Color(0xFFC5F135)),
                ),
              );
            }
            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
            final isProfileCompleted = userData?['profile_completed'] == true;
            if (isProfileCompleted) return const RootNavigationScaffold();
            return const InjuryProfileScreen();
          },
        );
      },
    );
  }
}

// ── ROOT NAVIGATION SCAFFOLD ─────────────────────────────────────────────────
class RootNavigationScaffold extends StatefulWidget {
  const RootNavigationScaffold({super.key});

  @override
  State<RootNavigationScaffold> createState() =>
      _RootNavigationScaffoldState();
}

class _RootNavigationScaffoldState extends State<RootNavigationScaffold> {
  int _currentIndex = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
    backgroundColor: const Color(0xFF0D0D0D),
    body: Stack(
      children: [
        _buildTab(0, const HomeDashboardTab()),
        _buildTab(1, const NutritionAssistantScreen()),
        _buildTab(2, const WorkoutTrackerScreen()),
        _buildTab(3, const MealTrackerScreen()),
        _buildTab(4, const ProfileScreen()),
      ],
    ),
    bottomNavigationBar: _FloatingNav(
      currentIndex: _currentIndex,
      onTap: (i) => setState(() => _currentIndex = i),
    ),
  );
  }

  // ── CAMERA FIX ────────────────────────────────────────────────────────────
  // DO NOT use SizedBox.shrink() for index 2 — that destroys WorkoutTracker
  // and QuickPose reinitialises every time, crashing on emulators.
  // Instead keep ALL tabs alive with Visibility + maintainState: true.
  Widget _buildTab(int index, Widget child) {
    return Visibility(
      visible: _currentIndex == index,
      maintainState: true,
      maintainAnimation: true,
      maintainSize: true,
      child: IgnorePointer(ignoring: _currentIndex != index, child: child),
    );
  }
}

// ── FLOATING PILL NAVBAR ──────────────────────────────────────────────────────
class _FloatingNav extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const _FloatingNav({required this.currentIndex, required this.onTap});

  static const _items = [
    (icon: Icons.home_rounded,        label: 'Home'),
    (icon: Icons.chat_bubble_rounded, label: 'AI Coach'),
    (icon: Icons.camera_alt_rounded,  label: 'Pose'),
    (icon: Icons.restaurant_rounded,  label: 'Meals'),
    (icon: Icons.person_rounded,      label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: const Border(top: BorderSide(color: Colors.white10, width: 1)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 20,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: List.generate(_items.length, (i) {
              final item = _items[i];
              final isActive = i == currentIndex;

              return GestureDetector(
                onTap: () => onTap(i),
                behavior: HitTestBehavior.opaque,
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOutCubic,
                  padding: isActive
                      ? const EdgeInsets.symmetric(horizontal: 14, vertical: 8)
                      : const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                  decoration: BoxDecoration(
                    color: isActive ? const Color(0xFFC5F135) : Colors.transparent,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: isActive
                        ? [
                            BoxShadow(
                              color: const Color(0xFFC5F135).withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            )
                          ]
                        : [],
                  ),
                  child: isActive
                      ? Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(item.icon, color: const Color(0xFF1A1A1A), size: 17),
                            const SizedBox(width: 6),
                            Text(
                              item.label,
                              style: const TextStyle(
                                color: Color(0xFF1A1A1A),
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 0.1,
                              ),
                            ),
                          ],
                        )
                      : Icon(item.icon, color: Colors.white.withOpacity(0.4), size: 22),
                ),
              );
            }),
          ),
        ),
      ),
    );
  }
}

// ── HOME DASHBOARD TAB ───────────────────────────────────────────────────────
class HomeDashboardTab extends StatefulWidget {
  const HomeDashboardTab({super.key});

  @override
  State<HomeDashboardTab> createState() => _HomeDashboardTabState();
}

class _HomeDashboardTabState extends State<HomeDashboardTab> {
  Future<void> _updateFatigue(
    BuildContext context,
    String uid,
    int currentFatigue,
  ) async {
    int? newFatigue = await showDialog<int>(
      context: context,
      builder: (context) {
        int tempFatigue = currentFatigue;
        return StatefulBuilder(
          builder: (context, setState) {
            return AlertDialog(
              backgroundColor: const Color(0xFF1A1A2E),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              title: const Text('Set Fatigue Level', style: TextStyle(color: Colors.white)),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: tempFatigue.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    activeColor: const Color(0xFFC5F135),
                    inactiveColor: Colors.white24,
                    label: tempFatigue.toString(),
                    onChanged: (val) => setState(() => tempFatigue = val.toInt()),
                  ),
                  Text(
                    'Level: $tempFatigue/10',
                    style: const TextStyle(color: Colors.white70, fontSize: 16),
                  ),
                ],
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, tempFatigue),
                  child: const Text(
                    'Save',
                    style: TextStyle(color: Color(0xFFC5F135), fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (newFatigue != null && newFatigue != currentFatigue) {
      await FirebaseFirestore.instance
          .collection('users')
          .doc(uid)
          .update({'fatigue_score': newFatigue});
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return SafeArea(
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFC5F135)),
            );
          }

          final data    = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
          final name    = data['name']           ?? 'Athlete';
          final streak  = data['current_streak'] ?? 0;
          final fatigue = data['fatigue_score']  ?? 5;

          final bodyStats      = data['body_stats']      as Map<String, dynamic>? ?? {};
          final healthInsights = data['health_insights'] as Map<String, dynamic>? ?? {};

          final currentWeightStr = bodyStats['weight']?.toString() ?? '-- kg';
          final unit             = currentWeightStr.contains('lbs') ? 'lbs' : 'kg';
          final targetWeightRaw  = bodyStats['target_weight']?.toString();
          final targetWeightStr  = targetWeightRaw != null
              ? (targetWeightRaw.contains('kg') || targetWeightRaw.contains('lbs')
                  ? targetWeightRaw
                  : '$targetWeightRaw $unit')
              : currentWeightStr;

          final recommendedCalories = healthInsights['suggested_calories'] ?? 2000;
          final fatigueColor = fatigue > 7
              ? const Color(0xFFFF7B6B)
              : const Color(0xFFC5F135);

          final now   = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('meals')
                .doc(uid)
                .collection('logs')
                .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
                .snapshots(),
            builder: (context, mealSnapshot) {
              // FIX: was named totalCaloriesDouble in one branch but totalCal in the other
              double totalCal = 0;
              if (mealSnapshot.hasData) {
                for (var doc in mealSnapshot.data!.docs) {
                  final d = doc.data() as Map<String, dynamic>;
                  totalCal += (d['calories'] as num?)?.toDouble() ?? 0.0;
                }
              }
              final int currentIntake = totalCal.round();

              double calorieProgress =
                  currentIntake / (recommendedCalories > 0 ? recommendedCalories : 1);
              if (calorieProgress > 1.0) calorieProgress = 1.0;

              return SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(24, 12, 24, 120),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [

                    // ── Header ────────────────────────────────────────────
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        RichText(
                          text: const TextSpan(
                            style: TextStyle(
                              fontSize: 20,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              letterSpacing: -0.5,
                            ),
                            children: [
                              TextSpan(text: 'FIT'),
                              TextSpan(
                                text: 'SENSE',
                                style: TextStyle(color: Color(0xFFC5F135)),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(color: const Color(0xFFC5F135), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color: const Color(0xFFC5F135).withOpacity(0.3),
                                blurRadius: 12,
                                offset: const Offset(0, 4),
                              )
                            ],
                          ),
                          child: CircleAvatar(
                            radius: 20,
                            backgroundColor: const Color(0xFF1A1A2E),
                            child: Text(
                              name.toString().substring(0, 1).toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFFC5F135),
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ── Greeting ──────────────────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hi ${name.toString().split(' ').first}',
                          style: const TextStyle(
                            fontSize: 36,
                            fontWeight: FontWeight.w800,
                            color: Colors.white,
                            height: 1.1,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF9B8FFF).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text(
                                'Day Streak ',
                                style: TextStyle(
                                  color: Color(0xFF9B8FFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                              Text(
                                '$streak 🔥',
                                style: const TextStyle(
                                  color: Color(0xFF9B8FFF),
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Active Workout Plan ───────────────────────────────
                    _buildActiveWorkoutCard(context, uid),
                    const SizedBox(height: 24),

                    // ── Weight & Calories ─────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: Container(
                            height: 140,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A1A2E),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text(
                                  'WEIGHT',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF6B6B8A),
                                    letterSpacing: 1.5,
                                  ),
                                ),
                                Text(
                                  currentWeightStr,
                                  style: const TextStyle(
                                    fontSize: 32,
                                    fontWeight: FontWeight.w700,
                                    color: Colors.white,
                                    height: 1,
                                  ),
                                ),
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Container(
                                      height: 8,
                                      width: double.infinity,
                                      decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius: BorderRadius.circular(4),
                                      ),
                                      child: FractionallySizedBox(
                                        alignment: Alignment.centerLeft,
                                        widthFactor: 0.6,
                                        child: Container(
                                          decoration: BoxDecoration(
                                            color: const Color(0xFFC5F135),
                                            borderRadius: BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                    ),
                                    const SizedBox(height: 6),
                                    Text(
                                      'Goal: $targetWeightStr',
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.w500,
                                        color: Color(0xFFADADC4),
                                      ),
                                    ),
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 16),
                        Expanded(
                          child: Container(
                            height: 140,
                            padding: const EdgeInsets.all(20),
                            decoration: BoxDecoration(
                              color: const Color(0xFF9B8FFF).withOpacity(0.15),
                              borderRadius: BorderRadius.circular(24),
                            ),
                            child: Column(
                              children: [
                                const Align(
                                  alignment: Alignment.centerLeft,
                                  child: Text(
                                    'CALORIES',
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF9B8FFF),
                                      letterSpacing: 1.5,
                                    ),
                                  ),
                                ),
                                const Spacer(),
                                SizedBox(
                                  height: 64,
                                  width: 64,
                                  child: Stack(
                                    fit: StackFit.expand,
                                    children: [
                                      CircularProgressIndicator(
                                        value: calorieProgress,
                                        strokeWidth: 6,
                                        backgroundColor: Colors.white10,
                                        color: const Color(0xFFC5F135),
                                      ),
                                      Center(
                                        child: Text(
                                          '${(calorieProgress * 100).toInt()}%',
                                          style: const TextStyle(
                                            fontSize: 14,
                                            fontWeight: FontWeight.w700,
                                            color: Color(0xFF9B8FFF),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const Spacer(),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Vitals strip ──────────────────────────────────────
                    Container(
                      padding: const EdgeInsets.all(20),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(24),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          _buildVitalMini(
                            icon: Icons.local_fire_department,
                            color: const Color(0xFFFF7B6B),
                            value: '$streak',
                            label: 'Streak',
                          ),
                          Container(width: 1, height: 40, color: Colors.white10),
                          // FIX: GestureDetector now has its child restored
                          GestureDetector(
                            onTap: () => _updateFatigue(
                              context,
                              uid,
                              fatigue is int ? fatigue : (fatigue as num).toInt(),
                            ),
                            child: _buildVitalMini(
                              icon: Icons.battery_charging_full,
                              color: fatigueColor,
                              value: '$fatigue',
                              label: 'Fatigue',
                            ),
                          ),
                          Container(width: 1, height: 40, color: Colors.white10),
                          _buildVitalMini(
                            icon: Icons.restaurant,
                            color: const Color(0xFF9B8FFF),
                            value: '$currentIntake',
                            label: 'kcal',
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // ── Generate Routine ──────────────────────────────────
                    GestureDetector(
                      onTap: () => Navigator.push(
                        context,
                        MaterialPageRoute(builder: (_) => const WorkoutBuilderScreen()),
                      ),
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC5F135),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFC5F135).withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt, color: Color(0xFF2D4A00), size: 24),
                            SizedBox(width: 8),
                            Text(
                              'Generate Custom Routine',
                              style: TextStyle(
                                color: Color(0xFF2D4A00),
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              );
            },
          );
        },
      ),
    );
  }

  Widget _buildVitalMini({
    required IconData icon,
    required Color color,
    required String value,
    required String label,
  }) {
    return Column(
      children: [
        Icon(icon, color: color, size: 20),
        const SizedBox(height: 6),
        Text(
          value,
          style: const TextStyle(
            fontSize: 16,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        Text(
          label,
          style: const TextStyle(
            fontSize: 12,
            fontWeight: FontWeight.w500,
            color: Color(0xFF6B6B8A),
          ),
        ),
      ],
    );
  }

  Widget _buildActiveWorkoutCard(BuildContext context, String uid) {
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
          return Container(
            height: 170,
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A2E),
              borderRadius: BorderRadius.circular(24),
            ),
            child: const Center(
              child: CircularProgressIndicator(color: Color(0xFFC5F135), strokeWidth: 2),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return GestureDetector(
            onTap: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const WorkoutBuilderScreen()),
            ),
            child: Container(
              height: 170,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A2E),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.fitness_center, color: Colors.white24, size: 32),
                  ),
                  const SizedBox(width: 20),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          'No Active Plan',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          ),
                        ),
                        SizedBox(height: 6),
                        Text(
                          'Tap to generate your first workout',
                          style: TextStyle(color: Color(0xFF6B6B8A), fontSize: 13),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        }

        final doc       = snapshot.data!.docs.first;
        final plan      = doc.data() as Map<String, dynamic>;
        final planId    = doc.id;
        final goal      = plan['goal']         as String? ?? 'Workout Plan';
        final duration  = plan['duration']     as String? ?? '';
        final imageUrl  = plan['imageUrl']     as String? ?? '';
        final expiresAt = plan['expiresAt']    as Timestamp?;

        bool   isExpired   = false;
        String expiryLabel = '';
        if (expiresAt != null) {
          final diff = expiresAt.toDate().difference(DateTime.now());
          isExpired   = diff.isNegative;
          expiryLabel = isExpired
              ? 'Expired'
              : 'Expires in ${diff.inDays} ${diff.inDays == 1 ? 'day' : 'days'}';
        }

        return FutureBuilder<DocumentSnapshot>(
          future: FirebaseFirestore.instance
              .collection('users')
              .doc(uid)
              .collection('workout_plans')
              .doc(planId)
              .get(),
          builder: (context, progSnap) {
            double progress = 0.0;
            if (progSnap.hasData && progSnap.data!.exists) {
              final progData  = progSnap.data!.data() as Map<String, dynamic>? ?? {};
              final completed = progData['progress'] as Map<String, dynamic>? ?? {};
              final done  = completed.values.where((v) => v == true).length;
              final total = completed.length;
              if (total > 0) progress = done / total;
            }

            return GestureDetector(
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
                height: 170,
                clipBehavior: Clip.hardEdge,
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A2E),
                  borderRadius: BorderRadius.circular(24),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.2),
                      blurRadius: 24,
                      offset: const Offset(0, 4),
                    )
                  ],
                ),
                child: Stack(
                  children: [
                    // Background image or placeholder
                    if (imageUrl.isNotEmpty)
                      Positioned(
                        right: -30,
                        bottom: -20,
                        height: 220,
                        width: 200,
                        child: ClipRRect(
                          borderRadius: const BorderRadius.only(topLeft: Radius.circular(30)),
                          child: CachedNetworkImage(
                            imageUrl: imageUrl,
                            fit: BoxFit.cover,
                            alignment: Alignment.centerLeft,
                            placeholder: (context, url) =>
                                Container(color: const Color(0xFF2A2A2A)),
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF1A1A2A),
                              child: const Icon(Icons.fitness_center,
                                  color: Color(0xFF3A3A3A), size: 60),
                            ),
                            memCacheHeight: 300,
                            memCacheWidth:  300,
                          ),
                        ),
                      )
                    else
                      Positioned(
                        right: -30,
                        bottom: -20,
                        height: 220,
                        width: 200,
                        child: Container(
                          decoration: const BoxDecoration(
                            color: Color(0xFF2A2A2A),
                            borderRadius: BorderRadius.only(topLeft: Radius.circular(30)),
                          ),
                          child: const Icon(Icons.fitness_center,
                              color: Color(0xFF3A3A3A), size: 60),
                        ),
                      ),

                    // Gradient overlay
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              const Color(0xFF1A1A2E),
                              const Color(0xFF1A1A2E).withOpacity(0.7),
                              Colors.transparent,
                            ],
                            begin: Alignment.centerLeft,
                            end: Alignment.centerRight,
                          ),
                        ),
                      ),
                    ),

                    // Active/Expired badge
                    Positioned(
                      bottom: 16,
                      right: 16,
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                        decoration: BoxDecoration(
                          color: isExpired
                              ? const Color(0xFFFF7B6B)
                              : const Color(0xFFC5F135),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: isExpired
                                  ? const Color(0xFFFF7B6B).withOpacity(0.3)
                                  : const Color(0xFFC5F135).withOpacity(0.3),
                              blurRadius: 12,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        child: Text(
                          isExpired ? 'EXPIRED' : 'ACTIVE',
                          style: TextStyle(
                            color: isExpired ? Colors.white : const Color(0xFF2D4A00),
                            fontSize: 12,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                    ),

                    // Content
                    Padding(
                      padding: const EdgeInsets.all(24),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          SizedBox(
                            width: MediaQuery.of(context).size.width * 0.5,
                            child: Text(
                              goal,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 22,
                                fontWeight: FontWeight.w800,
                                color: Colors.white,
                                height: 1.1,
                              ),
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            duration.isNotEmpty ? 'Duration · $duration' : expiryLabel,
                            style: const TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: Color(0xFF9B8FFF),
                            ),
                          ),
                          const SizedBox(height: 20),
                          Row(
                            children: [
                              SizedBox(
                                width: 24,
                                height: 24,
                                child: CircularProgressIndicator(
                                  value: progress,
                                  strokeWidth: 3,
                                  backgroundColor: Colors.white10,
                                  color: const Color(0xFFC5F135),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Text(
                                '${(progress * 100).toInt()}% Done',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
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
        );
      },
    );
  }
}