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

  // ── Animation — single controller, always valid ──────────────────────────
  late final AnimationController _fadeController = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  // Derived non-null animation
  late final Animation<double> _fadeAnim = CurvedAnimation(
    parent: _fadeController,
    curve: Curves.easeInOut,
  );

  // ── STEP 1: Body Stats ───────────────────────────────────────────────────
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _ageController = TextEditingController();
  String _gender = 'Male';
  String _weightUnit = 'kg';
  String _heightUnit = 'cm';

  // ── STEP 2: Fitness Goal ─────────────────────────────────────────────────
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

  // ── STEP 3: Schedule ─────────────────────────────────────────────────────
  int _daysPerWeek = 3;
  String _workoutDuration = '45 mins';
  String _fitnessLevel = 'Beginner';
  final List<String> _durations = ['20 mins', '30 mins', '45 mins', '60 mins', '90 mins'];
  final List<String> _levels = ['Beginner', 'Intermediate', 'Advanced'];

  // ── STEP 4: Limitations ──────────────────────────────────────────────────
  bool rotatorCuff = false;
  bool deltoids = false;
  bool pectorals = false;
  bool biceps = false;
  bool triceps = false;
  bool latsRhomboids = false;
  bool elbowJoint = false;
  bool wristCarpals = false;
  bool glutesPelvis = false;
  bool quadriceps = false;
  bool hamstrings = false;
  bool calves = false;
  bool kneeMeniscus = false;
  bool achillesAnkle = false;
  bool plantarFoot = false;
  bool cervicalSpine = false;
  bool thoracicSpine = false;
  bool lumbarSpine = false;
  bool abdominalHernia = false;
  bool cardiovascular = false;
  bool respiratoryAsthma = false;
  bool osteoarthritis = false;
  bool usesWheelchair = false;
  bool usesProsthetic = false;
  bool noLimitations = false;
  final _clinicalNotesController = TextEditingController();

  @override
  void initState() {
    super.initState();
    _fadeController.forward();
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _ageController.dispose();
    _customGoalController.dispose();
    _clinicalNotesController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────

  List<String> _getActiveLimitations() {
    if (noLimitations) return [];
    final List<String> active = [];
    if (rotatorCuff)      active.add('Rotator Cuff / Shoulder');
    if (deltoids)         active.add('Deltoids');
    if (pectorals)        active.add('Pectorals');
    if (biceps)           active.add('Biceps');
    if (triceps)          active.add('Triceps');
    if (latsRhomboids)    active.add('Lats / Rhomboids');
    if (elbowJoint)       active.add('Elbow Joint');
    if (wristCarpals)     active.add('Wrist / Carpals');
    if (glutesPelvis)     active.add('Glutes / Pelvis');
    if (quadriceps)       active.add('Quadriceps');
    if (hamstrings)       active.add('Hamstrings');
    if (calves)           active.add('Calves');
    if (kneeMeniscus)     active.add('Knee / Meniscus');
    if (achillesAnkle)    active.add('Achilles / Ankle');
    if (plantarFoot)      active.add('Plantar / Foot');
    if (cervicalSpine)    active.add('Cervical Spine (Neck)');
    if (thoracicSpine)    active.add('Thoracic Spine (Mid-Back)');
    if (lumbarSpine)      active.add('Lumbar Spine (Lower Back)');
    if (abdominalHernia)  active.add('Abdominal Hernia');
    if (cardiovascular)   active.add('Cardiovascular condition');
    if (respiratoryAsthma)active.add('Respiratory / Asthma');
    if (osteoarthritis)   active.add('Osteoarthritis');
    if (usesWheelchair)   active.add('Wheelchair User');
    if (usesProsthetic)   active.add('Uses Prosthesis');
    return active;
  }

  void _nextStep() {
    if (_currentStep < 3) {
      _fadeController.reset();
      setState(() => _currentStep++);
      _pageController.nextPage(duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      _fadeController.forward();
    } else {
      _saveAndGenerate();
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

  Future<void> _saveAndGenerate() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final limitations = _getActiveLimitations();
      final limitationsText = limitations.isEmpty ? 'None' : limitations.join(', ');
      final goal = _customGoalController.text.trim().isNotEmpty
          ? _customGoalController.text.trim()
          : _selectedGoal;

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fitness_goal': goal,
        'body_stats': {
          'weight': '${_weightController.text} $_weightUnit',
          'height': '${_heightController.text} $_heightUnit',
          'age': _ageController.text,
          'gender': _gender,
        },
        'workout_preferences': {
          'days_per_week': _daysPerWeek,
          'duration_per_session': _workoutDuration,
          'fitness_level': _fitnessLevel,
        },
        'biometrics': {
          'upperBody': {
            'rotatorCuff': rotatorCuff, 'deltoids': deltoids, 'pectorals': pectorals,
            'biceps': biceps, 'triceps': triceps, 'latsRhomboids': latsRhomboids,
            'elbowJoint': elbowJoint, 'wristCarpals': wristCarpals,
          },
          'lowerBody': {
            'glutesPelvis': glutesPelvis, 'quadriceps': quadriceps, 'hamstrings': hamstrings,
            'calves': calves, 'kneeMeniscus': kneeMeniscus, 'achillesAnkle': achillesAnkle,
            'plantarFoot': plantarFoot,
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
Generate a detailed, safe $_daysPerWeek-day workout plan for this user.

User Profile:
- Age: ${_ageController.text} years old
- Gender: $_gender
- Weight: ${_weightController.text} $_weightUnit
- Height: ${_heightController.text} $_heightUnit
- Fitness Level: $_fitnessLevel
- Fitness Goal: $goal
- Workout Days Per Week: $_daysPerWeek days
- Session Duration: $_workoutDuration per session
- Physical Limitations / Injuries: $limitationsText
- Clinical Notes: ${_clinicalNotesController.text.isEmpty ? 'None' : _clinicalNotesController.text}
- Uses Wheelchair: $usesWheelchair
- Uses Prosthesis: $usesProsthetic

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

      print('KEY LENGTH: ${AppConstants.geminiApiKey.length}');

      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConstants.geminiApiKey}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{'parts': [{'text': prompt}]}],
        }),
      );

      print('STATUS: ${response.statusCode}');

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final plan = data['candidates'][0]['content']['parts'][0]['text'];
        if (mounted) {
          Navigator.push(context, MaterialPageRoute(builder: (_) => WorkoutPlanScreen(plan: plan)));
        }
      } else {
        print('BODY: ${response.body}');
        throw Exception('Gemini API error: ${response.statusCode}');
      }
    } catch (e) {
      print('ERROR: $e');
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

  final List<String> _stepLabels = ['Body Stats', 'Your Goal', 'Schedule', 'Limitations'];

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
        title: const Text('Build My Plan',
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
                _buildStep3(),
                _buildStep4(),
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

  // ── STEP 1: BODY STATS ────────────────────────────────────────────────────
  Widget _buildStep1() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _stepHeader('Your Body Stats', 'Personalise your plan with accurate data', Icons.person_outline),
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
                        color: sel ? const Color(0xFFFF5E00) : const Color(0xFF1A1A1A), // Electric Orange / Dark Surface
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: sel ? const Color(0xFFFF5E00) : Colors.white12),
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
            _field(controller: _ageController, hint: 'e.g. 25', suffix: 'years', keyboard: TextInputType.number),
            const SizedBox(height: 20),
            _label('Body Weight'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _field(controller: _weightController, hint: 'e.g. 70', keyboard: TextInputType.number)),
              const SizedBox(width: 12),
              _unitToggle(['kg', 'lbs'], _weightUnit, (v) => setState(() => _weightUnit = v)),
            ]),
            const SizedBox(height: 20),
            _label('Height'),
            const SizedBox(height: 8),
            Row(children: [
              Expanded(child: _field(controller: _heightController, hint: _heightUnit == 'cm' ? 'e.g. 170' : 'e.g. 68', keyboard: TextInputType.number)),
              const SizedBox(width: 12),
              _unitToggle(['cm', 'ft'], _heightUnit, (v) => setState(() => _heightUnit = v)),
            ]),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── STEP 2: GOAL ──────────────────────────────────────────────────────────
  Widget _buildStep2() {
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

  // ── STEP 3: SCHEDULE ──────────────────────────────────────────────────────
  Widget _buildStep3() {
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

  // ── STEP 4: LIMITATIONS ───────────────────────────────────────────────────
  Widget _buildStep4() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _stepHeader('Physical Limitations', 'Our AI strictly avoids exercises that may re-injure you', Icons.medical_information_outlined),
            const SizedBox(height: 16),

            // No limitations shortcut
            GestureDetector(
              onTap: () => setState(() {
                noLimitations = !noLimitations;
                if (noLimitations) {
                  rotatorCuff = deltoids = pectorals = biceps = triceps =
                      latsRhomboids = elbowJoint = wristCarpals = glutesPelvis =
                          quadriceps = hamstrings = calves = kneeMeniscus =
                              achillesAnkle = plantarFoot = cervicalSpine =
                                  thoracicSpine = lumbarSpine = abdominalHernia =
                                      cardiovascular = respiratoryAsthma =
                                          osteoarthritis = usesWheelchair = usesProsthetic = false;
                }
              }),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  // Solid Volt Green to indicate clear/healthy state
                  color: noLimitations ? const Color(0xFFB9FF2B) : const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: noLimitations ? const Color(0xFFB9FF2B) : Colors.white12, width: noLimitations ? 2 : 1),
                ),
                child: Row(children: [
                  Icon(noLimitations ? Icons.check_circle : Icons.check_circle_outline,
                      color: noLimitations ? Colors.black : Colors.white38, size: 22),
                  const SizedBox(width: 12),
                  Expanded(child: Text("No physical limitations — I'm fully healthy",
                      style: TextStyle(color: noLimitations ? Colors.black : Colors.white70, fontSize: 14, fontWeight: FontWeight.w600))),
                ]),
              ),
            ),

            if (!noLimitations) ...[
              const SizedBox(height: 20),
              _limitSection('Upper Body', [
                ['Rotator Cuff / Shoulder', rotatorCuff,   (v) => setState(() => rotatorCuff   = v!)],
                ['Deltoids',                deltoids,       (v) => setState(() => deltoids       = v!)],
                ['Pectorals (Chest)',        pectorals,      (v) => setState(() => pectorals      = v!)],
                ['Biceps Brachii',           biceps,         (v) => setState(() => biceps         = v!)],
                ['Triceps Brachii',          triceps,        (v) => setState(() => triceps        = v!)],
                ['Lats / Rhomboids',         latsRhomboids,  (v) => setState(() => latsRhomboids  = v!)],
                ['Elbow Joint',              elbowJoint,     (v) => setState(() => elbowJoint     = v!)],
                ['Wrist / Carpals',          wristCarpals,   (v) => setState(() => wristCarpals   = v!)],
              ]),
              const SizedBox(height: 12),
              _limitSection('Lower Body', [
                ['Glutes / Pelvis',          glutesPelvis,   (v) => setState(() => glutesPelvis   = v!)],
                ['Quadriceps',               quadriceps,     (v) => setState(() => quadriceps     = v!)],
                ['Hamstrings',               hamstrings,     (v) => setState(() => hamstrings     = v!)],
                ['Calves / Gastrocnemius',   calves,         (v) => setState(() => calves         = v!)],
                ['Knee / Meniscus',          kneeMeniscus,   (v) => setState(() => kneeMeniscus   = v!)],
                ['Achilles / Ankle',         achillesAnkle,  (v) => setState(() => achillesAnkle  = v!)],
                ['Plantar / Foot',           plantarFoot,    (v) => setState(() => plantarFoot    = v!)],
              ]),
              const SizedBox(height: 12),
              _limitSection('Spine & Core', [
                ['Cervical (Neck)',           cervicalSpine,  (v) => setState(() => cervicalSpine  = v!)],
                ['Thoracic (Mid-Back)',       thoracicSpine,  (v) => setState(() => thoracicSpine  = v!)],
                ['Lumbar (Lower Back)',       lumbarSpine,    (v) => setState(() => lumbarSpine    = v!)],
                ['Abdominal / Hernia',        abdominalHernia,(v) => setState(() => abdominalHernia= v!)],
              ]),
              const SizedBox(height: 12),
              _limitSection('Systemic & Mobility', [
                ['Cardiovascular',            cardiovascular,    (v) => setState(() => cardiovascular    = v!)],
                ['Respiratory / Asthma',      respiratoryAsthma, (v) => setState(() => respiratoryAsthma = v!)],
                ['Osteoarthritis',            osteoarthritis,    (v) => setState(() => osteoarthritis    = v!)],
              ]),
              const SizedBox(height: 12),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
                child: Column(children: [
                  _switchRow('Wheelchair User', usesWheelchair, (v) => setState(() => usesWheelchair = v)),
                  const Divider(color: Colors.white12, height: 16),
                  _switchRow('Uses Prosthesis', usesProsthetic, (v) => setState(() => usesProsthetic = v)),
                ]),
              ),
              const SizedBox(height: 16),
              _label('Additional Notes (optional)'),
              const SizedBox(height: 8),
              _field(controller: _clinicalNotesController, hint: 'e.g. Post-op knee, cleared for light activity only...', maxLines: 3),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── BOTTOM BUTTON ─────────────────────────────────────────────────────────
  Widget _buildBottomButton() {
    final isLast = _currentStep == 3;
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
                    Text(isLast ? 'Generate My Plan 🚀' : 'Continue',
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

  Widget _unitToggle(List<String> options, String selected, Function(String) onSelect) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
      child: Row(
        children: options.map((opt) {
          final sel = selected == opt;
          return GestureDetector(
            onTap: () => onSelect(opt),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 200),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
              decoration: BoxDecoration(color: sel ? const Color(0xFFFF5E00) : Colors.transparent, borderRadius: BorderRadius.circular(9)),
              child: Text(opt, style: TextStyle(color: sel ? Colors.white : Colors.white38, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
            ),
          );
        }).toList(),
      ),
    );
  }

  Widget _limitSection(String title, List<List<dynamic>> items) {
    return Container(
      decoration: BoxDecoration(color: const Color(0xFF1A1A1A), borderRadius: BorderRadius.circular(12), border: Border.all(color: Colors.white12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 8),
            child: Text(title, style: const TextStyle(color: Color(0xFFFF5E00), fontWeight: FontWeight.w700, fontSize: 13, letterSpacing: 0.5)),
          ),
          const Divider(color: Colors.white12, height: 1),
          ...items.map((item) => _checkRow(item[0] as String, item[1] as bool, item[2] as Function(bool?))),
        ],
      ),
    );
  }

  Widget _checkRow(String title, bool value, Function(bool?) onChanged) {
    return InkWell(
      onTap: () => onChanged(!value),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            width: 20, height: 20,
            decoration: BoxDecoration(
              color: value ? const Color(0xFFFF5E00) : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: value ? const Color(0xFFFF5E00) : Colors.white30, width: 2),
            ),
            child: value ? const Icon(Icons.check, size: 14, color: Colors.white) : null,
          ),
          const SizedBox(width: 12),
          Text(title, style: TextStyle(color: value ? Colors.white : Colors.white60, fontSize: 13, fontWeight: value ? FontWeight.w600 : FontWeight.w400)),
        ]),
      ),
    );
  }

  Widget _switchRow(String title, bool value, Function(bool) onChanged) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text(title, style: const TextStyle(color: Colors.white70, fontSize: 13)),
        Switch(value: value, onChanged: onChanged, activeColor: const Color(0xFFFF5E00), materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
      ],
    );
  }
}