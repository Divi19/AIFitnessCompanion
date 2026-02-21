import 'dart:typed_data';
import 'package:firebase_vertexai/firebase_vertexai.dart';

class GeminiService {
  // Use 'late' to ensure Firebase is initialized before this is accessed
  late final _model = FirebaseVertexAI.instance.generativeModel(
    model: 'gemini-1.5-pro',
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
        // In ^1.0.0, the specific class is InlineDataPart
        InlineDataPart('image/jpeg', Uint8List.fromList(imageBytes)),
        TextPart(prompt),
      ])
    ];
    
    final response = await _model.generateContent(content);
    return response.text ?? '';
  }
}