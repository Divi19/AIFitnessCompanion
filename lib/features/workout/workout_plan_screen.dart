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
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            
            // ── AI Context Banner (Electric Orange) ──────────────────────────
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: const Color(0xFFFF5E00).withOpacity(0.15),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFF5E00).withOpacity(0.5)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.auto_awesome, color: Color(0xFFFF5E00)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'AI-Generated based on your specific goals and injury profile.',
                      style: TextStyle(
                        color: const Color(0xFFFF5E00).withOpacity(0.9),
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        height: 1.4,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            
            const SizedBox(height: 24),

            // ── The Plan Container (Volt Green Glow) ─────────────────────────
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A), // Dark Surface
                borderRadius: BorderRadius.circular(16),
                border: Border.all(
                  color: const Color(0xFFB9FF2B).withOpacity(0.3), 
                  width: 1.5,
                ), // Volt Green accent border
                boxShadow: [
                  BoxShadow(
                    color: const Color(0xFFB9FF2B).withOpacity(0.05), // Subtle neon glow
                    blurRadius: 20,
                    spreadRadius: 2,
                  ),
                ],
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
            
            // Extra padding at the bottom so the FAB doesn't cover the text
            const SizedBox(height: 100), 
          ],
        ),
      ),
      
      // ── Finish Button ──────────────────────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.pop(context), // Sends them back to home
        backgroundColor: const Color(0xFFB9FF2B), // Volt Green
        foregroundColor: Colors.black, // High contrast text
        icon: const Icon(Icons.check),
        label: const Text(
          'Finish & Save',
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }
}