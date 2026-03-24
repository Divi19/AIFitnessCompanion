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
// FLOW (3 steps):
//
//   Step 1 — FOOD VALIDATION (Gemini):
//     Send image to Gemini and ask: "Is this food?"
//     If NOT food → UI shows invalid state. Flow stops.
//
//   Step 2 — DISH IDENTIFICATION (Gemini):
//     Identifies dish name, estimates grams, flags regional dishes,
//     provides fallback macros. Returns 3 candidates by confidence.
//     No example dish names in prompt — avoids biasing the model.
//
//   Step 3 — NUTRITION LOOKUP (meal_service.dart):
//     USDA lookup by dish name → found: real macros × grams
//     Not found (regional) → Gemini fallback macros
//     If all candidates < 0.35 confidence → treated as unidentifiable.
// ─────────────────────────────────────────────────────────────────────────────
class MealGeminiService {

  // ── STEP 1: VALIDATE ──────────────────────────────────────────────────────
  // Is this actually a food image?
  // Called FIRST before any nutrition lookup.
  // Returns true if food/beverage, false otherwise.
  // On network error → returns true so user isn't blocked.
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
      final text = (data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '')
          .trim()
          .toUpperCase();
      print('Food validation result: "$text"');
      return text.contains('FOOD') && !text.contains('NOT_FOOD');

    } catch (e) {
      print('validateFoodImage error: $e');
      return true; // Network error → don't block user
    }
  }

  // ── STEP 2: IDENTIFY DISH + ESTIMATE GRAMS ────────────────────────────────
  // Called only after validateFoodImage() returns true.
  //
  // IMPORTANT: No example dish names anywhere in the prompt.
  // Example names bias Gemini toward guessing those dishes
  // even when the image shows something completely different.
  //
  // Returns 3 candidates each with:
  //   name, estimated_grams, confidence (0.0–1.0), is_regional,
  //   fallback_calories/protein/carbs/fat (for that gram weight),
  //   portion_reasoning
  Future<List<Map<String, dynamic>>> classifyMealWithGrams(List<int> imageBytes) async {
    const prompt = '''
You are a professional nutritionist and food recognition AI.

Analyse this food photo carefully and do the following:

STEP 1 — IDENTIFY: What food or dish is shown in THIS specific image?
  - Look only at what is visible in the image
  - Do NOT assume or guess a dish that is not clearly visible
  - If the image is blurry, unclear, or the food cannot be confidently identified,
    set confidence below 0.40 and name it "Unidentified food"

STEP 2 — ESTIMATE WEIGHT: How many grams of food are on the plate/bowl?
  - Standard dinner plate (26cm) typically holds 400–600g of food
  - Small bowl typically holds 200–350g
  - Judge by food depth, density, and any visible reference objects

STEP 3 — CLASSIFY: Is this dish in the USDA FoodData Central database?
  - USDA has: Western/American foods, raw ingredients, packaged foods
  - USDA does NOT have: Malaysian, Indonesian, Thai, Indian, Middle Eastern,
    African, or other regional/local cuisine dishes

Return ONLY a raw JSON array — no markdown, no backticks, no explanation.
Return exactly 3 candidates ranked from most to least confident.

JSON format (fill in based on what YOU actually see in the image):
[
  {
    "name": "name of what you actually see in the image",
    "estimated_grams": 300,
    "confidence": 0.85,
    "is_regional": false,
    "fallback_calories": 500,
    "fallback_protein": 20.0,
    "fallback_carbs": 60.0,
    "fallback_fat": 15.0,
    "portion_reasoning": "describe what you see and how you estimated the weight"
  },
  {
    "name": "second most likely identification",
    "estimated_grams": 300,
    "confidence": 0.60,
    "is_regional": false,
    "fallback_calories": 480,
    "fallback_protein": 18.0,
    "fallback_carbs": 58.0,
    "fallback_fat": 14.0,
    "portion_reasoning": "alternative identification reason"
  },
  {
    "name": "third most likely identification",
    "estimated_grams": 300,
    "confidence": 0.30,
    "is_regional": false,
    "fallback_calories": 460,
    "fallback_protein": 16.0,
    "fallback_carbs": 55.0,
    "fallback_fat": 13.0,
    "portion_reasoning": "third alternative reason"
  }
]

STRICT RULES — follow every one:
- "name": identify from the IMAGE ONLY — do not default to any specific dish
- "estimated_grams": a specific number based on what you actually see
- "confidence": float 0.0–1.0, NOT a string. Be honest — if unclear, use a low value
- "is_regional": true for non-Western/non-American cuisine
- "fallback_calories/protein/carbs/fat": macros for that EXACT gram weight, NOT per 100g
- "portion_reasoning": describe what you visually see to justify the gram estimate
- ALL numeric values must be actual numbers, never strings
- If food is completely unidentifiable, return 3 candidates all with confidence < 0.40
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

      if (response.statusCode != 200) {
        throw Exception('Meal API error ${response.statusCode}: ${response.body}');
      }

      final data    = jsonDecode(response.body);
      final rawText = data['candidates']?[0]?['content']?['parts']?[0]?['text'] as String? ?? '';

      // Strip markdown fences Gemini sometimes adds despite instructions
      final cleaned = rawText
          .replaceAll(RegExp(r'```json', caseSensitive: false), '')
          .replaceAll('```', '')
          .trim();

      final s = cleaned.indexOf('[');
      final e = cleaned.lastIndexOf(']');
      if (s == -1 || e == -1) {
        throw Exception('No JSON array in Gemini response: $cleaned');
      }

      final parsed = jsonDecode(cleaned.substring(s, e + 1)) as List;
      return parsed.cast<Map<String, dynamic>>();

    } catch (e) {
      print('classifyMealWithGrams error: $e');
      // Return zero-confidence fallback — meal_tracker_screen will detect
      // this as unidentifiable and show the invalid state
      return [_fallbackCandidate()];
    }
  }

  // ── FALLBACK ───────────────────────────────────────────────────────────────
  // Used ONLY when the API call fails entirely (network error, bad JSON).
  // confidence: 0.0 → meal_tracker_screen treats this as unidentifiable
  // and shows the invalid image state instead of a wrong suggestion.
  Map<String, dynamic> _fallbackCandidate() => {
    'name'              : 'Unidentified food',
    'estimated_grams'   : 200,
    'confidence'        : 0.0,
    'is_regional'       : false,
    'fallback_calories' : 0,
    'fallback_protein'  : 0.0,
    'fallback_carbs'    : 0.0,
    'fallback_fat'      : 0.0,
    'portion_reasoning' : 'API call failed — could not analyse image',
    'cal_per_100g'      : 0.0,
    'prot_per_100g'     : 0.0,
    'carb_per_100g'     : 0.0,
    'fat_per_100g'      : 0.0,
    'source'            : 'Error',
  };
}