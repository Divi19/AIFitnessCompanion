import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class GeminiService {
  // ── GENERATION ────────────────────────────────────────────────────────────
  // Uses firebase_ai package — routed securely through your Firebase project.
  // No API key needed here; Firebase handles auth for generation.
  final _generationModel = FirebaseAI.vertexAI().generativeModel(
import 'dart:typed_data';
import 'dart:convert';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as genai;

class GeminiService {
  // Use 'late' to ensure Firebase is initialized before this is accessed
  late final _model = FirebaseVertexAI.instance.generativeModel(
    model: 'gemini-2.0-flash',
  );

  Future<String> generateResponse(String fullPrompt) async {
    final content = [Content.text(fullPrompt)];
    final response = await _generationModel.generateContent(content);
    return response.text ?? 'Could not generate a response. Please try again.';
  }

  // ── EMBEDDING (document) ──────────────────────────────────────────────────
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

  // ── SHARED PRIVATE IMPLEMENTATION ─────────────────────────────────────────
  Future<List<double>> _callEmbeddingApi(String text, String taskType) async {
    // Guard: catch missing API key early with a clear error message
    if (AppConstants.geminiApiKey.isEmpty) {
      throw Exception(
        'GEMINI_API_KEY is empty. '
        'Run with: flutter run --dart-define-from-file=.env',
      );
    }

    // gemini-embedding-001 lives under v1beta on the generativelanguage endpoint.
    // Note: this is v1beta NOT v1 — unlike text-embedding-004, this model
    // is accessed via the beta endpoint with the Gemini Developer API key.
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent',
    );

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        // Gemini REST API requires x-goog-api-key — NOT a Bearer token
        'x-goog-api-key': AppConstants.geminiApiKey,
      },
      body: jsonEncode({
        // model field required in the body for gemini-embedding-001
        'model': 'models/gemini-embedding-001',
        'content': {
          'parts': [
            {'text': text}
          ]
        },
        // taskType IS supported on gemini-embedding-001 unlike older models
        'taskType': taskType,
        // outputDimensionality: pin to 768 so it matches your Firestore
        // vector index dimension. gemini-embedding-001 defaults to 3072
        // but 768 has only 0.26% quality loss and uses 75% less storage.
        // IMPORTANT: this value must match the dimension in your Firestore
        // vector index. Do not change this after ingesting data.
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
  // Image + text prompt for your Diet & Menu scanning
  Future<String> analyzeImage(List<int> imageBytes, String prompt) async {
    final content = [
      Content.multi([

        InlineDataPart('image/jpeg', Uint8List.fromList(imageBytes)),
        TextPart(prompt),
      ]),
    ];

    final response = await _model.generateContent(content);
    return response.text ?? '';
  }
}

class MealGeminiService {

  static const String _apiKey = 'AIzaSyC7ukW7XGh9BinYOza2N69f6P0uisDc3IQ';

  genai.GenerativeModel get _model => genai.GenerativeModel(
    model: 'gemini-2.5-flash-lite',
    apiKey: _apiKey,
  );

  Future<List<Map<String, dynamic>>> classifyMeal(List<int> imageBytes) async {
    const prompt = '''
  You are a nutritionist AI. Analyze this food image and return ONLY a JSON array 
  with no markdown, no code fences, no explanation - just the raw JSON.

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

      print('=== CALLING GEMINI with ${imageBytes.length} bytes ===');
      final response = await _model.generateContent([
        genai.Content.multi([
          genai.DataPart('image/jpeg', Uint8List.fromList(imageBytes)),
          genai.TextPart(prompt),
        ])
      ]);

      final text = response.text ?? '';

      // Strip markdown fences if Gemini adds them despite instructions
      final cleaned = text
          .replaceAll('```json', '')
          .replaceAll('```', '')
          .trim();

      final List<dynamic> parsed = jsonDecode(cleaned);
      return parsed.cast<Map<String, dynamic>>();

    } catch (e) {
      print('=== GEMINI ERROR: $e ===');
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