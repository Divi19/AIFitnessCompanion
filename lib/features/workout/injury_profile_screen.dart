import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:math' as math;
import '../../core/constants.dart';

/// ONBOARDING ONLY — Body Stats + Insights + Body Limitations (visual body map).
/// Goal / Schedule are handled in WorkoutBuilderScreen.
class InjuryProfileScreen extends StatefulWidget {
  const InjuryProfileScreen({Key? key}) : super(key: key);
  @override
  _InjuryProfileScreenState createState() => _InjuryProfileScreenState();
}

class _InjuryProfileScreenState extends State<InjuryProfileScreen>
    with SingleTickerProviderStateMixin {

  final PageController _pageController = PageController();
  int  _currentStep = 0;
  bool _isLoading   = false;

  late final AnimationController _fadeController = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 350));
  late final Animation<double> _fadeAnim =
      CurvedAnimation(parent: _fadeController, curve: Curves.easeInOut);

  // ── STEP 1: Body Stats ────────────────────────────────────────────────────
  final _weightController = TextEditingController();
  final _heightController = TextEditingController();
  final _ageController    = TextEditingController();
  String _gender     = 'Male';
  String _weightUnit = 'kg';
  String _heightUnit = 'cm';

  // ── STEP 2: Insights ──────────────────────────────────────────────────────
  final _targetWeightController = TextEditingController();

  // ── STEP 3: Limitations ───────────────────────────────────────────────────
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

  // ── THEME ─────────────────────────────────────────────────────────────────
  static const _orange    = Color(0xFF9B8FFF);
  static const _voltGreen = Color(0xFFB9FF2B);
  static const _surface   = Color(0xFF1A1A1A);
  static const _bg        = Color(0xFF0D0D0D);

  final List<String> _stepLabels = ['Body Stats', 'Insights', 'Limitations'];

  @override
  void initState() {
    super.initState();
    _fadeController.forward();
    _targetWeightController.addListener(() => setState(() {}));
    _loadExistingProfile();
  }

  /// Load saved profile from Firestore so users don't lose data when updating
  Future<void> _loadExistingProfile() async {
    try {
      final uid = FirebaseAuth.instance.currentUser?.uid;
      if (uid == null) return;
      final doc  = await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (!doc.exists) return;
      final data = doc.data() ?? {};

      final stats    = data['body_stats']  as Map<String, dynamic>? ?? {};
      final bio      = data['biometrics']  as Map<String, dynamic>? ?? {};
      final upper    = bio['upperBody']    as Map<String, dynamic>? ?? {};
      final lower    = bio['lowerBody']    as Map<String, dynamic>? ?? {};
      final core     = bio['coreSpine']    as Map<String, dynamic>? ?? {};
      final systemic = bio['systemic']     as Map<String, dynamic>? ?? {};

      if (!mounted) return;
      setState(() {
        // Body stats
        final w = stats['weight'] as String? ?? '';
        final h = stats['height'] as String? ?? '';
        if (w.contains('lbs')) { _weightUnit = 'lbs'; _weightController.text = w.replaceAll(' lbs', ''); }
        else { _weightUnit = 'kg'; _weightController.text = w.replaceAll(' kg', ''); }
        if (h.contains('ft'))  { _heightUnit = 'ft';  _heightController.text = h.replaceAll(' ft', ''); }
        else { _heightUnit = 'cm'; _heightController.text = h.replaceAll(' cm', ''); }
        _ageController.text = stats['age']?.toString() ?? '';
        _gender = stats['gender'] as String? ?? 'Male';
        final tw = stats['target_weight'] as String?;
        if (tw != null) _targetWeightController.text = tw.split(' ').first;

        // Biometrics — upper
        rotatorCuff   = upper['rotatorCuff']   == true;
        deltoids      = upper['deltoids']       == true;
        pectorals     = upper['pectorals']      == true;
        biceps        = upper['biceps']         == true;
        triceps       = upper['triceps']        == true;
        latsRhomboids = upper['latsRhomboids']  == true;
        elbowJoint    = upper['elbowJoint']     == true;
        wristCarpals  = upper['wristCarpals']   == true;
        // lower
        glutesPelvis  = lower['glutesPelvis']   == true;
        quadriceps    = lower['quadriceps']     == true;
        hamstrings    = lower['hamstrings']     == true;
        calves        = lower['calves']         == true;
        kneeMeniscus  = lower['kneeMeniscus']   == true;
        achillesAnkle = lower['achillesAnkle']  == true;
        plantarFoot   = lower['plantarFoot']    == true;
        // core/spine
        cervicalSpine   = core['cervicalSpine']   == true;
        thoracicSpine   = core['thoracicSpine']   == true;
        lumbarSpine     = core['lumbarSpine']     == true;
        abdominalHernia = core['abdominalHernia'] == true;
        // systemic
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
    _weightController.dispose();
    _heightController.dispose();
    _ageController.dispose();
    _targetWeightController.dispose();
    _clinicalNotesController.dispose();
    super.dispose();
  }

  // ── MATH ──────────────────────────────────────────────────────────────────
  double _getKg() {
    final w = double.tryParse(_weightController.text) ?? 0.0;
    return _weightUnit == 'lbs' ? w * 0.453592 : w;
  }
  double _getCm() {
    final h = double.tryParse(_heightController.text) ?? 0.0;
    return _heightUnit == 'ft' ? h * 30.48 : h;
  }
  double _getBMI() {
    final kg = _getKg(); final m = _getCm() / 100;
    if (m <= 0 || kg <= 0) return 0.0;
    return kg / (m * m);
  }
  String _getBMICategory(double bmi) {
    if (bmi == 0)    return 'Unknown';
    if (bmi < 18.5)  return 'Underweight';
    if (bmi <= 24.9) return 'Healthy';
    if (bmi <= 29.9) return 'Overweight';
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
    final kg = _getKg(); final cm = _getCm();
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

  void _nextStep() {
    if (_currentStep == 0 &&
        (_weightController.text.isEmpty || _heightController.text.isEmpty)) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please enter weight and height first.')));
      return;
    }
    if (_currentStep < 2) {
      _fadeController.reset();
      setState(() => _currentStep++);
      _pageController.nextPage(
          duration: const Duration(milliseconds: 400), curve: Curves.easeInOut);
      _fadeController.forward();
    } else {
      _saveProfile();
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

  Future<void> _saveProfile() async {
    setState(() => _isLoading = true);
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'body_stats': {
          'weight':        '${_weightController.text} $_weightUnit',
          'height':        '${_heightController.text} $_heightUnit',
          'age':           _ageController.text,
          'gender':        _gender,
          'target_weight': _targetWeightController.text.trim().isEmpty
              ? null : '${_targetWeightController.text.trim()} $_weightUnit',
        },
        'health_insights': {
          'bmi':                double.parse(_getBMI().toStringAsFixed(1)),
          'suggested_calories': _getCalories(),
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
        },
        'profile_completed': true,
      }, SetOptions(merge: true));
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e'), backgroundColor: Colors.red[700]));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0,
        leading: _currentStep > 0
            ? IconButton(icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20), onPressed: _prevStep)
            : IconButton(icon: const Icon(Icons.close, color: Colors.white70, size: 22), onPressed: () => Navigator.pop(context)),
        title: const Text('My Profile Setup',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w700)),
        centerTitle: true,
      ),
      body: Column(children: [
        _buildStepIndicator(),
        Expanded(child: PageView(
          controller: _pageController,
          physics: const NeverScrollableScrollPhysics(),
          children: [_buildStep1BodyStats(), _buildStep2Insights(), _buildStep3Limitations()],
        )),
        _buildBottomButton(),
      ]),
    );
  }

  Widget _buildStepIndicator() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      child: Row(children: List.generate(_stepLabels.length, (i) {
        final isActive = i == _currentStep;
        final isDone   = i < _currentStep;
        return Expanded(child: Padding(
          padding: EdgeInsets.only(right: i < _stepLabels.length - 1 ? 5 : 0),
          child: Column(children: [
            AnimatedContainer(
              duration: const Duration(milliseconds: 300), height: 3,
              decoration: BoxDecoration(
                  color: isDone || isActive ? _orange : Colors.white12,
                  borderRadius: BorderRadius.circular(2)),
            ),
            const SizedBox(height: 5),
            Text(_stepLabels[i], style: TextStyle(
              fontSize: 9,
              color: isActive ? _orange : isDone ? Colors.white54 : Colors.white24,
              fontWeight: isActive ? FontWeight.w700 : FontWeight.w400,
            )),
          ]),
        ));
      })),
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
          _stepHeader('Your Body Stats', 'Personalise your plan with accurate data', Icons.person_outline),
          const SizedBox(height: 24),
          _label('Gender'),
          const SizedBox(height: 8),
          Row(children: ['Male', 'Female', 'Other'].map((g) {
            final sel = _gender == g;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _gender = g),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: sel ? _orange : _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? _orange : Colors.white12),
                ),
                child: Text(g, textAlign: TextAlign.center,
                    style: TextStyle(color: sel ? Colors.white : Colors.white54,
                        fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 14)),
              ),
            ));
          }).toList()),
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
            Expanded(child: _field(controller: _heightController,
                hint: _heightUnit == 'cm' ? 'e.g. 170' : 'e.g. 68', keyboard: TextInputType.number)),
            const SizedBox(width: 12),
            _unitToggle(['cm', 'ft'], _heightUnit, (v) => setState(() => _heightUnit = v)),
          ]),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── STEP 2: INSIGHTS ──────────────────────────────────────────────────────
  Widget _buildStep2Insights() {
    final bmi = _getBMI(); final bmiColor = _getBMIColor(bmi); final calories = _getCalories();
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _stepHeader('Your Body Insights', 'BMI and estimated daily calorie goal', Icons.insights_outlined),
          const SizedBox(height: 24),
          Container(
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: Colors.white10)),
            child: Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const Text('Your BMI', style: TextStyle(color: Colors.white54, fontSize: 13, fontWeight: FontWeight.w600)),
                const SizedBox(height: 4),
                Text(bmi > 0 ? bmi.toStringAsFixed(1) : '--',
                    style: const TextStyle(color: Colors.white, fontSize: 36, fontWeight: FontWeight.bold)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                decoration: BoxDecoration(
                    color: bmiColor.withOpacity(0.15), borderRadius: BorderRadius.circular(20), border: Border.all(color: bmiColor)),
                child: Text(_getBMICategory(bmi), style: TextStyle(color: bmiColor, fontWeight: FontWeight.bold, fontSize: 14)),
              ),
            ]),
          ),
          const SizedBox(height: 20),
          _label('Target Weight (optional)'),
          const SizedBox(height: 4),
          const Text('Leave blank to maintain current weight', style: TextStyle(color: Colors.white38, fontSize: 11)),
          const SizedBox(height: 8),
          _field(controller: _targetWeightController, hint: 'e.g. 65', suffix: _weightUnit, keyboard: TextInputType.number),
          const SizedBox(height: 24),
          Container(
            width: double.infinity, padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _orange.withOpacity(0.4))),
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Row(children: [
                const Icon(Icons.local_fire_department, color: _orange, size: 20),
                const SizedBox(width: 8),
                const Text('Recommended Daily Intake', style: TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600)),
              ]),
              const SizedBox(height: 12),
              Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Text(calories > 0 ? '$calories' : '--',
                    style: const TextStyle(color: Colors.white, fontSize: 38, fontWeight: FontWeight.bold, height: 1)),
                const SizedBox(width: 6),
                const Padding(padding: EdgeInsets.only(bottom: 4),
                    child: Text('kcal / day', style: TextStyle(color: Colors.white54, fontSize: 14))),
              ]),
              const SizedBox(height: 8),
              const Text('Calculated via Mifflin-St Jeor, adjusted for your target.',
                  style: TextStyle(color: Colors.white38, fontSize: 11)),
            ]),
          ),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  // ── STEP 3: LIMITATIONS — PROFESSIONAL BODY MAP ───────────────────────────
  Widget _buildStep3Limitations() {
    return FadeTransition(
      opacity: _fadeAnim,
      child: SingleChildScrollView(
        padding: const EdgeInsets.symmetric(horizontal: 20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(height: 8),
          _stepHeader('Physical Limitations',
              'Tap any area that has injury or chronic pain', Icons.accessibility_new),
          const SizedBox(height: 16),
          // "No limitations" pill
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
                color: noLimitations ? _voltGreen.withOpacity(0.15) : _surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: noLimitations ? _voltGreen : Colors.white12, width: noLimitations ? 2 : 1),
              ),
              child: Row(children: [
                Icon(noLimitations ? Icons.check_circle : Icons.check_circle_outline,
                    color: noLimitations ? _voltGreen : Colors.white38, size: 22),
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

            // Active selections legend
            if (_getActiveLimitations().isNotEmpty) ...[
              const Text('Selected areas:', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: _getActiveLimitations().map((l) =>
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: _orange.withOpacity(0.15), borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: _orange.withOpacity(0.5))),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    const Icon(Icons.circle, color: _orange, size: 6),
                    const SizedBox(width: 6),
                    Text(l, style: const TextStyle(color: _orange, fontSize: 11, fontWeight: FontWeight.w600)),
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
                Row(children: [
                  const Icon(Icons.medical_services_outlined, color: _orange, size: 16),
                  const SizedBox(width: 8),
                  const Text('Other Conditions', style: TextStyle(color: _orange, fontWeight: FontWeight.w700, fontSize: 13)),
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

  // ── PROFESSIONAL LABELED BODY MAP ─────────────────────────────────────────
  Widget _buildProfessionalBodyMap() {
    return LayoutBuilder(builder: (ctx, constraints) {
      final totalW = constraints.maxWidth;
      final figureW = (totalW - 24) / 2; // width of each figure

      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // FRONT VIEW
          _buildFigureWithLabels(
            figureW: figureW,
            isFront: true,
            title: 'FRONT',
          ),
          const SizedBox(width: 24),
          // BACK VIEW
          _buildFigureWithLabels(
            figureW: figureW,
            isFront: false,
            title: 'BACK',
          ),
        ],
      );
    });
  }

  Widget _buildFigureWithLabels({required double figureW, required bool isFront, required String title}) {
    // Figure height proportional to width
    final figH = figureW * 2.8;

    return Column(children: [
      // Title
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.white.withOpacity(0.05),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(title, style: const TextStyle(color: Colors.white38, fontSize: 10, fontWeight: FontWeight.w700, letterSpacing: 1.5)),
      ),
      const SizedBox(height: 12),
      SizedBox(
        width: figureW,
        height: figH,
        child: Stack(clipBehavior: Clip.none, children: [
          // Body silhouette
          Positioned.fill(child: CustomPaint(
            painter: _ProfessionalBodyPainter(
              isFront: isFront,
              activeColor: _orange,
              activeRegions: _getActiveRegionNames(),
            ),
          )),

          // Hotspot dots + labels
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

  /// Each hotspot: (relX, relY) as fractions of figureW/figureH, key, label, onTap
  List<Widget> _buildHotspots({required bool isFront, required double fw, required double fh}) {
    final active = _getActiveRegionNames();

    // Define hotspot data: [relX, relY, key, label, isLeft]
    // relX/relY are 0..1 fractions of figure width/height
    final List<Map<String, dynamic>> hotspots = isFront ? [
      {'x': 0.50, 'y': 0.045, 'key': 'neck',    'label': 'Neck',        'toggle': () => setState(() => cervicalSpine    = !cervicalSpine)},
      {'x': 0.22, 'y': 0.13,  'key': 'shoulder', 'label': 'Shoulder',   'toggle': () => setState(() => rotatorCuff      = !rotatorCuff)},
      {'x': 0.78, 'y': 0.13,  'key': 'shoulder', 'label': 'Shoulder',   'toggle': () => setState(() => rotatorCuff      = !rotatorCuff)},
      {'x': 0.50, 'y': 0.17,  'key': 'chest',    'label': 'Chest',       'toggle': () => setState(() => pectorals        = !pectorals)},
      {'x': 0.14, 'y': 0.22,  'key': 'bicep',    'label': 'Bicep',       'toggle': () => setState(() => biceps           = !biceps)},
      {'x': 0.86, 'y': 0.22,  'key': 'bicep',    'label': 'Bicep',       'toggle': () => setState(() => biceps           = !biceps)},
      {'x': 0.50, 'y': 0.28,  'key': 'core',     'label': 'Core',        'toggle': () => setState(() => abdominalHernia  = !abdominalHernia)},
      {'x': 0.12, 'y': 0.35,  'key': 'elbow',    'label': 'Elbow',       'toggle': () => setState(() => elbowJoint       = !elbowJoint)},
      {'x': 0.88, 'y': 0.35,  'key': 'elbow',    'label': 'Elbow',       'toggle': () => setState(() => elbowJoint       = !elbowJoint)},
      {'x': 0.10, 'y': 0.44,  'key': 'wrist',    'label': 'Wrist',       'toggle': () => setState(() => wristCarpals     = !wristCarpals)},
      {'x': 0.90, 'y': 0.44,  'key': 'wrist',    'label': 'Wrist',       'toggle': () => setState(() => wristCarpals     = !wristCarpals)},
      {'x': 0.50, 'y': 0.42,  'key': 'glute',    'label': 'Hips',        'toggle': () => setState(() => glutesPelvis     = !glutesPelvis)},
      {'x': 0.35, 'y': 0.56,  'key': 'quad',     'label': 'Quad',        'toggle': () => setState(() => quadriceps       = !quadriceps)},
      {'x': 0.65, 'y': 0.56,  'key': 'quad',     'label': 'Quad',        'toggle': () => setState(() => quadriceps       = !quadriceps)},
      {'x': 0.35, 'y': 0.72,  'key': 'knee',     'label': 'Knee',        'toggle': () => setState(() => kneeMeniscus     = !kneeMeniscus)},
      {'x': 0.65, 'y': 0.72,  'key': 'knee',     'label': 'Knee',        'toggle': () => setState(() => kneeMeniscus     = !kneeMeniscus)},
      {'x': 0.35, 'y': 0.84,  'key': 'calf',     'label': 'Shin',        'toggle': () => setState(() => calves           = !calves)},
      {'x': 0.65, 'y': 0.84,  'key': 'calf',     'label': 'Shin',        'toggle': () => setState(() => calves           = !calves)},
      {'x': 0.35, 'y': 0.93,  'key': 'ankle',    'label': 'Ankle',       'toggle': () => setState(() => achillesAnkle    = !achillesAnkle)},
      {'x': 0.65, 'y': 0.93,  'key': 'ankle',    'label': 'Ankle',       'toggle': () => setState(() => achillesAnkle    = !achillesAnkle)},
    ] : [
      {'x': 0.50, 'y': 0.045, 'key': 'neck',      'label': 'Neck',      'toggle': () => setState(() => cervicalSpine    = !cervicalSpine)},
      {'x': 0.22, 'y': 0.13,  'key': 'deltoid',   'label': 'Delt',      'toggle': () => setState(() => deltoids         = !deltoids)},
      {'x': 0.78, 'y': 0.13,  'key': 'deltoid',   'label': 'Delt',      'toggle': () => setState(() => deltoids         = !deltoids)},
      {'x': 0.50, 'y': 0.18,  'key': 'upperback', 'label': 'Upper Back','toggle': () => setState(() => thoracicSpine    = !thoracicSpine)},
      {'x': 0.14, 'y': 0.22,  'key': 'tricep',    'label': 'Tricep',    'toggle': () => setState(() => triceps          = !triceps)},
      {'x': 0.86, 'y': 0.22,  'key': 'tricep',    'label': 'Tricep',    'toggle': () => setState(() => triceps          = !triceps)},
      {'x': 0.22, 'y': 0.30,  'key': 'lat',       'label': 'Lat',       'toggle': () => setState(() => latsRhomboids    = !latsRhomboids)},
      {'x': 0.78, 'y': 0.30,  'key': 'lat',       'label': 'Lat',       'toggle': () => setState(() => latsRhomboids    = !latsRhomboids)},
      {'x': 0.50, 'y': 0.34,  'key': 'lowerback', 'label': 'Lower Back','toggle': () => setState(() => lumbarSpine      = !lumbarSpine)},
      {'x': 0.50, 'y': 0.43,  'key': 'glute',     'label': 'Glutes',    'toggle': () => setState(() => glutesPelvis     = !glutesPelvis)},
      {'x': 0.35, 'y': 0.57,  'key': 'hamstring', 'label': 'Hamstring', 'toggle': () => setState(() => hamstrings       = !hamstrings)},
      {'x': 0.65, 'y': 0.57,  'key': 'hamstring', 'label': 'Hamstring', 'toggle': () => setState(() => hamstrings       = !hamstrings)},
      {'x': 0.35, 'y': 0.72,  'key': 'knee',      'label': 'Knee',      'toggle': () => setState(() => kneeMeniscus     = !kneeMeniscus)},
      {'x': 0.65, 'y': 0.72,  'key': 'knee',      'label': 'Knee',      'toggle': () => setState(() => kneeMeniscus     = !kneeMeniscus)},
      {'x': 0.35, 'y': 0.83,  'key': 'calf',      'label': 'Calf',      'toggle': () => setState(() => calves           = !calves)},
      {'x': 0.65, 'y': 0.83,  'key': 'calf',      'label': 'Calf',      'toggle': () => setState(() => calves           = !calves)},
      {'x': 0.35, 'y': 0.93,  'key': 'ankle',     'label': 'Ankle',     'toggle': () => setState(() => achillesAnkle    = !achillesAnkle)},
      {'x': 0.65, 'y': 0.93,  'key': 'ankle',     'label': 'Ankle',     'toggle': () => setState(() => achillesAnkle    = !achillesAnkle)},
      {'x': 0.35, 'y': 0.985, 'key': 'foot',      'label': 'Foot',      'toggle': () => setState(() => plantarFoot      = !plantarFoot)},
      {'x': 0.65, 'y': 0.985, 'key': 'foot',      'label': 'Foot',      'toggle': () => setState(() => plantarFoot      = !plantarFoot)},
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
                color: isActive ? _orange : const Color(0xFF2A2A2A),
                border: Border.all(
                  color: isActive ? _orange : const Color(0xFF4A4A4A),
                  width: isActive ? 2 : 1.5,
                ),
                boxShadow: isActive ? [BoxShadow(color: _orange.withOpacity(0.5), blurRadius: 8, spreadRadius: 1)] : null,
              ),
              child: isActive ? const Icon(Icons.close, size: 10, color: Colors.white) : null,
            ),
            // Connector line + label
            if (isActive) ...[
              Container(width: 1, height: 6, color: _orange.withOpacity(0.6)),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
                decoration: BoxDecoration(
                  color: _orange,
                  borderRadius: BorderRadius.circular(4),
                ),
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

  // ── HELPERS ───────────────────────────────────────────────────────────────
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
              color: value ? _orange : Colors.transparent,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: value ? _orange : Colors.white30, width: 2),
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
      Switch(value: value, onChanged: onChanged, activeColor: _orange,
          materialTapTargetSize: MaterialTapTargetSize.shrinkWrap),
    ]);
  }

  Widget _buildBottomButton() {
    final isLast = _currentStep == 2;
    return Container(
      padding: const EdgeInsets.fromLTRB(20, 12, 20, 28),
      decoration: BoxDecoration(color: _bg, border: Border(top: BorderSide(color: Colors.white.withOpacity(0.06)))),
      child: SizedBox(
        width: double.infinity, height: 54,
        child: ElevatedButton(
          onPressed: _isLoading ? null : _nextStep,
          style: ElevatedButton.styleFrom(
            backgroundColor: _orange, disabledBackgroundColor: Colors.white12,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)), elevation: 0),
          child: _isLoading
              ? const SizedBox(height: 22, width: 22, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Text(isLast ? 'Save Profile ✓' : 'Continue',
                      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700, color: Colors.white, letterSpacing: 0.3)),
                  if (!isLast) ...[const SizedBox(width: 8), const Icon(Icons.arrow_forward, color: Colors.white, size: 18)],
                ]),
        ),
      ),
    );
  }

  Widget _stepHeader(String title, String subtitle, IconData icon) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(color: _orange.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
        child: Icon(icon, color: _orange, size: 24),
      ),
      const SizedBox(height: 12),
      Text(title, style: const TextStyle(color: Colors.white, fontSize: 22, fontWeight: FontWeight.w800, letterSpacing: -0.3)),
      const SizedBox(height: 4),
      Text(subtitle, style: const TextStyle(color: Colors.white54, fontSize: 13)),
    ]);
  }
  Widget _label(String text) => Text(text,
      style: const TextStyle(color: Colors.white70, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.3));
  Widget _field({required TextEditingController controller, required String hint,
      String? suffix, TextInputType keyboard = TextInputType.text, int maxLines = 1}) {
    return TextField(
      controller: controller, keyboardType: keyboard, maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        suffixText: suffix, suffixStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        filled: true, fillColor: _surface,
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _orange, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
  Widget _unitToggle(List<String> options, String selected, Function(String) onSelect) {
    return Container(
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(10), border: Border.all(color: Colors.white12)),
      child: Row(children: options.map((opt) {
        final sel = selected == opt;
        return GestureDetector(
          onTap: () => onSelect(opt),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
                color: sel ? _orange : Colors.transparent,
                borderRadius: BorderRadius.circular(9)),
            child: Text(opt, style: TextStyle(
                color: sel ? Colors.white : Colors.white38,
                fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
          ),
        );
      }).toList()),
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

    // Scale factor — all coordinates designed for w=160, h=448 (ratio 1:2.8)
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