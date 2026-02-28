import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants.dart';
import 'workout_plan_screen.dart';

class WorkoutBuilderScreen extends StatefulWidget {
  const WorkoutBuilderScreen({Key? key}) : super(key: key);

  @override
  State<WorkoutBuilderScreen> createState() => _WorkoutBuilderScreenState();
}

class _WorkoutBuilderScreenState extends State<WorkoutBuilderScreen>
    with SingleTickerProviderStateMixin {
  final PageController _pageController = PageController();
  int _currentStep = 0;
  bool _isLoading = false;

  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  late final Animation<double> _fadeAnim = CurvedAnimation(
    parent: _fadeController,
    curve: Curves.easeInOut,
  );

  // ── STEP 1: Fitness Goal ─────────────────────────────────────────────────
  String _selectedGoal = 'Weight Loss';
  final List<Map<String, dynamic>> _goals = [
    {'label': 'Weight Loss',    'icon': Icons.trending_down,    'desc': 'Burn fat & slim down'},
    {'label': 'Muscle Gain',    'icon': Icons.fitness_center,   'desc': 'Build size & strength'},
    {'label': 'Endurance',      'icon': Icons.directions_run,   'desc': 'Improve stamina & cardio'},
    {'label': 'Flexibility',    'icon': Icons.self_improvement, 'desc': 'Mobility & stretching'},
    {'label': 'General Fitness','icon': Icons.favorite,         'desc': 'Overall health & wellness'},
    {'label': 'Rehabilitation', 'icon': Icons.healing,          'desc': 'Recover & rebuild safely'},
  ];
  final _customGoalController = TextEditingController();

  // ── STEP 2: Schedule ─────────────────────────────────────────────────────
  int _daysPerWeek = 3;
  String _workoutDuration = '45 mins';
  String _fitnessLevel = 'Beginner';
  final List<String> _durations = ['20 mins', '30 mins', '45 mins', '60 mins', '90 mins'];
  final List<String> _levels = ['Beginner', 'Intermediate', 'Advanced'];

  @override
  void initState() {
    super.initState();
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    _customGoalController.dispose();
    super.dispose();
  }

  void _nextStep() {
    if (_currentStep < 1) { // 2 steps total (0 and 1)
      _fadeController.reset();
      setState(() => _currentStep++);
      _pageController.nextPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      _fadeController.forward();
    } else {
      _fetchDataAndGeneratePlan();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _fadeController.reset();
      setState(() => _currentStep--);
      _pageController.previousPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      _fadeController.forward();
    }
  }

  // Parses the complex biometrics map back into a readable string for the AI
  String _parseLimitationsForAI(Map<String, dynamic>? biometrics) {
    if (biometrics == null || biometrics['noLimitations'] == true) {
      return 'None';
    }

    List<String> activeInjuries = [];
    
    void extractInjuries(Map<String, dynamic>? section) {
      section?.forEach((key, value) {
        if (value == true) activeInjuries.add(key);
      });
    }

    extractInjuries(biometrics['upperBody']);
    extractInjuries(biometrics['lowerBody']);
    extractInjuries(biometrics['coreSpine']);
    
    // Systemic needs careful handling to exclude wheelchair/prosthesis from general injury list
    final systemic = biometrics['systemic'] as Map<String, dynamic>?;
    if (systemic?['cardiovascular'] == true) activeInjuries.add('cardiovascular');
    if (systemic?['respiratoryAsthma'] == true) activeInjuries.add('asthma');
    if (systemic?['osteoarthritis'] == true) activeInjuries.add('osteoarthritis');

    String notes = biometrics['clinicalNotes'] ?? '';
    String result = activeInjuries.isEmpty ? 'None' : activeInjuries.join(', ');
    
    if (notes.isNotEmpty) {
      result += ' | Clinical Notes: $notes';
    }
    
    return result;
  }

  Future<void> _fetchDataAndGeneratePlan() async {
    setState(() => _isLoading = true);
    
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      
      // 1. Save their new preferences so it remembers for next time
      final goal = _customGoalController.text.trim().isNotEmpty
          ? _customGoalController.text.trim()
          : _selectedGoal;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fitness_goal': goal,
        'workout_preferences': {
          'days_per_week': _daysPerWeek,
          'duration_per_session': _workoutDuration,
          'fitness_level': _fitnessLevel,
        },
      }, SetOptions(merge: true));

      // 2. Fetch the baseline static data (Body stats & injuries)
      final userDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};
      
      final bodyStats = userData['body_stats'] as Map<String, dynamic>? ?? {};
      final biometrics = userData['biometrics'] as Map<String, dynamic>?;

      final age = bodyStats['age'] ?? 'Unknown';
      final gender = bodyStats['gender'] ?? 'Unknown';
      final weight = bodyStats['weight'] ?? 'Unknown';
      final height = bodyStats['height'] ?? 'Unknown';
      
      final limitationsText = _parseLimitationsForAI(biometrics);
      final usesWheelchair = biometrics?['systemic']?['wheelchair'] ?? false;
      final usesProsthesis = biometrics?['systemic']?['prosthesis'] ?? false;

      // 3. Build the context-rich prompt
      final prompt = '''
You are an expert physiotherapist and certified personal trainer.
Generate a detailed, safe $_daysPerWeek-day workout plan for this user.

User Profile:
- Age: $age years old
- Gender: $gender
- Weight: $weight
- Height: $height
- Fitness Level: $_fitnessLevel
- Fitness Goal: $goal
- Workout Days Per Week: $_daysPerWeek days
- Session Duration: $_workoutDuration per session
- Physical Limitations / Injuries: $limitationsText
- Uses Wheelchair: $usesWheelchair
- Uses Prosthesis: $usesProsthesis

Strict Rules:
- NEVER include any exercise that involves or stresses the injured areas
- Adapt ALL movements to their physical limitations and fitness level
- Each session must fit within $_workoutDuration
- For each exercise include: name, sets, reps/duration, rest time, and WHY it is safe
- If wheelchair user, only include seated or upper body exercises
- Include warm-up and cool-down for each day
- Format clearly with Day 1, Day 2 etc. (only $_daysPerWeek days total)
- End with weekly recovery tips and nutrition advice specific to their goal
''';

      // 4. Call Gemini API
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConstants.geminiApiKey}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
        }),
      );

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final plan = data['candidates'][0]['content']['parts'][0]['text'] as String;
        
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutPlanScreen(plan: plan)));
        }
      } else {
        throw Exception('Gemini API error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────

  final List<String> _stepLabels = ['Your Goal', 'Schedule'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D), // Deep Black
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                onPressed: _prevStep,
              )
            : IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                onPressed: () => Navigator.pop(context),
              ),
        title: const Text('Build My Routine',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: Column(
        children: [
          _buildStepIndicator(),
          Expanded(
            child: PageView(
              controller: _pageController,
              physics: const NeverScrollableScrollPhysics(),
              children: [
                _buildStep1(),
                _buildStep2(),
              ],
            ),
          ),
          _buildBottomButton(),
        ],
      ),
    );
  }

  // ── STEP INDICATOR ────────────────────────────────────────────────────────
  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(
        children: List.generate(_stepLabels.length, (i) {
          final isActive = i == _currentStep;
          final isDone   = i < _currentStep;
          return Expanded(
            child: Padding(
              padding: EdgeInsets.only(right: i < _stepLabels.length - 1 ? 6 : 0),
              child: Column(
                children: [
                  AnimatedContainer(
                    duration: const Duration(milliseconds: 300),
                    height: 3,
                    decoration: BoxDecoration(
                      color: isDone || isActive ? const Color(0xFFFF5E00) : Colors.white12, // Electric Orange
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text(
                    _stepLabels[i],
                    style: TextStyle(
                      fontSize: 10,
                      color: isActive ? const Color(0xFFFF5E00) : isDone ? Colors.white54 : Colors.white24,
                      fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
                    ),
                  ),
                ],
              ),
            ),
          );
        }),
      ),
    );
  }

  // ── STEP 1: GOAL ──────────────────────────────────────────────────────────
  Widget _buildStep1() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _stepHeader("What's Your Goal?", 'Pick the primary focus for your plan', Icons.flag_outlined),
            const SizedBox(height: 24),
            GridView.count(
              crossAxisCount: 2,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
              childAspectRatio: 1.5,
              children: _goals.map((g) {
                final sel = _selectedGoal == g['label'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedGoal = g['label'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.all(14),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFFFF5E00).withOpacity(0.15) : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(color: sel ? const Color(0xFFFF5E00) : Colors.white12, width: sel ? 2 : 1),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(g['icon'] as IconData, color: sel ? const Color(0xFFFF5E00) : Colors.white38, size: 26),
                        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Text(g['label'] as String, style: TextStyle(color: sel ? Colors.white : Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
                          Text(g['desc'] as String, style: const TextStyle(color: Colors.white38, fontSize: 11)),
                        ]),
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 20),
            _label('Or describe your own goal (optional)'),
            const SizedBox(height: 8),
            _field(controller: _customGoalController, hint: 'e.g. Prepare for a marathon in 3 months...', maxLines: 2),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── STEP 2: SCHEDULE ──────────────────────────────────────────────────────
  Widget _buildStep2() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _stepHeader('Your Schedule', 'How often and how long do you want to train?', Icons.calendar_today_outlined),
            const SizedBox(height: 24),
            _label('Days Per Week'),
            const SizedBox(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: List.generate(7, (i) {
                final day = i + 1;
                final sel = _daysPerWeek == day;
                return GestureDetector(
                  onTap: () => setState(() => _daysPerWeek = day),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: 40, height: 40,
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFFFF5E00) : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? const Color(0xFFFF5E00) : Colors.white12),
                    ),
                    child: Center(child: Text('$day', style: TextStyle(color: sel ? Colors.white : Colors.white54, fontWeight: FontWeight.w700, fontSize: 16))),
                  ),
                );
              }),
            ),
            const SizedBox(height: 8),
            Center(child: Text('$_daysPerWeek ${_daysPerWeek == 1 ? 'day' : 'days'} per week', style: const TextStyle(color: Color(0xFFFF5E00), fontSize: 13, fontWeight: FontWeight.w600))),
            const SizedBox(height: 28),
            _label('Session Duration'),
            const SizedBox(height: 12),
            Wrap(
              spacing: 10, runSpacing: 10,
              children: _durations.map((d) {
                final sel = _workoutDuration == d;
                return GestureDetector(
                  onTap: () => setState(() => _workoutDuration = d),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                    decoration: BoxDecoration(
                      color: sel ? const Color(0xFFFF5E00) : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: sel ? const Color(0xFFFF5E00) : Colors.white12),
                    ),
                    child: Text(d, style: TextStyle(color: sel ? Colors.white : Colors.white54, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 28),
            _label('Fitness Level'),
            const SizedBox(height: 12),
            Row(
              children: _levels.map((level) {
                final sel = _fitnessLevel == level;
                // Volt Green for beginner, Orange for intermediate, Red for advanced
                final c = level == 'Beginner' ? const Color(0xFFB9FF2B) : level == 'Intermediate' ? const Color(0xFFFF5E00) : const Color(0xFFFF3B30);
                final textColor = sel ? (level == 'Beginner' ? Colors.black : Colors.white) : Colors.white54;
                
                return Expanded(
                  child: GestureDetector(
                    onTap: () => setState(() => _fitnessLevel = level),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 8),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      decoration: BoxDecoration(
                        color: sel ? c : const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel ? c : Colors.white12, width: sel ? 2 : 1),
                      ),
                      child: Text(level, textAlign: TextAlign.center, style: TextStyle(color: textColor, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── BOTTOM BUTTON ─────────────────────────────────────────────────────────
  Widget _buildBottomButton() {
    final isLast = _currentStep == 1;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: const Color(0xFF0D0D0D),
        border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: SizedBox(
        width: double.infinity, height: 54,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFFFF5E00), // Electric Orange
            disabledBackgroundColor: Colors.white12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(isLast ? 'Generate My Plan' : 'Continue',
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3)),
                    if (!isLast) ...[const SizedBox(width: 8), const Icon(Icons.arrow_forward, color: Colors.white, size: 18)],
                  ],
                ),
        ),
      ),
    );
  }

  // ── HELPERS ───────────────────────────────────────────────────────────────

  Widget _stepHeader(String title, String subtitle, IconData icon) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: const Color(0xFFFF5E00).withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: const Color(0xFFFF5E00), size: 24),
      ),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
    ]);
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3));

  Widget _field({
    required TextEditingController controller,
    required String hint,
    String? suffix,
    TextInputType keyboard = TextInputType.text,
    int maxLines = 1,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboard,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        suffixText: suffix,
        suffixStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        filled: true,
        fillColor: const Color(0xFF1A1A1A),
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF5E00), width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}