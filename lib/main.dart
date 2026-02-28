import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'core/constants.dart';
import 'features/auth/auth_screen.dart';
import 'features/nutrition/nutrition_assistant.dart';
import 'screens/workout_tracker_screen.dart'; 
import 'features/workout/injury_profile_screen.dart'; 
import 'features/workout/workout_builder_screen.dart';
import 'features/profile/profile_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  AppConstants.assertKeysLoaded();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
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
          primary: Color(0xFFB9FF2B), // Volt Lime Green
          secondary: Color(0xFFFF5E00), // Electric Orange
          surface: Color(0xFF1A1A1A), 
        ),
        useMaterial3: true,
      ),
      home: const AuthGate(),
    );
  }
}

// ── AUTH GATE (THE INTERCEPTOR) ─────────────────────────────────────────────
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFB9FF2B))));
        }

        if (!snapshot.hasData || snapshot.data == null) {
          return const AuthScreen();
        }

        final user = snapshot.data!;

        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(body: Center(child: CircularProgressIndicator(color: Color(0xFFB9FF2B))));
            }

            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
            final isProfileCompleted = userData?['profile_completed'] == true;

            if (isProfileCompleted) {
              return const RootNavigationScaffold(); // Routes to the new Tabbed layout
            }

            return const InjuryProfileScreen();
          },
        );
      },
    );
  }
}

// ── ROOT NAVIGATION SCAFFOLD (Bottom Tabs) ──────────────────────────────────
class RootNavigationScaffold extends StatefulWidget {
  const RootNavigationScaffold({super.key});

  @override
  State<RootNavigationScaffold> createState() => _RootNavigationScaffoldState();
}

class _RootNavigationScaffoldState extends State<RootNavigationScaffold> {
  int _currentIndex = 0;

  final List<Widget> _screens = [
    const HomeDashboardTab(),
    const NutritionAssistantScreen(),
    const WorkoutTrackerScreen(),
    const ProfileScreen(),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _currentIndex,
        children: _screens,
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
          selectedItemColor: const Color(0xFFB9FF2B), // Volt Green active tab
          unselectedItemColor: Colors.grey,
          showUnselectedLabels: true,
          items: const [
            BottomNavigationBarItem(icon: Icon(Icons.home_filled), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.chat_bubble), label: 'Assistant'),
            BottomNavigationBarItem(icon: Icon(Icons.camera_alt), label: 'Tracker'),
            BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile'),
          ],
        ),
      ),
    );
  }
}

// ── HOME DASHBOARD TAB (Upgraded to StatefulWidget) ─────────────────────────
class HomeDashboardTab extends StatefulWidget {
  const HomeDashboardTab({super.key});

  @override
  State<HomeDashboardTab> createState() => _HomeDashboardTabState();
}

class _HomeDashboardTabState extends State<HomeDashboardTab> {
  // State variables moved to the class level so the analyzer knows they can change!
  bool step1 = false;
  bool step2 = false;

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser!.uid;

    return SafeArea(
      child: StreamBuilder<DocumentSnapshot>(
        stream: FirebaseFirestore.instance.collection('users').doc(uid).snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator(color: Color(0xFFB9FF2B)));
          }

          final data = snapshot.data!.data() as Map<String, dynamic>? ?? {};
          final name = data['name'] ?? 'Athlete';
          final streak = data['current_streak'] ?? 0;
          final fatigue = data['fatigue_score'] ?? 5;

          // Extract Data
          final bodyStats = data['body_stats'] as Map<String, dynamic>? ?? {};
          final healthInsights = data['health_insights'] as Map<String, dynamic>? ?? {};
          
          final currentWeightStr = bodyStats['weight'] ?? '-- kg';
          final unit = currentWeightStr.toString().contains('lbs') ? 'lbs' : 'kg';
          
          final targetWeightRaw = bodyStats['target_weight'];
          final targetWeightStr = targetWeightRaw != null ? '$targetWeightRaw$unit' : currentWeightStr;

          final recommendedCalories = healthInsights['suggested_calories'] ?? 2000;
          final int currentIntake = 1200; 
          
          double calorieProgress = currentIntake / (recommendedCalories > 0 ? recommendedCalories : 1);
          if (calorieProgress > 1.0) calorieProgress = 1.0;

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // 1. Personalized Greeting
                Center(
                  child: Column(
                    children: [
                      Text(
                        'welcome back,',
                        style: TextStyle(
                          fontSize: 18, 
                          color: const Color(0xFFB9FF2B).withOpacity(0.8),
                          fontStyle: FontStyle.italic,
                          fontWeight: FontWeight.w600,
                          letterSpacing: 1.2,
                        ),
                      ),
                      Text(
                        name.toString().split(' ').first, 
                        style: const TextStyle(fontSize: 36, fontWeight: FontWeight.w900, color: Colors.white),
                      ),
                    ],
                  ),
                ),
                
