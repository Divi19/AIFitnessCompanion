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

  // ── TEXT STREAMING ────────────────────────────────────────────────────────
  Stream<String> streamResponse(String fullPrompt) async* {
    final content = [Content.text(fullPrompt)];
    final responseStream = _generationModel.generateContentStream(content);
    await for (final chunk in responseStream) {
      if (chunk.text != null) yield chunk.text!;
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
          'parts': [{'text': text}]
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
    final values  = decoded['embedding']['values'] as List<dynamic>;
    return values.map((v) => (v as num).toDouble()).toList();
  }
}

// ── MEAL CLASSIFICATION SERVICE ───────────────────────────────────────────────
//
// Responsible for analysing food photos using Gemini Vision.
//
// OLD FLOW (classifyMeal — removed):
//   Photo → Gemini guesses dish name + makes up calorie numbers from training data
//   Problem: Gemini has no database. Calorie numbers were 100% hallucinated.
//   Confidence was "High" / "Medium" / "Low" string — caused type cast crashes.
//
// NEW FLOW (classifyMealWithGrams):
//   Photo → Gemini identifies dish AND estimates gram weight from visual cues
//        → Returns fallback macros calculated FOR that gram weight (not per 100g)
//        → meal_service.dart then tries USDA FoodData Central by dish name
//        → If USDA found: real database macros × (grams / 100) ← most accurate
//        → If not found (nasi lemak, rendang, laksa etc.): Gemini fallback used
//        → User sees gram input pre-filled with Gemini's estimate, can adjust
//        → All macros recalculate live as grams change
//
// Why gram estimation matters:
//   Gemini can recognise "that's nasi lemak" fairly well, but had no idea if
//   the plate was 200g or 500g — it always returned the same calorie number.
//   Now it looks at plate size, food depth, and density to guess grams first.
// ─────────────────────────────────────────────────────────────────────────────
class MealGeminiService {

  // ── NEW: classifyMealWithGrams ─────────────────────────────────────────────
  // Replaces the old classifyMeal(). Key differences:
  //   - Returns estimated_grams (Gemini's visual estimate of portion weight)
  //   - Returns fallback macros for THAT gram weight (not for "one serving")
  //   - Returns is_regional flag so meal_service knows whether to try USDA
  //   - confidence is 0.0–1.0 float (not "High"/"Medium"/"Low" string)
  //   - portion_reasoning explains how Gemini estimated the grams
  Future<List<Map<String, dynamic>>> classifyMealWithGrams(
      List<int> imageBytes) async {

    // ── PROMPT ──────────────────────────────────────────────────────────────
    // Low temperature (0.2) = consistent, less creative outputs.
    // We ask Gemini to think about gram weight BEFORE calories because
    // anchoring on weight first leads to more calibrated macro estimates.
    const prompt = '''
You are a professional nutritionist and food recognition AI.

Look at this meal photo carefully. Analyse:
- What dish is this?
- How much food is on the plate? Estimate weight in grams by looking at:
  * Plate/bowl diameter (standard dinner plate ≈ 26cm, holds 400–600g of food)
  * Food depth and density (rice is denser than salad)
  * Any reference objects visible (spoon, fork, hand, drink cup)
- Is this dish in the USDA FoodData Central database?
  USDA covers: standard Western/American foods, raw ingredients, packaged foods.
  USDA does NOT cover: Malaysian, Indonesian, Thai, Indian, Middle Eastern,
  African, or other regional dishes.

Return ONLY a raw JSON array — no markdown, no backticks, no explanation.
Exactly 3 candidates ranked from most to least likely:

[
  {
    "name": "exact dish name in English",
    "estimated_grams": 350,
    "confidence": 0.88,
    "is_regional": true,
    "fallback_calories": 620,
    "fallback_protein": 18.5,
    "fallback_carbs": 72.0,
    "fallback_fat": 28.0,
    "portion_reasoning": "Standard nasi lemak on medium plate, rice ~200g, sambal+egg+anchovies ~150g"
  }
]

RULES — follow exactly:
- estimated_grams: specific number based on what you see (e.g. 320, not 300).
- confidence: float 0.0 to 1.0 — NOT a string like "High".
- is_regional: true for any non-Western cuisine.
- fallback_calories / fallback_protein / fallback_carbs / fallback_fat:
  macros for the EXACT estimated_grams weight you gave — NOT per 100g.
  Use your knowledge of the dish's typical recipe and cooking method.
- portion_reasoning: one sentence explaining your gram estimate.
- ALL numeric values must be numbers, never strings.
''';

    try {
      if (AppConstants.geminiApiKey.isEmpty) {
        throw Exception(
          'GEMINI_API_KEY is empty. '
          'Run with: flutter run --dart-define-from-file=.env',
        );
      }

      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.5-flash-lite:generateContent?key=${AppConstants.geminiApiKey}',
      );

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
          'generationConfig': {
            // Low temperature = consistent estimates, less hallucination
            'temperature': 0.2,
            'maxOutputTokens': 1024,
          },
        }),
      );

      if (response.statusCode != 200) {
        throw Exception(
            'Meal API error ${response.statusCode}: ${response.body}');
      }

      final data = jsonDecode(response.body);
      final text = data['candidates'][0]['content']['parts'][0]['text'] as String;

      // Strip markdown fences if Gemini adds them despite instructions
      final cleaned = text
          .replaceAll(RegExp(r'```json', caseSensitive: false), '')
          .replaceAll('```', '')
          .trim();

      // Find the JSON array boundaries — handles any leading/trailing text
      final s = cleaned.indexOf('[');
      final e = cleaned.lastIndexOf(']');
      if (s == -1 || e == -1) {
        throw Exception('No JSON array found in Gemini response: $cleaned');
      }

      final List<dynamic> parsed = jsonDecode(cleaned.substring(s, e + 1));
      return parsed.cast<Map<String, dynamic>>();

    } catch (e) {
      print('MealGeminiService.classifyMealWithGrams error: $e');
      // Return a single safe fallback so the UI doesn't crash
      return [_fallbackCandidate()];
    }
  }

  // ── FALLBACK ───────────────────────────────────────────────────────────────
  // Used when Gemini call fails entirely (network error, malformed response).
  // Per-100g values are set so gram adjustments in the card still work.
  Map<String, dynamic> _fallbackCandidate() => {
    'name'              : 'Unknown dish',
    'estimated_grams'   : 200,
    'confidence'        : 0.3,
    'is_regional'       : false,
    'fallback_calories' : 400,
    'fallback_protein'  : 15.0,
    'fallback_carbs'    : 50.0,
    'fallback_fat'      : 12.0,
    'portion_reasoning' : 'Could not analyse image',
    // These per-100g values are set by meal_service.enrichCandidate()
    // after the USDA lookup. Pre-filled here so the card renders safely
    // even if enrichment hasn't run yet.
    'cal_per_100g'      : 200.0,
    'prot_per_100g'     : 7.5,
    'carb_per_100g'     : 25.0,
    'fat_per_100g'      : 6.0,
    'source'            : 'Gemini estimate',
  };
}