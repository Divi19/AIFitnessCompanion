import 'dart:convert';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/rag_service.dart';
import '../../services/workout_session_service.dart';

const Map<String, Color> _exerciseColours = {
  'squat':        Color(0xFFFF5E00),
  'pushup':       Color(0xFFB9FF2B),
  'bicep_curl':   Color(0xFFFFB800),
  'jumping_jack': Color(0xFF00E5FF),
  'lunge_left':   Color(0xFFFF2B6B),
  'lunge_right':  Color(0xFFFF2B6B),
  'sit_up':       Color(0xFF9B59FF),
  'plank':        Color(0xFF00FF9B),
  'glute_bridge': Color(0xFFFFE600),
};

Color _colourFor(String exercise) =>
    _exerciseColours[exercise] ?? const Color(0xFFFF5E00);

class NutritionAssistantScreen extends StatefulWidget {
  const NutritionAssistantScreen({super.key});

  @override
  State<NutritionAssistantScreen> createState() =>
      _NutritionAssistantScreenState();
}

class _NutritionAssistantScreenState extends State<NutritionAssistantScreen> {
  final _ragService            = RagService();
  final _sessionService        = WorkoutSessionService();
  final _controller            = TextEditingController();
  final _scrollController      = ScrollController();
  final _stripScrollController = ScrollController();
  final GlobalKey _stripKey    = GlobalKey();

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;

  WorkoutSession? _expandedSession;
  String?         _selectedDay;

