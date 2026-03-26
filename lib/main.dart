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
              child: CircularProgressIndicator(color: Color(0xFFB9FF2B)),
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
                  child: CircularProgressIndicator(color: Color(0xFFB9FF2B)),
                ),
              );
            }

            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
            final isProfileCompleted = userData?['profile_completed'] == true;

            if (isProfileCompleted) {
              return const RootNavigationScaffold();
            }

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
      // Stack so the floating navbar sits on top of content
      body: Stack(
        children: [
          // ── All tabs kept alive, just hidden ──────────────────────────
          _buildTab(0, const HomeDashboardTab()),
          _buildTab(1, const NutritionAssistantScreen()),
          _buildTab(2, const WorkoutTrackerScreen()),
          _buildTab(3, const MealTrackerScreen()),
          _buildTab(4, const ProfileScreen()),

          // ── Floating bottom nav overlaid at the bottom ─────────────────
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: _FloatingNav(
              currentIndex: _currentIndex,
              onTap: (i) => setState(() => _currentIndex = i),
            ),
          ),
        ],
      ),
      bottomNavigationBar: Container(
        decoration: const BoxDecoration(
          border: Border(top: BorderSide(color: Colors.white10, width: 1)),
        ),
        child: BottomNavigationBar(
          currentIndex: _currentIndex,
          onTap: (index) => setState(() => _currentIndex = index),
          backgroundColor: const Color(0xFF0D0D0D),
          type: BottomNavigationBarType.fixed,
          selectedItemColor: const Color(0xFFB9FF2B),
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(
              icon: Icon(Icons.home_filled),
              label: 'Home',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.chat_bubble),
              label: 'Assistant',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.camera_alt),
              label: 'Pose',
            ),
            BottomNavigationBarItem(
              icon: Icon(Icons.restaurant),
              label: 'Meals',
            ),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
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
      maintainState: true,      // keeps state alive — camera never reinitialises
      maintainAnimation: true,
      maintainSize: true,
      child: IgnorePointer(ignoring: _currentIndex != index, child: child),
    );
  }
}

// ── FLOATING PILL NAVBAR ──────────────────────────────────────────────────────
// Sits 20px above the bottom edge, floating over content.
// Active tab → volt green pill with icon + label.
// Inactive   → ghost icon only.
class _FloatingNav extends StatelessWidget {
  final int currentIndex;
  final void Function(int) onTap;

  const _FloatingNav({required this.currentIndex, required this.onTap});

