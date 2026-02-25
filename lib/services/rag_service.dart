import 'package:cloud_firestore/cloud_firestore.dart';
import 'gemini_service.dart';
import 'knowledge_base_service.dart';

class RagService {
  final _geminiService = GeminiService();
  final _knowledgeBaseService = KnowledgeBaseService();
  final _db = FirebaseFirestore.instance;

  /// The main entry point. Takes the user's question and their Firebase uid,
  /// runs the full RAG pipeline, and returns a generated response string.
  Future<String> query({
    required String userQuestion,
    required String userId,
  }) async {
    // ── STEP 1: EMBED THE QUERY ──────────────────────────────────────────────
    // Convert the user's question into a vector so we can search Firestore.
    // This uses the same embedding model used during ingestion — that's what
    // makes the similarity search work mathematically.
    final queryVector = await _geminiService.getEmbedding(userQuestion);

    // ── STEP 2: RETRIEVE ─────────────────────────────────────────────────────
    // Search Firestore for the 3 PDF chunks whose vectors are closest to the
    // query vector. "Closest" means most semantically similar in meaning.
    final relevantChunks = await _knowledgeBaseService.searchSimilarChunks(
      queryVector: queryVector,
      limit: 3,
    );

    // ── STEP 3: FETCH USER PROFILE ───────────────────────────────────────────
    // Pull the user's stored profile data so we can personalise the response.
    final userDoc = await _db.collection('users').doc(userId).get();
    final userData = userDoc.data();

    final userName = userData?['name'] ?? 'the user';
    final limitations =
        List<String>.from(userData?['physical_limitations'] ?? []);
    final fatigueScore = userData?['fatigue_score'] ?? 5;

    // ── STEP 4: AUGMENT — Build the prompt ───────────────────────────────────
    // Combine everything into one structured prompt for Gemini.
    final prompt = _buildPrompt(
      userQuestion: userQuestion,
      userName: userName,
      limitations: limitations,
      fatigueScore: fatigueScore,
      retrievedChunks: relevantChunks,
    );

    // ── STEP 5: GENERATE ─────────────────────────────────────────────────────
    // Send the assembled prompt to Gemini and return its response.
    final response = await _geminiService.generateResponse(prompt);

    return response;
  }

  /// Assembles the full prompt sent to Gemini.
  /// The system instruction strictly locks Gemini to only use the provided context —
  /// this is what prevents hallucination and keeps the app evidence-based.
  String _buildPrompt({
    required String userQuestion,
    required String userName,
    required List<String> limitations,
    required int fatigueScore,
    required List<Map<String, dynamic>> retrievedChunks,
  }) {
    // Format the retrieved PDF chunks into a numbered reference block
    final contextBlock = retrievedChunks
        .asMap()
        .entries
        .map((e) =>
            '[Reference ${e.key + 1}] (Source: ${e.value['source']})\n${e.value['text']}')
        .join('\n\n');

    final limitationsText =
        limitations.isEmpty ? 'None reported.' : limitations.join(', ');

    return '''
You are a safe and evidence-based fitness and nutrition assistant.

STRICT RULES YOU MUST FOLLOW:
1. Base your answer ONLY on the provided Reference Context below. Do not use outside knowledge.
2. If the answer cannot be found in the references, say: "I could not find specific guidance on this in the current knowledge base."
3. Actively consider the user's physical limitations and fatigue score in every response.
4. If any recommendation in the references conflicts with the user's limitations, flag it clearly with a warning and suggest a safe alternative.
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