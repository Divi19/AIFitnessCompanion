import 'package:cloud_firestore/cloud_firestore.dart';
import 'gemini_service.dart';
import 'knowledge_base_service.dart';

class RagService {
  final _geminiService = GeminiService();
  final _knowledgeBaseService = KnowledgeBaseService();
  final _db = FirebaseFirestore.instance;

  // Dictionary to convert database keys into human-readable text for the AI
  final Map<String, String> _injuryNames = {
    'rotatorCuff': 'Rotator Cuff / Shoulder',
    'deltoids': 'Deltoids',
    'pectorals': 'Pectorals (Chest)',
    'biceps': 'Biceps',
    'triceps': 'Triceps',
    'latsRhomboids': 'Lats / Rhomboids',
    'elbowJoint': 'Elbow Joint',
    'wristCarpals': 'Wrist / Carpals',
    'glutesPelvis': 'Glutes / Pelvis',
    'quadriceps': 'Quadriceps',
    'hamstrings': 'Hamstrings',
    'calves': 'Calves',
    'kneeMeniscus': 'Knee / Meniscus',
    'achillesAnkle': 'Achilles / Ankle',
    'plantarFoot': 'Plantar / Foot',
    'cervicalSpine': 'Cervical Spine (Neck)',
    'thoracicSpine': 'Thoracic Spine (Mid-Back)',
    'lumbarSpine': 'Lumbar Spine (Lower Back)',
    'abdominalHernia': 'Abdominal Hernia',
  };

  // Helper to unpack the complex biometrics map into a flat list of injuries
  List<String> _extractActiveLimitations(Map<String, dynamic>? biometrics) {
    if (biometrics == null || biometrics['noLimitations'] == true) {
      return [];
    }

    final List<String> active = [];

    void checkSection(Map<String, dynamic>? section) {
      section?.forEach((key, value) {
        if (value == true) {
          active.add(_injuryNames[key] ?? key); // Use readable name if available
        }
      });
    }

    checkSection(biometrics['upperBody']);
    checkSection(biometrics['lowerBody']);
    checkSection(biometrics['coreSpine']);

    // Systemic needs careful handling to translate keys to readable strings
    final systemic = biometrics['systemic'] as Map<String, dynamic>?;
    if (systemic?['cardiovascular'] == true) active.add('Cardiovascular condition');
    if (systemic?['respiratoryAsthma'] == true) active.add('Asthma / Respiratory');
    if (systemic?['osteoarthritis'] == true) active.add('Osteoarthritis');
    if (systemic?['wheelchair'] == true) active.add('Wheelchair user');
    if (systemic?['prosthesis'] == true) active.add('Uses prosthesis');

    return active;
  }

  Future<String> query({
    required String userQuestion,
    required String userId,
  }) async {
    // STEP 1: Embed the user's question
    final queryVector = await _geminiService.getQueryEmbedding(userQuestion);

    // STEP 2: Retrieve relevant chunks from Firestore
    final relevantChunks = await _knowledgeBaseService.searchSimilarChunks(
      queryVector: queryVector,
      limit: 3,
    );

    // STEP 3: Fetch full user profile
    final userDoc = await _db.collection('users').doc(userId).get();
    final userData = userDoc.data() ?? {};

    final userName = userData['name'] ?? 'the user';
    
    // Parse the biometrics map
    final biometrics = userData['biometrics'] as Map<String, dynamic>?;
    final limitations = _extractActiveLimitations(biometrics);
    final clinicalNotes = biometrics?['clinicalNotes'] as String? ?? '';

    final fatigueScore = (userData['fatigue_score'] as num?)?.toInt() ?? 5;
    final fitnessGoal = userData['fitness_goal'] ?? 'general fitness';
    final currentStreak = (userData['current_streak'] as num?)?.toInt() ?? 0;

    // STEP 3.5: Fetch ONLY the most recent Workout Plan
    final workoutPlansSnapshot = await _db
        .collection('users')
        .doc(userId)
        .collection('workout_plans')
        .orderBy('timestamp', descending: true) // Sort newest first
        .limit(1) // Only grab the single newest plan
        .get();

    String formattedWorkoutPlans = 'No active workout plans found.';
    if (workoutPlansSnapshot.docs.isNotEmpty) {
      final doc = workoutPlansSnapshot.docs.first;
      formattedWorkoutPlans = 'Plan ID: ${doc.id}\nDetails: ${doc.data().toString()}';
    }

    // STEP 4: Build the augmented prompt
    final prompt = _buildPrompt(
      userQuestion: userQuestion,
      userName: userName,
      limitations: limitations,
      clinicalNotes: clinicalNotes,
      fatigueScore: fatigueScore,
      fitnessGoal: fitnessGoal,
      currentStreak: currentStreak,
      retrievedChunks: relevantChunks,
      workoutPlans: formattedWorkoutPlans,
    );

    // STEP 5: Generate response
    return _geminiService.generateResponse(prompt);
  }

  String _buildPrompt({
    required String userQuestion,
    required String userName,
    required List<String> limitations,
    required String clinicalNotes,
    required int fatigueScore,
    required String fitnessGoal,
    required int currentStreak,
    required List<Map<String, dynamic>> retrievedChunks,
    required String workoutPlans,
  }) {
    // Just map the raw text. No reference numbers or filenames.
    final contextBlock = retrievedChunks
        .map((e) => e['text'])
        .join('\n\n---\n\n');

    String limitationsText = limitations.isEmpty ? 'None reported' : limitations.join(', ');
    if (clinicalNotes.isNotEmpty) {
      limitationsText += '\nClinical Notes: $clinicalNotes';
    }

    String fatigueContext;
    if (fatigueScore >= 8) {
      fatigueContext = '$fatigueScore/10 — HIGH. Recommend active recovery only today.';
    } else if (fatigueScore >= 5) {
      fatigueContext = '$fatigueScore/10 — MODERATE. Recommend moderate intensity.';
    } else {
      fatigueContext = '$fatigueScore/10 — LOW. Full intensity appropriate.';
    }

    return '''
You are an expert, conversational fitness and nutrition AI assistant for the AI Fitness Companion app. 

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
REFERENCE DOCUMENTS (retrieved from knowledge base)
════════════════════════════════════
$contextBlock

════════════════════════════════════
STRICT RULES FOR YOUR RESPONSE
════════════════════════════════════
1. ACT AS AN EXPERT TRAINER: Use the Reference Documents as the FOUNDATION of your knowledge, but you MUST use your general expertise to ADAPT that knowledge to the user's specific injuries, goals, and their CURRENT WORKOUT PLANS.
2. PROTECT THE USER: If the reference documents suggest an exercise that conflicts with the user's Physical Limitations (e.g., suggesting barbell squats to someone with a knee injury), you MUST explicitly flag it as unsafe and suggest a safe alternative using your own knowledge. 
3. BE CONVERSATIONAL: Do NOT say things like "Based on the reference texts" or "Considering your physical limitations (x, y, z)." Speak naturally, like a human coach talking to a client they already know. 
4. DO NOT REFUSE TO HELP: You are allowed to generate specific exercise recommendations as long as they respect the user's injury profile.

════════════════════════════════════
USER'S QUESTION
════════════════════════════════════
$userQuestion

════════════════════════════════════
YOUR RESPONSE
════════════════════════════════════
''';
  }
}