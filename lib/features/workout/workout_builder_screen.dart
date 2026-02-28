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

  // ── THEME ──────────────────────────────────────────────────────────────────
  static const _orange  = Color(0xFFFF5E00);
  static const _volt    = Color(0xFFB9FF2B);
  static const _bg      = Color(0xFF0D0D0D);
  static const _surface = Color(0xFF1A1A1A);

  // ── STEP 1: Goal ──────────────────────────────────────────────────────────
  String _selectedGoal    = 'Weight Loss';
  String _selectedSubGoal = '';
  int    _planWeeks       = 4;

  final List<Map<String, dynamic>> _goals = [
    {'label': 'Weight Loss',    'icon': Icons.trending_down,    'desc': 'Burn fat & slim down',          'color': const Color(0xFFFF6B6B),
     'subOptions': [{'label':'Fat Burn','desc':'Cardio-heavy, high rep'},{'label':'Toning','desc':'Lean muscle & low fat'},{'label':'HIIT Focus','desc':'Max calorie burn'},{'label':'Steady Cardio','desc':'Sustainable fat loss'}]},
    {'label': 'Muscle Gain',    'icon': Icons.fitness_center,   'desc': 'Build size & strength',         'color': const Color(0xFF4F8EF7),
     'subOptions': [{'label':'Hypertrophy','desc':'Volume for size'},{'label':'Strength','desc':'Heavy compounds'},{'label':'Power','desc':'Explosive movements'},{'label':'Lean Bulk','desc':'Muscle with minimal fat'}]},
    {'label': 'Endurance',      'icon': Icons.directions_run,   'desc': 'Improve stamina & cardio',      'color': const Color(0xFF4CAF50),
     'subOptions': [{'label':'Running','desc':'Aerobic base'},{'label':'Cycling','desc':'Leg endurance'},{'label':'Swimming','desc':'Full-body stamina'},{'label':'General Cardio','desc':'Mixed endurance'}]},
    {'label': 'Flexibility',    'icon': Icons.self_improvement, 'desc': 'Mobility & stretching',         'color': const Color(0xFFAB47BC),
     'subOptions': [{'label':'Yoga','desc':'Flow & mindfulness'},{'label':'Stretching','desc':'Range of motion'},{'label':'Mobility','desc':'Joint health'},{'label':'Pilates','desc':'Core control'}]},
    {'label': 'General Fitness','icon': Icons.favorite,         'desc': 'Overall health & wellness',     'color': const Color(0xFFFF9800),
     'subOptions': [{'label':'Full Body','desc':'Balanced training'},{'label':'Athletic','desc':'Functional sport'},{'label':'Maintenance','desc':'Stay healthy'},{'label':'Weight Control','desc':'Manage weight'}]},
    {'label': 'Rehabilitation', 'icon': Icons.healing,          'desc': 'Recover & rebuild safely',      'color': const Color(0xFF26C6DA),
     'subOptions': [{'label':'Post-Surgery','desc':'Gentle recovery'},{'label':'Injury Recovery','desc':'Rebuild safely'},{'label':'Chronic Pain','desc':'Low-impact'},{'label':'Posture','desc':'Fix imbalances'}]},
  ];

  final _customGoalController = TextEditingController();

  // ── STEP 2: Schedule ──────────────────────────────────────────────────────
  int    _daysPerWeek     = 3;
  String _workoutDuration = '45 mins';
  String _fitnessLevel    = 'Beginner';
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

      // Save updated preferences
      await FirebaseFirestore.instance.collection('users').doc(uid).set({
        'fitness_goal': goal,
        'goal_focus':   _selectedSubGoal,
        'plan_weeks':   _planWeeks,
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

      final prompt = '''
You are an expert physiotherapist and certified personal trainer.
Generate a complete $_planWeeks-week workout program for this user.

User Profile:
- Age: ${stats['age'] ?? 'Unknown'} years old
- Gender: ${stats['gender'] ?? 'Unknown'}
- Weight: ${stats['weight'] ?? 'Unknown'}
- Target Weight: ${stats['target_weight'] ?? 'Maintain current weight'}
- Height: ${stats['height'] ?? 'Unknown'}
- BMI: $bmi
- Daily Calorie Target: $calories kcal
- Fitness Level: $_fitnessLevel
- Primary Goal: $_selectedGoal
- Specific Focus: $_selectedSubGoal
- Workout Days Per Week: $_daysPerWeek days
- Session Duration: $_workoutDuration per session
- Plan Duration: $_planWeeks weeks ($totalDays total sessions)
- Physical Limitations / Injuries: $limitationsText
- Uses Wheelchair: $usesWheelchair
- Uses Prosthesis: $usesProsthesis

Strict Rules:
- NEVER include exercises that stress injured areas
- Adapt ALL movements for fitness level and limitations
- Each session must fit within $_workoutDuration
- Structure as Week 1, Week 2 etc. with Day labels
- For each exercise: name, sets, reps/duration, rest time, and why it is safe
- Add progressive overload each week
- Include warm-up and cool-down for each day
- Reference their $calories kcal daily target in nutrition section
- End with monthly milestones, recovery tips and nutrition advice
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
          'fitnessLevel': _fitnessLevel,
          'daysPerWeek':  _daysPerWeek,
          'planWeeks':    _planWeeks,
          'duration':     _workoutDuration,
          'limitations':  limitationsText,
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
                color: isDone || isActive ? _orange : Colors.white12,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 5),
            Text(_stepLabels[i], style: TextStyle(
              fontSize: 10,
              color: isActive ? _orange : isDone ? Colors.white54 : Colors.white24,
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
    final accentColor = goalData['color'] as Color;

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
                    color: sel ? color.withOpacity(0.18) : _surface,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: sel ? color : Colors.white12, width: sel ? 2 : 1),
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
                    Icon(g['icon'] as IconData, color: sel ? color : Colors.white38, size: 22),
                    Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(g['label'] as String, style: TextStyle(color: sel ? Colors.white : Colors.white70, fontWeight: FontWeight.w700, fontSize: 12)),
                      Text(g['desc'] as String, style: TextStyle(color: sel ? color.withOpacity(0.8) : Colors.white38, fontSize: 10)),
                    ]),
                  ]),
                ),
              );
            }).toList(),
          ),

          const SizedBox(height: 16),

          // Sub-options panel
          Container(
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
                    style: TextStyle(color: accentColor, fontWeight: FontWeight.w700, fontSize: 13)),
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
                      color: sel ? accentColor.withOpacity(0.2) : const Color(0xFF111111),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: sel ? accentColor : Colors.white12, width: sel ? 1.5 : 1),
                    ),
                    child: Row(children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 180),
                        width: 18, height: 18,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: sel ? accentColor : Colors.transparent,
                          border: Border.all(color: sel ? accentColor : Colors.white30, width: 2),
                        ),
                        child: sel ? const Icon(Icons.check, size: 11, color: Colors.white) : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(sub['label'] as String, style: TextStyle(color: sel ? Colors.white : Colors.white70, fontWeight: sel ? FontWeight.w700 : FontWeight.w500, fontSize: 13)),
                        Text(sub['desc'] as String, style: TextStyle(color: sel ? accentColor.withOpacity(0.8) : Colors.white38, fontSize: 11)),
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
                  color: sel ? _orange : _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? _orange : Colors.white12),
                ),
                child: Column(children: [
                  Text('$weeks', style: TextStyle(color: sel ? Colors.white : Colors.white54, fontWeight: FontWeight.w800, fontSize: 18)),
                  Text(weeks == 1 ? 'week' : 'weeks', style: TextStyle(color: sel ? Colors.white70 : Colors.white24, fontSize: 10)),
                ]),
              ),
            ));
          }).toList()),
          const SizedBox(height: 8),
          Center(child: Text(
            '$_planWeeks-week plan · ${_daysPerWeek * _planWeeks} total sessions',
            style: const TextStyle(color: _orange, fontSize: 12, fontWeight: FontWeight.w600),
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
                    color: sel ? _orange : _surface,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: sel ? _orange : Colors.white12),
                  ),
                  child: Center(child: Text('$day', style: TextStyle(color: sel ? Colors.white : Colors.white54, fontWeight: FontWeight.w700, fontSize: 16))),
                ),
              );
            }),
          ),
          const SizedBox(height: 8),
          Center(child: Text('$_daysPerWeek ${_daysPerWeek == 1 ? 'day' : 'days'}/week · ${_daysPerWeek * _planWeeks} total sessions',
              style: const TextStyle(color: _orange, fontSize: 13, fontWeight: FontWeight.w600))),
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
                  color: sel ? _orange : _surface,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: sel ? _orange : Colors.white12),
                ),
                child: Text(d, style: TextStyle(color: sel ? Colors.white : Colors.white54, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
              ),
            );
          }).toList()),
          const SizedBox(height: 28),
          _label('Fitness Level'),
          const SizedBox(height: 12),
          Row(children: _levels.map((level) {
            final sel = _fitnessLevel == level;
            final c   = level == 'Beginner' ? _volt : level == 'Intermediate' ? _orange : const Color(0xFFFF3B30);
            final tc  = sel ? (level == 'Beginner' ? Colors.black : Colors.white) : Colors.white54;
            return Expanded(child: GestureDetector(
              onTap: () => setState(() => _fitnessLevel = level),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: const EdgeInsets.only(right: 8),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: sel ? c : _surface,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: sel ? c : Colors.white12, width: sel ? 2 : 1),
                ),
                child: Text(level, textAlign: TextAlign.center,
                    style: TextStyle(color: tc, fontWeight: sel ? FontWeight.w700 : FontWeight.w400, fontSize: 13)),
              ),
            ));
          }).toList()),
          const SizedBox(height: 40),
        ]),
      ),
    );
  }

  Widget _buildBottomButton() {
    final isLast = _currentStep == 1;
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
                  Text(isLast ? 'Generate My Plan 🚀' : 'Continue',
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

  Widget _field({required TextEditingController controller, required String hint, String? suffix, TextInputType keyboard = TextInputType.text, int maxLines = 1}) {
    return TextField(
      controller: controller, keyboardType: keyboard, maxLines: maxLines,
      style: const TextStyle(color: Colors.white, fontSize: 15),
      decoration: InputDecoration(
        hintText: hint, hintStyle: const TextStyle(color: Colors.white24, fontSize: 14),
        suffixText: suffix, suffixStyle: const TextStyle(color: Colors.white38, fontSize: 13),
        filled: true, fillColor: _surface,
        border:        OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Colors.white12)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: _orange, width: 1.5)),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      ),
    );
  }
}