import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

// Represents a completed workout session
class WorkoutSession {
  final String id;
  final String exercise;
  final int reps;
  final int durationMs;
  final Map<String, int> feedbackMap;
  final String debriefText;
  final DateTime timestamp;

  WorkoutSession({
    required this.id,
    required this.exercise,
    required this.reps,
    required this.durationMs,
    required this.feedbackMap,
    required this.debriefText,
    required this.timestamp,
  });

  // ── Form quality score ───────────────────────────────────────────────────
  // score = reps / (reps + totalFeedback) * 100, clamped 10–100.
  // Perfect form (0 feedback) = 100. Equal feedback to reps = 50.
  double get formScore {
    if (reps == 0) return 10.0;
    final totalFeedback = feedbackMap.values.fold(0, (a, b) => a + b);
    final raw = reps / (reps + totalFeedback) * 100;
    return raw.clamp(10.0, 100.0);
  }

  String get timeAgo {
    final diff = DateTime.now().difference(timestamp);
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays == 1) return 'Yesterday';
    return '${diff.inDays} days ago';
  }

  String get exerciseDisplayName {
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

  String get durationFormatted {
    final seconds = durationMs ~/ 1000;
    final m = seconds ~/ 60;
    final s = seconds % 60;
    return m > 0 ? '${m}m ${s}s' : '${s}s';
  }

  String get debriefPreview {
    final sentences = debriefText.split(RegExp(r'(?<=[.!?])\s+'));
    final preview = sentences.take(2).join(' ').trim();
    return preview.length > 120
        ? '${preview.substring(0, 120)}...'
        : preview;
  }

  factory WorkoutSession.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    final rawFeedback = data['feedbackMap'] as Map<String, dynamic>? ?? {};
    return WorkoutSession(
      id:          doc.id,
      exercise:    data['exercise']    ?? '',
      reps:        data['reps']        ?? 0,
      durationMs:  data['durationMs']  ?? 0,
      feedbackMap: rawFeedback.map((k, v) => MapEntry(k, (v as num).toInt())),
      debriefText: data['debriefText'] ?? '',
      timestamp:   (data['timestamp'] as Timestamp).toDate(),
    );
  }
}

// ── Set trend data point ─────────────────────────────────────────────────
// One point per set (session) of a specific exercise, ordered oldest→newest.
// setNumber restarts at 1 for each new calendar day — so if the user did
// squats on Monday and Wednesday, Monday has Set 1, Set 2 and Wednesday
// has its own Set 1, Set 2.
// sessionIndex tells the chart which "day group" this point belongs to,
// used to colour-code sets from different days differently.
class SetTrendPoint {
  final String sessionId;
  final double score;       // formScore 0–100
  final int setNumber;      // 1-based within the day
  final int sessionIndex;   // 0-based day group index (for colour banding)
  final String xLabel;      // e.g. "S1", "S2", "S1*" (new session marker)
  final DateTime timestamp;

  const SetTrendPoint({
    required this.sessionId,
    required this.score,
    required this.setNumber,
    required this.sessionIndex,
    required this.xLabel,
    required this.timestamp,
  });
}

class WorkoutSessionService {
  final _db = FirebaseFirestore.instance;

  // ── Save session + generate debrief ─────────────────────────────────────
  Future<WorkoutSession?> saveSession({
    required String exercise,
    required int reps,
    required int durationMs,
    required Map<String, int> feedbackMap,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    try {
      final userDoc  = await _db.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};

      final debriefText = await _generateDebrief(
        exercise:    exercise,
        reps:        reps,
        durationMs:  durationMs,
        feedbackMap: feedbackMap,
        userData:    userData,
      );

      final docRef = await _db
          .collection('users')
          .doc(uid)
          .collection('workout_sessions')
          .add({
        'exercise':    exercise,
        'reps':        reps,
        'durationMs':  durationMs,
        'feedbackMap': feedbackMap,
        'debriefText': debriefText,
        'timestamp':   FieldValue.serverTimestamp(),
      });

      final saved = await docRef.get();
      return WorkoutSession.fromFirestore(saved);
    } catch (e) {
      debugPrint('WorkoutSessionService error: $e');
      return null;
    }
  }

  // ── Fetch recent sessions (for assistant context injection) ──────────────
  Future<List<WorkoutSession>> getRecentSessions({int limit = 3}) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workout_sessions')
        .orderBy('timestamp', descending: true)
        .limit(limit)
        .get();

