import 'package:cloud_firestore/cloud_firestore.dart';
import 'gemini_service.dart';
import 'knowledge_base_service.dart';

class RagService {
  final _geminiService = GeminiService();
  final _knowledgeBaseService = KnowledgeBaseService();
  final _db = FirebaseFirestore.instance;

  // Helper to unpack the complex biometrics map into a flat list of injuries
  List<String> _extractActiveLimitations(Map<String, dynamic>? biometrics) {
    if (biometrics == null || biometrics['noLimitations'] == true) {
      return [];
    }

    final List<String> active = [];

    void checkSection(Map<String, dynamic>? section) {
      section?.forEach((key, value) {
        if (value == true) active.add(key);
      });
    }

    checkSection(biometrics['upperBody']);
    checkSection(biometrics['lowerBody']);
    checkSection(biometrics['coreSpine']);

    // Systemic needs careful handling to translate keys to readable strings
    final systemic = biometrics['systemic'] as Map<String, dynamic>?;
    if (systemic?['cardiovascular'] == true) active.add('cardiovascular condition');
    if (systemic?['respiratoryAsthma'] == true) active.add('asthma');
    if (systemic?['osteoarthritis'] == true) active.add('osteoarthritis');
    if (systemic?['wheelchair'] == true) active.add('wheelchair user');
    if (systemic?['prosthesis'] == true) active.add('uses prosthesis');

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
    
    // THE FIX: Parse the new biometrics map instead of the old flat list
    final biometrics = userData['biometrics'] as Map<String, dynamic>?;
    final limitations = _extractActiveLimitations(biometrics);
    final clinicalNotes = biometrics?['clinicalNotes'] as String? ?? '';

    final fatigueScore = (userData['fatigue_score'] as num?)?.toInt() ?? 5;
    final fitnessGoal = userData['fitness_goal'] ?? 'general fitness';
    final currentStreak = (userData['current_streak'] as num?)?.toInt() ?? 0;

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
You are an evidence-based fitness and nutrition assistant for the AI Fitness Companion app.
Speak naturally and conversationally. Do not list references, sources, or personalization steps in your output.

════════════════════════════════════
USER PROFILE
════════════════════════════════════
Name: $userName
Fitness Goal: $fitnessGoal
Physical Limitations / Injuries: $limitationsText
Current Fatigue Score: $fatigueContext
Workout Streak: $currentStreak days

════════════════════════════════════
REFERENCE DOCUMENTS (retrieved from knowledge base)
════════════════════════════════════
$contextBlock

════════════════════════════════════
STRICT RULES
════════════════════════════════════
1. Base your fitness advice ONLY on the Reference Documents above.
2. Seamlessly adapt your advice to the user's profile, especially their physical limitations. If a reference recommends something that conflicts with their injury, flag it conversationally and suggest a safe alternative.
3. If the answer is not in the references, say exactly: "This topic is not covered in the current knowledge base."
4. Never invent information. Never use outside knowledge.

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