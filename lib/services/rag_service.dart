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
    // STEP 1: Embed the user's question with RETRIEVAL_QUERY taskType
    final queryVector = await _geminiService.getQueryEmbedding(userQuestion);

    // STEP 2: Find the most semantically relevant chunks in Firestore
    final relevantChunks = await _knowledgeBaseService.searchSimilarChunks(
      queryVector: queryVector,
      limit: 3,
    );

    // STEP 3: Fetch the user's profile for personalisation
    final userDoc = await _db.collection('users').doc(userId).get();
    final userData = userDoc.data();

    final userName = userData?['name'] ?? 'the user';
    final limitations = List<String>.from(
      userData?['physical_limitations'] ?? [],
    );
    final fatigueScore = userData?['fatigue_score'] ?? 5;

    // STEP 4: Build the augmented prompt
    final prompt = _buildPrompt(
      userQuestion: userQuestion,
      userName: userName,
      limitations: limitations,
      fatigueScore: fatigueScore,
      retrievedChunks: relevantChunks,
    );

    // STEP 5: Generate and return the response
    return _geminiService.generateResponse(prompt);
  }

  String _buildPrompt({
    required String userQuestion,
    required String userName,
    required List<String> limitations,
    required int fatigueScore,
    required List<Map<String, dynamic>> retrievedChunks,
  }) {
    final contextBlock = retrievedChunks
        .asMap()
        .entries
        .map((e) =>
            '[Reference ${e.key + 1}] (Source: ${e.value['source']})\n'
            '${e.value['text']}')
        .join('\n\n');

    final limitationsText =
        limitations.isEmpty ? 'None reported.' : limitations.join(', ');

    return '''
You are a safe and evidence-based fitness and nutrition assistant.

STRICT RULES YOU MUST FOLLOW:
1. Base your answer ONLY on the provided Reference Context below. Do not use outside knowledge.
2. If the answer cannot be found in the references, say: "I could not find specific guidance on this in the current knowledge base."
3. Actively consider the user's physical limitations and fatigue score in every response.
4. If any recommendation conflicts with the user's limitations, flag it with a warning and suggest a safe alternative.
5. Never give advice that could harm someone with the listed limitations.
6. Keep your response concise, friendly, and actionable.

--- USER PROFILE ---
Name: $userName
Physical Limitations / Injuries: $limitationsText
Current Fatigue Score: $fatigueScore / 10

--- REFERENCE CONTEXT (from verified fitness literature) ---
$contextBlock

--- USER'S QUESTION ---
$userQuestion

--- YOUR RESPONSE ---
''';
  }
}