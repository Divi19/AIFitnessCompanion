import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants.dart';
import 'workout_plan_screen.dart';

/// Quick re-generate screen for returning users who already completed the
/// full InjuryProfileScreen. Only asks Goal + Schedule, then reads their
/// saved body stats & injuries from Firestore.
class WorkoutBuilderScreen extends StatefulWidget {
  const WorkoutBuilderScreen({Key? key}) : super(key: key);

  @override
  State<WorkoutBuilderScreen> createState() => _WorkoutBuilderScreenState();
}

class _WorkoutBuilderScreenState extends State<WorkoutBuilderScreen>
    with SingleTickerProviderStateMixin {

  final PageController _pageController = PageController();
  int  _currentStep = 0;
  bool _isLoading   = false;

  late final AnimationController _fadeController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350));
  late final Animation<double> _fadeAnim = CurvedAnimation(
      parent: _fadeController, curve: Curves.easeInOut);

  // ── THEME (Updated to Lime Accent) ───────────────────────────────────────────
  static const _accentLime = Color(0xFFC5F135);
  static const _darkTextOnAccent = Color(0xFF2D4A00); // Dark green for text on lime background
  static const _bg      = Color(0xFF0D0D0D); // Pure Black
  static const _surface = Color(0xFF1A1A2E); // Slightly Lighter Dark Surface
  static const _surfaceLight = Color(0xFF25253D);

  // ── Placeholder Image Logic ──────────────────────────────────────────────
  // The specific pixel art image provided by the user. 
  // Map this image string to your asset path in Firebase later.
  // Make sure you save image_a4ab04.png into assets/images/ in your project.
  static const _defaultPixelArtImage = 'assets/images/image_a4ab04.png'; 

  // ── STEP 1: Goal (Updated with unique web images for each category) ───────
  String _selectedGoal    = 'Weight Loss';
  String _selectedSubGoal = '';
  int    _planWeeks       = 4;

  final List<Map<String, dynamic>> _goals = [
    {
      'label': 'Weight Loss', 'icon': Icons.trending_down, 'desc': 'Burn fat & slim down', 'color': const Color(0xFFFF6B6B),
      // Intense cardio / running image
      'image': 'https://images.unsplash.com/photo-1518611012118-696072aa579a?auto=format&fit=crop&q=80&w=800', 
      'subOptions': [{'label':'Fat Burn','desc':'Cardio-heavy, high rep'},{'label':'Toning','desc':'Lean muscle & low fat'},{'label':'HIIT Focus','desc':'Max calorie burn'},{'label':'Steady Cardio','desc':'Sustainable fat loss'}]
    },
    {
      'label': 'Muscle Gain', 'icon': Icons.fitness_center, 'desc': 'Build size & strength', 'color': const Color(0xFF4F8EF7),
      // Heavy lifting / bicep image
      'image': 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?auto=format&fit=crop&q=80&w=800', 
      'subOptions': [{'label':'Hypertrophy','desc':'Volume for size'},{'label':'Strength','desc':'Heavy compounds'},{'label':'Power','desc':'Explosive movements'},{'label':'Lean Bulk','desc':'Muscle with minimal fat'}]
    },
    {
      'label': 'Endurance', 'icon': Icons.directions_run, 'desc': 'Improve stamina & cardio', 'color': const Color(0xFF4CAF50),
      // Running track / athletic image
      'image': 'https://images.unsplash.com/photo-1534438327276-14e5300c3a48?auto=format&fit=crop&q=80&w=800', 
      'subOptions': [{'label':'Running','desc':'Aerobic base'},{'label':'Cycling','desc':'Leg endurance'},{'label':'Swimming','desc':'Full-body stamina'},{'label':'General Cardio','desc':'Mixed endurance'}]
    },
    {
      'label': 'Flexibility', 'icon': Icons.self_improvement, 'desc': 'Mobility & stretching', 'color': const Color(0xFFAB47BC),
      // Yoga pose / stretching image
      'image': 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?auto=format&fit=crop&q=80&w=800', 
      'subOptions': [{'label':'Yoga','desc':'Flow & mindfulness'},{'label':'Stretching','desc':'Range of motion'},{'label':'Mobility','desc':'Joint health'},{'label':'Pilates','desc':'Core control'}]
    },
    {
      'label': 'General Fitness','icon': Icons.favorite, 'desc': 'Overall health & wellness', 'color': const Color(0xFFFF9800),
      // Balanced gym / kettlebell image
      'image': 'https://images.unsplash.com/photo-1517836357463-d25dfeac3438?auto=format&fit=crop&q=80&w=800', 
      'subOptions': [{'label':'Full Body','desc':'Balanced training'},{'label':'Athletic','desc':'Functional sport'},{'label':'Maintenance','desc':'Stay healthy'},{'label':'Weight Control','desc':'Manage weight'}]
    },
    {
      'label': 'Rehabilitation', 'icon': Icons.healing, 'desc': 'Recover & rebuild safely', 'color': const Color(0xFF26C6DA),
      // Gentle stretching / physical therapy image
      'image': 'https://images.unsplash.com/photo-1576678927484-cc907957088c?auto=format&fit=crop&q=80&w=800', 
      'subOptions': [{'label':'Post-Surgery','desc':'Gentle recovery'},{'label':'Injury Recovery','desc':'Rebuild safely'},{'label':'Chronic Pain','desc':'Low-impact'},{'label':'Posture','desc':'Fix imbalances'}]
    },
  ];

  final _customGoalController = TextEditingController();

  // ── STEP 2: Schedule ──────────────────────────────────────────────────────
  int    _daysPerWeek     = 3;
  String _workoutDuration = '45 mins';
  String _fitnessLevel    = 'Beginner';
  bool   _hasWeights      = false;
  final List<String> _durations = ['20 mins', '30 mins', '45 mins', '60 mins', '90 mins'];
  final List<String> _levels    = ['Beginner', 'Intermediate', 'Advanced'];

  @override
  void initState() {
    super.initState();
    _selectedSubGoal = ((_goals[0]['subOptions'] as List)
        .cast<Map<String,dynamic>>())[0]['label'] as String;
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    _customGoalController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _currentGoalData =>
      _goals.firstWhere((g) => g['label'] == _selectedGoal);

  void _nextStep() {
    if (_currentStep < 1) {
      _fadeController.reset();
      setState(() => _currentStep++);
      _pageController.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      _fadeController.forward();
    } else {
      _fetchAndGenerate();
    }
  }

  void _prevStep() {
    if (_currentStep > 0) {
      _fadeController.reset();
      setState(() => _currentStep--);
      _pageController.previousPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      _fadeController.forward();
    }
  }

  /// Converts stored Firestore biometrics map → readable string for Gemini
  String _parseLimitations(Map<String, dynamic>? bio) {
    if (bio == null || bio['noLimitations'] == true) return 'None';
    final injuries = <String>[];
    void extract(Map<String, dynamic>? section) =>
        section?.forEach((k, v) { if (v == true) injuries.add(k); });
    extract(bio['upperBody'] as Map<String, dynamic>?);
    extract(bio['lowerBody'] as Map<String, dynamic>?);
    extract(bio['coreSpine'] as Map<String, dynamic>?);
    final sys = bio['systemic'] as Map<String, dynamic>?;
    if (sys?['cardiovascular']    == true) injuries.add('cardiovascular');
    if (sys?['respiratoryAsthma'] == true) injuries.add('asthma');
    if (sys?['osteoarthritis']    == true) injuries.add('osteoarthritis');
    final notes  = bio['clinicalNotes'] as String? ?? '';
    String result = injuries.isEmpty ? 'None' : injuries.join(', ');
    if (notes.isNotEmpty) result += ' | Clinical Notes: $notes';
    return result;
  }

  Future<void> _fetchAndGenerate() async {
    setState(() => _isLoading = true);
    try {
      final uid  = FirebaseAuth.instance.currentUser!.uid;
      final goal = _customGoalController.text.trim().isNotEmpty
          ? _customGoalController.text.trim()
          : '$_selectedGoal – $_selectedSubGoal';

      // ── SAVE Updated Preferences + Active Plan Image URL ──────────────────────
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fitness_goal': goal,
        'goal_focus':   _selectedSubGoal,
        'plan_weeks':   _planWeeks,
        'active_plan_image': _currentGoalData['image'], // <--- SAVE IMAGE URL TO PROFILE
        'workout_preferences': {
          'days_per_week':        _daysPerWeek,
          'duration_per_session': _workoutDuration,
          'fitness_level':        _fitnessLevel,
        },
      }, SetOptions(merge: true));

      // Read static body stats & injuries
      final doc      = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data     = doc.data() ?? {};
      final stats    = data['body_stats'] as Map<String, dynamic>? ?? {};
      final bio      = data['biometrics'] as Map<String, dynamic>?;
      final insights = data['health_insights'] as Map<String, dynamic>? ?? {};

      final limitationsText = _parseLimitations(bio);
      final usesWheelchair  = bio?['systemic']?['wheelchair']  ?? false;
      final usesProsthesis  = bio?['systemic']?['prosthesis']  ?? false;
      final totalDays       = _daysPerWeek * _planWeeks;
      final calories        = insights['suggested_calories'] ?? 'Unknown';
      final bmi             = insights['bmi'] ?? 'Unknown';

      // ── EXERCISE LIBRARY ────────────────────────────────────────────────────
      const trackableExercises = '''
TRACKABLE EXERCISES (available in the app's Pose Tracker — prefer these):
  • Squat 
  • Push Up
  • Bicep Curl
  • Jumping Jack
  • Right Lunge
  • Left Lunge
  • Sit Up
  • Plank
  • Glute Bridge

ALLOWED SIMPLE EXTRAS:
  • Walk / Brisk Walk
  • Jog in Place
  • High Knees
  • Mountain Climbers
  • Burpee
  • Yoga Flow
  • Static Stretch
''';

      const goalExerciseGuide = '''
GOAL → RECOMMENDED EXERCISE FOCUS:
  Weight Loss: Jumping Jack, Burpee, High Knees, Squat, Push Up, Lunge
  Muscle Gain: Squat, Push Up, Glute Bridge, Bicep Curl (high reps/sets)
  Endurance: Jumping Jack, High Knees, Jog in Place, Plank
  Flexibility: Yoga Flow, Static Stretch
  General Fitness: Mix all categories
  Rehabilitation: Low-impact ONLY (Glute Bridge, Plank, Static Stretch) — SKIP Burpee, Jumping Jack
''';

      final prompt = '''
You are an expert physiotherapist and certified personal trainer.
Generate a complete $_planWeeks-week workout program for this user.

User Profile:
- Age: ${stats['age'] ?? 'Unknown'}
- Primary Goal: $goal
- Fitness Level: $_fitnessLevel
- Workout Days Per Week: $_daysPerWeek days
- Session Duration: $_workoutDuration
- Plan Duration: $_planWeeks weeks ($totalDays sessions)
- Physical Limitations / Injuries: $limitationsText
- Equipment Available: ${_hasWeights ? 'Has weights' : 'NO equipment — restrict to bodyweight list below ONLY'}

$trackableExercises

$goalExerciseGuide

STRICT RULES:
1. NEVER include exercises that stress injured body parts.
2. Output ONLY a raw JSON array — no markdown, no backticks.

JSON structure EXACTLY as follows:
[
  {
    "week": 1,
    "days": [
      {
        "day": 1,
        "title": "Full Body Burn",
        "isRest": false,
        "exercises": [
          {"name": "Jumping Jack", "detail": "3 sets × 30 sec"},
          {"name": "Squat", "detail": "3 sets × 15 reps"}
        ]
      },
      {
        "day": 2,
        "title": "Rest Day",
        "isRest": true,
        "exercises": []
      }
    ]
  }
]
''';

      final response = await http.post(
        Uri.parse('https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConstants.geminiApiKey}'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'contents': [{'parts': [{'text': prompt}]}]}),
      );

      if (response.statusCode == 200) {
        final json    = jsonDecode(response.body);
        final plan    = json['candidates'][0]['content']['parts'][0]['text'] as String;
        final planRef = await FirebaseFirestore.instance
            .collection('users').doc(uid)
            .collection('workout_plans')
            .add({
          'plan':         plan,
          'goal':         goal,
          'imageUrl':     _currentGoalData['image'], // <--- SAVE IMAGE URL TO WORKOUT PLAN DOCUMENT
          'fitnessLevel': _fitnessLevel,
          'daysPerWeek':  _daysPerWeek,
          'planWeeks':    _planWeeks,
          'duration':     _workoutDuration,
          'limitations':  limitationsText,
          'hasWeights':   _hasWeights,
          'createdAt':    FieldValue.serverTimestamp(),
          'expiresAt':    Timestamp.fromDate(DateTime.now().add(Duration(days: _planWeeks * 7))),
        });

        if (mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => WorkoutPlanScreen(plan: plan, planId: planRef.id, uid: uid),
          ));
        }
      } else {
        throw Exception('Gemini API error: ${response.statusCode}');
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[700]),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  final List<String> _stepLabels = ['Your Goal', 'Schedule'];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0,
        leading: _currentStep > 0
            ? IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20), onPressed: _prevStep)
            : IconButton(icon: const Icon(Icons.close, color: Colors.white70, size: 22), onPressed: () => Navigator.pop(context)),
        title: const Text('Build My Routine',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: Column(children: [
        _buildStepIndicator(),
        Expanded(child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [_buildStep1Goal(), _buildStep2Schedule()],
        )),
        _buildBottomButton(),
      ]),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
      child: Row(children: List.generate(_stepLabels.length, (i) {
        final isActive = i == _currentStep;
        final isDone   = i < _currentStep;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: i < _stepLabels.length - 1 ? 6 : 0),
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300),
              height: 3,
              decoration: BoxDecoration(
                // Colors Updated to Lime Accent
                color: isDone || isActive ? _accentLime : Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 5),
            Text(_stepLabels[i], style: TextStyle(
              fontSize: 10,
              // Colors Updated to Lime Accent
              color: isActive ? _accentLime : isDone ? Colors.white54 : Colors.white24,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            )),
          ]),
        ));
      })),
    );
  }

  Widget _buildStep1Goal() {
    final goalData    = _currentGoalData;
    final subOptions  = (goalData['subOptions'] as List).cast<Map<String, dynamic>>();
    // Toned down the specific colors so they don't clash with the Lime theme
    final originalAccentColor = goalData['color'] as Color;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _stepHeader("What's Your Goal?", 'Pick your focus and training style', Icons.flag_outlined),
          const SizedBox(height: 20),

          GridView.count(
            crossAxisCount: 2, shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10, mainAxisSpacing: 10, childAspectRatio: 1.6,
            children: _goals.map((g) {
              final sel   = _selectedGoal == g['label'];
              final color = g['color'] as Color;
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedGoal    = g['label'] as String;
                  _selectedSubGoal = ((g['subOptions'] as List).cast<Map<String,dynamic>>())[0]['label'] as String;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    // Colors Updated to Lime Accent for selected state
                    color: sel ? _accentLime.withOpacity(0.18) : _surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? _accentLime : Colors.white12, width: sel ? 2 : 1),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    // Icon color is now Lime when selected, subtle tint otherwise
                    Icon(g['icon'] as IconData, color: sel ? _accentLime : color.withOpacity(0.5), size: 22),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(g['label'] as String, style: TextStyle(color: sel ? Colors.white : Colors.white70, fontWeight: FontWeight.w700, fontSize: 12)),
                      Text(g['desc'] as String, style: TextStyle(color: sel ? _accentLime.withOpacity(0.8) : Colors.white38, fontSize: 10)),
                    ]),
                  ]),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Sub-options panel (Unified to Lime Accent theme)
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _accentLime.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accentLime.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                // Icon uses original accent, text uses Lime
                Icon(goalData['icon'] as IconData, color: originalAccentColor.withOpacity(0.7), size: 16),
                const SizedBox(width: 8),
                Text('$_selectedGoal — Choose your focus',
                    style: const TextStyle(color: _accentLime, fontWeight: FontWeight.w700, fontSize: 13)),
              ]),
              const SizedBox(height: 12),
              ...subOptions.map((sub) {
                final sel = _selectedSubGoal == sub['label'];
                return GestureDetector(
                  onTap: () => setState(() => _selectedSubGoal = sub['label'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      // Colors Updated to Lime Accent for selected state
                      color: sel ? _accentLime.withOpacity(0.2) : const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? _accentLime : Colors.white12, width: sel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? _accentLime : Colors.transparent,
                          border: Border.all(color: sel ? _accentLime : Colors.white30, width: 2),
                        ),
                        // Check icon uses Dark text color on Lime background
                        child: sel ? const Icon(Icons.check, size: 11, color: _darkTextOnAccent) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(sub['label'] as String, style: TextStyle(color: sel ? Colors.white : Colors.white70, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
                        Text(sub['desc'] as String, style: TextStyle(color: sel ? _accentLime.withOpacity(0.8) : Colors.white38, fontSize: 11)),
                      ])),
                    ]),
                  ),
                );
              }),
            ]),
          ),

          const SizedBox(height: 20),

          // Plan Duration
          _label('Plan Duration'),
          const SizedBox(height: 4),
          const Text('Max 1 month — regenerate for continued progress',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 12),
          Row(children: [1, 2, 3, 4].map((weeks) {
            final sel = _planWeeks == weeks;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _planWeeks = weeks),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  // Colors Updated to Lime Accent for selected state
                  color: sel ? _accentLime : _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? _accentLime : Colors.white12),
                ),
                child: Column(children: [
                  Text('$weeks', style: TextStyle(color: sel ? _darkTextOnAccent : Colors.white54, fontWeight: FontWeight.w800, fontSize: 18)),
                  Text(weeks == 1 ? 'week' : 'weeks', style: TextStyle(color: sel ? _darkTextOnAccent.withOpacity(0.8) : Colors.white24, fontSize: 10)),
                ]),
              ),
            ));
          }).toList()),
          const SizedBox(height: 8),
          const Center(child: Text(
            'We recommend 4 weeks for noticeable change',
            style: TextStyle(color: _accentLime, fontSize: 12, fontWeight: FontWeight.w600),
          )),

          const SizedBox(height: 20),
          _label('Additional context (optional)'),
          const SizedBox(height: 8),
          _field(controller: _customGoalController, hint: 'e.g. Preparing for a competition...', maxLines: 2),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildStep2Schedule() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
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
                    // Colors Updated to Lime Accent for selected state
                    color: sel ? _accentLime : _surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? _accentLime : Colors.white12),
                  ),
                  child: Center(child: Text('$day', style: TextStyle(color: sel ? _darkTextOnAccent : Colors.white54, fontWeight: FontWeight.w700, fontSize: 16))),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          const Center(child: Text('More days usually means shorter sessions',
              style: TextStyle(color: _accentLime, fontSize: 13, fontWeight: FontWeight.w600))),
          const SizedBox(height: 28),
          _label('Session Duration'),
          const SizedBox(height: 12),
          Wrap(spacing: 10, runSpacing: 10, children: _durations.map((d) {
            final sel = _workoutDuration == d;
            return GestureDetector(
              onTap: () => setState(() => _workoutDuration = d),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                decoration: BoxDecoration(
                  // Colors Updated to Lime Accent for selected state
                  color: sel ? _accentLime : _surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? _accentLime : Colors.white12),
                ),
                child: Text(d, style: TextStyle(color: sel ? _darkTextOnAccent : Colors.white54, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
              ),
            );
          }).toList()),
          const SizedBox(height: 28),
          _label('Fitness Level'),
          const SizedBox(height: 12),
          Row(children: _levels.map((level) {
            final sel = _fitnessLevel == level;
            // Kept semantic level colors, but unified selection background to Lime
            final levelPrimaryColor = level == 'Beginner' ? _accentLime : level == 'Intermediate' ? const Color(0xFFFF5E00) : const Color(0xFFFF3B30);
            
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _fitnessLevel = level),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  // Background is Lime when selected, surface otherwise
                  color: sel ? _accentLime : _surface,
                  borderRadius: BorderRadius.circular(12),
                  // Border uses the level specific color when selected
                  border: Border.all(color: sel ? levelPrimaryColor : Colors.white12, width: sel ? 2 : 1),
                ),
                child: Text(level, textAlign: TextAlign.center,
                    // Text color flips to dark on lime background
                    style: TextStyle(color: sel ? _darkTextOnAccent : Colors.white54, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
              ),
            ));
          }).toList()),
          const SizedBox(height: 28),
          _label('Do you have weights / equipment?'),
          const SizedBox(height: 4),
          const Text('Helps us tailor exercises to what you have available',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 12),
          Row(children: [
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _hasWeights = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    // Colors Updated to Lime Accent for selected state
                    color: !_hasWeights ? _accentLime : _surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: !_hasWeights ? _accentLime : Colors.white12),
                  ),
                  child: Column(children: [
                    Icon(Icons.person_outline,
                        color: !_hasWeights ? _darkTextOnAccent : Colors.white38, size: 22),
                    const SizedBox(height: 6),
                    Text('No Equipment',
                        style: TextStyle(color: !_hasWeights ? _darkTextOnAccent : Colors.white54,
                            fontWeight: !_hasWeights ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
                    Text('Bodyweight only',
                        style: TextStyle(color: !_hasWeights ? _darkTextOnAccent.withOpacity(0.8) : Colors.white24, fontSize: 10)),
                  ]),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: GestureDetector(
                onTap: () => setState(() => _hasWeights = true),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  decoration: BoxDecoration(
                    // Colors Updated to Lime Accent for selected state
                    color: _hasWeights ? _accentLime : _surface,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: _hasWeights ? _accentLime : Colors.white12),
                  ),
                  child: Column(children: [
                    Icon(Icons.fitness_center,
                        color: _hasWeights ? _darkTextOnAccent : Colors.white38, size: 22),
                    const SizedBox(height: 6),
                    Text('Has Weights',
                        style: TextStyle(color: _hasWeights ? _darkTextOnAccent : Colors.white54,
                            fontWeight: _hasWeights ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
                    Text('Gym / home weights',
                        style: TextStyle(color: _hasWeights ? _darkTextOnAccent.withOpacity(0.8) : Colors.white24, fontSize: 10)),
                  ]),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── Bottom Navigation Button (Updated Colors) ──────────────────────────────
  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      color: _bg, // Keeps background clean
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _nextStep,
          style: ElevatedButton.styleFrom(
            // Updated Colors: Lime Background, Dark Text
            backgroundColor: _accentLime,
            foregroundColor: _darkTextOnAccent,
            disabledBackgroundColor: Colors.white10,
            disabledForegroundColor: Colors.white30,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _darkTextOnAccent))
              : Text(_currentStep < 1 ? 'Next Step' : 'Generate My Plan',
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800, letterSpacing: 0.5)),
        ),
      ),
    );
  }

  // ── Helper UI Widgets ────────────────────────────────────────────────────────
  Widget _stepHeader(String title, String subtitle, IconData icon) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16)),
      child: Row(children: [
        // Updated colors
        Container(width: 40, height: 40, decoration: BoxDecoration(color: _accentLime.withOpacity(0.15), shape: BoxShape.circle), child: Icon(icon, color: _accentLime, size: 20)),
        const SizedBox(width: 14),
        Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title, style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700)),
          Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 12)),
        ])),
      ]),
    );
  }

  Widget _label(String text) {
    return Text(text, style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.w700));
  }

  Widget _field({required TextEditingController controller, required String hint, int maxLines = 1}) {
    return TextField(
      controller: controller,
      maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 13),
      decoration: InputDecoration(
        hintText: hint,
        hintStyle: const TextStyle(color: Colors.white24, fontSize: 13),
        filled: true,
        fillColor: _surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        contentPadding: const EdgeInsets.all(14),
      ),
    );
  }
}