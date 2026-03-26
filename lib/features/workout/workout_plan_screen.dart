import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'dart:convert';

class WorkoutPlanScreen extends StatefulWidget {
  final String plan;
  final String planId;
  final String uid;

  const WorkoutPlanScreen({
    Key? key,
    required this.plan,
    required this.planId,
    required this.uid,
  }) : super(key: key);

  @override
  State<WorkoutPlanScreen> createState() => _WorkoutPlanScreenState();
}

class _WorkoutPlanScreenState extends State<WorkoutPlanScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tabController;

  // FitSense Theme Colors
  static const _lime   = Color(0xFFC5F135);
  static const _purple = Color(0xFF9B8FFF);
  static const _coral  = Color(0xFFFF7B6B);
  static const _bg     = Color(0xFF0D0D0D);
  static const _surface = Color(0xFF1A1A2E);

  List<Map<String, dynamic>> _weeks = [];
  bool _planParsed = false;
  Map<String, bool> _completed = {};
  bool _allDone = false;
  String _limitations = '';

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _parsePlan();
    _loadProgress();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  // ── PARSE ──────────────────────────────────────────────────────────────────
  void _parsePlan() {
    try {
      final raw = widget.plan.trim();
      final s   = raw.indexOf('[');
      final e   = raw.lastIndexOf(']');
      if (s != -1 && e != -1) {
        _weeks = (jsonDecode(raw.substring(s, e + 1)) as List)
            .cast<Map<String, dynamic>>();
        setState(() => _planParsed = true);
        return;
      }
    } catch (_) {}
    _weeks = _parseMarkdownPlan(widget.plan);
    setState(() => _planParsed = true);
  }

  List<Map<String, dynamic>> _parseMarkdownPlan(String text) {
    final weeks = <Map<String, dynamic>>[];
    final lines = text.split('\n');
    Map<String, dynamic>? currentWeek;
    Map<String, dynamic>? currentDay;

    for (final line in lines) {
      final t = line.trim();
      if (t.isEmpty) continue;

      final wm = RegExp(r'week\s*(\d+)', caseSensitive: false).firstMatch(t);
      if (wm != null && (t.startsWith('#') || t.toLowerCase().startsWith('week') || t.contains('**Week'))) {
        if (currentDay != null && currentWeek != null) { (currentWeek['days'] as List).add(currentDay); currentDay = null; }
        if (currentWeek != null) weeks.add(currentWeek);
        currentWeek = {'week': int.tryParse(wm.group(1) ?? '1') ?? (weeks.length + 1), 'days': <Map<String, dynamic>>[]};
        continue;
      }

      final dm = RegExp(r'day\s*(\d+)', caseSensitive: false).firstMatch(t);
      if (dm != null && currentWeek != null) {
        if (currentDay != null) (currentWeek['days'] as List).add(currentDay);
        final afterDay = t.replaceAll(RegExp(r'[*#]'), '').trim();
        currentDay = {
          'day': int.tryParse(dm.group(1) ?? '1') ?? ((currentWeek['days'] as List).length + 1),
          'title': afterDay,
          'isRest': t.toLowerCase().contains('rest'),
          'exercises': <Map<String, dynamic>>[],
        };
        continue;
      }

      if (currentWeek != null && currentDay == null &&
          (t.toLowerCase().contains('rest day') || t.toLowerCase() == 'rest')) {
        (currentWeek['days'] as List).add({'day': (currentWeek['days'] as List).length + 1, 'title': 'Rest Day', 'isRest': true, 'exercises': []});
        continue;
      }

      if (currentDay != null && currentDay['isRest'] != true) {
        final exLine = t.replaceAll(RegExp(r'^[-*•\d.)\s]+'), '').trim();
        if (exLine.length > 3 && !exLine.startsWith('#')) {
          String name = exLine, detail = '';
          final sm = RegExp(r'(\d+)\s*(?:sets?|x)\s*(?:x\s*)?(\d+(?:-\d+)?)\s*(?:reps?|rep)?', caseSensitive: false).firstMatch(exLine);
          if (sm != null) {
            detail = '${sm.group(1)} sets × ${sm.group(2)} reps';
            name   = exLine.substring(0, sm.start).replaceAll(RegExp(r'[:\-–]'), '').trim();
          } else {
            final tm = RegExp(r'(\d+)\s*(?:min|sec|seconds?|minutes?)', caseSensitive: false).firstMatch(exLine);
            if (tm != null) { detail = tm.group(0) ?? ''; name = exLine.substring(0, tm.start).replaceAll(RegExp(r'[:\-–]'), '').trim(); }
          }
          if (name.isNotEmpty && name.length < 60) {
            (currentDay['exercises'] as List).add({'name': name, 'detail': detail.isEmpty ? 'As prescribed' : detail});
          }
        }
      }
    }

    if (currentDay != null && currentWeek != null) (currentWeek['days'] as List).add(currentDay);
    if (currentWeek != null) weeks.add(currentWeek);

    return weeks.isEmpty
        ? [{'week': 1, 'days': [{'day': 1, 'title': 'View Full Plan', 'isRest': false, 'exercises': [{'name': 'See your plan', 'detail': 'Tap to expand'}]}]}]
        : weeks;
  }

  // ── PROGRESS ───────────────────────────────────────────────────────────────
  Future<void> _loadProgress() async {
    final doc = await FirebaseFirestore.instance
        .collection('users').doc(widget.uid)
        .collection('workout_plans').doc(widget.planId)
        .get();
    if (doc.exists) {
      final data = doc.data() ?? {};
      final raw  = data['progress'] as Map<String, dynamic>? ?? {};
      setState(() {
        _completed   = raw.map((k, v) => MapEntry(k, v as bool));
        _limitations = data['limitations'] as String? ?? '';
        _checkAllDone();
      });
    }
  }

  Future<void> _toggleExercise(String key) async {
    setState(() { _completed[key] = !(_completed[key] ?? false); _checkAllDone(); });
    await FirebaseFirestore.instance
        .collection('users').doc(widget.uid)
        .collection('workout_plans').doc(widget.planId)
        .set({'progress': _completed}, SetOptions(merge: true));
  }

  void _checkAllDone() {
    int total = 0, done = 0;
    for (var wi = 0; wi < _weeks.length; wi++) {
      final days = (_weeks[wi]['days'] as List).cast<Map<String, dynamic>>();
      for (var di = 0; di < days.length; di++) {
        if (days[di]['isRest'] == true) continue;
        final exs = (days[di]['exercises'] as List).cast<Map<String, dynamic>>();
        for (var ei = 0; ei < exs.length; ei++) { total++; if (_completed['w${wi}_d${di}_e$ei'] == true) done++; }
      }
    }
    _allDone = total > 0 && done == total;
  }

  double _weekProgress(int wi) {
    int total = 0, done = 0;
    final days = (_weeks[wi]['days'] as List).cast<Map<String, dynamic>>();
    for (var di = 0; di < days.length; di++) {
      if (days[di]['isRest'] == true) continue;
      final exs = (days[di]['exercises'] as List).cast<Map<String, dynamic>>();
      for (var ei = 0; ei < exs.length; ei++) { total++; if (_completed['w${wi}_d${di}_e$ei'] == true) done++; }
    }
    return total == 0 ? 0.0 : done / total;
  }

  bool _isDayComplete(int wi, int di) {
    final days = (_weeks[wi]['days'] as List).cast<Map<String, dynamic>>();
    if (days[di]['isRest'] == true) return true;
    final exs = (days[di]['exercises'] as List).cast<Map<String, dynamic>>();
    return exs.isNotEmpty && exs.asMap().entries.every((e) => _completed['w${wi}_d${di}_e${e.key}'] == true);
  }

  // ── BUILD ──────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        backgroundColor: _bg, elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_ios, color: Colors.white, size: 20),
          onPressed: () => Navigator.pop(context),
        ),
        title: const Text('My Workout Plan',
            style: TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.close, color: Colors.white54, size: 24),
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
          ),
        ],
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: _lime,
          indicatorWeight: 2.5,
          labelColor: _lime,
          unselectedLabelColor: Colors.white38,
          labelStyle: const TextStyle(fontWeight: FontWeight.w700, fontSize: 13),
          tabs: const [Tab(text: 'My Plan'), Tab(text: 'Previous Workouts')],
        ),
      ),
      body: TabBarView(
        controller: _tabController,
        children: [_buildInteractivePlan(), _buildHistory()],
      ),
    );
  }

  // ── INTERACTIVE PLAN ───────────────────────────────────────────────────────
  Widget _buildInteractivePlan() {
    if (!_planParsed) return const Center(child: CircularProgressIndicator(color: _lime));
    if (_allDone)     return _buildCongratulations();

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _buildOverallProgress(),
        const SizedBox(height: 20),
        for (var wi = 0; wi < _weeks.length; wi++) _buildWeekCard(wi),
        const SizedBox(height: 20),
        SizedBox(
          width: double.infinity, height: 52,
          child: ElevatedButton.icon(
            onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
            style: ElevatedButton.styleFrom(
              backgroundColor: _surface,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14), side: const BorderSide(color: Colors.white12)),
              elevation: 0,
            ),
            icon: const Icon(Icons.refresh, color: Colors.white54, size: 18),
            label: const Text('Generate New Plan', style: TextStyle(fontSize: 14, color: Colors.white54, fontWeight: FontWeight.w600)),
          ),
        ),
        const SizedBox(height: 30),
      ],
    );
  }

  Widget _buildOverallProgress() {
    int total = 0, done = 0;
    for (var wi = 0; wi < _weeks.length; wi++) {
      final days = (_weeks[wi]['days'] as List).cast<Map<String, dynamic>>();
      for (var di = 0; di < days.length; di++) {
        if (days[di]['isRest'] == true) continue;
        final exs = (days[di]['exercises'] as List).cast<Map<String, dynamic>>();
        for (var ei = 0; ei < exs.length; ei++) { total++; if (_completed['w${wi}_d${di}_e$ei'] == true) done++; }
      }
    }
    final pct = total == 0 ? 0.0 : done / total;
    return Container(
      padding: const EdgeInsets.all(18),
      decoration: BoxDecoration(color: _surface, borderRadius: BorderRadius.circular(16), border: Border.all(color: _lime.withOpacity(0.2))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          const Icon(Icons.auto_awesome, color: _purple, size: 18),
          const SizedBox(width: 8),
          const Text('Overall Progress', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
          const Spacer(),
          Text('${(pct * 100).round()}%', style: const TextStyle(color: _lime, fontWeight: FontWeight.w800, fontSize: 18)),
        ]),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(value: pct, backgroundColor: Colors.white10, valueColor: const AlwaysStoppedAnimation(_lime), minHeight: 8),
        ),
        const SizedBox(height: 8),
        Text('$done of $total exercises completed', style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500)),
      ]),
    );
  }

  Widget _buildWeekCard(int wi) {
    final weekNum    = _weeks[wi]['week'] as int;
    final days       = (_weeks[wi]['days'] as List).cast<Map<String, dynamic>>();
    final progress   = _weekProgress(wi);
    final isComplete = progress >= 1.0;

    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      decoration: BoxDecoration(
        color: _surface, borderRadius: BorderRadius.circular(16),
        border: Border.all(color: isComplete ? _lime.withOpacity(0.5) : Colors.white12, width: isComplete ? 1.5 : 1),
      ),
      child: Theme(
        data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: wi == 0,
          tilePadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          iconColor: Colors.white38, collapsedIconColor: Colors.white38,
          title: Row(children: [
            Container(
              width: 36, height: 36,
              decoration: BoxDecoration(
                color: isComplete ? _lime.withOpacity(0.15) : _purple.withOpacity(0.15),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Center(child: isComplete
                  ? const Icon(Icons.check, color: _lime, size: 18)
                  : Text('W$weekNum', style: const TextStyle(color: _purple, fontWeight: FontWeight.w800, fontSize: 12))),
            ),
            const SizedBox(width: 12),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Week $weekNum', style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800, fontSize: 15)),
              const SizedBox(height: 4),
              Row(children: [
                Expanded(child: ClipRRect(
                  borderRadius: BorderRadius.circular(3),
                  child: LinearProgressIndicator(
                    value: progress, backgroundColor: Colors.white10,
                    valueColor: AlwaysStoppedAnimation(isComplete ? _lime : _purple), minHeight: 4),
                )),
                const SizedBox(width: 8),
                Text('${(progress * 100).round()}%',
                    style: TextStyle(color: isComplete ? _lime : _purple, fontWeight: FontWeight.w700, fontSize: 11)),
              ]),
            ])),
          ]),
          children: [for (var di = 0; di < days.length; di++) _buildDayTile(wi, di, days[di])],
        ),
      ),
    );
  }

  Widget _buildDayTile(int wi, int di, Map<String, dynamic> day) {
    final isRest  = day['isRest'] == true;
    final dayNum  = day['day'] as int;
    final title   = day['title'] as String? ?? 'Day $dayNum';
    final isDone  = _isDayComplete(wi, di);
    final exercises = isRest ? <Map<String, dynamic>>[] : (day['exercises'] as List).cast<Map<String, dynamic>>();

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF111111), borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isDone ? _lime.withOpacity(0.3) : Colors.white10),
      ),
      child: isRest
          ? Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
              child: Row(children: [
                Container(width: 32, height: 32,
                  decoration: BoxDecoration(color: Colors.white.withOpacity(0.05), borderRadius: BorderRadius.circular(8)),
                  child: const Icon(Icons.self_improvement, color: Colors.white38, size: 18)),
                const SizedBox(width: 12),
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Day $dayNum — Rest', style: const TextStyle(color: Colors.white70, fontWeight: FontWeight.w700, fontSize: 13)),
                  const Text('Recovery & light stretching', style: TextStyle(color: Colors.white24, fontSize: 11, fontWeight: FontWeight.w500)),
                ]),
                const Spacer(),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(color: _purple.withOpacity(0.15), borderRadius: BorderRadius.circular(20)),
                  child: const Text('REST', style: TextStyle(color: _purple, fontSize: 10, fontWeight: FontWeight.w800)),
                ),
              ]),
            )
          : Theme(
              data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
              child: ExpansionTile(
                tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                childrenPadding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                iconColor: Colors.white24, collapsedIconColor: Colors.white24,
                title: Row(children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: isDone ? _lime.withOpacity(0.12) : _purple.withOpacity(0.12),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Center(child: isDone
                        ? const Icon(Icons.check, color: _lime, size: 16)
                        : Text('$dayNum', style: const TextStyle(color: _purple, fontWeight: FontWeight.w800, fontSize: 13))),
                  ),
                  const SizedBox(width: 12),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(title.length > 30 ? 'Day $dayNum' : title,
                        style: TextStyle(color: isDone ? Colors.white54 : Colors.white, fontWeight: FontWeight.w700, fontSize: 13)),
                    Text('${exercises.length} exercises', style: const TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w500)),
                  ])),
                  if (isDone) Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                    decoration: BoxDecoration(color: _lime.withOpacity(0.12), borderRadius: BorderRadius.circular(10)),
                    child: const Text('Done ✓', style: TextStyle(color: _lime, fontSize: 10, fontWeight: FontWeight.w800)),
                  ),
                ]),
                children: [
                  for (var ei = 0; ei < exercises.length; ei++)
                    _buildExerciseTile(wi, di, ei, exercises[ei]),
                  _buildSafetyBanner(),
                ],
              ),
            ),
    );
  }

  Widget _buildExerciseTile(int wi, int di, int ei, Map<String, dynamic> ex) {
    final key    = 'w${wi}_d${di}_e$ei';
    final isDone = _completed[key] == true;
    final name   = (ex['name'] as String? ?? '').replaceAll(RegExp(r'\*+'), '').replaceAll(RegExp(r':+$'), '').trim();
    final detail = ex['detail'] as String? ?? '';
    final tips   = ex['tips']   as String? ?? '';

    return AnimatedContainer(
      duration: const Duration(milliseconds: 200),
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: isDone ? _lime.withOpacity(0.07) : Colors.white.withOpacity(0.03),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: isDone ? _lime.withOpacity(0.3) : Colors.white.withOpacity(0.06)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          GestureDetector(
            onTap: () => _toggleExercise(key),
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 24, height: 24,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: isDone ? _lime : Colors.transparent,
                  border: Border.all(color: isDone ? _lime : Colors.white30, width: 2),
                ),
                child: isDone ? const Icon(Icons.check, size: 14, color: Colors.black) : null,
              ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: () => _toggleExercise(key),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text(name, style: TextStyle(
                      color: isDone ? Colors.white38 : Colors.white,
                      fontWeight: FontWeight.w700, fontSize: 13,
                      decoration: isDone ? TextDecoration.lineThrough : null)),
                  if (detail.isNotEmpty)
                    Text(detail, style: TextStyle(color: isDone ? Colors.white24 : _purple, fontSize: 11, fontWeight: FontWeight.w600)),
                ]),
              ),
            ),
          ),
          GestureDetector(
            onTap: () => _showExerciseInfo(name, detail, tips),
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 12, vertical: 12),
              child: Icon(Icons.info_outline, color: Colors.white24, size: 18),
            ),
          ),
        ]),
        // Try it Live button
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
            decoration: BoxDecoration(
              color: _lime.withOpacity(0.10), borderRadius: BorderRadius.circular(8),
              border: Border.all(color: _lime.withOpacity(0.35)),
            ),
            child: const Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.videocam_outlined, color: _lime, size: 14),
              SizedBox(width: 6),
              Text('Try it Live', style: TextStyle(color: _lime, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 0.3)),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── SAFETY BANNER ──────────────────────────────────────────────────────────
  Widget _buildSafetyBanner() {
    final tips = <String>[];
    final lim  = _limitations.toLowerCase();

    if (lim == 'none' || lim.isEmpty) {
      tips.add('Maintain proper form throughout every rep.');
      tips.add('Stop immediately if you feel sharp or unexpected pain.');
    } else {
      if (lim.contains('knee') || lim.contains('meniscus')) {
        tips.add('Keep knees tracking over toes — never cave inward.');
        tips.add('Avoid deep knee flexion if it causes discomfort.');
      }
      if (lim.contains('lower back') || lim.contains('lumbar')) {
        tips.add('Brace your core before every movement to protect the lumbar spine.');
        tips.add('Avoid rounding your lower back — hinge at the hips instead.');
      }
      if (lim.contains('shoulder') || lim.contains('rotator')) {
        tips.add('Keep shoulders packed — avoid shrugging or impingement positions.');
        tips.add('Reduce range of motion on pressing movements if you feel pinching.');
      }
      if (lim.contains('wrist') || lim.contains('carpal')) {
        tips.add('Maintain neutral wrists — avoid excessive extension under load.');
      }
      if (lim.contains('ankle') || lim.contains('achilles')) {
        tips.add('Land softly and avoid sudden direction changes.');
        tips.add('Stretch calves before any jumping or running movements.');
      }
      if (lim.contains('hip') || lim.contains('glute') || lim.contains('pelvis')) {
        tips.add('Warm up hip flexors thoroughly before lower body work.');
      }
      if (lim.contains('neck') || lim.contains('cervical')) {
        tips.add('Keep your neck neutral — avoid tucking chin excessively.');
      }
      if (lim.contains('cardiovascular') || lim.contains('respiratory') || lim.contains('asthma')) {
        tips.add('Monitor your heart rate — stay within a comfortable exertion level.');
        tips.add('Have your inhaler nearby if you have asthma.');
      }
      if (lim.contains('elbow')) tips.add('Avoid locking out elbows fully under load.');
      if (lim.contains('thoracic') || lim.contains('upper back')) {
        tips.add('Keep chest open and shoulder blades retracted during rows and pulls.');
      }
      tips.add('All exercises in this plan are pre-screened for your injury profile.');
      tips.add('Stop and rest if pain exceeds a 3 out of 10.');
    }

    return Container(
      margin: const EdgeInsets.only(top: 4, bottom: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: _coral.withOpacity(0.05), borderRadius: BorderRadius.circular(10),
        border: Border.all(color: _coral.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(color: _coral.withOpacity(0.15), borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.health_and_safety_outlined, color: _coral, size: 15),
          ),
          const SizedBox(width: 8),
          const Text('Safety for Your Injury',
              style: TextStyle(color: _coral, fontWeight: FontWeight.w800, fontSize: 12, letterSpacing: 0.3)),
          const Spacer(),
          if (_limitations.isNotEmpty && _limitations.toLowerCase() != 'none')
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(color: _coral.withOpacity(0.1), borderRadius: BorderRadius.circular(10)),
              child: Text(
                _limitations.split(',').first.trim().length > 18
                    ? '${_limitations.split(',').first.trim().substring(0, 16)}…'
                    : _limitations.split(',').first.trim(),
                style: const TextStyle(color: _coral, fontSize: 9, fontWeight: FontWeight.w700),
              ),
            ),
        ]),
        const SizedBox(height: 10),
        ...tips.map((tip) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Padding(padding: EdgeInsets.only(top: 4), child: Icon(Icons.circle, size: 5, color: _coral)),
            const SizedBox(width: 8),
            Expanded(child: Text(tip, style: TextStyle(color: _coral.withOpacity(0.9), fontSize: 12, height: 1.5))),
          ]),
        )),
      ]),
    );
  }

  // ── EXERCISE INFO MODAL ────────────────────────────────────────────────────
  void _showExerciseInfo(String name, String detail, String tips) {
    final descriptions = <String, String>{
      'push-up': 'Start in plank. Lower chest to floor, push back up. Keep core tight.',
      'push up': 'Start in plank. Lower chest to floor, push back up. Keep core tight.',
      'squat': 'Feet shoulder-width. Lower until thighs parallel. Drive through heels.',
      'plank': 'Forearms on ground, body straight head to heels. Hold.',
      'lunge': 'Step forward, lower back knee toward floor. Front knee over ankle.',
      'pull-up': 'Hang from bar, pull until chin clears. Lower with control.',
      'pull up': 'Hang from bar, pull until chin clears. Lower with control.',
      'deadlift': 'Hinge at hips, grip bar, drive hips forward to stand. Back flat.',
      'burpee': 'Squat, jump feet back, push-up, jump feet in, jump up.',
      'mountain climber': 'In plank, alternate driving knees to chest rapidly.',
      'hip thrust': 'Shoulders on bench, drive hips up. Squeeze glutes at top.',
      'row': 'Pull weight toward torso, squeeze shoulder blades. Lower with control.',
      'curl': 'Keep elbows fixed, curl weight to shoulders. Lower slowly.',
      'bicep curl': 'Keep elbows fixed at sides, curl weight to shoulders. Lower slowly.',
      'tricep': 'Extend arms, focus on straightening the elbow.',
      'calf raise': 'Rise onto toes as high as possible. Lower slowly.',
      'bridge': 'Lie on back, feet flat, push hips toward ceiling. Squeeze glutes.',
      'dip': 'Lower body until elbows at 90°. Push back up.',
      'press': 'Push weight away from body. Chest: horizontally. Shoulder: overhead.',
    };

    String howTo = 'Perform the movement with controlled form. Focus on full range of motion.';
    descriptions.forEach((k, v) { if (name.toLowerCase().contains(k)) howTo = v; });

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Container(
        padding: const EdgeInsets.all(24),
        decoration: const BoxDecoration(
          color: _surface,
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)))),
          const SizedBox(height: 20),
          Row(children: [
            Container(padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(color: _purple.withOpacity(0.15), borderRadius: BorderRadius.circular(12)),
              child: const Icon(Icons.fitness_center, color: _purple, size: 22)),
            const SizedBox(width: 14),
            Expanded(child: Text(name, style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800))),
          ]),
          const SizedBox(height: 16),
          if (detail.isNotEmpty) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(color: _purple.withOpacity(0.1), borderRadius: BorderRadius.circular(12), border: Border.all(color: _purple.withOpacity(0.3))),
              child: Row(children: [
                const Icon(Icons.repeat, color: _purple, size: 16), const SizedBox(width: 8),
                Text(detail, style: const TextStyle(color: _purple, fontWeight: FontWeight.w700, fontSize: 14)),
              ]),
            ),
            const SizedBox(height: 16),
          ],
          const Text('How to perform', style: TextStyle(color: Colors.white54, fontSize: 12, fontWeight: FontWeight.w700, letterSpacing: 0.5)),
          const SizedBox(height: 8),
          Text(tips.isNotEmpty ? tips : howTo, style: const TextStyle(color: Colors.white, fontSize: 14, height: 1.6)),
          const SizedBox(height: 32),
        ]),
      ),
    );
  }

  // ── CONGRATULATIONS ────────────────────────────────────────────────────────
  Widget _buildCongratulations() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Container(width: 100, height: 100,
            decoration: BoxDecoration(color: _lime.withOpacity(0.15), shape: BoxShape.circle, border: Border.all(color: _lime, width: 2)),
            child: const Icon(Icons.emoji_events, color: _lime, size: 50)),
          const SizedBox(height: 28),
          const Text('Congratulations! 🎉', textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 26, fontWeight: FontWeight.w800)),
          const SizedBox(height: 12),
          Text('You\'ve completed your ${_weeks.length}-week plan! Ready for the next challenge?',
              textAlign: TextAlign.center,
              style: const TextStyle(color: Colors.white54, fontSize: 15, height: 1.6, fontWeight: FontWeight.w500)),
          const SizedBox(height: 40),
          SizedBox(width: double.infinity, height: 54,
            child: ElevatedButton(
              onPressed: () => Navigator.popUntil(context, (r) => r.isFirst),
              style: ElevatedButton.styleFrom(backgroundColor: _lime, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)), elevation: 0),
              child: const Text('Generate Month 2 🚀', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800, color: Colors.black)),
            ),
          ),
          const SizedBox(height: 14),
          TextButton(
            onPressed: () => setState(() {
              _completed.clear(); _allDone = false;
              FirebaseFirestore.instance.collection('users').doc(widget.uid)
                  .collection('workout_plans').doc(widget.planId)
                  .set({'progress': {}}, SetOptions(merge: true));
            }),
            child: const Text('Reset Progress', style: TextStyle(color: Colors.white38, fontSize: 13, fontWeight: FontWeight.w600)),
          ),
        ]),
      ),
    );
  }

  // ── PREVIOUS WORKOUTS TAB ──────────────────────────────────────────────────
  Widget _buildHistory() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users').doc(widget.uid)
          .collection('workout_plans')
          .orderBy('createdAt', descending: true)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: _lime));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Icon(Icons.history, size: 60, color: Colors.white12),
            SizedBox(height: 16),
            Text('No saved plans yet', style: TextStyle(color: Colors.white38, fontSize: 16, fontWeight: FontWeight.w600)),
          ]));
        }

        final docs = snapshot.data!.docs;
        return ListView.separated(
          padding: const EdgeInsets.all(16),
          itemCount: docs.length,
          separatorBuilder: (_, __) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            final data          = docs[index].data() as Map<String, dynamic>;
            final isCurrentPlan = docs[index].id == widget.planId;
            final createdAt     = data['createdAt'] as Timestamp?;
            final dateStr       = createdAt != null ? _formatDate(createdAt.toDate()) : 'Recently';

            return GestureDetector(
              onTap: () => Navigator.push(context, MaterialPageRoute(
                builder: (_) => WorkoutPlanScreen(
                  plan:   data['plan'] as String? ?? '',
                  planId: docs[index].id,
                  uid:    widget.uid,
                ),
              )),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isCurrentPlan ? _lime.withOpacity(0.08) : _surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: isCurrentPlan ? _lime.withOpacity(0.5) : Colors.white12,
                    width: isCurrentPlan ? 1.5 : 1,
                  ),
                ),
                child: Row(children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: isCurrentPlan ? _lime.withOpacity(0.2) : Colors.white.withOpacity(0.05),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(child: Text('${index + 1}',
                        style: TextStyle(color: isCurrentPlan ? _lime : Colors.white54, fontWeight: FontWeight.w800, fontSize: 16))),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text(data['goal'] ?? 'Workout Plan',
                          style: TextStyle(color: isCurrentPlan ? Colors.white : Colors.white70, fontWeight: FontWeight.w800, fontSize: 15),
                          maxLines: 1, overflow: TextOverflow.ellipsis)),
                      if (isCurrentPlan) Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(color: _lime.withOpacity(0.2), borderRadius: BorderRadius.circular(8)),
                        child: const Text('Current', style: TextStyle(color: _lime, fontSize: 10, fontWeight: FontWeight.w800)),
                      ),
                    ]),
                    const SizedBox(height: 6),
                    Text('${data['daysPerWeek'] ?? '?'} days · ${data['duration'] ?? '?'} · ${data['fitnessLevel'] ?? '?'}',
                        style: const TextStyle(color: Colors.white38, fontSize: 12, fontWeight: FontWeight.w500)),
                    const SizedBox(height: 4),
                    Text(dateStr, style: const TextStyle(color: Colors.white24, fontSize: 11)),
                  ])),
                  const Icon(Icons.chevron_right, color: Colors.white24, size: 20),
                ]),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(DateTime date) {
    final now  = DateTime.now();
    final diff = now.difference(date);
    if (diff.inDays == 0) return 'Today';
    if (diff.inDays == 1) return 'Yesterday';
    if (diff.inDays < 7)  return '${diff.inDays} days ago';
    return '${date.day}/${date.month}/${date.year}';
  }
}