  Future<void> _sendMessage({String? overrideText, String? displayText}) async {
    final question = overrideText ?? _controller.text.trim();
    if (question.isEmpty || _isLoading) return;

    final userId   = FirebaseAuth.instance.currentUser?.uid ?? '';
    final chatText = displayText ?? question;

    setState(() {
      _messages.add({'role': 'user', 'text': chatText, 'isStreaming': false});
      _isLoading = true;
    });

    _controller.clear();
    _scrollToBottom();

    final previousMessages = _messages
        .sublist(0, _messages.length - 1)
        .map((m) => {'role': m['role'] as String, 'text': m['text'] as String})
        .toList();

    try {
      final recentSessions = await _sessionService.getRecentSessions(limit: 3);
      final stream = _ragService.query(
        userQuestion:   question,
        userId:         userId,
        chatHistory:    previousMessages,
        recentSessions: recentSessions,
      );

      bool isFirstChunk = true;
      int  chunkCount   = 0;

      await for (final chunk in stream) {
        chunkCount++;
        setState(() {
          if (isFirstChunk) {
            _isLoading = false;
            _messages.add(
                {'role': 'assistant', 'text': chunk, 'isStreaming': true});
            isFirstChunk = false;
          } else {
            final lastIndex   = _messages.length - 1;
            final currentText = _messages[lastIndex]['text'] as String;
            _messages[lastIndex] = {
              'role': 'assistant',
              'text': currentText + chunk,
              'isStreaming': true,
            };
          }
        });
        if (chunkCount <= 7) _scrollToBottom();
      }

      setState(() {
        _messages[_messages.length - 1]['isStreaming'] = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.add({
          'role': 'assistant',
          'text': 'Something went wrong. Please try again.\nError: $e',
          'isStreaming': false,
        });
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _openTrendFlow() async {
    final exercises = await _sessionService.getExercisesWithSessions();
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => _ExercisePickerSheet(
        exercises:      exercises,
        sessionService: _sessionService,
      ),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    _stripScrollController.dispose();
    super.dispose();
  }

  Widget _buildStrip() {
    return _SessionHistoryStrip(
      key:                   _stripKey,
      sessionService:        _sessionService,
      expandedSession:       _expandedSession,
      selectedDay:           _selectedDay,
      stripScrollController: _stripScrollController,
      onDaySelected:         (day) => setState(() => _selectedDay = day),
      onTrendTap:            _openTrendFlow,
      onSessionTap: (session) {
        setState(() {
          _expandedSession =
              _expandedSession?.id == session.id ? null : session;
        });
      },
      onAskFollowUp: (session, setNumber) {
        setState(() => _expandedSession = null);
        _sendMessage(
          overrideText:
              'Based on my ${session.exerciseDisplayName} session where I did '
              '${session.reps} reps, ${session.debriefText} '
              'What should I focus on to improve next time?',
          displayText:
              'How can I improve my ${session.exerciseDisplayName} — '
              'Set $setNumber, ${session.reps} reps (${session.timeAgo})?',
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFFB9FF2B), size: 26),
            SizedBox(width: 8),
            Text(
              'AI Fitness Coach',
              style: TextStyle(
                color: Color(0xFFB9FF2B),
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
      ),
      body: Column(
        children: [
          if (_expandedSession != null)
            Expanded(child: _buildStrip())
          else
            _buildStrip(),

          if (_expandedSession == null)
            Expanded(
              child: _messages.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Text(
                            'Ask me anything about fitness,\nnutrition, or recovery.',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey, fontSize: 16),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'Tap a session above to ask about your form',
                            style: TextStyle(
                                color: Colors.white.withOpacity(0.25),
                                fontSize: 13),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: _messages.length + (_isLoading ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index == _messages.length && _isLoading) {
                          return const _TypingIndicator();
                        }
                        final msg = _messages[index];
                        return _ChatBubble(
                          text:        msg['text']       as String,
                          isUser:      msg['role']       == 'user',
                          isStreaming: msg['isStreaming'] as bool,
                        );
                      },
                    ),
            ),

          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Give me 3 alternatives to deadlifts',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: _isLoading
                        ? Colors.transparent
                        : const Color(0xFFB9FF2B),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.send,
                        color: _isLoading ? Colors.grey : Colors.black),
                    onPressed: _isLoading ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Exercise Picker Bottom Sheet ──────────────────────────────────────────
class _ExercisePickerSheet extends StatelessWidget {
  final List<String> exercises;
  final WorkoutSessionService sessionService;

  const _ExercisePickerSheet({
    required this.exercises,
    required this.sessionService,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(
        color: Color(0xFF111111),
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 20),
              decoration: BoxDecoration(
                color: Colors.white24,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const Text(
            'SELECT EXERCISE',
            style: TextStyle(
              color: Colors.white38,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: 1.5,
            ),
          ),
          const SizedBox(height: 4),
          const Text(
            'View your form trend per set',
            style: TextStyle(color: Colors.white54, fontSize: 13),
          ),
          const SizedBox(height: 20),
          if (exercises.isEmpty)
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: const Color(0xFF1A1A1A),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white10),
              ),
              child: const Row(
                children: [
                  Icon(Icons.info_outline, color: Colors.white38, size: 18),
                  SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      'No sessions recorded yet. Complete a workout to see your form trends here.',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 13, height: 1.5),
                    ),
                  ),
                ],
              ),
            )
          else
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: exercises.length,
                itemBuilder: (context, index) {
                  final ex     = exercises[index];
                  final colour = _colourFor(ex);
                  final name   = _displayName(ex);

                  return GestureDetector(
                    onTap: () {
                      Navigator.of(context).pop();
                      showModalBottomSheet(
                        context: context,
                        backgroundColor: Colors.transparent,
                        isScrollControlled: true,
                        builder: (_) => _SetTrendSheet(
                          exercise:       ex,
                          exerciseName:   name,
                          colour:         colour,
                          sessionService: sessionService,
                        ),
                      );
                    },
                    child: Container(
                      margin: const EdgeInsets.only(bottom: 10),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 14),
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                            color: colour.withOpacity(0.35), width: 1.2),
                      ),
                      child: Row(
                        children: [
                          Container(
                            width: 10, height: 10,
                            decoration: BoxDecoration(
                              color: colour,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 14),
                          Text(
                            name,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                          const Spacer(),
                          Icon(Icons.chevron_right,
                              color: colour.withOpacity(0.6), size: 20),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  String _displayName(String exercise) {
    const names = {
      'squat':        'Squat',
      'pushup':       'Push Up',
      'bicep_curl':   'Bicep Curl',
      'jumping_jack': 'Jumping Jack',
      'lunge_left':   'Left Lunge',
      'lunge_right':  'Right Lunge',
      'sit_up':       'Sit Up',
      'plank':        'Plank',
      'glute_bridge': 'Glute Bridge',
    };
    return names[exercise] ?? exercise;
  }
}

// ── Per-set trend chart bottom sheet ──────────────────────────────────────
class _SetTrendSheet extends StatefulWidget {
  final String exercise;
  final String exerciseName;
  final Color colour;
  final WorkoutSessionService sessionService;

  const _SetTrendSheet({
    required this.exercise,
    required this.exerciseName,
    required this.colour,
    required this.sessionService,
  });

  @override
  State<_SetTrendSheet> createState() => _SetTrendSheetState();
}

class _SetTrendSheetState extends State<_SetTrendSheet> {
  List<SetTrendPoint>? _points;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final pts =
        await widget.sessionService.getSetTrendForExercise(widget.exercise);
    if (mounted) setState(() { _points = pts; _loading = false; });
  }

  String _trendLabel(List<SetTrendPoint> pts) {
    if (pts.length < 2) return '';
    final delta = pts.last.score - pts.first.score;
    if (delta >= 5)  return '↑ Improving';
    if (delta <= -5) return '↓ Declining';
    return '→ Steady';
  }

  Color _trendColour(List<SetTrendPoint> pts) {
    if (pts.length < 2) return Colors.white54;
    final delta = pts.last.score - pts.first.score;
    if (delta >= 5)  return const Color(0xFFB9FF2B);
    if (delta <= -5) return const Color(0xFFFF5E00);
    return Colors.white54;
  }

  @override
  Widget build(BuildContext context) {
    // ── Angle data ────────────────────────────────────────────────────────
    // anglePoints: all sets that have landmark data
    // latestAngle: most recent set with data → the bright actionable tick
    // allTimeAvg:  average across all sets → the faded historical tick
    //              divided by 2 to match the /2f applied in angleDeg()
    final anglePoints = _points
        ?.where((p) => p.avgJointAngle != null)
        .toList() ?? [];

    final double? latestAngle = anglePoints.isNotEmpty
        ? anglePoints.last.avgJointAngle
        : null;

    final double? allTimeAvg = anglePoints.length > 1
        ? (anglePoints.map((p) => p.avgJointAngle!).reduce((a, b) => a + b) /
              anglePoints.length)
        : null;

    return DraggableScrollableSheet(
      initialChildSize: 0.82,
      minChildSize:     0.5,
      maxChildSize:     0.95,
      builder: (_, scrollController) => Container(
        decoration: const BoxDecoration(
          color: Color(0xFF111111),
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        child: ListView(
          controller: scrollController,
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 32),
          children: [
            Center(
              child: Container(
                width: 40, height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),

            Row(
              children: [
                Container(
                  width: 12, height: 12,
                  decoration: BoxDecoration(
                    color: widget.colour,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 10),
                Text(
                  widget.exerciseName.toUpperCase(),
                  style: TextStyle(
                    color: widget.colour,
                    fontSize: 13,
                    fontWeight: FontWeight.w800,
                    letterSpacing: 1.2,
                  ),
                ),
                const Spacer(),
                if (_points != null && _points!.length >= 2)
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: _trendColour(_points!).withOpacity(0.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _trendColour(_points!).withOpacity(0.4)),
                    ),
                    child: Text(
                      _trendLabel(_points!),
                      style: TextStyle(
                        color: _trendColour(_points!),
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            const Text(
              'Form score per set — all time',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 20),

            if (_loading)
              const SizedBox(
                height: 180,
                child: Center(
                  child: CircularProgressIndicator(
                      strokeWidth: 2, color: Color(0xFFFF5E00)),
                ),
              )
            else if (_points == null || _points!.isEmpty)
              Container(
                height: 100,
                alignment: Alignment.center,
                child: const Text(
                  'No sets recorded yet.',
                  style: TextStyle(color: Colors.white38, fontSize: 14),
                ),
              )
            else
              _buildChart(_points!),

            const SizedBox(height: 20),

            if (_points != null && _points!.isNotEmpty)
              _buildSessionLegend(_points!),

            // ── Joint angle comparison ────────────────────────────────────
            // Shown when we have at least one angle reading AND the exercise
            // has an ideal range defined. Shows two ticks:
            //   bright = latest session (actionable)
            //   faded  = all-time average (context), only if 2+ data points
            if (latestAngle != null &&
                kIdealAngles.containsKey(widget.exercise)) ...[
              const SizedBox(height: 24),
              _buildAngleComparison(latestAngle, allTimeAvg),
            ],

            const SizedBox(height: 24),
            _buildHowItWorks(),
          ],
        ),
      ),
    );
  }

  Widget _buildChart(List<SetTrendPoint> pts) {
    final spots = pts.asMap().entries.map((e) {
      return FlSpot(e.key.toDouble(), e.value.score);
    }).toList();

    final bestScore = pts.map((p) => p.score).reduce((a, b) => a > b ? a : b);
    final avgScore  = pts.map((p) => p.score).reduce((a, b) => a + b) / pts.length;

    final sessionStartIndices = <int>[];
    for (int i = 0; i < pts.length; i++) {
      if (pts[i].isSessionStart) sessionStartIndices.add(i);
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          height: 180,
          child: LineChart(
            LineChartData(
              minY: 0,
              maxY: 100,
              gridData: FlGridData(
                show: true,
                drawVerticalLine: false,
                horizontalInterval: 25,
                getDrawingHorizontalLine: (_) => FlLine(
                  color: Colors.white.withOpacity(0.07),
                  strokeWidth: 1,
                ),
              ),
              borderData: FlBorderData(
                show: true,
                border: Border(
                  bottom: BorderSide(
                      color: Colors.white.withOpacity(0.2), width: 1),
                  left: BorderSide(
                      color: Colors.white.withOpacity(0.2), width: 1),
                ),
              ),
              extraLinesData: ExtraLinesData(
                verticalLines: sessionStartIndices.map((i) {
                  return VerticalLine(
                    x: i.toDouble(),
                    color: Colors.white.withOpacity(0.25),
                    strokeWidth: 1.2,
                    dashArray: [5, 4],
                    label: VerticalLineLabel(
                      show: true,
                      alignment: Alignment.topRight,
                      padding: const EdgeInsets.only(left: 4),
                      style: const TextStyle(
                          color: Colors.white38,
                          fontSize: 8,
                          fontWeight: FontWeight.w600),
                      labelResolver: (_) => 'new session',
                    ),
                  );
                }).toList(),
              ),
              titlesData: FlTitlesData(
                topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false)),
                leftTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 32,
                    interval: 25,
                    getTitlesWidget: (value, _) => Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        '${value.toInt()}',
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 9),
                      ),
                    ),
                  ),
                ),
                bottomTitles: AxisTitles(
                  sideTitles: SideTitles(
                    showTitles: true,
                    reservedSize: 22,
                    interval: 1,
                    getTitlesWidget: (value, meta) {
                      final idx = value.toInt();
                      if (value != idx.toDouble()) return const SizedBox.shrink();
                      if (idx < 0 || idx >= pts.length) return const SizedBox.shrink();
                      final pt           = pts[idx];
                      final isNewSession = pt.isSessionStart;
                      return Text(
                        pt.xLabel,
                        style: TextStyle(
                          color: isNewSession
                              ? widget.colour
                              : Colors.white54,
                          fontSize: 9,
                          fontWeight: isNewSession
                              ? FontWeight.w800
                              : FontWeight.w500,
                        ),
                      );
                    },
                  ),
                ),
              ),
              lineTouchData: LineTouchData(
                touchTooltipData: LineTouchTooltipData(
                  getTooltipColor: (_) => const Color(0xFF2A2A2A),
                  getTooltipItems: (touchedSpots) =>
                      touchedSpots.map((s) {
                        final idx = s.x.toInt();
                        if (idx < 0 || idx >= pts.length) return null;
                        final pt  = pts[idx];
                        final angleStr = pt.avgJointAngle != null
                            ? '  ·  ${pt.avgJointAngle!.toStringAsFixed(1)}°'
                            : '';
                        return LineTooltipItem(
                          'Session ${pt.sessionIndex + 1} · Set ${pt.setNumber}\n'
                          '${pt.score.toInt()}% form$angleStr',
                          TextStyle(
                            color: widget.colour,
                            fontWeight: FontWeight.w700,
                            fontSize: 11,
                          ),
                        );
                      }).toList(),
                ),
              ),
              lineBarsData: [
                LineChartBarData(
                  spots: spots,
                  isCurved: true,
                  curveSmoothness: 0.3,
                  color: widget.colour,
                  barWidth: 2.5,
                  dotData: FlDotData(
                    show: true,
                    getDotPainter: (spot, _, __, ___) {
                      return FlDotCirclePainter(
                        radius:      4,
                        color:       widget.colour,
                        strokeWidth: 1,
                        strokeColor: widget.colour.withOpacity(0.4),
                      );
                    },
                  ),
                  belowBarData: BarAreaData(
                    show: true,
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end:   Alignment.bottomCenter,
                      colors: [
                        widget.colour.withOpacity(0.15),
                        widget.colour.withOpacity(0.0),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),

        const SizedBox(height: 12),

        Row(
          children: [
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: widget.colour.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: widget.colour.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'AVERAGE SET',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${avgScore.toInt()}%',
                      style: TextStyle(
                        color: widget.colour,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(
                    vertical: 10, horizontal: 12),
                decoration: BoxDecoration(
                  color: widget.colour.withOpacity(0.08),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(
                      color: widget.colour.withOpacity(0.25)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'BEST SET',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1,
                      ),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${bestScore.toInt()}%',
                      style: TextStyle(
                        color: widget.colour,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),

        const SizedBox(height: 8),

        Text(
          '${pts.length} set${pts.length == 1 ? '' : 's'} total',
          style: TextStyle(
            color: widget.colour,
            fontSize: 14,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }

  Widget _buildSessionLegend(List<SetTrendPoint> pts) {
    final Map<int, DateTime> groups = {};
    for (final pt in pts) {
      groups.putIfAbsent(pt.sessionIndex, () => pt.timestamp);
    }

    if (groups.length <= 1) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Divider(color: Colors.white10, height: 24),
        const Text(
          'SESSIONS',
          style: TextStyle(
            color: Colors.white70,
            fontSize: 10,
            fontWeight: FontWeight.w700,
            letterSpacing: 1.5,
          ),
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: groups.entries.map((entry) {
            final idx   = entry.key;
            final date  = entry.value;
            final now   = DateTime.now();
            final day   = DateTime(date.year, date.month, date.day);
            final today = DateTime(now.year, now.month, now.day);
            final diff  = today.difference(day).inDays;

            final String dateLabel;
            if (diff == 0) {
              dateLabel = 'Today';
            } else if (diff == 1) {
              dateLabel = 'Yesterday';
            } else {
              const months = [
                'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
                'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
              ];
              dateLabel = '${day.day} ${months[day.month - 1]}';
            }

            final setsInSession = pts
                .where((p) => p.sessionIndex == idx)
                .map((p) => p.xLabel)
                .toList();
            final rangeLabel = setsInSession.length == 1
                ? setsInSession.first
                : '${setsInSession.first}–${setsInSession.last}';

            return Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: widget.colour.withOpacity(0.08),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color: widget.colour.withOpacity(0.3)),
              ),
              child: Text(
                'Session ${idx + 1} · $dateLabel · $rangeLabel',
                style: TextStyle(
                  color: widget.colour.withOpacity(0.9),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  // ── Joint angle comparison — dual tick ───────────────────────────────────
  // latestAngle : angle from the most recent set (bright tick — act on this)
  // allTimeAvg  : average across all sets (faded tick — context only)
  //               null when there is only one data point
  Widget _buildAngleComparison(double latestAngle, double? allTimeAvg) {
    final ideal          = kIdealAngles[widget.exercise]!;
    final exerciseColour = widget.colour;
    final isInIdealRange = latestAngle >= ideal.min && latestAngle <= ideal.max;

    final double deviation;
    final String direction;
    if (latestAngle < ideal.min) {
      deviation = ideal.min - latestAngle;
      direction = 'too acute';
    } else if (latestAngle > ideal.max) {
      deviation = latestAngle - ideal.max;
      direction = 'too shallow';
    } else {
      deviation = 0;
      direction = '';
    }

    // Latest tick — full exercise colour, bright
    final latestTickColour = exerciseColour;
    // Average tick — same colour but clearly dimmer
    final avgTickColour    = exerciseColour.withOpacity(0.4);

    final String statusText;
    if (isInIdealRange) {
      statusText = 'Your depth is within the ideal range — great work.';
    } else if (direction == 'too shallow') {
      statusText =
          'You\'re ${deviation.toStringAsFixed(0)}° too shallow — try to go '
          '${deviation > 20 ? 'significantly' : 'slightly'} deeper next set.';
    } else {
      statusText =
          'You\'re going ${deviation.toStringAsFixed(0)}° past the ideal range '
          '— ease off depth slightly to protect your joints.';
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: exerciseColour.withOpacity(0.35)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Header ───────────────────────────────────────────────────────
          // Title same brightness as "Latest session" label (full opacity)
          Row(
            children: [
              Icon(Icons.straighten_rounded,
                  color: exerciseColour, size: 14),
              const SizedBox(width: 8),
              Text(
                'JOINT ANGLE ANALYSIS',
                style: TextStyle(
                  color: exerciseColour,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          // Subtitle — same darkness as angle markers (0.4 opacity)
          Text(
            ideal.joint,
            style: TextStyle(
                color: exerciseColour.withOpacity(0.4), fontSize: 11),
          ),
          const SizedBox(height: 20),

          // ── Single bar with both ticks ────────────────────────────────
          LayoutBuilder(builder: (context, constraints) {
            final totalWidth     = constraints.maxWidth;
            final idealStartFrac = ideal.min / ideal.scale;
            final idealEndFrac   = ideal.max / ideal.scale;
            final latestFrac     = (latestAngle / ideal.scale).clamp(0.0, 1.0);
            final avgFrac        = allTimeAvg != null
                ? (allTimeAvg / ideal.scale).clamp(0.0, 1.0)
                : null;

            // Pixel positions of each tick centre
            final latestPx = (totalWidth * latestFrac).clamp(0.0, totalWidth);
            final avgPx    = avgFrac != null
                ? (totalWidth * avgFrac).clamp(0.0, totalWidth)
                : null;

            // Ideal zone label sits centred above the green zone
            final idealCentrePx =
                totalWidth * (idealStartFrac + idealEndFrac) / 2;

            return Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Axis edge labels ──────────────────────────────────────
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('0°',
                        style: TextStyle(
                            color: exerciseColour.withOpacity(0.4),
                            fontSize: 9)),
                    Text('${ideal.scale.toInt()}°',
                        style: TextStyle(
                            color: exerciseColour.withOpacity(0.4),
                            fontSize: 9)),
                  ],
                ),
                const SizedBox(height: 4),

                // ── Bar ───────────────────────────────────────────────────
                SizedBox(
                  height: 20,
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      // Background track
                      Positioned(
                        top: 7, left: 0, right: 0,
                        child: Container(
                          height: 6,
                          decoration: BoxDecoration(
                            color: Colors.white.withOpacity(0.06),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      // Ideal zone — exercise colour tinted
                      Positioned(
                        left: totalWidth * idealStartFrac,
                        width: totalWidth * (idealEndFrac - idealStartFrac),
                        top: 7,
                        height: 6,
                        child: Container(
                          decoration: BoxDecoration(
                            color: exerciseColour.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                      // Average tick — thinner, dimmer
                      if (avgPx != null)
                        Positioned(
                          left: (avgPx - 1.5).clamp(0.0, totalWidth - 3),
                          top: 5,
                          child: Container(
                            width: 3,
                            height: 10,
                            decoration: BoxDecoration(
                              color: avgTickColour,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        ),
                      // Latest tick — wider, full brightness
                      Positioned(
                        left: (latestPx - 2.5).clamp(0.0, totalWidth - 5),
                        top: 2,
                        child: Container(
                          width: 5,
                          height: 16,
                          decoration: BoxDecoration(
                            color: latestTickColour,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Ideal zone label — centred below its zone ─────────────
                const SizedBox(height: 4),
                Stack(
                  children: [
                    SizedBox(width: totalWidth, height: 14),
                    Positioned(
                      left: (idealCentrePx - 40).clamp(0.0, totalWidth - 80),
                      top: 0,
                      child: SizedBox(
                        width: 80,
                        child: Text(
                          'Ideal ${ideal.min.toInt()}–${ideal.max.toInt()}°',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: exerciseColour,
                            fontSize: 9,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),

                // ── Angle value labels pinned to tick positions ───────────
                // Latest: full brightness at its tick position
                // Average: dimmer at its tick position
                const SizedBox(height: 10),
                Stack(
                  children: [
                    SizedBox(width: totalWidth, height: 32),

                    // Latest label
                    Positioned(
                      left: (latestPx - 28).clamp(0.0, totalWidth - 56),
                      top: 0,
                      child: SizedBox(
                        width: 56,
                        child: Column(
                          children: [
                            Text(
                              '${latestAngle.toStringAsFixed(1)}°',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: latestTickColour,
                                fontSize: 11,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                            Text(
                              'Latest',
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: latestTickColour,
                                fontSize: 9,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    // Average label — only shown if 2+ sessions
                    if (avgPx != null && allTimeAvg != null)
                      Positioned(
                        left: (avgPx - 28).clamp(0.0, totalWidth - 56),
                        top: 0,
                        child: SizedBox(
                          width: 56,
                          child: Column(
                            children: [
                              Text(
                                '${allTimeAvg.toStringAsFixed(1)}°',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: avgTickColour,
                                  fontSize: 10,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                'Avg',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  color: avgTickColour,
                                  fontSize: 9,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ],
            );
          }),

          const SizedBox(height: 14),
          Divider(color: exerciseColour.withOpacity(0.15), height: 1),
          const SizedBox(height: 12),

          // Status line
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(
                isInIdealRange
                    ? Icons.check_circle_outline_rounded
                    : Icons.info_outline_rounded,
                color: exerciseColour,
                size: 14,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  statusText,
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.75),
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHowItWorks() {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.white10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(Icons.info_outline,
                  color: widget.colour.withOpacity(0.7), size: 14),
              const SizedBox(width: 8),
              const Text(
                'HOW THIS WORKS',
                style: TextStyle(
                  color: Colors.white54,
                  fontSize: 10,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.4,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _howItWorksRow(
            icon: Icons.bar_chart_rounded,
            colour: widget.colour,
            title: 'Form Score',
            body:
                'Each set is scored using: reps ÷ (reps + form corrections) × 100. '
                'A perfect set with zero corrections scores 100%. '
                'The more the AI had to correct your form, the lower the score.',
          ),
          const SizedBox(height: 10),
          _howItWorksRow(
            icon: Icons.straighten_rounded,
            colour: widget.colour,
            title: 'Joint Angle',
            body:
                'The bright tick shows your most recent session — that\'s what '
                'to act on. The faded tick shows your all-time average for context. '
                'Angles are measured at the deepest point of each rep using '
                'MediaPipe pose landmarks.',
          ),
          const SizedBox(height: 10),
          _howItWorksRow(
            icon: Icons.timeline_rounded,
            colour: widget.colour,
            title: 'Set Numbering',
            body:
                'Sets are numbered globally across all time — S1, S2, S3 … '
                'so every point on the chart is unique. '
                'The dashed vertical line marks where a new workout day begins.',
          ),
          const SizedBox(height: 10),
          _howItWorksRow(
            icon: Icons.block_rounded,
            colour: widget.colour,
            title: 'What\'s Filtered Out',
            body:
                'Positioning messages like "step closer" or "centre yourself" '
                'are excluded from the score — only genuine form feedback '
                'counts against you.',
          ),
        ],
      ),
    );
  }

  Widget _howItWorksRow({
    required IconData icon,
    required Color colour,
    required String title,
    required String body,
  }) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, color: colour.withOpacity(0.5), size: 14),
        const SizedBox(width: 10),
        Expanded(
          child: RichText(
            text: TextSpan(
              children: [
                TextSpan(
                  text: '$title  ',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                TextSpan(
                  text: body,
                  style: const TextStyle(
                    color: Colors.white38,
                    fontSize: 12,
                    height: 1.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Session History Strip ─────────────────────────────────────────────────
class _SessionHistoryStrip extends StatefulWidget {
  final WorkoutSessionService sessionService;
  final WorkoutSession? expandedSession;
  final String? selectedDay;
  final ScrollController stripScrollController;
  final void Function(String?) onDaySelected;
  final void Function(WorkoutSession) onSessionTap;
  final void Function(WorkoutSession session, int setNumber) onAskFollowUp;
  final VoidCallback onTrendTap;

  const _SessionHistoryStrip({
    super.key,
    required this.sessionService,
    required this.expandedSession,
    required this.selectedDay,
    required this.stripScrollController,
    required this.onDaySelected,
    required this.onSessionTap,
    required this.onAskFollowUp,
    required this.onTrendTap,
  });

  @override
  State<_SessionHistoryStrip> createState() => _SessionHistoryStripState();
}

class _SessionHistoryStripState extends State<_SessionHistoryStrip> {
  final FlutterTts _tts = FlutterTts();
  bool _isSpeaking = false;

  @override
  void initState() {
    super.initState();
    _tts.setLanguage('en-US');
    _tts.setSpeechRate(0.58);
    _tts.setVolume(1.0);
    _tts.setPitch(1.15);
    _tts.setCompletionHandler(() {
      if (mounted) setState(() => _isSpeaking = false);
    });
    _tts.setErrorHandler((_) {
      if (mounted) setState(() => _isSpeaking = false);
    });
  }

  @override
  void didUpdateWidget(_SessionHistoryStrip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.expandedSession?.id != widget.expandedSession?.id) {
      _stopSpeaking();
    }
  }

  @override
  void dispose() {
    _tts.stop();
    super.dispose();
  }

  Future<void> _toggleSpeaking(String text) async {
    if (_isSpeaking) {
      await _stopSpeaking();
    } else {
      setState(() => _isSpeaking = true);
      await _tts.speak(text);
    }
  }

  Future<void> _stopSpeaking() async {
    await _tts.stop();
    if (mounted) setState(() => _isSpeaking = false);
  }

  Map<String, List<WorkoutSession>> _groupByDay(List<WorkoutSession> sessions) {
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final Map<String, List<WorkoutSession>> groups = {};
    for (final s in sessions) {
      final d    = DateTime(
          s.timestamp.year, s.timestamp.month, s.timestamp.day);
      final diff = today.difference(d).inDays;
      final String label;
      if (diff == 0) {
        label = 'Today';
      } else if (diff == 1) {
        label = 'Yesterday';
      } else {
        const weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
        const months   = [
          'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
          'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
        ];
        label = '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
      }
      groups.putIfAbsent(label, () => []).add(s);
    }
    return groups;
  }

  IconData _iconFor(String exercise) {
    switch (exercise) {
      case 'squat':
      case 'lunge_left':
      case 'lunge_right':  return Icons.directions_run;
      case 'pushup':       return Icons.fitness_center;
      case 'bicep_curl':   return Icons.sports_gymnastics;
      case 'jumping_jack': return Icons.directions_walk;
      case 'sit_up':
      case 'glute_bridge': return Icons.self_improvement;
      case 'plank':        return Icons.accessibility_new;
      default:             return Icons.sports;
    }
  }

  int _setNumberFor(WorkoutSession target, List<WorkoutSession> daySessions) {
    int setNum = 0;
    for (int i = daySessions.length - 1; i >= 0; i--) {
      if (daySessions[i].exercise == target.exercise) {
        setNum++;
        if (daySessions[i].id == target.id) return setNum;
      }
    }
    return 1;
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WorkoutSession>>(
      stream: widget.sessionService.sessionsStream(),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? [];
        if (sessions.isEmpty) return const SizedBox.shrink();

        final groups = _groupByDay(sessions);

        if (widget.selectedDay != null &&
            !groups.containsKey(widget.selectedDay)) {
          widget.onDaySelected(null);
        }

        final daySessions = groups[widget.selectedDay] ?? [];

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.max,
          children: [

            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 12, 8),
              child: Row(
                children: [
                  if (widget.selectedDay != null) ...[
                    GestureDetector(
                      onTap: () {
                        if (widget.expandedSession != null) {
                          widget.onSessionTap(widget.expandedSession!);
                        }
                        widget.onDaySelected(null);
                      },
                      child: const Icon(Icons.arrow_back_ios_new_rounded,
                          color: Color(0xFFB9FF2B), size: 12),
                    ),
                    const SizedBox(width: 6),
                  ],
                  Text(
                    widget.selectedDay != null
                        ? widget.selectedDay!.toUpperCase()
                        : 'RECENT SESSIONS',
                    style: TextStyle(
                      color: Colors.white.withOpacity(0.35),
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.5,
                    ),
                  ),
                  const Spacer(),
                  GestureDetector(
                    onTap: widget.onTrendTap,
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 5),
                      decoration: BoxDecoration(
                        color: const Color(0xFFFF5E00).withOpacity(0.1),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: const Color(0xFFFF5E00).withOpacity(0.4)),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.show_chart_rounded,
                              color: Color(0xFFFF5E00), size: 14),
                          SizedBox(width: 5),
                          Text(
                            'Trend',
                            style: TextStyle(
                              color: Color(0xFFFF5E00),
                              fontSize: 11,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            SizedBox(
              height: 100,
              child: AnimatedSwitcher(
                duration: const Duration(milliseconds: 180),
                child: widget.selectedDay == null
                    ? ListView(
                        key: const ValueKey('dates'),
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        children: groups.entries.map((entry) {
                          final label   = entry.key;
                          final daySess = entry.value;
                          return GestureDetector(
                            onTap: () => widget.onDaySelected(label),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 10),
                              width: 130,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: const Color(0xFFFF5E00)
                                      .withOpacity(0.5),
                                  width: 1.2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: const Color(0xFFFF5E00)
                                        .withOpacity(0.08),
                                    blurRadius: 8,
                                    offset: const Offset(0, 3),
                                  ),
                                ],
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      const Icon(
                                          Icons.calendar_today_rounded,
                                          color: Color(0xFFFF5E00),
                                          size: 13),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          label,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${daySess.length} session${daySess.length == 1 ? '' : 's'}',
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 11),
                                  ),
                                  const Spacer(),
                                  Row(
                                    children: [
                                      Text(
                                        'Tap to view',
                                        style: TextStyle(
                                          color:
                                              Colors.white.withOpacity(0.3),
                                          fontSize: 10,
                                        ),
                                      ),
                                      const SizedBox(width: 2),
                                      Icon(Icons.chevron_right,
                                          color: Colors.white.withOpacity(0.3),
                                          size: 12),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          );
                        }).toList(),
                      )
                    : ListView.builder(
                        key: ValueKey(widget.selectedDay),
                        controller: widget.stripScrollController,
                        scrollDirection: Axis.horizontal,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: daySessions.length,
                        itemBuilder: (context, index) {
                          final session = daySessions[index];
                          final isExpanded =
                              widget.expandedSession?.id == session.id;
                          final setNum =
                              _setNumberFor(session, daySessions);

                          return GestureDetector(
                            onTap: () => widget.onSessionTap(session),
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              margin: const EdgeInsets.only(right: 10),
                              width: 140,
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: isExpanded
                                    ? const Color(0xFFFF5E00)
                                        .withOpacity(0.15)
                                    : const Color(0xFF1A1A1A),
                                borderRadius: BorderRadius.circular(14),
                                border: Border.all(
                                  color: isExpanded
                                      ? const Color(0xFFFF5E00)
                                      : Colors.white12,
                                  width: isExpanded ? 1.5 : 1,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(_iconFor(session.exercise),
                                          color: const Color(0xFFB9FF2B),
                                          size: 14),
                                      const SizedBox(width: 6),
                                      Expanded(
                                        child: Text(
                                          session.exerciseDisplayName,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12,
                                            fontWeight: FontWeight.w700,
                                          ),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Set $setNum',
                                    style: TextStyle(
                                      color: const Color(0xFFFF5E00)
                                          .withOpacity(0.85),
                                      fontSize: 10,
                                      fontWeight: FontWeight.w700,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    '${session.reps} reps · ${session.durationFormatted}',
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 11),
                                  ),
                                  const Spacer(),
                                  Text(
                                    session.timeAgo,
                                    style: TextStyle(
                                      color: Colors.white.withOpacity(0.3),
                                      fontSize: 10,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
              ),
            ),

            if (widget.expandedSession != null)
              Expanded(
                child: SingleChildScrollView(
                  physics: const BouncingScrollPhysics(),
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 250),
                    margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                          color: const Color(0xFFFF5E00).withOpacity(0.4)),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.record_voice_over,
                                color: Color(0xFFFF5E00), size: 16),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                '${widget.expandedSession!.exerciseDisplayName} Debrief',
                                style: const TextStyle(
                                  color: Color(0xFFFF5E00),
                                  fontSize: 13,
                                  fontWeight: FontWeight.w700,
                                ),
                              ),
                            ),
                            GestureDetector(
                              onTap: () => _toggleSpeaking(
                                  widget.expandedSession!.debriefText),
                              child: AnimatedContainer(
                                duration: const Duration(milliseconds: 200),
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: _isSpeaking
                                      ? const Color(0xFFFF5E00)
                                      : const Color(0xFFFF5E00)
                                          .withOpacity(0.15),
                                  shape: BoxShape.circle,
                                  border: Border.all(
                                    color: const Color(0xFFFF5E00)
                                        .withOpacity(0.6),
                                  ),
                                ),
                                child: Icon(
                                  _isSpeaking
                                      ? Icons.stop_rounded
                                      : Icons.play_arrow_rounded,
                                  color: _isSpeaking
                                      ? Colors.white
                                      : const Color(0xFFFF5E00),
                                  size: 20,
                                ),
                              ),
                            ),
                          ],
                        ),

                        const SizedBox(height: 10),

                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: Colors.black.withOpacity(0.3),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Text(
                            widget.expandedSession!.debriefText,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 15,
                              height: 1.7,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                        ),

                        const SizedBox(height: 12),

                        GestureDetector(
                          onTap: () {
                            final setNum = _setNumberFor(
                                widget.expandedSession!, daySessions);
                            widget.onAskFollowUp(
                                widget.expandedSession!, setNum);
                          },
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              color: const Color(0xFFB9FF2B)
                                  .withOpacity(0.1),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(
                                  color: const Color(0xFFB9FF2B)
                                      .withOpacity(0.4)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(Icons.chat_bubble_outline,
                                    color: Color(0xFFB9FF2B), size: 14),
                                SizedBox(width: 6),
                                Text(
                                  'Ask the coach about this session',
                                  style: TextStyle(
                                    color: Color(0xFFB9FF2B),
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

            const Divider(color: Colors.white10, height: 1),
          ],
        );
      },
    );
  }
}

// ── Chat Bubble ───────────────────────────────────────────────────────────
class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isStreaming;

  const _ChatBubble({
    required this.text,
    required this.isUser,
    required this.isStreaming,
  });

  @override
  Widget build(BuildContext context) {
    final isJsonFormat =
        text.trimLeft().startsWith('[') ||
        text.trimLeft().startsWith('```json');

    if (!isUser && isStreaming && isJsonFormat) {
      return const _CardGenerationPlaceholder();
    }

    if (!isUser && !isStreaming) {
      final cleanedText =
          text.replaceAll('```json', '').replaceAll('```', '').trim();
      if (cleanedText.startsWith('[')) {
        try {
          final List<dynamic> parsed = jsonDecode(cleanedText);
          if (parsed.isNotEmpty && parsed.first is Map) {
            return _CardDeck(cards: parsed.cast<Map<String, dynamic>>());
          }
        } catch (_) {}
      }
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFB9FF2B) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: const Color(0xFFFF5E00).withOpacity(0.75),
                  width: 1.2),
          boxShadow: isUser
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFFFF5E00).withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: isUser
            ? Text(text,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w600))
            : MarkdownBody(
                data: text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                      color: Colors.white, fontSize: 15, height: 1.6),
                  h1: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 2),
                  h2: const TextStyle(
                      color: Color(0xFFFF5E00),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 2),
                  h3: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.8),
                  strong: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                  em: const TextStyle(
                      color: Colors.white70,
                      fontStyle: FontStyle.italic),
                  listBullet: const TextStyle(
                      color: Color(0xFFFF5E00), fontSize: 15),
                ),
              ),
      ),
    );
  }
}

// ── Card Deck ─────────────────────────────────────────────────────────────
class _CardDeck extends StatefulWidget {
  final List<Map<String, dynamic>> cards;
  const _CardDeck({required this.cards});

  @override
  State<_CardDeck> createState() => _CardDeckState();
}

class _CardDeckState extends State<_CardDeck> {
  late List<Map<String, dynamic>> _currentCards;

  @override
  void initState() {
    super.initState();
    _currentCards = List.from(widget.cards);
  }

  void _resetCards() =>
      setState(() => _currentCards = List.from(widget.cards));

  @override
  Widget build(BuildContext context) {
    if (_currentCards.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _resetCards,
          icon: const Icon(Icons.refresh, color: Color(0xFFFF5E00)),
          label: const Text('Review Cards Again',
              style: TextStyle(
                  color: Color(0xFFFF5E00), fontWeight: FontWeight.bold)),
          style: TextButton.styleFrom(
            backgroundColor: const Color(0xFFFF5E00).withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      height: 380,
      child: Stack(
        alignment: Alignment.center,
        children: _currentCards.asMap().entries.map((entry) {
          final index = entry.key;
          final card  = entry.value;
          if (index > 2) return const SizedBox.shrink();
          final scale  = 1.0 - (index * 0.05);
          final offset = index * 14.0;
          Widget inner = Transform.scale(
            scale: scale,
            alignment: Alignment.topCenter,
            child: _buildCardContent(card),
          );
          if (index == 0) {
            inner = Dismissible(
              key: UniqueKey(),
              onDismissed: (_) =>
                  setState(() => _currentCards.removeAt(0)),
              child: inner,
            );
          }
          return Positioned(
            top: offset, bottom: 0,
            left: index * 8.0, right: index * 8.0,
            child: inner,
          );
        }).toList().reversed.toList(),
      ),
    );
  }

  Widget _buildCardContent(Map<String, dynamic> card) {
    final title       = card['title']       ?? card['name']        ?? card['step']    ?? 'Detail';
    final description = card['description'] ?? card['instruction'] ?? card['details'] ?? '';
    final badge       = card['badge']       ?? card['impact']      ??
                        card['muscle_group'] ?? card['confidence'];

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E1200), Color(0xFF110500)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFF5E00), width: 2),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5E00).withOpacity(0.25),
            blurRadius: 15,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5E00),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge.toString().toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5),
                  ),
                ),
              const Icon(Icons.local_fire_department,
                  color: Color(0xFFFF5E00), size: 28),
            ],
          ),
          const SizedBox(height: 20),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.1)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: Colors.white24, height: 1),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Text(description,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.6,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard_double_arrow_left,
                    color: Colors.white38, size: 16),
                SizedBox(width: 8),
                Text('SWIPE TO DISMISS',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
                SizedBox(width: 8),
                Icon(Icons.keyboard_double_arrow_right,
                    color: Colors.white38, size: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CardGenerationPlaceholder extends StatelessWidget {
  const _CardGenerationPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2E1200), Color(0xFF110500)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(
              color: const Color(0xFFFF5E00).withOpacity(0.5), width: 1.5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFFF5E00)),
            ),
            SizedBox(width: 16),
            Text('Designing custom deck...',
                style: TextStyle(
                    color: Colors.white70,
                    fontStyle: FontStyle.italic,
                    fontSize: 15)),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(
              color: const Color(0xFFFF5E00).withOpacity(0.75), width: 1.2),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFFF5E00)),
            ),
            SizedBox(width: 12),
            Text('Searching knowledge base...',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}