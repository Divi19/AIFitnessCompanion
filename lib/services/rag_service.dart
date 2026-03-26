import 'package:cloud_firestore/cloud_firestore.dart';
import 'gemini_service.dart';
import 'knowledge_base_service.dart';
import 'workout_session_service.dart';

class RagService {
  final _geminiService        = GeminiService();
  final _knowledgeBaseService = KnowledgeBaseService();
  final _db                   = FirebaseFirestore.instance;

  final Map<String, String> _injuryNames = {
    'rotatorCuff':    'Rotator Cuff / Shoulder',
    'deltoids':       'Deltoids',
    'pectorals':      'Pectorals (Chest)',
    'biceps':         'Biceps',
    'triceps':        'Triceps',
    'latsRhomboids':  'Lats / Rhomboids',
    'elbowJoint':     'Elbow Joint',
    'wristCarpals':   'Wrist / Carpals',
    'glutesPelvis':   'Glutes / Pelvis',
    'quadriceps':     'Quadriceps',
    'hamstrings':     'Hamstrings',
    'calves':         'Calves',
    'kneeMeniscus':   'Knee / Meniscus',
    'achillesAnkle':  'Achilles / Ankle',
    'plantarFoot':    'Plantar / Foot',
    'cervicalSpine':  'Cervical Spine (Neck)',
    'thoracicSpine':  'Thoracic Spine (Mid-Back)',
    'lumbarSpine':    'Lumbar Spine (Lower Back)',
    'abdominalHernia':'Abdominal Hernia',
  };

  List<String> _extractActiveLimitations(Map<String, dynamic>? biometrics) {
    if (biometrics == null || biometrics['noLimitations'] == true) return [];
    final List<String> active = [];
    void checkSection(Map<String, dynamic>? section) {
      section?.forEach((key, value) {
        if (value == true) active.add(_injuryNames[key] ?? key);
      });
    }
    checkSection(biometrics['upperBody'] as Map<String, dynamic>?);
    checkSection(biometrics['lowerBody'] as Map<String, dynamic>?);
    checkSection(biometrics['coreSpine'] as Map<String, dynamic>?);
    final systemic = biometrics['systemic'] as Map<String, dynamic>?;
    if (systemic?['cardiovascular']    == true) active.add('Cardiovascular condition');
    if (systemic?['respiratoryAsthma'] == true) active.add('Asthma / Respiratory');
    if (systemic?['osteoarthritis']    == true) active.add('Osteoarthritis');
    if (systemic?['wheelchair']        == true) active.add('Wheelchair user');
    if (systemic?['prosthesis']        == true) active.add('Uses prosthesis');
    return active;
  }

  // ── Fetch today's meal logs from meals/{uid}/logs ─────────────────────────
  // Returns a formatted string ready for prompt injection.
  // Only fetches logs from today to keep context focused and token-efficient.
  Future<String> _fetchTodayMealLogs(String userId) async {
    try {
      final now   = DateTime.now();
      final today = DateTime(now.year, now.month, now.day);

      final snapshot = await _db
          .collection('meals')
          .doc(userId)
          .collection('logs')
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
          .orderBy('timestamp', descending: false)
          .get();

      if (snapshot.docs.isEmpty) return 'No meals logged today.';

      double totalCalories    = 0;
      double totalProtein     = 0;
      double totalCarbs       = 0;
      double totalFat         = 0;
      final List<String> mealLines = [];

      for (final doc in snapshot.docs) {
        final d        = doc.data();
        final name     = d['name']     as String? ?? 'Unknown item';
        final calories = (d['calories'] as num?)?.toDouble() ?? 0;
        final protein  = (d['protein']  as num?)?.toDouble() ?? 0;
        final carbs    = (d['carbs']    as num?)?.toDouble() ?? 0;
        final fat      = (d['fat']      as num?)?.toDouble() ?? 0;

        totalCalories += calories;
        totalProtein  += protein;
        totalCarbs    += carbs;
        totalFat      += fat;

        final ts        = (d['timestamp'] as Timestamp?)?.toDate();
        final timeLabel = ts != null
            ? '${ts.hour.toString().padLeft(2, '0')}:${ts.minute.toString().padLeft(2, '0')}'
            : '';

        mealLines.add(
          '- $name${timeLabel.isNotEmpty ? ' ($timeLabel)' : ''}: '
          '${calories.toInt()} kcal'
          '${protein > 0 ? ', ${protein.toStringAsFixed(1)}g protein' : ''}'
          '${carbs   > 0 ? ', ${carbs.toStringAsFixed(1)}g carbs'   : ''}'
          '${fat     > 0 ? ', ${fat.toStringAsFixed(1)}g fat'       : ''}',
        );
      }

      final summary =
          'Today\'s total: ${totalCalories.toInt()} kcal | '
          '${totalProtein.toStringAsFixed(1)}g protein | '
          '${totalCarbs.toStringAsFixed(1)}g carbs | '
          '${totalFat.toStringAsFixed(1)}g fat';

      return '${mealLines.join('\n')}\n\n$summary';
    } catch (_) {
      return 'Meal log data unavailable.';
    }
  }