  static const _items = [
    (icon: Icons.home_rounded,      label: 'Home'),
    (icon: Icons.chat_bubble_rounded, label: 'AI Coach'),
    (icon: Icons.camera_alt_rounded, label: 'Pose'),
    (icon: Icons.restaurant_rounded, label: 'Meals'),
    (icon: Icons.person_rounded,     label: 'Profile'),
  ];

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        // Frosted dark glass look
        color: const Color(0xFF1A1A1A).withOpacity(0.95),
        borderRadius: BorderRadius.circular(32),
        border: Border.all(color: Colors.white.withOpacity(0.08), width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 30,
            offset: const Offset(0, 8),
          ),
          BoxShadow(
            color: const Color(0xFFC5F135).withOpacity(0.05),
            blurRadius: 20,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: List.generate(_items.length, (i) {
          final item     = _items[i];
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
                color: isActive
                    ? const Color(0xFFC5F135)
                    : Colors.transparent,
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
                  // Active: icon + label
                  ? Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(item.icon,
                            color: const Color(0xFF1A1A1A), size: 17),
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
                  // Inactive: icon only
                  : Icon(item.icon,
                      color: Colors.white.withOpacity(0.4), size: 22),
            ),
          );
        }),
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
              backgroundColor: const Color(0xFF1A1A1A),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              title: const Text(
                'Set Fatigue Level',
                style: TextStyle(color: Colors.white),
              ),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Slider(
                    value: tempFatigue.toDouble(),
                    min: 1,
                    max: 10,
                    divisions: 9,
                    activeColor: const Color(0xFFB9FF2B),
                    inactiveColor: Colors.white24,
                    label: tempFatigue.toString(),
                    onChanged: (val) {
                      setState(() {
                        tempFatigue = val.toInt();
                      });
                    },
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
                  child: const Text(
                    'Cancel',
                    style: TextStyle(color: Colors.grey),
                  ),
                ),
                TextButton(
                  onPressed: () => Navigator.pop(context, tempFatigue),
                  child: const Text(
                    'Save',
                    style: TextStyle(
                      color: Color(0xFFB9FF2B),
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            );
          },
        );
      },
    );
    if (newFatigue != null && newFatigue != currentFatigue) {
      await FirebaseFirestore.instance.collection('users').doc(uid).update({
        'fatigue_score': newFatigue,
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return SafeArea(
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .snapshots(),
        builder: (context, userSnapshot) {
          if (!userSnapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Color(0xFFB9FF2B)),
            );
          }

          final data = userSnapshot.data!.data() as Map<String, dynamic>? ?? {};
          final name = data['name'] ?? 'Athlete';
          final streak = data['current_streak'] ?? 0;
          final fatigue = data['fatigue_score'] ?? 5;

          final bodyStats = data['body_stats'] as Map<String, dynamic>? ?? {};
          final healthInsights =
              data['health_insights'] as Map<String, dynamic>? ?? {};

          final currentWeightStr =
              bodyStats['weight']?.toString() ?? '-- kg';
          final unit =
              currentWeightStr.contains('lbs') ? 'lbs' : 'kg';
          final targetWeightRaw =
              bodyStats['target_weight']?.toString();
          final targetWeightStr = targetWeightRaw != null
              ? (targetWeightRaw.contains('kg') ||
                        targetWeightRaw.contains('lbs')
                    ? targetWeightRaw
                    : '$targetWeightRaw $unit')
              : currentWeightStr;

          final recommendedCalories =
              healthInsights['suggested_calories'] ?? 2000;
          final fatigueColor = fatigue > 7
              ? const Color(0xFFFF7B6B)
              : const Color(0xFFC5F135);

          final now = DateTime.now();
          final today = DateTime(now.year, now.month, now.day);

          return StreamBuilder<QuerySnapshot>(
            stream: FirebaseFirestore.instance
                .collection('meals')
                .doc(uid)
                .collection('logs')
                .where(
                  'timestamp',
                  isGreaterThanOrEqualTo: Timestamp.fromDate(today),
                )
                .snapshots(),
            builder: (context, mealSnapshot) {
              double totalCal = 0;
              if (mealSnapshot.hasData) {
                for (var doc in mealSnapshot.data!.docs) {
                  final d = doc.data() as Map<String, dynamic>;
                  totalCal += (d['calories'] as num?)?.toDouble() ?? 0.0;
                }
              }
              final int currentIntake = totalCaloriesDouble.round();

              double calorieProgress =
                  currentIntake /
                  (recommendedCalories > 0 ? recommendedCalories : 1);
              if (calorieProgress > 1.0) calorieProgress = 1.0;

              // Extra bottom padding so content clears the floating navbar
              return SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 24,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // ── Greeting ──────────────────────────────────────────
                    Center(
                      child: Column(
                        children: [
                          const Text(
                            'welcome back,',
                            style: TextStyle(
                              fontSize: 18,
                              color: Color(0xFFB9FF2B),
                              fontStyle: FontStyle.italic,
                              fontWeight: FontWeight.w600,
                              letterSpacing: 1.2,
                            ),
                          ),
                          Text(
                            name.toString().split(' ').first,
                            style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Weight Goal Card ──────────────────────────────────
                    Container(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                        horizontal: 16,
                      ),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: const Color(0xFFB9FF2B).withOpacity(0.5),
                          width: 2,
                        ),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFB9FF2B).withOpacity(0.15),
                            blurRadius: 30,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: Column(
                        children: [
                          Text(
                            targetWeightStr,
                            style: const TextStyle(
                              fontSize: 42,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFFB9FF2B),
                              height: 1,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            'current weight: $currentWeightStr',
                            style: const TextStyle(
                              fontSize: 16,
                              color: Colors.white70,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Active Workout Plan (kevin branch) ────────────────
                    // Shows real Firestore data — replaces the old hardcoded
                    // checklist that referenced undefined step1/step2 vars.
                    const Text(
                      "Active Workout Plan:",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB9FF2B),
                      ),
                    ),
                    const SizedBox(height: 12),
                    _buildActiveWorkoutCard(context, uid),

                    const SizedBox(height: 32),

                    // ── Generate Routine Button ───────────────────────────
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [
                            const Color(0xFFFF5E00),
                            const Color(0xFFFF5E00).withOpacity(0.8),
                          ],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: const Color(0xFFFF5E00).withOpacity(0.3),
                            blurRadius: 20,
                            offset: const Offset(0, 8),
                          ),
                        ],
                      ),
                      child: Material(
                        color: Colors.transparent,
                        child: InkWell(
                          borderRadius: BorderRadius.circular(20),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const WorkoutBuilderScreen(),
                            ),
                          ),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: 24,
                              horizontal: 24,
                            ),
                            child: Column(
                              children: [
                                Icon(Icons.bolt, size: 36, color: Colors.white),
                                SizedBox(height: 12),
                                Text(
                                  'Generate Routine',
                                  style: TextStyle(
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold,
                                    color: Colors.white,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Calories Progress Bar ─────────────────────────────
                    const Text(
                      "Calories Intake:",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFFB9FF2B),
                      ),
                    ),
                    const SizedBox(height: 16),

                    ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: LinearProgressIndicator(
                        value: calorieProgress,
                        minHeight: 24,
                        backgroundColor: const Color(
                          0xFFFF5E00,
                        ).withOpacity(0.15),
                        valueColor: const AlwaysStoppedAnimation<Color>(
                          Color(0xFFFF5E00),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          'Intake: $currentIntake kcal',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          'Goal: $recommendedCalories kcal',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),

                    const SizedBox(height: 16),

                    // ── Scan Meal Button ──────────────────────────────────
                    ElevatedButton.icon(
                      onPressed: () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => const MealTrackerScreen(),
                        ),
                      ),
                      icon: const Icon(Icons.camera_alt, size: 20),
                      label: const Text(
                        'Scan a Meal',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1A1A1A),
                        foregroundColor: const Color(0xFFFF5E00),
                        side: BorderSide(
                          color: const Color(0xFFFF5E00).withOpacity(0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                    ),

                    const SizedBox(height: 40),
                    const Divider(color: Colors.white10),
                    const SizedBox(height: 24),

                    // ── Vitals Row ────────────────────────────────────────
                    Row(
                      children: [
                        Expanded(
                          child: _buildVitalCard(
                            title: 'Day Streak',
                            value: '$streak',
                            icon: Icons.local_fire_department,
                            bgColor: const Color(0xFFFF5E00).withOpacity(0.15),
                            textColor: const Color(0xFFFF5E00),
                            borderColor: const Color(
                              0xFFFF5E00,
                            ).withOpacity(0.5),
                          ),
                        ),
                        Container(
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                                color: const Color(0xFFC5F135), width: 2),
                            boxShadow: [
                              BoxShadow(
                                color:
                                    const Color(0xFFC5F135).withOpacity(0.3),
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
                                  fontSize: 16),
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 32),

                    // ── Greeting ──────────────────────────────────────
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Hi ${name.toString().split(' ').first}',
                          style: const TextStyle(
                              fontSize: 36,
                              fontWeight: FontWeight.w800,
                              color: Colors.white,
                              height: 1.1),
                        ),
                        const SizedBox(height: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 12, vertical: 6),
                          decoration: BoxDecoration(
                            color:
                                const Color(0xFF9B8FFF).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Text('Day Streak ',
                                  style: TextStyle(
                                      color: Color(0xFF9B8FFF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700)),
                              Text('$streak 🔥',
                                  style: const TextStyle(
                                      color: Color(0xFF9B8FFF),
                                      fontSize: 12,
                                      fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),

                    // ── Active Workout Plan ───────────────────────────
                    _buildActiveWorkoutCard(context, uid),
                    const SizedBox(height: 24),

                    // ── Weight & Calories ─────────────────────────────
                    Row(children: [
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
                            mainAxisAlignment:
                                MainAxisAlignment.spaceBetween,
                            children: [
                              const Text('WEIGHT',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF6B6B8A),
                                      letterSpacing: 1.5)),
                              Text(currentWeightStr,
                                  style: const TextStyle(
                                      fontSize: 32,
                                      fontWeight: FontWeight.w700,
                                      color: Colors.white,
                                      height: 1)),
                              Column(
                                crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                children: [
                                  Container(
                                    height: 8,
                                    width: double.infinity,
                                    decoration: BoxDecoration(
                                        color: Colors.white10,
                                        borderRadius:
                                            BorderRadius.circular(4)),
                                    child: FractionallySizedBox(
                                      alignment: Alignment.centerLeft,
                                      widthFactor: 0.6,
                                      child: Container(
                                        decoration: BoxDecoration(
                                            color:
                                                const Color(0xFFC5F135),
                                            borderRadius:
                                                BorderRadius.circular(4)),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text('Goal: $targetWeightStr',
                                      style: const TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.w500,
                                          color: Color(0xFFADADC4))),
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
                            color:
                                const Color(0xFF9B8FFF).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(24),
                          ),
                          child: Column(children: [
                            const Align(
                              alignment: Alignment.centerLeft,
                              child: Text('CALORIES',
                                  style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w600,
                                      color: Color(0xFF9B8FFF),
                                      letterSpacing: 1.5)),
                            ),
                            const Spacer(),
                            SizedBox(
                              height: 64, width: 64,
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
                                          color: Color(0xFF9B8FFF)),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const Spacer(),
                          ]),
                        ),
                      ),
                    ]),

                    const SizedBox(height: 24),

                    // ── Vitals strip ──────────────────────────────────
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
                              label: 'Streak'),
                          Container(
                              width: 1, height: 40, color: Colors.white10),
                          GestureDetector(
                            onTap: () => _updateFatigue(
                              context,
                              uid,
                              fatigue is int
                                  ? fatigue
                                  : (fatigue as num).toInt(),
                            ),
                          ),
                          Container(
                              width: 1, height: 40, color: Colors.white10),
                          _buildVitalMini(
                              icon: Icons.restaurant,
                              color: const Color(0xFF9B8FFF),
                              value: '$currentIntake',
                              label: 'kcal'),
                        ],
                      ),
                    ),

                    const SizedBox(height: 32),

                    // ── Generate Routine ──────────────────────────────
                    GestureDetector(
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  const WorkoutBuilderScreen())),
                      child: Container(
                        height: 60,
                        decoration: BoxDecoration(
                          color: const Color(0xFFC5F135),
                          borderRadius: BorderRadius.circular(20),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFC5F135)
                                  .withOpacity(0.3),
                              blurRadius: 16,
                              offset: const Offset(0, 4),
                            )
                          ],
                        ),
                        alignment: Alignment.center,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.bolt,
                                color: Color(0xFF2D4A00), size: 24),
                            SizedBox(width: 8),
                            Text('Generate Custom Routine',
                                style: TextStyle(
                                    color: Color(0xFF2D4A00),
                                    fontSize: 16,
                                    fontWeight: FontWeight.w800)),
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
    return Column(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 6),
      Text(value,
          style: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: Colors.white)),
      Text(label,
          style: const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w500,
              color: Color(0xFF6B6B8A))),
    ]);
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
                borderRadius: BorderRadius.circular(24)),
            child: const Center(
              child: CircularProgressIndicator(
                color: Color(0xFFFF5E00),
                strokeWidth: 2,
              ),
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
                    padding: const EdgeInsets.all(10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.fitness_center,
                      color: Colors.white24,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 14),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'No Active Plan',
                          style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 15,
                          ),
                        ),
                        SizedBox(height: 3),
                        Text(
                          'Tap to generate your first workout',
                          style: TextStyle(color: Colors.white38, fontSize: 12),
                        ),
                      ],
                    ),
                  ),
                  const Icon(
                    Icons.arrow_forward_ios,
                    color: Colors.white24,
                    size: 14,
                  ),
                ],
              ),
            ),
          );
        }

        final doc = snapshot.data!.docs.first;
        final plan = doc.data() as Map<String, dynamic>;
        final planId = doc.id;
        final goal = plan['goal'] as String? ?? 'Workout Plan';
        final days = plan['daysPerWeek'];
        final duration = plan['duration'] as String? ?? '';
        final level = plan['fitnessLevel'] as String? ?? '';
        final expiresAt = plan['expiresAt'] as Timestamp?;

        bool isExpired = false;
        String expiryLabel = '';
        if (expiresAt != null) {
          final diff = expiresAt.toDate().difference(DateTime.now());
          isExpired = diff.isNegative;
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
              final progData =
                  progSnap.data!.data() as Map<String, dynamic>? ?? {};
              final completed =
                  progData['progress'] as Map<String, dynamic>? ?? {};
              final done = completed.values.where((v) => v == true).length;
              final total = completed.length;
              if (total > 0) progress = done / total;
            }

            return GestureDetector(
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (_) => WorkoutPlanScreen(
                    plan: plan['plan'] as String? ?? '',
                    planId: planId,
                    uid: uid,
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
                        offset: const Offset(0, 4))
                  ],
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Goal + active/expired badge
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(9),
                          decoration: BoxDecoration(
                            color: const Color(0xFFFF5E00).withOpacity(0.15),
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: const Icon(
                            Icons.fitness_center,
                            color: Color(0xFFFF5E00),
                            size: 20,
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            goal,
                            style: const TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.w800,
                              fontSize: 15,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
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
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 14),
                    const Divider(color: Colors.white10, height: 1),
                    const SizedBox(height: 14),
                    // Progress bar
                    Row(
                      children: [
                        Expanded(
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(4),
                            child: LinearProgressIndicator(
                              value: progress,
                              backgroundColor: Colors.white10,
                              valueColor: const AlwaysStoppedAnimation(
                                Color(0xFFFF5E00),
                              ),
                              minHeight: 6,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          '${(progress * 100).round()}%',
                          style: const TextStyle(
                            color: Color(0xFFFF5E00),
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 12),
                    // Stats row
                    Row(
                      children: [
                        Flexible(
                          child: _miniStat(
                            Icons.calendar_today_outlined,
                            '${days ?? '?'} days/wk',
                          ),
                        ),
                        const SizedBox(width: 12),
                        Flexible(
                          child: _miniStat(Icons.timer_outlined, duration),
                        ),
                        const SizedBox(width: 12),
                        Flexible(child: _miniStat(Icons.bar_chart, level)),
                        const SizedBox(width: 8),
                        if (expiryLabel.isNotEmpty)
                          Flexible(
                            child: Text(
                              expiryLabel,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: isExpired
                                    ? Colors.redAccent
                                    : Colors.white38,
                                fontSize: 11,
                              ),
                            ),
                          ),
                      ],
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

  Widget _miniStat(IconData icon, String label) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white38, size: 12),
        const SizedBox(width: 4),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(color: Colors.white54, fontSize: 11),
          ),
        ),
      ],
    );
  }

  Widget _buildVitalCard({
    required String title,
    required String value,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    Color? borderColor,
    VoidCallback? onTap,
    String? subtitle,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: bgColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: borderColor ?? Colors.transparent),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: textColor, size: 24),
            const SizedBox(height: 12),
            Text(
              value,
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.w800,
                color: textColor,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              title,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: textColor.withOpacity(0.8),
              ),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(
                subtitle,
                style: TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w500,
                  color: textColor.withOpacity(0.6),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
