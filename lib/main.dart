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

  // The 4 main screens of your app
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

// ── HOME DASHBOARD TAB ──────────────────────────────────────────────────────
class HomeDashboardTab extends StatelessWidget {
  const HomeDashboardTab({super.key});

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

          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Personalized Greeting
                Text(
                  'Ready to crush it,',
                  style: TextStyle(fontSize: 16, color: Colors.grey),
                ),
                const SizedBox(height: 4),
                Text(
                  name.toString().split(' ').first, // First name only
                  style: const TextStyle(fontSize: 32, fontWeight: FontWeight.w800, color: Colors.white),
                ),
                
                const SizedBox(height: 32),

                // 2. Vitals Row (Streak & Fatigue)
                Row(
                  children: [
                    Expanded(
                      child: _buildVitalCard(
                        title: 'Day Streak',
                        value: '$streak',
                        icon: Icons.local_fire_department,
                        bgColor: const Color(0xFFB9FF2B), // Volt Green
                        textColor: Colors.black,
                      ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: _buildVitalCard(
                        title: 'Fatigue Level',
                        value: '$fatigue/10',
                        icon: Icons.battery_charging_full,
                        bgColor: const Color(0xFF1A1A1A), // Dark Surface
                        textColor: Colors.white,
                        borderColor: fatigue > 7 ? const Color(0xFFFF5E00) : Colors.white10,
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 40),

                // 3. Primary Action: Generate Routine
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
                        padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 24),
                        child: Column(
                          children: [
                            const Icon(Icons.bolt, size: 48, color: Colors.white),
                            const SizedBox(height: 16),
                            const Text(
                              'Generate Today\'s Routine',
                              style: TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.bold,
                                color: Colors.white,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'AI-tailored to your goals & recovery.',
                              style: TextStyle(color: Colors.white.withOpacity(0.8), fontSize: 13),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  // Helper for the small stat cards
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