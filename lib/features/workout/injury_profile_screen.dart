import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'dart:convert';
import '../../core/constants.dart';
import 'workout_plan_screen.dart';

class InjuryProfileScreen extends StatefulWidget {
  const InjuryProfileScreen({Key? key}) : super(key: key);

  @override
  _InjuryProfileScreenState createState() => _InjuryProfileScreenState();
}

class _InjuryProfileScreenState extends State<InjuryProfileScreen>
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

  // ── STEP 1: Body Stats ───────────────────────────────────────────────────
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _ageController    = TextEditingController();
  String _gender     = 'Male';
  String _weightUnit = 'kg';
  String _heightUnit = 'cm';

  // ── STEP 2: Insights & Target (friend's addition) ────────────────────────
  final _targetWeightController = TextEditingController();

  // ── STEP 3: Goal + Sub-options + Duration ────────────────────────────────
  String _selectedGoal    = 'Weight Loss';
  String _selectedSubGoal = '';
  int    _planWeeks       = 4;

  final List<Map<String, dynamic>> _goals = [
    {
      'label': 'Weight Loss',
      'icon': Icons.trending_down,
      'desc': 'Burn fat & slim down',
      'color': const Color(0xFFFF6B6B),
      'subOptions': [
        {'label': 'Fat Burn',      'desc': 'Cardio-heavy, high rep training'},
        {'label': 'Toning',        'desc': 'Lean muscle with low body fat'},
        {'label': 'HIIT Focus',    'desc': 'Intense intervals for max calorie burn'},
        {'label': 'Steady Cardio', 'desc': 'Moderate pace, sustainable fat loss'},
      ],
    },
    {
      'label': 'Muscle Gain',
      'icon': Icons.fitness_center,
      'desc': 'Build size & strength',
      'color': const Color(0xFF4F8EF7),
      'subOptions': [
        {'label': 'Hypertrophy', 'desc': 'Size-focused, moderate weight & high volume'},
        {'label': 'Strength',    'desc': 'Heavy compound lifts, low reps'},
        {'label': 'Power',       'desc': 'Explosive movements & athleticism'},
        {'label': 'Lean Bulk',   'desc': 'Muscle gain with minimal fat'},
      ],
    },
    {
      'label': 'Endurance',
      'icon': Icons.directions_run,
      'desc': 'Improve stamina & cardio',
      'color': const Color(0xFF4CAF50),
      'subOptions': [
        {'label': 'Running',       'desc': 'Build aerobic base for running'},
        {'label': 'Cycling',       'desc': 'Leg endurance & cardio for cycling'},
        {'label': 'Swimming',      'desc': 'Full-body stamina & breathing'},
        {'label': 'General Cardio','desc': 'Mixed cardio endurance'},
      ],
    },
    {
      'label': 'Flexibility',
      'icon': Icons.self_improvement,
      'desc': 'Mobility & stretching',
      'color': const Color(0xFFAB47BC),
      'subOptions': [
        {'label': 'Yoga',       'desc': 'Flow-based flexibility & mindfulness'},
        {'label': 'Stretching', 'desc': 'Static & dynamic range of motion'},
        {'label': 'Mobility',   'desc': 'Joint health & functional movement'},
        {'label': 'Pilates',    'desc': 'Core strength & body control'},
      ],
    },
    {
      'label': 'General Fitness',
      'icon': Icons.favorite,
      'desc': 'Overall health & wellness',
      'color': const Color(0xFFFF9800),
      'subOptions': [
        {'label': 'Full Body',      'desc': 'Balanced training for all muscle groups'},
        {'label': 'Athletic',       'desc': 'Sport-style functional training'},
        {'label': 'Maintenance',    'desc': 'Stay active & healthy long-term'},
        {'label': 'Weight Control', 'desc': 'Manage weight with balanced workouts'},
      ],
    },
    {
      'label': 'Rehabilitation',
      'icon': Icons.healing,
      'desc': 'Recover & rebuild safely',
      'color': const Color(0xFF26C6DA),
      'subOptions': [
        {'label': 'Post-Surgery',      'desc': 'Gentle recovery after surgery'},
        {'label': 'Injury Recovery',   'desc': 'Rebuild strength around injured area'},
        {'label': 'Chronic Pain',      'desc': 'Low-impact pain management'},
        {'label': 'Posture Correction','desc': 'Fix muscle imbalances & alignment'},
      ],
    },
  ];

  final _customGoalController = TextEditingController();

  // ── STEP 4: Schedule ─────────────────────────────────────────────────────
  int    _daysPerWeek     = 3;
  String _workoutDuration = '45 mins';
  String _fitnessLevel    = 'Beginner';
  final List<String> _durations = ['20 mins', '30 mins', '45 mins', '60 mins', '90 mins'];
  final List<String> _levels    = ['Beginner', 'Intermediate', 'Advanced'];

  // ── STEP 5: Limitations ──────────────────────────────────────────────────
  bool rotatorCuff = false, deltoids = false, pectorals = false,
       biceps = false, triceps = false, latsRhomboids = false,
       elbowJoint = false, wristCarpals = false, glutesPelvis = false,
       quadriceps = false, hamstrings = false, calves = false,
       kneeMeniscus = false, achillesAnkle = false, plantarFoot = false,
       cervicalSpine = false, thoracicSpine = false, lumbarSpine = false,
       abdominalHernia = false, cardiovascular = false,
       respiratoryAsthma = false, osteoarthritis = false,
       usesWheelchair = false, usesProsthetic = false, noLimitations = false;
  final _clinicalNotesController = TextEditingController();

  // ── COLOR THEME (friend's orange theme) ──────────────────────────────────
  static const _orange = Color(0xFFFF5E00);
  static const _voltGreen = Color(0xFFB9FF2B);
  static const _surface = Color(0xFF1A1A1A);
  static const _bg = Color(0xFF0D0D0D);

  // ─────────────────────────────────────────────────────────────────────────

  @override
  void initState() {
    super.initState();
    _selectedSubGoal = ((_goals[0]['subOptions'] as List)
        .cast<Map<String, dynamic>>())[0]['label'] as String;
    _fadeController.forward();
    _targetWeightController.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _ageController.dispose();
    _targetWeightController.dispose();
    _customGoalController.dispose();
    _clinicalNotesController.dispose();
    super.dispose();
  }

  // ── FRIEND'S MATH HELPERS ────────────────────────────────────────────────
  double _getKg() {
    final w = double.tryParse(_weightController.text) ?? 0.0;
    return _weightUnit == 'lbs' ? w * 0.453592 : w;
  }

  double _getCm() {
    final h = double.tryParse(_heightController.text) ?? 0.0;
    return _heightUnit == 'ft' ? h * 30.48 : h;
  }

  double _getBMI() {
    final kg = _getKg();
    final m  = _getCm() / 100;
    if (m <= 0 || kg <= 0) return 0.0;
    return kg / (m * m);
  }

  String _getBMICategory(double bmi) {
    if (bmi == 0)              return 'Unknown';
    if (bmi < 18.5)            return 'Underweight';
    if (bmi <= 24.9)           return 'Healthy';
    if (bmi <= 29.9)           return 'Overweight';
    return 'Obese';
  }

  Color _getBMIColor(double bmi) {
    if (bmi == 0)    return Colors.grey;
    if (bmi < 18.5)  return const Color(0xFFFFCC00);
    if (bmi <= 24.9) return _voltGreen;
    if (bmi <= 29.9) return _orange;
    return Colors.redAccent;
  }

  int _getCalories() {
    final kg  = _getKg();
    final cm  = _getCm();
    final age = int.tryParse(_ageController.text) ?? 25;
    if (kg <= 0 || cm <= 0) return 0;
    double bmr = (10 * kg) + (6.25 * cm) - (5 * age);
    bmr += (_gender == 'Male') ? 5 : -161;
    double tdee = bmr * 1.375;
    final target = double.tryParse(_targetWeightController.text);
    if (target != null && target > 0) {
      final targetKg = _weightUnit == 'lbs' ? target * 0.453592 : target;
      if (targetKg < _getKg() - 1) return (tdee - 500).round();
      if (targetKg > _getKg() + 1) return (tdee + 300).round();
    }
    return tdee.round();
  }

  Map<String, dynamic> get _currentGoalData =>
      _goals.firstWhere((g) => g['label'] == _selectedGoal);

  List<String> _getActiveLimitations() {
    if (noLimitations) return [];
    final List<String> a = [];
    if (rotatorCuff)       a.add('Rotator Cuff / Shoulder');
    if (deltoids)          a.add('Deltoids');
    if (pectorals)         a.add('Pectorals');
    if (biceps)            a.add('Biceps');
    if (triceps)           a.add('Triceps');
    if (latsRhomboids)     a.add('Lats / Rhomboids');
    if (elbowJoint)        a.add('Elbow Joint');
    if (wristCarpals)      a.add('Wrist / Carpals');
    if (glutesPelvis)      a.add('Glutes / Pelvis');
    if (quadriceps)        a.add('Quadriceps');
    if (hamstrings)        a.add('Hamstrings');
    if (calves)            a.add('Calves');
    if (kneeMeniscus)      a.add('Knee / Meniscus');
    if (achillesAnkle)     a.add('Achilles / Ankle');
    if (plantarFoot)       a.add('Plantar / Foot');
    if (cervicalSpine)     a.add('Cervical Spine (Neck)');
    if (thoracicSpine)     a.add('Thoracic Spine (Mid-Back)');
    if (lumbarSpine)       a.add('Lumbar Spine (Lower Back)');
    if (abdominalHernia)   a.add('Abdominal Hernia');
    if (cardiovascular)    a.add('Cardiovascular condition');
    if (respiratoryAsthma) a.add('Respiratory / Asthma');
    if (osteoarthritis)    a.add('Osteoarthritis');
    if (usesWheelchair)    a.add('Wheelchair User');
    if (usesProsthetic)    a.add('Uses Prosthesis');
    return a;
  }

  void _nextStep() {
    if (_currentStep == 0) {
      if (_weightController.text.isEmpty || _heightController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter weight and height first.')),
        );
        return;
      }
    }
    if (_currentStep < 4) {
      _fadeController.reset();
      setState(() => _currentStep++);
      _pageController.nextPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      _fadeController.forward();
    } else {
      _saveAndGenerate();
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

  Future<void> _saveAndGenerate() async {
    setState(() => _isLoading = true);
    try {
      final uid             = FirebaseAuth.instance.currentUser!.uid;
      final limitations     = _getActiveLimitations();
      final limitationsText = limitations.isEmpty ? 'None' : limitations.join(', ');
      final goal            = _customGoalController.text.trim().isNotEmpty
          ? _customGoalController.text.trim()
          : '$_selectedGoal – $_selectedSubGoal';
      final totalDays       = _daysPerWeek * _planWeeks;
      final targetStr       = _targetWeightController.text.trim().isEmpty
          ? 'Maintain current weight'
          : '${_targetWeightController.text.trim()} $_weightUnit';

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fitness_goal':  goal,
        'goal_focus':    _selectedSubGoal,
        'plan_weeks':    _planWeeks,
        'body_stats': {
          'weight':        '${_weightController.text} $_weightUnit',
          'height':        '${_heightController.text} $_heightUnit',
          'age':           _ageController.text,
          'gender':        _gender,
          'target_weight': _targetWeightController.text.trim().isEmpty
              ? null
              : '${_targetWeightController.text.trim()} $_weightUnit',
        },
        'health_insights': {
          'bmi':                double.parse(_getBMI().toStringAsFixed(1)),
          'suggested_calories': _getCalories(),
        },
        'workout_preferences': {
          'days_per_week':        _daysPerWeek,
          'duration_per_session': _workoutDuration,
          'fitness_level':        _fitnessLevel,
        },
        'biometrics': {
          'upperBody': {
            'rotatorCuff': rotatorCuff, 'deltoids': deltoids, 'pectorals': pectorals,
            'biceps': biceps, 'triceps': triceps, 'latsRhomboids': latsRhomboids,
            'elbowJoint': elbowJoint, 'wristCarpals': wristCarpals,
          },
          'lowerBody': {
            'glutesPelvis': glutesPelvis, 'quadriceps': quadriceps,
            'hamstrings': hamstrings, 'calves': calves, 'kneeMeniscus': kneeMeniscus,
            'achillesAnkle': achillesAnkle, 'plantarFoot': plantarFoot,
          },
          'coreSpine': {
            'cervicalSpine': cervicalSpine, 'thoracicSpine': thoracicSpine,
            'lumbarSpine': lumbarSpine, 'abdominalHernia': abdominalHernia,
          },
          'systemic': {
            'cardiovascular': cardiovascular, 'respiratoryAsthma': respiratoryAsthma,
            'osteoarthritis': osteoarthritis, 'wheelchair': usesWheelchair,
            'prosthesis': usesProsthetic,
          },
          'clinicalNotes': _clinicalNotesController.text,
          'noLimitations': noLimitations,
        },
        'profile_completed': true,
      }, SetOptions(merge: true));

      final prompt = '''
You are an expert physiotherapist and certified personal trainer.
Generate a complete $_planWeeks-week workout program for this user.

User Profile:
- Age: ${_ageController.text} years old
- Gender: $_gender
- Current Weight: ${_weightController.text} $_weightUnit
- Target Weight: $targetStr
- Height: ${_heightController.text} $_heightUnit
- BMI: ${_getBMI().toStringAsFixed(1)} (${_getBMICategory(_getBMI())})
- Daily Calorie Target: ${_getCalories()} kcal
- Fitness Level: $_fitnessLevel
- Primary Goal: $_selectedGoal
- Specific Focus: $_selectedSubGoal
- Custom Notes: ${_customGoalController.text.isEmpty ? 'None' : _customGoalController.text}
- Workout Days Per Week: $_daysPerWeek days
- Session Duration: $_workoutDuration per session
- Plan Duration: $_planWeeks weeks ($totalDays total sessions)
- Physical Limitations / Injuries: $limitationsText
- Clinical Notes: ${_clinicalNotesController.text.isEmpty ? 'None' : _clinicalNotesController.text}
- Uses Wheelchair: $usesWheelchair
- Uses Prosthesis: $usesProsthetic

Strict Rules:
- NEVER include exercises that stress injured areas
- Adapt ALL movements for their fitness level and limitations
- Each session must fit within $_workoutDuration
- Structure as Week 1, Week 2 etc. with Day labels inside each week
- For each exercise: name, sets, reps/duration, rest time, and why it is safe
- Add progressive overload: each week slightly harder than the last
- Include warm-up and cool-down for each day
- Reference their daily calorie target of ${_getCalories()} kcal in the nutrition section
- End with monthly milestones, recovery tips and nutrition advice for $_selectedGoal – $_selectedSubGoal
''';

      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConstants.geminiApiKey}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({'contents': [{'parts': [{'text': prompt}]}]}),
      );

      if (response.statusCode == 200) {
        final data    = jsonDecode(response.body);
        final plan    = data['candidates'][0]['content']['parts'][0]['text'] as String;
        final planRef = await FirebaseFirestore.instance
            .collection('users').doc(uid)
            .collection('workout_plans')
            .add({
          'plan':         plan,
          'goal':         '$_selectedGoal – $_selectedSubGoal',
          'fitnessLevel': _fitnessLevel,
          'daysPerWeek':  _daysPerWeek,
          'planWeeks':    _planWeeks,
          'duration':     _workoutDuration,
          'limitations':  limitationsText,
          'calories':     _getCalories(),
          'bmi':          double.parse(_getBMI().toStringAsFixed(1)),
          'createdAt':    FieldValue.serverTimestamp(),
          'expiresAt':    Timestamp.fromDate(
              DateTime.now().add(Duration(days: _planWeeks * 7))),
        });

        if (mounted) {
          Navigator.push(context, MaterialPageRoute(
            builder: (_) => WorkoutPlanScreen(
                plan: plan, planId: planRef.id, uid: uid),
          ));
        }
      } else {
        throw Exception('Gemini API error: ${response.statusCode}\n${response.body}');
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
  //  BUILD
  // ─────────────────────────────────────────────────────────────────────────

  // 5 steps now
  final List<String> _stepLabels = [
    'Body Stats', 'Insights', 'Your Goal', 'Schedule', 'Limitations'
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg,
        elevation: 0,
        leading: _currentStep > 0
            ? IconButton(
                icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
                onPressed: _prevStep)
            : IconButton(
                icon: const Icon(Icons.close, color: Colors.white70, size: 22),
                onPressed: () => Navigator.pop(context)),
        title: const Text('Build My Plan',
            style: TextStyle(
                color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
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
                _buildStep1BodyStats(),
                _buildStep2Insights(),
                _buildStep3Goal(),
                _buildStep4Schedule(),
                _buildStep5Limitations(),
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
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(
        children: List.generate(_stepLabels.length, (i) {
          final isActive = i == _currentStep;
          final isDone   = i < _currentStep;
          return Expanded(
            child: Padding(
              padding:
                  EdgeInsets.only(right: i < _stepLabels.length - 1 ? 5 : 0),
              child: Column(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  height: 3,
                  decoration: BoxDecoration(
                    color: isDone || isActive ? _orange : Colors.white12,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const SizedBox(height: 5),
                Text(_stepLabels[i],
                    style: TextStyle(
                      fontSize: 9,
                      color: isActive
                          ? _orange
                          : isDone ? Colors.white54 : Colors.white24,
                      fontWeight:
                          isActive ? FontWeight.w700 : FontWeight.w400,
                    )),
              ]),
            ),
          );
        }),
      ),
    );
  }

  // ── STEP 1: BODY STATS ────────────────────────────────────────────────────
  Widget _buildStep1BodyStats() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _stepHeader('Your Body Stats',
              'Personalise your plan with accurate data', Icons.person_outline),
          const SizedBox(height: 24),
          _label('Gender'),
          const SizedBox(height: 8),
          Row(
            children: ['Male', 'Female', 'Other'].map((g) {
              final sel = _gender == g;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _gender = g),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: sel ? _orange : _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: sel ? _orange : Colors.white12),
                    ),
                    child: Text(g,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: sel ? Colors.white : Colors.white54,
                          fontWeight: sel ? FontWeight.w700 : FontWeight.w400,
                          fontSize: 14,
                        )),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          _label('Age'),
          const SizedBox(height: 8),
          _field(
              controller: _ageController,
              hint: 'e.g. 25',
              suffix: 'years',
              keyboard: TextInputType.number),
          const SizedBox(height: 20),
          _label('Current Weight'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _field(
                    controller: _weightController,
                    hint: 'e.g. 70',
                    keyboard: TextInputType.number)),
            const SizedBox(width: 12),
            _unitToggle(['kg', 'lbs'], _weightUnit,
                (v) => setState(() => _weightUnit = v)),
          ]),
          const SizedBox(height: 20),
          _label('Height'),
          const SizedBox(height: 8),
          Row(children: [
            Expanded(
                child: _field(
                    controller: _heightController,
                    hint: _heightUnit == 'cm' ? 'e.g. 170' : 'e.g. 68',
                    keyboard: TextInputType.number)),
            const SizedBox(width: 12),
            _unitToggle(['cm', 'ft'], _heightUnit,
                (v) => setState(() => _heightUnit = v)),
          ]),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── STEP 2: INSIGHTS & TARGET (friend's step) ────────────────────────────
  Widget _buildStep2Insights() {
    final bmi         = _getBMI();
    final bmiCategory = _getBMICategory(bmi);
    final bmiColor    = _getBMIColor(bmi);
    final calories    = _getCalories();

    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _stepHeader('Your Body Insights',
              'BMI and estimated daily calorie goal', Icons.insights_outlined),
          const SizedBox(height: 24),

          // BMI Card
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white10),
            ),
            child: Row(children: [
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  const Text('Your BMI',
                      style: TextStyle(
                          color: Colors.white54,
                          fontSize: 13,
                          fontWeight: FontWeight.w600)),
                  const SizedBox(height: 4),
                  Text(
                    bmi > 0 ? bmi.toStringAsFixed(1) : '--',
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 36,
                        fontWeight: FontWeight.bold),
                  ),
                ]),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                  color: bmiColor.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: bmiColor),
                ),
                child: Text(bmiCategory,
                    style: TextStyle(
                        color: bmiColor,
                        fontWeight: FontWeight.bold,
                        fontSize: 14)),
              ),
            ]),
          ),

          const SizedBox(height: 20),
          _label('Target Weight (optional)'),
          const SizedBox(height: 4),
          const Text('Leave blank to maintain current weight',
              style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 8),
          _field(
              controller: _targetWeightController,
              hint: 'e.g. 65',
              suffix: _weightUnit,
              keyboard: TextInputType.number),
          const SizedBox(height: 24),

          // Calories Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              color: _surface,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: _orange.withOpacity(0.4)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.local_fire_department, color: _orange, size: 20),
                const SizedBox(width: 8),
                const Text('Recommended Daily Intake',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(
                  calories > 0 ? '$calories' : '--',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 38,
                      fontWeight: FontWeight.bold,
                      height: 1),
                ),
                const SizedBox(width: 6),
                const Padding(
                  padding: EdgeInsets.only(bottom: 4),
                  child: Text('kcal / day',
                      style: TextStyle(color: Colors.white54, fontSize: 14)),
                ),
              ]),
              const SizedBox(height: 8),
              const Text(
                  'Calculated via Mifflin-St Jeor, adjusted for your target.',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── STEP 3: GOAL + SUB-OPTIONS + DURATION ────────────────────────────────
  Widget _buildStep3Goal() {
    final goalData    = _currentGoalData;
    final subOptions  = (goalData['subOptions'] as List).cast<Map<String, dynamic>>();
    final accentColor = goalData['color'] as Color;

    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _stepHeader("What's Your Goal?",
              'Pick your focus and a specific training style', Icons.flag_outlined),
          const SizedBox(height: 20),

          // Goal grid
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            crossAxisSpacing: 10,
            mainAxisSpacing: 10,
            childAspectRatio: 1.6,
            children: _goals.map((g) {
              final sel   = _selectedGoal == g['label'];
              final color = g['color'] as Color;
              return GestureDetector(
                onTap: () => setState(() {
                  _selectedGoal    = g['label'] as String;
                  _selectedSubGoal = ((g['subOptions'] as List)
                      .cast<Map<String, dynamic>>())[0]['label'] as String;
                }),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: sel ? color.withOpacity(0.18) : _surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                        color: sel ? color : Colors.white12,
                        width: sel ? 2 : 1),
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Icon(g['icon'] as IconData,
                            color: sel ? color : Colors.white38, size: 22),
                        Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(g['label'] as String,
                                  style: TextStyle(
                                      color: sel ? Colors.white : Colors.white70,
                                      fontWeight: FontWeight.w700,
                                      fontSize: 12)),
                              Text(g['desc'] as String,
                                  style: TextStyle(
                                      color: sel
                                          ? color.withOpacity(0.8)
                                          : Colors.white38,
                                      fontSize: 10)),
                            ]),
                      ]),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 20),

          // Sub-options panel
          AnimatedContainer(
            duration: const Duration(milliseconds: 300),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: accentColor.withOpacity(0.07),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: accentColor.withOpacity(0.3)),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                Icon(goalData['icon'] as IconData, color: accentColor, size: 16),
                const SizedBox(width: 8),
                Text('$_selectedGoal — Choose your focus',
                    style: TextStyle(
                        color: accentColor,
                        fontWeight: FontWeight.w700,
                        fontSize: 13)),
              ]),
              const SizedBox(height: 12),
              ...subOptions.map((sub) {
                final sel = _selectedSubGoal == sub['label'];
                return GestureDetector(
                  onTap: () =>
                      setState(() => _selectedSubGoal = sub['label'] as String),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 180),
                    margin: const EdgeInsets.only(bottom: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 11),
                    decoration: BoxDecoration(
                      color: sel
                          ? accentColor.withOpacity(0.2)
                          : const Color(0xFF0F1624),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                          color: sel ? accentColor : Colors.white12,
                          width: sel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? accentColor : Colors.transparent,
                          border: Border.all(
                              color: sel ? accentColor : Colors.white30,
                              width: 2),
                        ),
                        child: sel
                            ? const Icon(Icons.check,
                                size: 11, color: Colors.white)
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                            Text(sub['label'] as String,
                                style: TextStyle(
                                  color: sel ? Colors.white : Colors.white70,
                                  fontWeight: sel
                                      ? FontWeight.w700
                                      : FontWeight.w500,
                                  fontSize: 13,
                                )),
                            Text(sub['desc'] as String,
                                style: TextStyle(
                                  color: sel
                                      ? accentColor.withOpacity(0.8)
                                      : Colors.white38,
                                  fontSize: 11,
                                )),
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
          Row(
            children: [1, 2, 3, 4].map((weeks) {
              final sel = _planWeeks == weeks;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _planWeeks = weeks),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: sel ? _orange : _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: sel ? _orange : Colors.white12),
                    ),
                    child: Column(children: [
                      Text('$weeks',
                          style: TextStyle(
                            color: sel ? Colors.white : Colors.white54,
                            fontWeight: FontWeight.w800,
                            fontSize: 18,
                          )),
                      Text(weeks == 1 ? 'week' : 'weeks',
                          style: TextStyle(
                            color: sel ? Colors.white70 : Colors.white24,
                            fontSize: 10,
                          )),
                    ]),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 8),
          Center(
            child: Text(
              '$_planWeeks-week plan · ${_daysPerWeek * _planWeeks} total sessions',
              style: const TextStyle(
                  color: _orange, fontSize: 12, fontWeight: FontWeight.w600),
            ),
          ),
          const SizedBox(height: 20),
          _label('Additional context (optional)'),
          const SizedBox(height: 8),
          _field(
              controller: _customGoalController,
              hint: 'e.g. Preparing for a competition in 3 weeks...',
              maxLines: 2),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── STEP 4: SCHEDULE ──────────────────────────────────────────────────────
  Widget _buildStep4Schedule() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _stepHeader('Your Schedule',
              'How often and how long do you want to train?',
              Icons.calendar_today_outlined),
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
                    color: sel ? _orange : _surface,
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: sel ? _orange : Colors.white12),
                  ),
                  child: Center(
                      child: Text('$day',
                          style: TextStyle(
                              color: sel ? Colors.white : Colors.white54,
                              fontWeight: FontWeight.w700,
                              fontSize: 16))),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Center(
              child: Text(
            '$_daysPerWeek ${_daysPerWeek == 1 ? 'day' : 'days'}/week · '
            '${_daysPerWeek * _planWeeks} sessions over $_planWeeks weeks',
            style: const TextStyle(
                color: _orange, fontSize: 13, fontWeight: FontWeight.w600),
          )),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? _orange : _surface,
                    borderRadius: BorderRadius.circular(20),
                    border:
                        Border.all(color: sel ? _orange : Colors.white12),
                  ),
                  child: Text(d,
                      style: TextStyle(
                          color: sel ? Colors.white : Colors.white54,
                          fontWeight:
                              sel ? FontWeight.w700 : FontWeight.w400,
                          fontSize: 13)),
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
              // Keep friend's color scheme for levels
              final c = level == 'Beginner'
                  ? _voltGreen
                  : level == 'Intermediate'
                      ? _orange
                      : const Color(0xFFFF3B30);
              final textColor = sel
                  ? (level == 'Beginner' ? Colors.black : Colors.white)
                  : Colors.white54;
              return Expanded(
                child: GestureDetector(
                  onTap: () => setState(() => _fitnessLevel = level),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    decoration: BoxDecoration(
                      color: sel ? c : _surface,
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                          color: sel ? c : Colors.white12,
                          width: sel ? 2 : 1),
                    ),
                    child: Text(level,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                            color: textColor,
                            fontWeight: sel
                                ? FontWeight.w700
                                : FontWeight.w400,
                            fontSize: 13)),
                  ),
                ),
              );
            }).toList(),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── STEP 5: LIMITATIONS ───────────────────────────────────────────────────
  Widget _buildStep5Limitations() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _stepHeader('Physical Limitations',
              'Our AI strictly avoids exercises that may re-injure you',
              Icons.medical_information_outlined),
          const SizedBox(height: 16),
          GestureDetector(
            onTap: () => setState(() {
              noLimitations = !noLimitations;
              if (noLimitations) {
                rotatorCuff = deltoids = pectorals = biceps = triceps =
                    latsRhomboids = elbowJoint = wristCarpals =
                        glutesPelvis = quadriceps = hamstrings = calves =
                            kneeMeniscus = achillesAnkle = plantarFoot =
                                cervicalSpine = thoracicSpine = lumbarSpine =
                                    abdominalHernia = cardiovascular =
                                        respiratoryAsthma = osteoarthritis =
                                            usesWheelchair =
                                                usesProsthetic = false;
              }
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: noLimitations
                    ? _voltGreen.withOpacity(0.15)
                    : _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(
                    color: noLimitations ? _voltGreen : Colors.white12,
                    width: noLimitations ? 2 : 1),
              ),
              child: Row(children: [
                Icon(
                    noLimitations
                        ? Icons.check_circle
                        : Icons.check_circle_outline,
                    color:
                        noLimitations ? _voltGreen : Colors.white38,
                    size: 22),
                const SizedBox(width: 12),
                const Expanded(
                    child: Text("No physical limitations — I'm fully healthy",
                        style: TextStyle(
                            color: Colors.white70,
                            fontSize: 14,
                            fontWeight: FontWeight.w500))),
              ]),
            ),
          ),
          if (!noLimitations) ...[
            const SizedBox(height: 20),
            _limitSection('Upper Body', [
              ['Rotator Cuff / Shoulder', rotatorCuff,     (v) => setState(() => rotatorCuff     = v!)],
              ['Deltoids',                deltoids,         (v) => setState(() => deltoids         = v!)],
              ['Pectorals (Chest)',        pectorals,        (v) => setState(() => pectorals        = v!)],
              ['Biceps Brachii',           biceps,           (v) => setState(() => biceps           = v!)],
              ['Triceps Brachii',          triceps,          (v) => setState(() => triceps          = v!)],
              ['Lats / Rhomboids',         latsRhomboids,    (v) => setState(() => latsRhomboids    = v!)],
              ['Elbow Joint',              elbowJoint,       (v) => setState(() => elbowJoint       = v!)],
              ['Wrist / Carpals',          wristCarpals,     (v) => setState(() => wristCarpals     = v!)],
            ]),
            const SizedBox(height: 12),
            _limitSection('Lower Body', [
              ['Glutes / Pelvis',         glutesPelvis,     (v) => setState(() => glutesPelvis     = v!)],
              ['Quadriceps',              quadriceps,       (v) => setState(() => quadriceps       = v!)],
              ['Hamstrings',              hamstrings,       (v) => setState(() => hamstrings       = v!)],
              ['Calves / Gastrocnemius',  calves,           (v) => setState(() => calves           = v!)],
              ['Knee / Meniscus',         kneeMeniscus,     (v) => setState(() => kneeMeniscus     = v!)],
              ['Achilles / Ankle',        achillesAnkle,    (v) => setState(() => achillesAnkle    = v!)],
              ['Plantar / Foot',          plantarFoot,      (v) => setState(() => plantarFoot      = v!)],
            ]),
            const SizedBox(height: 12),
            _limitSection('Spine & Core', [
              ['Cervical (Neck)',          cervicalSpine,    (v) => setState(() => cervicalSpine    = v!)],
              ['Thoracic (Mid-Back)',      thoracicSpine,    (v) => setState(() => thoracicSpine    = v!)],
              ['Lumbar (Lower Back)',      lumbarSpine,      (v) => setState(() => lumbarSpine      = v!)],
              ['Abdominal / Hernia',       abdominalHernia,  (v) => setState(() => abdominalHernia  = v!)],
            ]),
            const SizedBox(height: 12),
            _limitSection('Systemic & Mobility', [
              ['Cardiovascular',           cardiovascular,    (v) => setState(() => cardiovascular    = v!)],
              ['Respiratory / Asthma',     respiratoryAsthma, (v) => setState(() => respiratoryAsthma = v!)],
              ['Osteoarthritis',           osteoarthritis,    (v) => setState(() => osteoarthritis    = v!)],
            ]),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                  color: _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12)),
              child: Column(children: [
                _switchRow('Wheelchair User', usesWheelchair,
                    (v) => setState(() => usesWheelchair = v)),
                const Divider(color: Colors.white12, height: 16),
                _switchRow('Uses Prosthesis', usesProsthetic,
                    (v) => setState(() => usesProsthetic = v)),
              ]),
            ),
            const SizedBox(height: 16),
            _label('Additional Notes (optional)'),
            const SizedBox(height: 8),
            _field(
                controller: _clinicalNotesController,
                hint: 'e.g. Post-op knee, cleared for light activity only...',
                maxLines: 3),
          ],
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── BOTTOM BUTTON ─────────────────────────────────────────────────────────
  Widget _buildBottomButton() {
    final isLast = _currentStep == 4;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(
        color: _bg,
        border:
            Border(top: BorderSide(color: Colors.white.withOpacity(0.06))),
      ),
      child: SizedBox(
        width: double.infinity,
        height: 54,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: _orange,
            disabledBackgroundColor: Colors.white12,
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14)),
            elevation: 0,
          ),
          child: _isLoading
              ? const SizedBox(
                  height: 22,
                  width: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
              : Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                        isLast ? 'Generate My Plan 🚀' : 'Continue',
                        style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.w700,
                            color: Colors.white,
                            letterSpacing: 0.3)),
                    if (!isLast) ...[
                      const SizedBox(width: 8),
                      const Icon(Icons.arrow_forward,
                          color: Colors.white, size: 18),
                    ],
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
        decoration: BoxDecoration(
            color: _orange.withOpacity(0.15),
            borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: _orange, size: 24),
      ),
      const SizedBox(height: 12),
      Text(title,
          style: const TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.3)),
      const SizedBox(height: 4),
      Text(subtitle,
          style: const TextStyle(color: Colors.white54, fontSize: 13)),
    ]);
  }

  Widget _label(String text) => Text(text,
      style: const TextStyle(
          color: Colors.white70,
          fontSize: 13,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.3));

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
        fillColor: _surface,
        border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: const BorderSide(color: _orange, width: 1.5)),
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }

  Widget _unitToggle(
      List<String> options, String selected, Function(String) onSelect) {
    return Container(
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.white12)),
      child: Row(
        children: options.map((opt) {
          final sel = selected == opt;
          return GestureDetector(
            onTap: () => onSelect(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding:
                  const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(
                  color: sel ? _orange : Colors.transparent,
                  borderRadius: BorderRadius.circular(9)),
              child: Text(opt,
                  style: TextStyle(
                      color: sel ? Colors.white : Colors.white38,
                      fontWeight:
                          sel ? FontWeight.w700 : FontWeight.w400,
                      fontSize: 13)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _limitSection(String title, List<List<dynamic>> items) {
    return Container(
      decoration: BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
          child: Text(title,
              style: const TextStyle(
                  color: _orange,
                  fontWeight: FontWeight.w700,
                  fontSize: 13,
                  letterSpacing: 0.5)),
        ),
        const Divider(color: Colors.white12, height: 1),
        ...items.map((item) => _checkRow(
            item[0] as String, item[1] as bool, item[2] as Function(bool?))),
      ]),
    );
  }

  Widget _checkRow(
      String title, bool value, Function(bool?) onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: value ? _orange : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(
                  color: value ? _orange : Colors.white30, width: 2),
            ),
            child: value
                ? const Icon(Icons.check, size: 14, color: Colors.white)
                : null,
          ),
          const SizedBox(width: 12),
          Text(title,
              style: TextStyle(
                  color: value ? Colors.white : Colors.white60,
                  fontSize: 13,
                  fontWeight:
                      value ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }

  Widget _switchRow(
      String title, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title,
            style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Switch(
            value: value,
            onChanged: onChanged,
            activeColor: _orange,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ],
    );
  }
}