    return snapshot.docs.map(WorkoutSession.fromFirestore).toList();
  }

  // ── Stream all sessions (for history list in assistant screen) ───────────
  Stream<List<WorkoutSession>> sessionsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return const Stream.empty();

    return _db
        .collection('users')
        .doc(uid)
        .collection('workout_sessions')
        .orderBy('timestamp', descending: true)
        .limit(20)
        .snapshots()
        .map((snap) => snap.docs.map(WorkoutSession.fromFirestore).toList());
  }

  // ── Distinct exercises that have at least one session ────────────────────
  // Used to populate the exercise picker in the trend chart flow.
  // Returns exercise keys (e.g. 'squat', 'pushup') in the order they were
  // most recently performed, deduped.
  Future<List<String>> getExercisesWithSessions() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workout_sessions')
        .orderBy('timestamp', descending: true)
        .limit(50)
        .get();

    final seen  = <String>{};
    final order = <String>[];
    for (final doc in snapshot.docs) {
      final ex = (doc.data()['exercise'] as String?) ?? '';
      if (ex.isNotEmpty && seen.add(ex)) order.add(ex);
    }
    return order;
  }

  // ── Per-set trend for a specific exercise ────────────────────────────────
  // Returns one SetTrendPoint per session of [exercise], ordered
  // oldest→newest (so the chart line goes left to right).
  //
  // Set numbering logic:
  //   - Sessions are grouped by calendar day.
  //   - Within each day the sets are numbered 1, 2, 3 …
  //   - When a new day begins the set counter resets to 1.
  //   - sessionIndex increments each time a new calendar day appears,
  //     allowing the chart to colour-band different days.
  Future<List<SetTrendPoint>> getSetTrendForExercise(String exercise) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return [];

    final snapshot = await _db
        .collection('users')
        .doc(uid)
        .collection('workout_sessions')
        .where('exercise', isEqualTo: exercise)
        .get();  // no orderBy — sort client-side to avoid composite index requirement

    if (snapshot.docs.isEmpty) return [];

    final sessions = snapshot.docs
        .map(WorkoutSession.fromFirestore)
        .toList()
      ..sort((a, b) => a.timestamp.compareTo(b.timestamp)); // oldest → newest

    final points   = <SetTrendPoint>[];
    DateTime? lastDay;
    int setNum       = 0;
    int sessionIndex = -1;

    for (final s in sessions) {
      final day = DateTime(
          s.timestamp.year, s.timestamp.month, s.timestamp.day);

      // New calendar day → reset set counter and bump session group index
      if (lastDay == null || day != lastDay) {
        lastDay      = day;
        setNum       = 0;
        sessionIndex++;
      }
      setNum++;

      // xLabel: "S1", "S2" … If this is the first set of a new day group
      // (other than the very first group), add a bullet to signal a new session
      final isNewSession = setNum == 1 && sessionIndex > 0;
      final xLabel       = isNewSession ? '●S$setNum' : 'S$setNum';

      points.add(SetTrendPoint(
        sessionId:    s.id,
        score:        s.formScore,
        setNumber:    setNum,
        sessionIndex: sessionIndex,
        xLabel:       xLabel,
        timestamp:    s.timestamp,
      ));
    }

    return points;
  }

  // ── Generate debrief via Gemini ──────────────────────────────────────────
  Future<String> _generateDebrief({
    required String exercise,
    required int reps,
    required int durationMs,
    required Map<String, int> feedbackMap,
    required Map<String, dynamic> userData,
  }) async {
    final limitations = _extractLimitations(userData['biometrics']);

    final sortedFeedback = feedbackMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final feedbackBlock = sortedFeedback.isEmpty
        ? 'No specific form feedback recorded — form looked clean.'
        : sortedFeedback
            .map((e) => '- "${e.key}" (${e.value} times)')
            .join('\n');

    final durationSec     = durationMs ~/ 1000;
    final exerciseDisplay = _displayName(exercise);

    final prompt = '''
You are a personal trainer giving a post-set coaching debrief based purely on pose tracking data.

Session Data:
- Exercise: $exerciseDisplay
- Reps completed: $reps
- Duration: ${durationSec}s
- Physical limitations: ${limitations.isEmpty ? 'None' : limitations.join(', ')}

Form feedback from pose tracker (most frequent first):
$feedbackBlock

Write a spoken coaching debrief of around 100-150 words. Rules:
- Focus ONLY on the pose tracking data above — do NOT mention the user's fitness goals, preferred activities, or anything outside this session
- Keep any positive opener to ONE short sentence maximum, then immediately move to coaching
- Cover: (1) the top 1-2 form issues from the data and WHY they matter for safety or effectiveness, (2) one specific actionable drill or cue to fix it next set
- If form feedback is empty, say their form looked clean and give one progression tip for this specific exercise
- If they have physical limitations, flag if any form issue could aggravate them
- Do NOT use bullet points, headers, numbers, or markdown — plain flowing sentences only
- Do NOT mention yoga, cardio, goals, or anything unrelated to the exercise just performed
- Sound like a real coach talking, not a report — direct, useful, energetic
''';

    try {
      final response = await http.post(
        Uri.parse(
          'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash:generateContent?key=${AppConstants.geminiApiKey}',
        ),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {'text': prompt}
              ]
            }
          ],
        }),
      );

      debugPrint('=== DEBRIEF: status=${response.statusCode} ===');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text =
            data['candidates'][0]['content']['parts'][0]['text'] as String;
        debugPrint('=== DEBRIEF: generated ${text.length} chars ===');
        return text;
      } else {
        debugPrint(
            '=== DEBRIEF FAILED: ${response.statusCode} body=${response.body} ===');
      }
    } catch (e) {
      debugPrint('Debrief generation error: $e');
    }

    return 'Great session! You completed $reps ${_displayName(exercise)} reps in ${durationSec}s. Keep it up!';
  }

  List<String> _extractLimitations(Map<String, dynamic>? biometrics) {
    if (biometrics == null || biometrics['noLimitations'] == true) return [];
    final active = <String>[];
    void check(Map<String, dynamic>? section) {
      section?.forEach((k, v) {
        if (v == true) active.add(k);
      });
    }
    check(biometrics['upperBody'] as Map<String, dynamic>?);
    check(biometrics['lowerBody'] as Map<String, dynamic>?);
    check(biometrics['coreSpine'] as Map<String, dynamic>?);
    return active;
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