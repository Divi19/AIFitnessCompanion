// ─────────────────────────────────────────────────────────────────────────────
// demo_seed.dart
// Place this file at:  lib/dev/demo_seed.dart
//
// HOW TO RUN:
//   1. Add one temporary import + call in main.dart AFTER login is confirmed:
//
//        import 'dev/demo_seed.dart';
//        // inside initState or after auth resolves:
//        await DemoSeed.seed();
//
//   2. Hot-restart once on the demo account. Watch logcat for:
//        [DemoSeed] Done — 20 sessions written.
//   3. Remove the import + call before the final demo build.
//
// KEEPING IT PRIVATE:
//   Option A — just delete this file after seeding (safest).
//   Option B — wrap with a compile-time flag so it never runs in production:
//
//        if (const bool.fromEnvironment('SEED_DEMO')) await DemoSeed.seed();
//
//     Then run:  flutter run --dart-define=SEED_DEMO=true
//     Normal builds skip it entirely.
//
// IDEMPOTENCY:
//   The script stamps each document with _seeded:true and checks for that
//   before writing. Safe to call multiple times — only writes once.
//
// WHAT IT WRITES:
//   Squats, push-ups, and bicep curls across 7 different days.
//   Form scores start rough (~35%) and trend clearly upward (~90%) by day 7.
//   The per-set trend chart for each exercise will show a satisfying upward curve.
// ─────────────────────────────────────────────────────────────────────────────

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

class DemoSeed {
  static Future<void> seed() async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) {
      debugPrint('[DemoSeed] No logged-in user — skipping.');
      return;
    }

    final db         = FirebaseFirestore.instance;
    final collection = db
        .collection('users')
        .doc(uid)
        .collection('workout_sessions');

    // Idempotency: only seed once
    final existing = await collection
        .where('_seeded', isEqualTo: true)
        .limit(1)
        .get();

    if (existing.docs.isNotEmpty) {
      debugPrint('[DemoSeed] Seed data already present — skipping.');
      return;
    }

    debugPrint('[DemoSeed] Writing demo data...');

    final now = DateTime.now();

    // Helper: midnight of N days ago
    DateTime dayAt(int daysAgo, int hour, int minute) {
      final base = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: daysAgo));
      return DateTime(base.year, base.month, base.day, hour, minute);
    }

    // ── Session list ─────────────────────────────────────────────────────
    // Fields: exercise, reps, durationMs, feedbackMap, daysAgo, hour, minute
    //
    // formScore = reps / (reps + sum(feedback)) * 100
    // Day 7: feedback ≈ reps      → score ≈ 33–40%
    // Day 4: feedback ≈ reps/2    → score ≈ 55–65%
    // Day 1: feedback ≈ 1–2       → score ≈ 85–92%
    // Day 0: feedback = 0         → score = 100%
    final sessions = [
      // ── Day 7 (oldest) ─────────────────────────────────────────────────
      _S('squat',      10, 38000, {'Go deeper': 8, 'Keep chest up': 4},    7, 9,  0),
      _S('pushup',      8, 32000, {'Get on floor': 6, 'Lock elbows': 3},   7, 9, 25),
      _S('bicep_curl',  9, 28000, {'Keep elbows tucked': 9},               7, 9, 50),

      // ── Day 6 ───────────────────────────────────────────────────────────
      _S('squat',      11, 40000, {'Go deeper': 6, 'Keep chest up': 3},    6, 9,  0),
      _S('pushup',      9, 33000, {'Get on floor': 5},                     6, 9, 20),

      // ── Day 5 ───────────────────────────────────────────────────────────
      _S('squat',      12, 42000, {'Go deeper': 4, 'Keep chest up': 2},    5, 9,  0),
      _S('bicep_curl', 10, 30000, {'Keep elbows tucked': 5},               5, 9, 20),

      // ── Day 4 ───────────────────────────────────────────────────────────
      _S('squat',      12, 43000, {'Go deeper': 3},                        4, 9,  0),
      _S('pushup',     10, 35000, {'Get on floor': 3},                     4, 9, 20),
      _S('bicep_curl', 11, 31000, {'Keep elbows tucked': 3},               4, 9, 40),

      // ── Day 3 ───────────────────────────────────────────────────────────
      _S('squat',      13, 44000, {'Go deeper': 2},                        3, 9,  0),
      _S('pushup',     11, 36000, {'Get on floor': 2},                     3, 9, 20),

      // ── Day 2 ───────────────────────────────────────────────────────────
      _S('squat',      14, 46000, {'Go deeper': 1},                        2, 9,  0),
      _S('bicep_curl', 12, 33000, {'Keep elbows tucked': 1},               2, 9, 20),

      // ── Yesterday ───────────────────────────────────────────────────────
      _S('squat',      15, 48000, {},                                       1, 9,  0),
      _S('pushup',     12, 38000, {'Get on floor': 1},                     1, 9, 20),
      _S('bicep_curl', 13, 34000, {},                                       1, 9, 40),

      // ── Today ───────────────────────────────────────────────────────────
      _S('squat',      15, 49000, {},                                       0, 9,  0),
      _S('pushup',     13, 39000, {},                                       0, 9, 20),
      _S('bicep_curl', 14, 35000, {},                                       0, 9, 40),
    ];

    final batch = db.batch();

    for (final s in sessions) {
      final ref = collection.doc();
      batch.set(ref, {
        'exercise':    s.exercise,
        'reps':        s.reps,
        'durationMs':  s.durationMs,
        'feedbackMap': s.feedbackMap,
        'debriefText': _debrief(s.exercise, s.reps, s.feedbackMap),
        'timestamp':   Timestamp.fromDate(
            dayAt(s.daysAgo, s.hour, s.minute)),
        '_seeded':     true,
      });
    }

    await batch.commit();
    debugPrint('[DemoSeed] Done — ${sessions.length} sessions written.');
  }

  static String _debrief(
      String exercise, int reps, Map<String, int> feedback) {
    if (feedback.isEmpty) {
      return 'Excellent session — clean form throughout. '
          'You completed $reps ${_name(exercise)} reps with no corrections needed. '
          'Next set try adding one more rep or reducing rest time by 15 seconds '
          'to keep the progressive overload going.';
    }
    final topEntry = (feedback.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value)))
        .first;
    return 'Good effort on $reps ${_name(exercise)} reps. '
        'The tracker flagged "${topEntry.key}" ${topEntry.value} times — '
        'focus on that cue at the start of your next set before adding load. '
        'Full range of motion is more valuable than extra reps at this stage.';
  }

  static String _name(String exercise) {
    const names = {
      'squat':      'squat',
      'pushup':     'push-up',
      'bicep_curl': 'bicep curl',
    };
    return names[exercise] ?? exercise;
  }
}

class _S {
  final String exercise;
  final int reps;
  final int durationMs;
  final Map<String, int> feedbackMap;
  final int daysAgo;
  final int hour;
  final int minute;
  const _S(this.exercise, this.reps, this.durationMs, this.feedbackMap,
      this.daysAgo, this.hour, this.minute);
}