                const SizedBox(height: 32),

                // 2. Weight Goal Card
                Container(
                  padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 16),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A), 
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: const Color(0xFFB9FF2B).withOpacity(0.3), width: 2), 
                  ),
                  child: Column(
                    children: [
                      Text(
                        targetWeightStr,
                        style: const TextStyle(fontSize: 42, fontWeight: FontWeight.bold, color: Colors.white, height: 1),
                      ),
                      const SizedBox(height: 8),
                      Text(
                        'current weight: $currentWeightStr',
                        style: const TextStyle(fontSize: 16, color: Colors.grey, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // 3. Today's Exercise Checklist
                const Text(
                  "Today's Exercise:",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 12),
                
                Container(
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A1A1A),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: Colors.white10),
                  ),
                  child: Column(
                    children: [
                      CheckboxListTile(
                        title: Text(
                          'hit 10k steps', 
                          style: TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.bold,
                            decoration: step1 ? TextDecoration.lineThrough : null,
                            decorationColor: Colors.grey,
                          )
                        ),
                        value: step1,
                        onChanged: (val) => setState(() => step1 = val!),
                        activeColor: const Color(0xFFFF5E00), 
                        checkColor: Colors.white,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                      const Divider(height: 1, color: Colors.white10),
                      CheckboxListTile(
                        title: Text(
                          'HIIT workout', 
                          style: TextStyle(
                            color: Colors.white, 
                            fontWeight: FontWeight.bold,
                            decoration: step2 ? TextDecoration.lineThrough : null,
                            decorationColor: Colors.grey,
                          )
                        ),
                        value: step2,
                        onChanged: (val) => setState(() => step2 = val!),
                        activeColor: const Color(0xFFFF5E00),
                        checkColor: Colors.white,
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 32),

                // 4. Calories Progress Bar
                const Text(
                  "Calories Intake:",
                  style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Colors.white),
                ),
                const SizedBox(height: 16),
                
                ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LinearProgressIndicator(
                    value: calorieProgress,
                    minHeight: 24,
                    backgroundColor: const Color(0xFF1A1A1A),
                    valueColor: const AlwaysStoppedAnimation<Color>(Color(0xFFB9FF2B)), 
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Intake: $currentIntake kcal', style: const TextStyle(color: Colors.grey, fontSize: 13, fontWeight: FontWeight.bold)),
                    Text('Goal: $recommendedCalories kcal', style: const TextStyle(color: Colors.white, fontSize: 13, fontWeight: FontWeight.bold)),
                  ],
                ),

                const SizedBox(height: 40),
                const Divider(color: Colors.white10),
                const SizedBox(height: 24),

                // 5. Existing Vitals Row 
                Row(
                  children: [
                    Expanded(
                      child: _buildVitalCard(
                        title: 'Day Streak',
                        value: '$streak',
                        icon: Icons.local_fire_department,
                        bgColor: const Color(0xFF1A1A1A), 
                        textColor: Colors.white,
                        borderColor: const Color(0xFFFF5E00).withOpacity(0.5),
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildVitalCard(
                        title: 'Fatigue',
                        value: '$fatigue/10',
                        icon: Icons.battery_charging_full,
                        bgColor: const Color(0xFF1A1A1A), 
                        textColor: Colors.white,
                        borderColor: Colors.white10,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 24),

                // 6. Generate Routine Button 
                Container(
                  width: double.infinity,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [const Color(0xFFFF5E00), const Color(0xFFFF5E00).withOpacity(0.8)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                    borderRadius: BorderRadius.circular(20),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFFFF5E00).withOpacity(0.2),
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
                        MaterialPageRoute(builder: (_) => const WorkoutBuilderScreen()),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 24),
                        child: Column(
                          children: [
                            const Icon(Icons.bolt, size: 36, color: Colors.white),
                            const SizedBox(height: 12),
                            const Text(
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
                
                const SizedBox(height: 20),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildVitalCard({
    required String title,
    required String value,
    required IconData icon,
    required Color bgColor,
    required Color textColor,
    Color? borderColor,
  }) {
    return Container(
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
            style: TextStyle(fontSize: 24, fontWeight: FontWeight.w800, color: textColor),
          ),
          const SizedBox(height: 4),
          Text(
            title,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: textColor.withOpacity(0.7)),
          ),
        ],
      ),
    );
  }
}