  Stream<String> query({
    required String userQuestion,
    required String userId,
    List<Map<String, String>> chatHistory  = const [],
    List<WorkoutSession>      recentSessions = const [],
  }) async* {
    final queryVector = await _geminiService.getQueryEmbedding(userQuestion);

    final relevantChunks = await _knowledgeBaseService.searchSimilarChunks(
      queryVector: queryVector,
      limit: 3,
    );

    final userDoc  = await _db.collection('users').doc(userId).get();
    final userData = userDoc.data() ?? {};

    final userName      = userData['name']          ?? 'the user';
    final biometrics    = userData['biometrics']    as Map<String, dynamic>?;
    final limitations   = _extractActiveLimitations(biometrics);
    final clinicalNotes = biometrics?['clinicalNotes'] as String? ?? '';
    final fatigueScore  = (userData['fatigue_score'] as num?)?.toInt() ?? 5;
    final fitnessGoal   = userData['fitness_goal']   ?? 'general fitness';
    final currentStreak = (userData['current_streak'] as num?)?.toInt() ?? 0;

    final workoutPlansSnapshot = await _db
        .collection('users')
        .doc(userId)
        .collection('workout_plans')
        .orderBy('createdAt', descending: true)
        .limit(1)
        .get();

    String formattedWorkoutPlans = 'No active workout plans found.';
    if (workoutPlansSnapshot.docs.isNotEmpty) {
      final doc = workoutPlansSnapshot.docs.first;
      formattedWorkoutPlans =
          'Plan ID: ${doc.id}\nDetails: ${doc.data().toString()}';
    }

    // ── Fetch today's meal logs ───────────────────────────────────────────
    final formattedMealLogs = await _fetchTodayMealLogs(userId);

    String formattedHistory =
        'No prior context. This is the start of the conversation.';
    if (chatHistory.isNotEmpty) {
      final recentHistory = chatHistory.length > 6
          ? chatHistory.sublist(chatHistory.length - 6)
          : chatHistory;
      formattedHistory = recentHistory.map((msg) {
        final role = msg['role'] == 'user' ? 'USER' : 'ASSISTANT';
        return '$role: ${msg['text']}';
      }).join('\n\n');
    }

    String formattedSessions = 'No recent workout sessions recorded.';
    if (recentSessions.isNotEmpty) {
      formattedSessions = recentSessions.map((s) {
        final sortedFeedback = s.feedbackMap.entries.toList()
          ..sort((a, b) => b.value.compareTo(a.value));
        final topIssues = sortedFeedback
            .take(3)
            .map((e) => '"${e.key}" (${e.value}x)')
            .join(', ');
        return '- ${s.exerciseDisplayName}: ${s.reps} reps, '
            '${s.durationFormatted}, ${s.timeAgo}'
            '${topIssues.isNotEmpty ? '\n  Top form issues: $topIssues' : ''}';
      }).join('\n');
    }

    final prompt = _buildPrompt(
      userQuestion:    userQuestion,
      userName:        userName,
      limitations:     limitations,
      clinicalNotes:   clinicalNotes,
      fatigueScore:    fatigueScore,
      fitnessGoal:     fitnessGoal,
      currentStreak:   currentStreak,
      retrievedChunks: relevantChunks,
      workoutPlans:    formattedWorkoutPlans,
      chatHistory:     formattedHistory,
      recentSessions:  formattedSessions,
      mealLogs:        formattedMealLogs,
    );

    yield* _geminiService.streamResponse(prompt);
  }

