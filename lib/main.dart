import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart'; // Added Firestore import
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'core/constants.dart';
import 'features/auth/auth_screen.dart';
// import 'features/admin/admin_ingestion.dart';
import 'features/nutrition/nutrition_assistant.dart';
import 'screens/workout_tracker_screen.dart'; // Pose detection screen
import 'features/workout/injury_profile_screen.dart'; // Step 1: Onboarding
import 'features/workout/workout_builder_screen.dart'; // Step 2: Plan Generator

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Crash immediately in debug mode if .env was not passed at run time
  AppConstants.assertKeysLoaded();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // ProviderScope wraps the entire app, fulfilling the requirement for both
  // the chat backend and the new WorkoutTrackerScreen.
  runApp(const ProviderScope(child: MyApp()));
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'AI Fitness Companion',
      debugShowCheckedModeBanner: false,
      // Switched to a sleek dark theme with your custom colors
      theme: ThemeData(
        brightness: Brightness.dark,
        scaffoldBackgroundColor: const Color(0xFF0D0D0D), // Deep Black
        colorScheme: const ColorScheme.dark(
          primary: Color(0xFFB9FF2B), // Volt Lime Green
          secondary: Color(0xFFFF5E00), // Electric Orange
          surface: Color(0xFF1A1A1A), // Slightly lighter grey for cards
        ),
        useMaterial3: true,
      ),
      // AuthGate sits at the root — ensuring users log in first
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
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(
                color: Color(0xFFB9FF2B), // Green loader
              ),
            ),
          );
        }

        // 1. Not signed in — show auth screen
        if (!snapshot.hasData || snapshot.data == null) {
          return const AuthScreen();
        }

        final user = snapshot.data!;

        // 2. Signed in — Intercept and check Firestore for profile_completed
        return StreamBuilder<DocumentSnapshot>(
          stream: FirebaseFirestore.instance.collection('users').doc(user.uid).snapshots(),
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: CircularProgressIndicator(
                    color: Color(0xFFB9FF2B),
                  ),
                ),
              );
            }

            final userData = userSnapshot.data?.data() as Map<String, dynamic>?;
            final isProfileCompleted = userData?['profile_completed'] == true;

            // 3. Profile is finished, unlock the Home Screen
            if (isProfileCompleted) {
              return const HomeScreen();
            }

            // 4. Profile incomplete, force them into the static Onboarding Wizard
            return const InjuryProfileScreen();
          },
        );
      },
    );
  }
}

// ── HOME SCREEN ──────────────────────────────────────────────────────────────
class HomeScreen extends StatelessWidget {
  const HomeScreen({super.key});

  Future<void> _signOut(BuildContext context) async {
    await FirebaseAuth.instance.signOut();
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;

    return Scaffold(
      appBar: AppBar(
        title: const Text(
          'AI Fitness Companion',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.transparent, // Modern transparent app bar
        elevation: 0,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.logout),
            tooltip: 'Sign out',
            onPressed: () => _signOut(context),
          ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Text(
                'Welcome back',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),
              Text(
                user?.email ?? '',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),

              const SizedBox(height: 40),

              // FEATURE 1: RAG Assistant (Green)
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const NutritionAssistantScreen(),
                  ),
                ),
                icon: const Icon(Icons.chat_bubble_outline),
                label: const Text(
                  'Open Fitness Assistant',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB9FF2B), // Volt Lime Green
                  foregroundColor: Colors.black, // High contrast text
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // FEATURE 2: Workout Tracker (Orange)
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WorkoutTrackerScreen(),
                  ),
                ),
                icon: const Icon(Icons.fitness_center),
                label: const Text(
                  'Start AI Workout Tracker',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF5E00), // Electric Orange
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // FEATURE 3: Plan Routine (Dark Surface) -> Routes to new WorkoutBuilderScreen
              ElevatedButton.icon(
                onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => const WorkoutBuilderScreen(),
                  ),
                ),
                icon: const Icon(Icons.assignment),
                label: const Text(
                  'Build a New Routine',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1A1A1A), // Dark surface color
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: const BorderSide(color: Colors.white10), // Subtle outline
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}