import 'package:flutter/material.dart';

class WorkoutPlanScreen extends StatelessWidget {
  final String plan;

  const WorkoutPlanScreen({Key? key, required this.plan}) : super(key: key);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D), // Deep Black
      appBar: AppBar(
        title: const Text(
          'Your Workout Plan',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(24),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A1A), // Dark Surface
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: Colors.white10), // Subtle outline matching your UI
          ),
          child: Text(
            plan,
            style: const TextStyle(
              fontSize: 15,
              height: 1.6, // Excellent line height for reading long AI responses
              color: Colors.white, // High contrast text
            ),
          ),
        ),
      ),
    );
  }
}