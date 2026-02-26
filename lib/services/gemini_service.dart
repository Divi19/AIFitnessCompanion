import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import '../core/constants.dart';

class GeminiService {
  // ── GENERATION ────────────────────────────────────────────────────────────
  // Uses firebase_ai package — routed securely through your Firebase project.
  // No API key needed here; Firebase handles auth for generation.
  final _generationModel = FirebaseAI.vertexAI().generativeModel(
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
  }
}