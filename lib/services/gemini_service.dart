import 'dart:typed_data'; // Required for Uint8List
import 'package:firebase_vertexai/firebase_vertexai.dart';

class GeminiService {
  // Added 'late' to ensure Firebase is ready before this triggers
  late final _model = FirebaseVertexAI.instance.generativeModel(
    model: 'gemini-1.5-pro', 
  );

  // Text-only prompt — used for RAG Nutrition Assistant and Workout Generation
  Future<String> generateText(String prompt) async {
    final content = [Content.text(prompt)];
    final response = await _model.generateContent(content);
    return response.text ?? '';
  }

  // Image + text prompt — used for Dietary & Menu Scanning
  Future<String> analyzeImage(List<int> imageBytes, String prompt) async {
    final content = [
      Content.multi([
        // Converted List<int> to Uint8List
        DataPart('image/jpeg', Uint8List.fromList(imageBytes)), 
        TextPart(prompt),
      ])
    ];
    final response = await _model.generateContent(content);
    return response.text ?? '';
  }
}