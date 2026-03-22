import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class GeminiService {
  // Routes through Firebase AI Logic (Vertex AI backend).
  // No API key needed — Firebase handles auth automatically.
  final _generationModel = FirebaseAI.vertexAI().generativeModel(
    model: 'gemini-2.0-flash',
  );

  Future<String> generateResponse(String fullPrompt) async {
    final content = [Content.text(fullPrompt)];
    final response = await _generationModel.generateContent(content);
    return response.text ?? 'Could not generate a response. Please try again.';
  }

  Stream<String> streamResponse(String fullPrompt) async* {
    final content = [Content.text(fullPrompt)];
    final responseStream = _generationModel.generateContentStream(content);
    await for (final chunk in responseStream) {
      if (chunk.text != null) yield chunk.text!;
    }
  }

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

  Future<List<double>> getEmbedding(String text) async {
    return _callEmbeddingApi(text, 'RETRIEVAL_DOCUMENT');
  }

  Future<List<double>> getQueryEmbedding(String text) async {
    return _callEmbeddingApi(text, 'RETRIEVAL_QUERY');
  }

  Future<List<double>> _callEmbeddingApi(String text, String taskType) async {
    if (AppConstants.geminiApiKey.isEmpty) {
      throw Exception('GEMINI_API_KEY is empty. Run with: flutter run --dart-define-from-file=.env');
    }
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/gemini-embedding-001:embedContent',
    );
    final response = await http.post(uri,
      headers: {'Content-Type': 'application/json', 'x-goog-api-key': AppConstants.geminiApiKey},
      body: jsonEncode({
        'model': 'models/gemini-embedding-001',
        'content': {'parts': [{'text': text}]},
        'taskType': taskType,
        // Pinned to 768 to match Firestore vector index dimension.
        // Do NOT change after ingesting data.
        'outputDimensionality': 768,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Embedding API error ${response.statusCode}: ${response.body}');
    }
    final decoded = jsonDecode(response.body);
    final values  = decoded['embedding']['values'] as List<dynamic>;
    return values.map((v) => (v as num).toDouble()).toList();
  }
}

// ── MEAL CLASSIFICATION SERVICE ───────────────────────────────────────────────
//
// NEW FLOW (3 steps):
//
//   Step 1 — FOOD VALIDATION (Gemini):
//     Send image to Gemini and ask: "Is this food?"
//     If NOT food → return { isFood: false } immediately.
//     UI shows invalid state. Flow stops here.
//
//   Step 2 — DISH IDENTIFICATION (Gemini):
//     If it IS food, Gemini identifies:
//       - dish name (English)
//       - estimated grams based on visual cues
//       - whether it's regional (USDA won't have it)
//       - fallback macros for that gram weight
//     Returns 3 candidates ranked by confidence.
//
//   Step 3 — NUTRITION LOOKUP (meal_service.dart):
//     For each candidate:
//       a. Search USDA FoodData Central by dish name
//       b. Found → use USDA per-100g macros × (grams / 100) ← most accurate
//       c. Not found (regional) → use Gemini's fallback macros
//     User sees gram input pre-filled with Gemini's estimate, can adjust.
//     All macros recalculate live.
// ─────────────────────────────────────────────────────────────────────────────
class MealGeminiService {

  // ── STEP 1: VALIDATE — is this actually a food image? ─────────────────────
  // Called FIRST before any nutrition lookup.
  // Returns true if the image contains food, false otherwise.
  // This prevents nonsense results when users photograph themselves,
  // their gym equipment, pets, scenery, etc.
  Future<bool> validateFoodImage(List<int> imageBytes) async {
    const prompt = '''
Look at this image carefully.

Answer with ONLY one of these two exact words — nothing else:
  FOOD      — if the image clearly contains food or a beverage that can be eaten/drunk
  NOT_FOOD  — if the image does not contain food (e.g. person, gym, landscape, object)

Be strict: a hand holding a protein bar is FOOD. An empty plate is NOT_FOOD.
A glass of water is FOOD. A running shoe is NOT_FOOD.
''';

    try {
      if (AppConstants.geminiApiKey.isEmpty) throw Exception('GEMINI_API_KEY is empty.');

      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.5-flash-lite:generateContent?key=${AppConstants.geminiApiKey}',
      );

      final response = await http.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [
              {'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(Uint8List.fromList(imageBytes))}},
              {'text': prompt},
            ]
          }],
          'generationConfig': {'temperature': 0.0, 'maxOutputTokens': 10},
        }),
      );

      if (response.statusCode != 200) return false;

      final data = jsonDecode(response.body);
      final text = (data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '').trim().toUpperCase();
      print('Food validation result: "$text"');
      return text.contains('FOOD') && !text.contains('NOT_FOOD');

    } catch (e) {
      print('validateFoodImage error: $e');
      // On network error, assume food so the user isn't blocked
      return true;
    }
  }

  // ── STEP 2: IDENTIFY DISH + ESTIMATE GRAMS ────────────────────────────────
  // Called only after validateFoodImage() returns true.
  // Returns 3 candidates each with:
  //   name, estimated_grams, confidence (0.0–1.0), is_regional,
  //   fallback_calories/protein/carbs/fat (for that gram weight),
  //   portion_reasoning
  Future<List<Map<String, dynamic>>> classifyMealWithGrams(List<int> imageBytes) async {
    const prompt = '''
You are a professional nutritionist and food recognition AI.

Look at this meal photo carefully and analyse:
1. What dish is this?
2. Estimate the weight in grams by looking at:
   - Plate/bowl size (standard dinner plate ≈ 26cm holds 400–600g of food)
   - Food depth and density (rice is denser than salad)
   - Any visible reference objects (spoon, fork, hand, cup)
3. Is this dish in the USDA FoodData Central database?
   USDA has: standard Western/American foods, raw ingredients, packaged foods.
   USDA does NOT have: Malaysian, Indonesian, Thai, Indian, Middle Eastern, African dishes.

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
    "portion_reasoning": "Standard nasi lemak on medium plate, rice ~200g, sides ~150g"
  }
]

STRICT RULES:
- estimated_grams: specific number (e.g. 320, not 300) based on what you see
- confidence: float 0.0–1.0, NOT a string like "High"
- is_regional: true for any non-Western/non-American cuisine
- fallback_calories/protein/carbs/fat: macros for the EXACT estimated_grams weight — NOT per 100g
- portion_reasoning: one sentence explaining your gram estimate
- ALL numeric values must be numbers, never strings
''';

    try {
      if (AppConstants.geminiApiKey.isEmpty) throw Exception('GEMINI_API_KEY is empty.');

      final uri = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/'
        'gemini-2.5-flash-lite:generateContent?key=${AppConstants.geminiApiKey}',
      );

      final response = await http.post(uri,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'contents': [{
            'parts': [
              {'inline_data': {'mime_type': 'image/jpeg', 'data': base64Encode(Uint8List.fromList(imageBytes))}},
              {'text': prompt},
            ]
          }],
          // Low temperature = consistent gram estimates, less hallucination
          'generationConfig': {'temperature': 0.2, 'maxOutputTokens': 1024},
        }),
      );

      if (response.statusCode != 200) throw Exception('Meal API error ${response.statusCode}');

      final data    = jsonDecode(response.body);
      final rawText = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';

      // Strip markdown fences Gemini sometimes adds despite instructions
      final cleaned = rawText
          .replaceAll(RegExp(r'```json', caseSensitive: false), '')
          .replaceAll('```', '')
          .trim();

      final s = cleaned.indexOf('[');
      final e = cleaned.lastIndexOf(']');
      if (s == -1 || e == -1) throw Exception('No JSON array in Gemini response: $cleaned');

      final parsed = jsonDecode(cleaned.substring(s, e + 1)) as List;
      return parsed.cast<Map<String, dynamic>>();

    } catch (e) {
      print('classifyMealWithGrams error: $e');
      return [_fallbackCandidate()];
    }
  }

  // ── FALLBACK ───────────────────────────────────────────────────────────────
  // Used only when Gemini call fails entirely (network error, bad JSON).
  // Per-100g values included so gram adjustments in the card still work.
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
    'cal_per_100g'      : 200.0,
    'prot_per_100g'     : 7.5,
    'carb_per_100g'     : 25.0,
    'fat_per_100g'      : 6.0,
    'source'            : 'Gemini estimate',
  };
}