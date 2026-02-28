import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'firebase_options.dart';
import 'screens/workout_tracker_screen.dart'; // Import the new screen for pose detection and correction
import 'screens/meal_tracker_screen.dart'; 

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialise Firebase before the app starts.
  // This must complete before any Firebase services (Firestore, Auth, etc.) are used.
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  runApp(
    
    const ProviderScope(
      child: MyApp(),
    ),
  );
}

class MyApp extends ConsumerWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'AI Fitness Companion',
      debugShowCheckedModeBanner: false, // Hides the red debug banner for demo
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),

      // Directly boot into the meal tracker for now, to test meal tracker screen
      home: const MealTrackerScreen()
    );
  }
}