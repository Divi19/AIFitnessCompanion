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
  final _ageController = TextEditingController();
  String _gender = 'Male';
  String _weightUnit = 'kg';
  String _heightUnit = 'cm';

  // ── STEP 2: Insights & Targets (NEW) ─────────────────────────────────────
  final _targetWeightController = TextEditingController();

  // ── STEP 3: Limitations ──────────────────────────────────────────────────
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
    
    // Listen to target weight changes to update the calorie recommendation live
    _targetWeightController.addListener(() {
      setState(() {}); 
    });
  }

  @override
  void dispose() {
    _fadeController.dispose();
    _pageController.dispose();
    _weightController.dispose();
    _heightController.dispose();
    _ageController.dispose();
    _targetWeightController.dispose();
    _clinicalNotesController.dispose();
    super.dispose();
  }

  // ── MATH & CALCULATION HELPERS ───────────────────────────────────────────
  
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
    final m = _getCm() / 100;
    if (m <= 0 || kg <= 0) return 0.0;
    return kg / (m * m);
  }

  String _getBMICategory(double bmi) {
    if (bmi == 0) return 'Unknown';
    if (bmi < 18.5) return 'Underweight';
    if (bmi >= 18.5 && bmi <= 24.9) return 'Healthy';
    if (bmi >= 25 && bmi <= 29.9) return 'Overweight';
    return 'Obese';
  }

  Color _getBMIColor(double bmi) {
    if (bmi == 0) return Colors.grey;
    if (bmi < 18.5) return const Color(0xFFFFCC00); // Yellow
    if (bmi >= 18.5 && bmi <= 24.9) return const Color(0xFFB9FF2B); // Volt Green
    if (bmi >= 25 && bmi <= 29.9) return const Color(0xFFFF5E00); // Orange
    return Colors.redAccent;
  }

  int _getCalories() {
    final kg = _getKg();
    final cm = _getCm();
    final age = int.tryParse(_ageController.text) ?? 25;
    if (kg <= 0 || cm <= 0) return 0;

    // Mifflin-St Jeor Equation for BMR
    double bmr = (10 * kg) + (6.25 * cm) - (5 * age);
    bmr += (_gender == 'Male') ? 5 : -161;

    // Assume lightly active multiplier for baseline TDEE
    double tdee = bmr * 1.375;

    final target = double.tryParse(_targetWeightController.text);
    if (target != null && target > 0) {
      final targetKg = _weightUnit == 'lbs' ? target * 0.453592 : target;
      // If they want to lose weight (deficit)
      if (targetKg < kg - 1) return (tdee - 500).round(); 
      // If they want to gain muscle (surplus)
      if (targetKg > kg + 1) return (tdee + 300).round(); 
    }
    // Maintenance
    return tdee.round(); 
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
    if (_currentStep == 0) {
      // Basic validation before going to math screen
      if (_weightController.text.isEmpty || _heightController.text.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter weight and height first.')),
        );
        return;
      }
    }

    if (_currentStep < 2) { // 3 steps total now (0, 1, 2)
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
      final targetWeightStr = _targetWeightController.text.trim();
      final targetStr = targetWeightStr.isEmpty ? 'Maintain weight' : '$targetWeightStr $_weightUnit';

      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'body_stats': {
          'weight': '${_weightController.text} $_weightUnit',
          'height': '${_heightController.text} $_heightUnit',
          'age': _ageController.text,
          'gender': _gender,
          'target_weight': targetWeightStr.isEmpty ? null : targetWeightStr,
        },
        'health_insights': {
          'bmi': double.parse(_getBMI().toStringAsFixed(1)),
          'suggested_calories': _getCalories(),
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
Generate a detailed, safe general workout plan for this user.

User Profile:
- Age: ${_ageController.text} years old
- Gender: $_gender
- Current Weight: ${_weightController.text} $_weightUnit
- Target Weight: $targetStr
- Height: ${_heightController.text} $_heightUnit
- Calculated BMI: ${_getBMI().toStringAsFixed(1)}
- Daily Calorie Target: ${_getCalories()} kcal
- Physical Limitations / Injuries: $limitationsText
- Clinical Notes: ${_clinicalNotesController.text.isEmpty ? 'None' : _clinicalNotesController.text}
- Uses Wheelchair: $usesWheelchair
- Uses Prosthesis: $usesProsthetic

Strict Rules:
- NEVER include any exercise that involves or stresses the injured areas
- Adapt ALL movements to their physical limitations and fitness level
- For each exercise include: name, sets, reps/duration, rest time, and WHY it is safe
- If wheelchair user, only include seated or upper body exercises
- Include warm-up and cool-down for each day
- End with weekly recovery tips
''';

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

  final List<String> _stepLabels = ['Body Stats', 'Insights', 'Limitations'];

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
                _buildStep2(), // NEW: Insights & Target
                _buildStep3(), // WAS: Limitations
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
                        color: sel ? const Color(0xFFFF5E00) : const Color(0xFF1A1A1A), 
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
            _label('Current Weight'),
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

  // ── STEP 2: INSIGHTS & TARGET (NEW) ──────────────────────────────────────
  Widget _buildStep2() {
    final bmi = _getBMI();
    final bmiCategory = _getBMICategory(bmi);
    final bmiColor = _getBMIColor(bmi);
    final calories = _getCalories();

    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 8),
            _stepHeader('Insights & Target', 'Your body metrics and daily energy goal', Icons.insights),
            const SizedBox(height: 24),

            // BMI CARD
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: Colors.white10),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text('Your BMI', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                        const SizedBox(height: 4),
                        Text(
                          bmi > 0 ? bmi.toStringAsFixed(1) : '--',
                          style: const TextStyle(color: Colors.white, fontSize: 32, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                    decoration: BoxDecoration(
                      color: bmiColor.withOpacity(0.15),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: bmiColor),
                    ),
                    child: Text(
                      bmiCategory,
                      style: TextStyle(color: bmiColor, fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  )
                ],
              ),
            ),

            const SizedBox(height: 24),
            _label('Desired Target Weight (Optional)'),
            const SizedBox(height: 8),
            _field(
              controller: _targetWeightController, 
              hint: 'e.g. 65', 
              suffix: _weightUnit, 
              keyboard: TextInputType.number
            ),
            const SizedBox(height: 8),
            const Text(
              'Leave blank if you want to maintain your current weight.',
              style: TextStyle(color: Colors.white38, fontSize: 12),
            ),

            const SizedBox(height: 24),

            // CALORIES CARD
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [const Color(0xFFFF5E00).withOpacity(0.1), Colors.transparent],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: const Color(0xFFFF5E00).withOpacity(0.5)),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.local_fire_department, color: Color(0xFFFF5E00), size: 20),
                      const SizedBox(width: 8),
                      const Text('Recommended Intake', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(
                        calories > 0 ? '$calories' : '--',
                        style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold, height: 1),
                      ),
                      const SizedBox(width: 6),
                      const Padding(
                        padding: EdgeInsets.only(bottom: 4),
                        child: Text('kcal / day', style: TextStyle(color: Colors.white54, fontSize: 14)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Based on the Mifflin-St Jeor formula adjusted for your target weight.',
                    style: TextStyle(color: Colors.grey, fontSize: 11),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  // ── STEP 3: LIMITATIONS ───────────────────────────────────────────────────
  Widget _buildStep3() {
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
    final isLast = _currentStep == 2;
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
                    Text(isLast ? 'Proceed' : 'Continue',
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