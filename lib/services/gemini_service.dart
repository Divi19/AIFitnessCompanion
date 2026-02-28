import 'dart:typed_data';
import 'dart:convert';
import 'package:firebase_vertexai/firebase_vertexai.dart';
import 'package:google_generative_ai/google_generative_ai.dart' as genai;

class GeminiService {
  // Use 'late' to ensure Firebase is initialized before this is accessed
  late final _model = FirebaseVertexAI.instance.generativeModel(
    model: 'gemini-2.0-flash',
  );

  // Text-only prompt
  Future<String> generateText(String prompt) async {
    final content = [Content.text(prompt)];
    final response = await _model.generateContent(content);
    return response.text ?? '';
  }

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