  String _buildPrompt({
    required String              userQuestion,
    required String              userName,
    required List<String>        limitations,
    required String              clinicalNotes,
    required int                 fatigueScore,
    required String              fitnessGoal,
    required int                 currentStreak,
    required List<Map<String, dynamic>> retrievedChunks,
    required String              workoutPlans,
    required String              chatHistory,
    required String              recentSessions,
    required String              mealLogs,
  }) {
    final contextBlock =
        retrievedChunks.map((e) => e['text']).join('\n\n---\n\n');

    String limitationsText =
        limitations.isEmpty ? 'None reported' : limitations.join(', ');
    if (clinicalNotes.isNotEmpty) {
      limitationsText += '\nClinical Notes: $clinicalNotes';
    }

    String fatigueContext;
    if (fatigueScore >= 8) {
      fatigueContext =
          '$fatigueScore/10 — HIGH. Recommend active recovery only today.';
    } else if (fatigueScore >= 5) {
      fatigueContext =
          '$fatigueScore/10 — MODERATE. Recommend moderate intensity.';
    } else {
      fatigueContext = '$fatigueScore/10 — LOW. Full intensity appropriate.';
    }

    return '''
You are an expert fitness and nutrition AI assistant for the AI Fitness Companion app. 

════════════════════════════════════
USER PROFILE
════════════════════════════════════
Name: $userName
Fitness Goal: $fitnessGoal
Physical Limitations / Injuries: $limitationsText
Current Fatigue Score: $fatigueContext
Workout Streak: $currentStreak days

════════════════════════════════════
USER'S CURRENT WORKOUT PLANS
════════════════════════════════════
$workoutPlans

════════════════════════════════════
RECENT WORKOUT SESSIONS
════════════════════════════════════
$recentSessions

Use this section to answer questions about the user's recent training,
form issues, and progress. If the user asks "how did I do today" or
"what should I work on", use this data to give a specific, informed answer.
You do NOT need the reference documents for session-specific questions.

════════════════════════════════════
TODAY'S MEAL LOGS
════════════════════════════════════
$mealLogs

Use this section to answer nutrition questions like "what have I eaten today",
"am I hitting my protein goal", or "what should I eat next". Cross-reference
with the user's fitness goal and fatigue score where relevant.

════════════════════════════════════
REFERENCE DOCUMENTS (retrieved from knowledge base)
════════════════════════════════════
$contextBlock

════════════════════════════════════
RECENT CONVERSATION HISTORY
════════════════════════════════════
$chatHistory

════════════════════════════════════
STRICT JSON OUTPUT RULES - CRITICAL
════════════════════════════════════
1. You MUST respond to EVERY prompt by returning ONLY a raw JSON array. 
2. Do NOT include markdown formatting, code fences (like ```json), conversational greetings, or any text outside the JSON brackets.
3. Every single response, whether it is a workout plan, a diet tip, or just a simple greeting, MUST be formatted as an array of card objects. 
4. Protect the user: Never recommend exercises that conflict with their Physical Limitations. Suggest safe alternatives in the cards.

Use this EXACT JSON format for every response:
[
  {
    "title": "Main Subject, Step, or Greeting",
    "description": "Detailed explanation, instructions, or conversational reply",
    "badge": "Impact Level, Muscle Group, or Category"
  }
]

════════════════════════════════════
USER'S CURRENT QUESTION
════════════════════════════════════
$userQuestion
''';
  }
}