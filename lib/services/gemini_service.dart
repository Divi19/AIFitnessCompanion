import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class GeminiService {

  // ── GENERATION MODEL ──────────────────────────────────────────────────────
  // Routes through Firebase AI Logic (Vertex AI backend).
  // No API key needed — Firebase handles auth automatically.
  final _generationModel = FirebaseAI.vertexAI().generativeModel(
    model: 'gemini-2.0-flash',
  );

  // ── TEXT GENERATION ───────────────────────────────────────────────────────
  Future<String> generateResponse(String fullPrompt) async {
    final content = [Content.text(fullPrompt)];
    final response = await _generationModel.generateContent(content);
    return response.text ?? 'Could not generate a response. Please try again.';
  }

  // ── TEXT STREAMING (NEW) ──────────────────────────────────────────────────
  Stream<String> streamResponse(String fullPrompt) async* {
    final content = [Content.text(fullPrompt)];
    final responseStream = _generationModel.generateContentStream(content);
    
    await for (final chunk in responseStream) {
      if (chunk.text != null) {
        yield chunk.text!;
      }
    }
  }

  // ── IMAGE + TEXT ANALYSIS (Diet & Menu scanning) ──────────────────────────
  Future<String> analyzeImage(List<int> imageBytes, String prompt) async {
    final content = [
      Content.multi([
        InlineDataPart('image/jpeg', Uint8List.fromList(imageBytes)),
        TextPart(prompt),
      ]),
    ];
    final response = await _generationModel.generateContent(content);
    return response.text ?? '';
  }

  // ── EMBEDDING (document ingestion) ───────────────────────────────────────
  // Used when ingesting PDF chunks in the Admin screen.
  // RETRIEVAL_DOCUMENT = this text is being indexed for later retrieval.
  Future<List<double>> getEmbedding(String text) async {
    return _callEmbeddingApi(text, 'RETRIEVAL_DOCUMENT');
  }

  // ── EMBEDDING (query) ─────────────────────────────────────────────────────
  // Used when embedding the user's live question at query time.
  // RETRIEVAL_QUERY = this text is a search query looking for relevant docs.
  Future<List<double>> getQueryEmbedding(String text) async {
    return _callEmbeddingApi(text, 'RETRIEVAL_QUERY');
  }

  // ── SHARED EMBEDDING IMPLEMENTATION ──────────────────────────────────────
  Future<List<double>> _callEmbeddingApi(String text, String taskType) async {
    if (AppConstants.geminiApiKey.isEmpty) {
      throw Exception(
        'GEMINI_API_KEY is empty. '
        'Run with: flutter run --dart-define-from-file=.env',
      );
    }

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent',
    );

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'x-goog-api-key': AppConstants.geminiApiKey,
      },
      body: jsonEncode({
        'model': 'models/gemini-embedding-001',
        'content': {
          'parts': [
            {'text': text}
          ]
        },
        'taskType': taskType,
        // Pinned to 768 to match Firestore vector index dimension.
        // gemini-embedding-001 defaults to 3072 but 768 saves 75% storage
        // with only 0.26% quality loss. Do NOT change after ingesting data.
        'outputDimensionality': 768,
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Embedding API error ${response.statusCode}: ${response.body}',
      );
    }

    final decoded = jsonDecode(response.body);
    final values = decoded['embedding']['values'] as List<dynamic>;
    return values.map((v) => (v as num).toDouble()).toList();
  }
}

// ── MEAL CLASSIFICATION SERVICE ───────────────────────────────────────────
// Separate service for food image analysis.
// Uses Gemini REST directly — no extra package needed.
class MealGeminiService {

  // NOTE: Move this key to AppConstants and .env before going to production
  static const String _apiKey = 'AIzaSyC7ukW7XGh9BinYOza2N69f6P0uisDc3IQ';

  Future<List<Map<String, dynamic>>> classifyMeal(List<int> imageBytes) async {
    const prompt = '''
You are a nutritionist AI. Analyze this food image and return ONLY a JSON array 
with no markdown, no code fences, no explanation — just the raw JSON.

Return exactly 3 possible dishes this could be, ranked from most to least likely.
For each dish estimate the nutrition for one standard serving.

Format:
[
  {
    "name": "Dish Name",
    "confidence": "High",
    "calories": 500,
    "protein": 25,
    "carbs": 60,
    "fat": 15
  }
]

Rules:
- confidence must be one of: "High", "Medium", "Low"
- All nutrition values must be numbers (not strings)
- Estimate for ONE standard serving portion
- If you cannot identify the food, still return 3 best guesses
''';

    try {
      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/gemini-2.5-flash-lite:generateContent?key=$_apiKey',
      );

      // Convert image bytes to base64 for the REST API
      final base64Image = base64Encode(Uint8List.fromList(imageBytes));

      final response = await http.post(
        uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [
            {
              'parts': [
                {
                  'inline_data': {
                    'mime_type': 'image/jpeg',
                    'data': base64Image,
                  }
                },
                {'text': prompt},
              ]
            }
          ],
        }),
      );

      if (response.statusCode != 200) {
        throw Exception('Meal API error ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final text = data['candidates'][0]['content']['parts'][0]['text'] as String;

      // Strip markdown fences if Gemini adds them despite instructions
      final cleaned = text
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final List<dynamic> parsed = jsonDecode(cleaned);
      return parsed.cast<Map<String, dynamic>>();

    } catch (e) {
      print('MealGeminiService error: $e');
      return [
        {
          'name': 'Could not identify dish',
          'confidence': 'Low',
          'calories': 0,
          'protein': 0,
          'carbs': 0,
          'fat': 0,
        }
      ];
    }
  }
}