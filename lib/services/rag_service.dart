import 'package:cloud_firestore/cloud_firestore.dart';
import 'gemini_service.dart';
import 'knowledge_base_service.dart';

class RagService {
  final _geminiService = GeminiService();
  final _knowledgeBaseService = KnowledgeBaseService();
  final _db = FirebaseFirestore.instance;

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
    final userData = userDoc.data();

    final userName = userData?['name'] ?? 'the user';
    final limitations = List<String>.from(
      userData?['physical_limitations'] ?? [],
    );
    final fatigueScore = (userData?['fatigue_score'] ?? 5) as int;
    final fitnessGoal = userData?['fitness_goal'] ?? 'general fitness';
    final currentStreak = (userData?['current_streak'] ?? 0) as int;

    // STEP 4: Build the augmented prompt
    final prompt = _buildPrompt(
      userQuestion: userQuestion,
      userName: userName,
      limitations: limitations,
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
    required int fatigueScore,
    required String fitnessGoal,
    required int currentStreak,
    required List<Map<String, dynamic>> retrievedChunks,
  }) {
    // Number each chunk and include its source filename
    final contextBlock = retrievedChunks
        .asMap()
        .entries
        .map((e) =>
            '[Reference ${e.key + 1}] Source: ${e.value['source']}\n'
            '${e.value['text']}')
        .join('\n\n---\n\n');

    final limitationsText =
        limitations.isEmpty ? 'None reported' : limitations.join(', ');

    // Build fatigue context string
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
You are an evidence-based fitness and nutrition assistant for the AI Fitness Companion app.

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
1. Base your answer ONLY on the Reference Documents above.
2. You MUST cite which Reference number supports each claim, like this:
   "Progressive overload is key for hypertrophy [Ref 1]."
3. If a reference recommends something that conflicts with the user's
   limitations, you MUST flag it with ⚠️ and suggest a safe alternative.
4. You MUST end every response with two clearly labelled sections:
   📚 SOURCES USED: list the source filename of each reference you used
   👤 PERSONALISATION APPLIED: list what user profile data influenced this answer
5. If the answer is not in the references, say exactly:
   "This topic is not covered in the current knowledge base."
6. Never invent information. Never use outside knowledge.

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