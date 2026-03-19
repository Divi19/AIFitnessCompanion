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

  // Human-readable "2 hours ago", "Yesterday", "3 days ago" etc.
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

  // Two-sentence preview shown on the session card
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

class WorkoutSessionService {
  final _db  = FirebaseFirestore.instance;

  // ── Save session + generate debrief ─────────────────────────────────────
  // Called by Flutter when it receives a valid session broadcast from Kotlin.
  // Generates the AI debrief first, then saves everything to Firestore.
  Future<WorkoutSession?> saveSession({
    required String exercise,
    required int reps,
    required int durationMs,
    required Map<String, int> feedbackMap,
  }) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return null;

    try {
      // Fetch user profile for personalised debrief
      final userDoc = await _db.collection('users').doc(uid).get();
      final userData = userDoc.data() ?? {};

      // Generate the debrief text via Gemini
      final debriefText = await _generateDebrief(
        exercise:    exercise,
        reps:        reps,
        durationMs:  durationMs,
        feedbackMap: feedbackMap,
        userData:    userData,
      );

      // Save to Firestore under users/{uid}/workout_sessions/{auto-id}
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

      // Fetch back to get the server timestamp
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

  // ── Generate debrief via Gemini ──────────────────────────────────────────
  Future<String> _generateDebrief({
    required String exercise,
    required int reps,
    required int durationMs,
    required Map<String, int> feedbackMap,
    required Map<String, dynamic> userData,
  }) async {
    final limitations = _extractLimitations(userData['biometrics']);

    // Sort feedback by frequency so most common issues appear first
    final sortedFeedback = feedbackMap.entries.toList()
      ..sort((a, b) => b.value.compareTo(a.value));

    final feedbackBlock = sortedFeedback.isEmpty
        ? 'No specific form feedback recorded — form looked clean.'
        : sortedFeedback
            .map((e) => '- "${e.key}" (${e.value} times)')
            .join('\n');

    final durationSec = durationMs ~/ 1000;
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
          'contents': [{'parts': [{'text': prompt}]}],
        }),
      );

      debugPrint('=== DEBRIEF: status=${response.statusCode} ===');
      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);
        final text = data['candidates'][0]['content']['parts'][0]['text'] as String;
        debugPrint('=== DEBRIEF: generated ${text.length} chars ===');
        return text;
      } else {
        debugPrint('=== DEBRIEF FAILED: ${response.statusCode} body=${response.body} ===');
      }
    } catch (e) {
      debugPrint('Debrief generation error: $e');
    }

    // Fallback if Gemini fails
    return 'Great session! You completed $reps $exerciseDisplay reps in ${durationSec}s. Keep it up!';
  }

  List<String> _extractLimitations(Map<String, dynamic>? biometrics) {
    if (biometrics == null || biometrics['noLimitations'] == true) return [];
    final active = <String>[];
    void check(Map<String, dynamic>? section) {
      section?.forEach((k, v) { if (v == true) active.add(k); });
    }
    check(biometrics['upperBody'] as Map<String, dynamic>?);
    check(biometrics['lowerBody'] as Map<String, dynamic>?);
    check(biometrics['coreSpine'] as Map<String, dynamic>?);
    return active;
  }

  String _displayName(String exercise) {
    const names = {
      'squat': 'Squat', 'pushup': 'Push Up', 'bicep_curl': 'Bicep Curl',
      'jumping_jack': 'Jumping Jack', 'lunge_left': 'Left Lunge',
      'lunge_right': 'Right Lunge', 'sit_up': 'Sit Up',
      'plank': 'Plank', 'glute_bridge': 'Glute Bridge',
    };
    return names[exercise] ?? exercise;
  }
}