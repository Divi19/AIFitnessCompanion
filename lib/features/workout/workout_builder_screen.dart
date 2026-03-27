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
  int  _currentStep = 0;
  bool _isLoading   = false;

  late final AnimationController _fadeController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350));
  late final Animation<double> _fadeAnim = CurvedAnimation(
      parent: _fadeController, curve: Curves.easeInOut);

  // ── THEME (Updated to Lime Accent) ───────────────────────────────────────────
  static const _accentLime = Color(0xFFC5F135);
  static const _darkTextOnAccent = Color(0xFF2D4A00); // Dark green for text on lime background
  static const _coral   = Color(0xFFFF7B6B); // Used for injury hotspots
  static const _bg      = Color(0xFF0D0D0D); // Pure Black
  static const _surface = Color(0xFF1A1A2E); // Slightly Lighter Dark Surface
  static const _surfaceLight = Color(0xFF25253D);

  static const _defaultPixelArtImage = 'assets/images/image_a4ab04.png'; 

  // ── STEP 1: Goal ───────────────────────────────────────────────────────────
  String _selectedGoal    = 'Weight Loss';
  String _selectedSubGoal = '';
  int    _planWeeks       = 4;

  final List<Map<String, dynamic>> _goals = [
    {
      'label': 'Weight Loss', 'icon': Icons.trending_down, 'desc': 'Burn fat & slim down', 'color': const Color(0xFFFF6B6B),
      'image': 'https://images.unsplash.com/photo-1518611012118-696072aa579a?auto=format&fit=crop&q=80&w=800', 
      'subOptions': [{'label':'Fat Burn','desc':'Cardio-heavy, high rep'},{'label':'Toning','desc':'Lean muscle & low fat'},{'label':'HIIT Focus','desc':'Max calorie burn'},{'label':'Steady Cardio','desc':'Sustainable fat loss'}]
    },
    {
      'label': 'Muscle Gain', 'icon': Icons.fitness_center, 'desc': 'Build size & strength', 'color': const Color(0xFF4F8EF7),
      'image': 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?auto=format&fit=crop&q=80&w=800', 
      'subOptions': [{'label':'Hypertrophy','desc':'Volume for size'},{'label':'Strength','desc':'Heavy compounds'},{'label':'Power','desc':'Explosive movements'},{'label':'Lean Bulk','desc':'Muscle with minimal fat'}]
    },
    {
      'label': 'Endurance', 'icon': Icons.directions_run, 'desc': 'Improve stamina & cardio', 'color': const Color(0xFF4CAF50),
      'image': 'https://images.pexels.com/photos/5687530/pexels-photo-5687530.jpeg?auto=compress&cs=tinysrgb&w=800&q=80', 
      'subOptions': [{'label':'Running','desc':'Aerobic base'},{'label':'Cycling','desc':'Leg endurance'},{'label':'Swimming','desc':'Full-body stamina'},{'label':'General Cardio','desc':'Mixed endurance'}]
    },
    {
      'label': 'Flexibility', 'icon': Icons.self_improvement, 'desc': 'Mobility & stretching', 'color': const Color(0xFFAB47BC),
      'image': 'https://images.unsplash.com/photo-1544367567-0f2fcb009e0b?auto=format&fit=crop&q=80&w=800', 
      'subOptions': [{'label':'Yoga','desc':'Flow & mindfulness'},{'label':'Stretching','desc':'Range of motion'},{'label':'Mobility','desc':'Joint health'},{'label':'Pilates','desc':'Core control'}]
    },
    {
      'label': 'General Fitness','icon': Icons.favorite, 'desc': 'Overall health & wellness', 'color': const Color(0xFFFF9800),
      'image': 'https://images.pexels.com/photos/6339358/pexels-photo-6339358.jpeg?auto=compress&cs=tinysrgb&w=300&q=80',
      'subOptions': [{'label':'Full Body','desc':'Balanced training'},{'label':'Athletic','desc':'Functional sport'},{'label':'Maintenance','desc':'Stay healthy'},{'label':'Weight Control','desc':'Manage weight'}]
    },
    {
      'label': 'Rehabilitation', 'icon': Icons.healing, 'desc': 'Recover & rebuild safely', 'color': const Color(0xFF26C6DA),
      'image': 'https://images.pexels.com/photos/5793911/pexels-photo-5793911.jpeg?auto=compress&cs=tinysrgb&w=800&q=80', 
      'subOptions': [{'label':'Post-Surgery','desc':'Gentle recovery'},{'label':'Injury Recovery','desc':'Rebuild safely'},{'label':'Chronic Pain','desc':'Low-impact'},{'label':'Posture','desc':'Fix imbalances'}]
    },
  ];

  final _customGoalController = TextEditingController();

  // ── STEP 2: Schedule ───────────────────────────────────────────────────────
  int    _daysPerWeek     = 3;
  String _workoutDuration = '45 mins';
  String _fitnessLevel    = 'Beginner';
  bool   _hasWeights      = false;
  final List<String> _durations = ['20 mins', '30 mins', '45 mins', '60 mins', '90 mins'];
  final List<String> _levels    = ['Beginner', 'Intermediate', 'Advanced'];

  // ── STEP 3: Limitations (Body Map) ─────────────────────────────────────────
  bool rotatorCuff      = false, deltoids       = false, pectorals    = false,
       biceps           = false, triceps        = false, latsRhomboids= false,
       elbowJoint       = false, wristCarpals   = false, glutesPelvis = false,
       quadriceps       = false, hamstrings     = false, calves       = false,
       kneeMeniscus     = false, achillesAnkle  = false, plantarFoot  = false,
       cervicalSpine    = false, thoracicSpine  = false, lumbarSpine  = false,
       abdominalHernia  = false, cardiovascular = false,
       respiratoryAsthma= false, osteoarthritis = false,
       usesWheelchair   = false, usesProsthetic = false, noLimitations= false;
  final _clinicalNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _selectedSubGoal = ((_goals[0]['subOptions'] as List)
        .cast<Map<String,dynamic>>())[0]['label'] as String;
    _fadeController.forward();
    _loadExistingLimitations();
  }

  // Load existing injuries so returning users don't start with a blank body map
  Future<void> _loadExistingLimitations() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) return;
      
      final data = doc.data() ?? {};
      final bio = data['biometrics'] as Map<String, dynamic>? ?? {};
      final upper = bio['upperBody'] as Map<String, dynamic>? ?? {};
      final lower = bio['lowerBody'] as Map<String, dynamic>? ?? {};
      final core = bio['coreSpine'] as Map<String, dynamic>? ?? {};
      final systemic = bio['systemic'] as Map<String, dynamic>? ?? {};

      if (!mounted) return;
      setState(() {
        rotatorCuff   = upper['rotatorCuff']   == true;
        deltoids      = upper['deltoids']      == true;
        pectorals     = upper['pectorals']     == true;
        biceps        = upper['biceps']        == true;
        triceps       = upper['triceps']       == true;
        latsRhomboids = upper['latsRhomboids'] == true;
        elbowJoint    = upper['elbowJoint']    == true;
        wristCarpals  = upper['wristCarpals']  == true;
        glutesPelvis  = lower['glutesPelvis']  == true;
        quadriceps    = lower['quadriceps']    == true;
        hamstrings    = lower['hamstrings']    == true;
        calves        = lower['calves']        == true;
        kneeMeniscus  = lower['kneeMeniscus']  == true;
        achillesAnkle = lower['achillesAnkle'] == true;
        plantarFoot   = lower['plantarFoot']   == true;
        cervicalSpine   = core['cervicalSpine']   == true;
        thoracicSpine   = core['thoracicSpine']   == true;
        lumbarSpine     = core['lumbarSpine']     == true;
        abdominalHernia = core['abdominalHernia'] == true;
        cardiovascular    = systemic['cardiovascular']    == true;
        respiratoryAsthma = systemic['respiratoryAsthma'] == true;
        osteoarthritis    = systemic['osteoarthritis']    == true;
        usesWheelchair    = systemic['wheelchair']        == true;
        usesProsthetic    = systemic['prosthesis']        == true;
        noLimitations     = bio['noLimitations']          == true;
        _clinicalNotesController.text = bio['clinicalNotes'] as String? ?? '';
      });
    } catch (_) {}
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    _customGoalController.dispose();
    _clinicalNotesController.dispose();
    super.dispose();
  }

  Map<String, dynamic> get _currentGoalData =>
      _goals.firstWhere((g) => g['label'] == _selectedGoal);

  void _nextStep() {
    if (_currentStep < 2) {
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

  List<String> _getActiveLimitations() {
    if (noLimitations) return [];
    return [
      if (cervicalSpine)    'Neck / Cervical',
      if (rotatorCuff)      'Shoulder / Rotator Cuff',
      if (deltoids)         'Deltoids',
      if (pectorals)        'Chest / Pectorals',
      if (biceps)           'Biceps',
      if (triceps)          'Triceps',
      if (latsRhomboids)    'Lats / Rhomboids',
      if (elbowJoint)       'Elbow',
      if (wristCarpals)     'Wrist / Carpals',
      if (thoracicSpine)    'Upper Back',
      if (lumbarSpine)      'Lower Back',
      if (abdominalHernia)  'Core / Abdomen',
      if (glutesPelvis)     'Glutes / Hips',
      if (quadriceps)       'Quadriceps',
      if (hamstrings)       'Hamstrings',
      if (kneeMeniscus)     'Knee',
      if (calves)           'Calves',
      if (achillesAnkle)    'Ankle / Achilles',
      if (plantarFoot)      'Foot / Plantar',
      if (cardiovascular)   'Cardiovascular',
      if (respiratoryAsthma)'Respiratory / Asthma',
      if (osteoarthritis)   'Osteoarthritis',
      if (usesWheelchair)   'Wheelchair User',
      if (usesProsthetic)   'Uses Prosthesis',
    ];
  }

  Future<void> _fetchAndGenerate() async {
    setState(() => _isLoading = true);
    try {
      final uid  = FirebaseAuth.instance.currentUser!.uid;
      final goal = _customGoalController.text.trim().isNotEmpty
          ? _customGoalController.text.trim()
          : '$_selectedGoal – $_selectedSubGoal';

      // Build Limitations String directly from UI state
      final activeLimits = _getActiveLimitations();
      String limitationsText = noLimitations || activeLimits.isEmpty ? 'None' : activeLimits.join(', ');
      if (_clinicalNotesController.text.isNotEmpty) {
        limitationsText += ' | Clinical Notes: ${_clinicalNotesController.text}';
      }

      // ── SAVE Updated Preferences + Active Plan Image URL + Biometrics ──────────
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fitness_goal': goal,
        'goal_focus':   _selectedSubGoal,
        'plan_weeks':   _planWeeks,
        'active_plan_image': _currentGoalData['image'],
        'workout_preferences': {
          'days_per_week':        _daysPerWeek,
          'duration_per_session': _workoutDuration,
          'fitness_level':        _fitnessLevel,
        },
        'biometrics': {
          'upperBody': {
            'rotatorCuff': rotatorCuff, 'deltoids': deltoids,
            'pectorals': pectorals, 'biceps': biceps, 'triceps': triceps,
            'latsRhomboids': latsRhomboids, 'elbowJoint': elbowJoint,
            'wristCarpals': wristCarpals,
          },
          'lowerBody': {
            'glutesPelvis': glutesPelvis, 'quadriceps': quadriceps,
            'hamstrings': hamstrings, 'calves': calves,
            'kneeMeniscus': kneeMeniscus, 'achillesAnkle': achillesAnkle,
            'plantarFoot': plantarFoot,
          },
          'coreSpine': {
            'cervicalSpine': cervicalSpine, 'thoracicSpine': thoracicSpine,
            'lumbarSpine': lumbarSpine, 'abdominalHernia': abdominalHernia,
          },
          'systemic': {
            'cardiovascular': cardiovascular,
            'respiratoryAsthma': respiratoryAsthma,
            'osteoarthritis': osteoarthritis,
            'wheelchair': usesWheelchair,
            'prosthesis': usesProsthetic,
          },
          'clinicalNotes': _clinicalNotesController.text,
          'noLimitations': noLimitations,
        }
      }, SetOptions(merge: true));

      // Read static body stats for AI prompt context
      final doc      = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      final data     = doc.data() ?? {};
      final stats    = data['body_stats'] as Map<String, dynamic>? ?? {};
      final totalDays= _daysPerWeek * _planWeeks;

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
          'imageUrl':     _currentGoalData['image'],
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
  final List<String> _stepLabels = ['Your Goal', 'Schedule', 'Limitations'];

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
          children: [_buildStep1Goal(), _buildStep2Schedule(), _buildStep3Limitations()],
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
                color: isDone || isActive ? _accentLime : Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 5),
            Text(_stepLabels[i], style: TextStyle(
              fontSize: 10,
              color: isActive ? _accentLime : isDone ? Colors.white54 : Colors.white24,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            )),
          ]),
        ));
      })),
    );
  }

  // ── STEP 1: GOAL ───────────────────────────────────────────────────────────
  Widget _buildStep1Goal() {
    final goalData    = _currentGoalData;
    final subOptions  = (goalData['subOptions'] as List).cast<Map<String, dynamic>>();
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
                    color: sel ? _accentLime.withOpacity(0.18) : _surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? _accentLime : Colors.white12, width: sel ? 2 : 1),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
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

          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: _accentLime.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: _accentLime.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
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

  // ── STEP 2: SCHEDULE ───────────────────────────────────────────────────────
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
            final levelPrimaryColor = level == 'Beginner' ? _accentLime : level == 'Intermediate' ? const Color(0xFFFF5E00) : const Color(0xFFFF3B30);
            
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _fitnessLevel = level),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: sel ? _accentLime : _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? levelPrimaryColor : Colors.white12, width: sel ? 2 : 1),
                ),
                child: Text(level, textAlign: TextAlign.center,
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

  // ── STEP 3: LIMITATIONS ────────────────────────────────────────────────────
  Widget _buildStep3Limitations() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _stepHeader('Physical Limitations', 'Tap any area that has injury or chronic pain', Icons.accessibility_new),
          const SizedBox(height: 16),
          // "No limitations" pill (Lime Theme)
          GestureDetector(
            onTap: () => setState(() {
              noLimitations = !noLimitations;
              if (noLimitations) {
                rotatorCuff = deltoids = pectorals = biceps = triceps =
                latsRhomboids = elbowJoint = wristCarpals = glutesPelvis =
                quadriceps = hamstrings = calves = kneeMeniscus = achillesAnkle =
                plantarFoot = cervicalSpine = thoracicSpine = lumbarSpine =
                abdominalHernia = cardiovascular = respiratoryAsthma =
                osteoarthritis = usesWheelchair = usesProsthetic = false;
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: noLimitations ? _accentLime.withOpacity(0.15) : _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: noLimitations ? _accentLime : Colors.white12, width: noLimitations ? 2 : 1),
              ),
              child: Row(children: [
                Icon(noLimitations ? Icons.check_circle : Icons.check_circle_outline,
                    color: noLimitations ? _accentLime : Colors.white38, size: 22),
                const SizedBox(width: 12),
                const Expanded(child: Text("I'm fully healthy — no limitations",
                    style: TextStyle(color: Colors.white70, fontSize: 14, fontWeight: FontWeight.w500))),
              ]),
            ),
          ),

          if (!noLimitations) ...[
            const SizedBox(height: 24),
            const Text('Tap on a body part to mark it as injured or painful',
                style: TextStyle(color: Colors.white38, fontSize: 12)),
            const SizedBox(height: 16),

            // ── PROFESSIONAL BODY MAP ──
            _buildProfessionalBodyMap(),

            const SizedBox(height: 20),

            // Active selections legend (Coral Theme for injuries)
            if (_getActiveLimitations().isNotEmpty) ...[
              const Text('Selected areas:', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _getActiveLimitations().map((l) =>
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _coral.withOpacity(0.15), borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _coral.withOpacity(0.5))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.circle, color: _coral, size: 6),
                    const SizedBox(width: 6),
                    Text(l, style: const TextStyle(color: _coral, fontSize: 11, fontWeight: FontWeight.w600)),
                  ]),
                ),
              ).toList()),
              const SizedBox(height: 20),
            ],

            // Other systemic conditions
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(14), border: Border.all(color: Colors.white12)),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Row(children: [
                  Icon(Icons.medical_services_outlined, color: _coral, size: 16),
                  SizedBox(width: 8),
                  Text('Other Conditions', style: TextStyle(color: _coral, fontWeight: FontWeight.w700, fontSize: 13)),
                ]),
                const SizedBox(height: 12),
                _checkChip('Cardiovascular condition', cardiovascular, (v) => setState(() => cardiovascular = v)),
                _checkChip('Respiratory / Asthma', respiratoryAsthma, (v) => setState(() => respiratoryAsthma = v)),
                _checkChip('Osteoarthritis', osteoarthritis, (v) => setState(() => osteoarthritis = v)),
                const Divider(color: Colors.white12, height: 20),
                _switchRow('Wheelchair User', usesWheelchair, (v) => setState(() => usesWheelchair = v)),
                const SizedBox(height: 8),
                _switchRow('Uses Prosthesis', usesProsthetic, (v) => setState(() => usesProsthetic = v)),
              ]),
            ),
            const SizedBox(height: 16),
            _label('Additional clinical notes (optional)'),
            const SizedBox(height: 8),
            _field(controller: _clinicalNotesController,
                hint: 'e.g. Post-op knee, cleared for light activity only...', maxLines: 3),
          ],
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── BODY MAP UI LOGIC ──────────────────────────────────────────────────────
  Widget _buildProfessionalBodyMap() {
    return LayoutBuilder(builder: (ctx, constraints) {
      final totalW = constraints.maxWidth;
      final figureW = (totalW - 24) / 2;

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildFigureWithLabels(figureW: figureW, isFront: true, title: 'FRONT'),
          const SizedBox(width: 24),
          _buildFigureWithLabels(figureW: figureW, isFront: false, title: 'BACK'),
        ],
      );
    });
  }

  Widget _buildFigureWithLabels({required double figureW, required bool isFront, required String title}) {
    final figH = figureW * 2.8;

    return Column(children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(20)),
        child: Text(title, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: figureW,
        height: figH,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: CustomPaint(
            painter: _ProfessionalBodyPainter(
              isFront: isFront,
              activeColor: _coral,
              activeRegions: _getActiveRegionNames(),
            ),
          )),
          ..._buildHotspots(isFront: isFront, fw: figureW, fh: figH),
        ]),
      ),
    ]);
  }

  Set<String> _getActiveRegionNames() {
    return {
      if (cervicalSpine)    'neck',
      if (rotatorCuff)      'shoulder',
      if (deltoids)         'deltoid',
      if (pectorals)        'chest',
      if (biceps)           'bicep',
      if (triceps)          'tricep',
      if (latsRhomboids)    'lat',
      if (elbowJoint)       'elbow',
      if (wristCarpals)     'wrist',
      if (thoracicSpine)    'upperback',
      if (lumbarSpine)      'lowerback',
      if (abdominalHernia)  'core',
      if (glutesPelvis)     'glute',
      if (quadriceps)       'quad',
      if (hamstrings)       'hamstring',
      if (kneeMeniscus)     'knee',
      if (calves)           'calf',
      if (achillesAnkle)    'ankle',
      if (plantarFoot)      'foot',
    };
  }

  List<Widget> _buildHotspots({required bool isFront, required double fw, required double fh}) {
    final active = _getActiveRegionNames();

    final List<Map<String, dynamic>> hotspots = isFront ? [
      {'x': 0.50, 'y': 0.045, 'key': 'neck',    'label': 'Neck',       'toggle': () => setState(() => cervicalSpine  = !cervicalSpine)},
      {'x': 0.22, 'y': 0.13,  'key': 'shoulder', 'label': 'Shoulder',  'toggle': () => setState(() => rotatorCuff    = !rotatorCuff)},
      {'x': 0.78, 'y': 0.13,  'key': 'shoulder', 'label': 'Shoulder',  'toggle': () => setState(() => rotatorCuff    = !rotatorCuff)},
      {'x': 0.50, 'y': 0.17,  'key': 'chest',    'label': 'Chest',      'toggle': () => setState(() => pectorals      = !pectorals)},
      {'x': 0.14, 'y': 0.22,  'key': 'bicep',    'label': 'Bicep',      'toggle': () => setState(() => biceps         = !biceps)},
      {'x': 0.86, 'y': 0.22,  'key': 'bicep',    'label': 'Bicep',      'toggle': () => setState(() => biceps         = !biceps)},
      {'x': 0.50, 'y': 0.28,  'key': 'core',     'label': 'Core',       'toggle': () => setState(() => abdominalHernia= !abdominalHernia)},
      {'x': 0.12, 'y': 0.35,  'key': 'elbow',    'label': 'Elbow',      'toggle': () => setState(() => elbowJoint     = !elbowJoint)},
      {'x': 0.88, 'y': 0.35,  'key': 'elbow',    'label': 'Elbow',      'toggle': () => setState(() => elbowJoint     = !elbowJoint)},
      {'x': 0.10, 'y': 0.44,  'key': 'wrist',    'label': 'Wrist',      'toggle': () => setState(() => wristCarpals   = !wristCarpals)},
      {'x': 0.90, 'y': 0.44,  'key': 'wrist',    'label': 'Wrist',      'toggle': () => setState(() => wristCarpals   = !wristCarpals)},
      {'x': 0.50, 'y': 0.42,  'key': 'glute',    'label': 'Hips',       'toggle': () => setState(() => glutesPelvis   = !glutesPelvis)},
      {'x': 0.35, 'y': 0.56,  'key': 'quad',     'label': 'Quad',       'toggle': () => setState(() => quadriceps     = !quadriceps)},
      {'x': 0.65, 'y': 0.56,  'key': 'quad',     'label': 'Quad',       'toggle': () => setState(() => quadriceps     = !quadriceps)},
      {'x': 0.35, 'y': 0.72,  'key': 'knee',     'label': 'Knee',       'toggle': () => setState(() => kneeMeniscus   = !kneeMeniscus)},
      {'x': 0.65, 'y': 0.72,  'key': 'knee',     'label': 'Knee',       'toggle': () => setState(() => kneeMeniscus   = !kneeMeniscus)},
      {'x': 0.35, 'y': 0.84,  'key': 'calf',     'label': 'Shin',       'toggle': () => setState(() => calves         = !calves)},
      {'x': 0.65, 'y': 0.84,  'key': 'calf',     'label': 'Shin',       'toggle': () => setState(() => calves         = !calves)},
      {'x': 0.35, 'y': 0.93,  'key': 'ankle',    'label': 'Ankle',      'toggle': () => setState(() => achillesAnkle  = !achillesAnkle)},
      {'x': 0.65, 'y': 0.93,  'key': 'ankle',    'label': 'Ankle',      'toggle': () => setState(() => achillesAnkle  = !achillesAnkle)},
    ] : [
      {'x': 0.50, 'y': 0.045, 'key': 'neck',      'label': 'Neck',      'toggle': () => setState(() => cervicalSpine  = !cervicalSpine)},
      {'x': 0.22, 'y': 0.13,  'key': 'deltoid',   'label': 'Delt',      'toggle': () => setState(() => deltoids       = !deltoids)},
      {'x': 0.78, 'y': 0.13,  'key': 'deltoid',   'label': 'Delt',      'toggle': () => setState(() => deltoids       = !deltoids)},
      {'x': 0.50, 'y': 0.18,  'key': 'upperback', 'label': 'Upper Back','toggle': () => setState(() => thoracicSpine  = !thoracicSpine)},
      {'x': 0.14, 'y': 0.22,  'key': 'tricep',    'label': 'Tricep',    'toggle': () => setState(() => triceps        = !triceps)},
      {'x': 0.86, 'y': 0.22,  'key': 'tricep',    'label': 'Tricep',    'toggle': () => setState(() => triceps        = !triceps)},
      {'x': 0.22, 'y': 0.30,  'key': 'lat',       'label': 'Lat',       'toggle': () => setState(() => latsRhomboids  = !latsRhomboids)},
      {'x': 0.78, 'y': 0.30,  'key': 'lat',       'label': 'Lat',       'toggle': () => setState(() => latsRhomboids  = !latsRhomboids)},
      {'x': 0.50, 'y': 0.34,  'key': 'lowerback', 'label': 'Lower Back','toggle': () => setState(() => lumbarSpine    = !lumbarSpine)},
      {'x': 0.50, 'y': 0.43,  'key': 'glute',     'label': 'Glutes',    'toggle': () => setState(() => glutesPelvis   = !glutesPelvis)},
      {'x': 0.35, 'y': 0.57,  'key': 'hamstring', 'label': 'Hamstring', 'toggle': () => setState(() => hamstrings     = !hamstrings)},
      {'x': 0.65, 'y': 0.57,  'key': 'hamstring', 'label': 'Hamstring', 'toggle': () => setState(() => hamstrings     = !hamstrings)},
      {'x': 0.35, 'y': 0.72,  'key': 'knee',      'label': 'Knee',      'toggle': () => setState(() => kneeMeniscus   = !kneeMeniscus)},
      {'x': 0.65, 'y': 0.72,  'key': 'knee',      'label': 'Knee',      'toggle': () => setState(() => kneeMeniscus   = !kneeMeniscus)},
      {'x': 0.35, 'y': 0.83,  'key': 'calf',      'label': 'Calf',      'toggle': () => setState(() => calves         = !calves)},
      {'x': 0.65, 'y': 0.83,  'key': 'calf',      'label': 'Calf',      'toggle': () => setState(() => calves         = !calves)},
      {'x': 0.35, 'y': 0.93,  'key': 'ankle',     'label': 'Ankle',     'toggle': () => setState(() => achillesAnkle  = !achillesAnkle)},
      {'x': 0.65, 'y': 0.93,  'key': 'ankle',     'label': 'Ankle',     'toggle': () => setState(() => achillesAnkle  = !achillesAnkle)},
      {'x': 0.35, 'y': 0.985, 'key': 'foot',      'label': 'Foot',      'toggle': () => setState(() => plantarFoot    = !plantarFoot)},
      {'x': 0.65, 'y': 0.985, 'key': 'foot',      'label': 'Foot',      'toggle': () => setState(() => plantarFoot    = !plantarFoot)},
    ];

    return hotspots.map((h) {
      final key    = h['key'] as String;
      final label  = h['label'] as String;
      final toggle = h['toggle'] as VoidCallback;
      final isActive = active.contains(key);
      final px = (h['x'] as double) * fw;
      final py = (h['y'] as double) * fh;

      return Positioned(
        left: px - 10,
        top:  py - 10,
        child: GestureDetector(
          onTap: toggle,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              width: 20, height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: isActive ? _coral : const Color(0xFF2A2A2A),
                border: Border.all(
                  color: isActive ? _coral : const Color(0xFF4A4A4A),
                  width: isActive ? 2 : 1.5,
                ),
                boxShadow: isActive ? [BoxShadow(color: _coral.withOpacity(0.5), blurRadius: 8, spreadRadius: 1)] : null,
              ),
              child: isActive ? const Icon(Icons.close, size: 10, color: Colors.white) : null,
            ),
            if (isActive) ...[
              Container(width: 1, height: 6, color: _coral.withOpacity(0.6)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(color: _coral, borderRadius: BorderRadius.circular(4)),
                child: Text(label, style: const TextStyle(color: Colors.white, fontSize: 10.5, fontWeight: FontWeight.w700)),
              ),
            ] else ...[
              Container(width: 1, height: 4, color: const Color(0xFF3A3A3A)),
              Text(label, style: const TextStyle(color: Color(0xFF666666), fontSize: 9, fontWeight: FontWeight.w500)),
            ],
          ]),
        ),
      );
    }).toList();
  }

  Widget _checkChip(String label, bool value, Function(bool) onChanged) {
    return GestureDetector(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: value ? _coral : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: value ? _coral : Colors.white30, width: 2),
            ),
            child: value ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
          ),
          const SizedBox(width: 12),
          Text(label, style: TextStyle(
              color: value ? Colors.white : Colors.white60, fontSize: 13,
              fontWeight: value ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }

  Widget _switchRow(String title, bool value, Function(bool) onChanged) {
    return Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
      Switch(value: value, onChanged: onChanged, activeColor: _coral,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
    ]);
  }

  // ── Bottom Navigation Button ───────────────────────────────────────────────
  Widget _buildBottomButton() {
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      color: _bg,
      child: SizedBox(
        height: 56,
        width: double.infinity,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: _accentLime,
            foregroundColor: _darkTextOnAccent,
            disabledBackgroundColor: Colors.white10,
            disabledForegroundColor: Colors.white30,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: _darkTextOnAccent))
              : Text(_currentStep < 2 ? 'Next Step' : 'Generate My Plan',
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

// ── PROFESSIONAL BODY PAINTER ─────────────────────────────────────────────────
class _ProfessionalBodyPainter extends CustomPainter {
  final bool isFront;
  final Color activeColor;
  final Set<String> activeRegions;
  const _ProfessionalBodyPainter({required this.isFront, required this.activeColor, required this.activeRegions});

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final cx = w / 2;

    final bodyFill = Paint()..color = const Color(0xFF252525)..style = PaintingStyle.fill;
    final bodyStroke = Paint()..color = const Color(0xFF404040)..style = PaintingStyle.stroke..strokeWidth = 1.2..strokeJoin = StrokeJoin.round;

    final sx = w / 160.0;
    final sy = h / 448.0;

    Offset s(double x, double y) => Offset(x * sx, y * sy);

    // ── HEAD ──
    final headCenter = s(80, 22);
    final headRx = 20 * sx;
    final headRy = 24 * sy;
    canvas.drawOval(Rect.fromCenter(center: headCenter, width: headRx * 2, height: headRy * 2), bodyFill);
    canvas.drawOval(Rect.fromCenter(center: headCenter, width: headRx * 2, height: headRy * 2), bodyStroke);

    // ── NECK ──
    final neckPath = Path()
      ..moveTo(s(74, 44).dx, s(74, 44).dy)
      ..lineTo(s(74, 56).dx, s(74, 56).dy)
      ..lineTo(s(86, 56).dx, s(86, 56).dy)
      ..lineTo(s(86, 44).dx, s(86, 44).dy)
      ..close();
    canvas.drawPath(neckPath, bodyFill);
    canvas.drawPath(neckPath, bodyStroke);

    // ── TORSO ──
    final torsoPath = Path()
      ..moveTo(s(56, 56).dx, s(56, 56).dy)
      ..cubicTo(s(40, 60).dx, s(40, 60).dy, s(36, 68).dx, s(36, 68).dy, s(38, 90).dx, s(38, 90).dy)
      ..lineTo(s(40, 168).dx, s(40, 168).dy)
      ..cubicTo(s(42, 178).dx, s(42, 178).dy, s(55, 182).dx, s(55, 182).dy, s(62, 184).dx, s(62, 184).dy)
      ..lineTo(s(98, 184).dx, s(98, 184).dy)
      ..cubicTo(s(105, 182).dx, s(105, 182).dy, s(118, 178).dx, s(118, 178).dy, s(120, 168).dx, s(120, 168).dy)
      ..lineTo(s(122, 90).dx, s(122, 90).dy)
      ..cubicTo(s(124, 68).dx, s(124, 68).dy, s(120, 60).dx, s(120, 60).dy, s(104, 56).dx, s(104, 56).dy)
      ..close();
    canvas.drawPath(torsoPath, bodyFill);
    canvas.drawPath(torsoPath, bodyStroke);

    // ── LEFT ARM ──
    final leftArm = Path()
      ..moveTo(s(40, 62).dx, s(40, 62).dy)
      ..cubicTo(s(28, 68).dx, s(28, 68).dy, s(20, 80).dx, s(20, 80).dy, s(18, 104).dx, s(18, 104).dy)
      ..lineTo(s(16, 148).dx, s(16, 148).dy)
      ..cubicTo(s(15, 164).dx, s(15, 164).dy, s(18, 178).dx, s(18, 178).dy, s(22, 192).dx, s(22, 192).dy)
      ..lineTo(s(32, 192).dx, s(32, 192).dy)
      ..cubicTo(s(34, 178).dx, s(34, 178).dy, s(35, 162).dx, s(35, 162).dy, s(34, 148).dx, s(34, 148).dy)
      ..lineTo(s(34, 104).dx, s(34, 104).dy)
      ..cubicTo(s(35, 84).dx, s(35, 84).dy, s(40, 72).dx, s(40, 72).dy, s(44, 68).dx, s(44, 68).dy)
      ..close();
    canvas.drawPath(leftArm, bodyFill);
    canvas.drawPath(leftArm, bodyStroke);

    // ── RIGHT ARM ──
    final rightArm = Path()
      ..moveTo(s(120, 62).dx, s(120, 62).dy)
      ..cubicTo(s(132, 68).dx, s(132, 68).dy, s(140, 80).dx, s(140, 80).dy, s(142, 104).dx, s(142, 104).dy)
      ..lineTo(s(144, 148).dx, s(144, 148).dy)
      ..cubicTo(s(145, 164).dx, s(145, 164).dy, s(142, 178).dx, s(142, 178).dy, s(138, 192).dx, s(138, 192).dy)
      ..lineTo(s(128, 192).dx, s(128, 192).dy)
      ..cubicTo(s(126, 178).dx, s(126, 178).dy, s(125, 162).dx, s(125, 162).dy, s(126, 148).dx, s(126, 148).dy)
      ..lineTo(s(126, 104).dx, s(126, 104).dy)
      ..cubicTo(s(125, 84).dx, s(125, 84).dy, s(120, 72).dx, s(120, 72).dy, s(116, 68).dx, s(116, 68).dy)
      ..close();
    canvas.drawPath(rightArm, bodyFill);
    canvas.drawPath(rightArm, bodyStroke);

    // ── LEFT LEG ──
    final leftLeg = Path()
      ..moveTo(s(62, 184).dx, s(62, 184).dy)
      ..lineTo(s(56, 192).dx, s(56, 192).dy)
      ..cubicTo(s(50, 230).dx, s(50, 230).dy, s(46, 270).dx, s(46, 270).dy, s(46, 300).dx, s(46, 300).dy)
      ..lineTo(s(44, 352).dx, s(44, 352).dy)
      ..cubicTo(s(44, 374).dx, s(44, 374).dy, s(46, 400).dx, s(46, 400).dy, s(48, 420).dx, s(48, 420).dy)
      ..lineTo(s(62, 420).dx, s(62, 420).dy)
      ..cubicTo(s(64, 400).dx, s(64, 400).dy, s(65, 374).dx, s(65, 374).dy, s(66, 352).dx, s(66, 352).dy)
      ..lineTo(s(68, 300).dx, s(68, 300).dy)
      ..cubicTo(s(70, 270).dx, s(70, 270).dy, s(72, 230).dx, s(72, 230).dy, s(74, 192).dx, s(74, 192).dy)
      ..lineTo(s(72, 184).dx, s(72, 184).dy)
      ..close();
    canvas.drawPath(leftLeg, bodyFill);
    canvas.drawPath(leftLeg, bodyStroke);

    // ── RIGHT LEG ──
    final rightLeg = Path()
      ..moveTo(s(98, 184).dx, s(98, 184).dy)
      ..lineTo(s(86, 184).dx, s(86, 184).dy)
      ..lineTo(s(86, 192).dx, s(86, 192).dy)
      ..cubicTo(s(88, 230).dx, s(88, 230).dy, s(90, 270).dx, s(90, 270).dy, s(92, 300).dx, s(92, 300).dy)
      ..lineTo(s(94, 352).dx, s(94, 352).dy)
      ..cubicTo(s(95, 374).dx, s(95, 374).dy, s(96, 400).dx, s(96, 400).dy, s(98, 420).dx, s(98, 420).dy)
      ..lineTo(s(112, 420).dx, s(112, 420).dy)
      ..cubicTo(s(114, 400).dx, s(114, 400).dy, s(116, 374).dx, s(116, 374).dy, s(114, 352).dx, s(114, 352).dy)
      ..lineTo(s(112, 300).dx, s(112, 300).dy)
      ..cubicTo(s(112, 270).dx, s(112, 270).dy, s(110, 230).dx, s(110, 230).dy, s(104, 192).dx, s(104, 192).dy)
      ..lineTo(s(104, 184).dx, s(104, 184).dy)
      ..close();
    canvas.drawPath(rightLeg, bodyFill);
    canvas.drawPath(rightLeg, bodyStroke);

    // ── FEET ──
    for (final side in [-1.0, 1.0]) {
      final fx = cx + side * 22 * sx;
      final footPath = Path()
        ..addRRect(RRect.fromRectAndRadius(
          Rect.fromCenter(center: Offset(fx, s(80, 434).dy), width: 16 * sx, height: 10 * sy),
          const Radius.circular(4)));
      canvas.drawPath(footPath, bodyFill);
      canvas.drawPath(footPath, bodyStroke);
    }
  }

  @override
  bool shouldRepaint(_ProfessionalBodyPainter old) =>
      old.isFront != isFront || old.activeRegions != activeRegions;
}