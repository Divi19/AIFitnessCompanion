import 'dart:convert';
import 'package:firebase_ai/firebase_ai.dart';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class GeminiService {
  // ── GENERATION ───────────────────────────────────────────────────────────
  // Uses the new firebase_ai package (replaces deprecated firebase_vertexai)
  final _generationModel = FirebaseAI.vertexAI().generativeModel(
    model: 'gemini-2.0-flash',
  );

  Future<String> generateResponse(String fullPrompt) async {
    final content = [Content.text(fullPrompt)];
    final response = await _generationModel.generateContent(content);
    return response.text ?? 'Could not generate a response. Please try again.';
  }

  // ── EMBEDDING ────────────────────────────────────────────────────────────
  // firebase_ai intentionally removed embedContent from its client SDK.
  // We call the Gemini REST API directly using an authenticated Firebase token.
  // This is still 100% within Flutter + Firebase — no external service needed.
  Future<List<double>> getEmbedding(String text) async {
    // Get the current Firebase user's ID token for authentication
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User must be signed in to call embedding API.');

    final idToken = await user.getIdToken();

    // Call the Gemini embedding REST endpoint directly
    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent',
    );

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'model': 'models/text-embedding-004',
        'content': {
          'parts': [
            {'text': text}
          ]
        },
        'taskType': 'RETRIEVAL_DOCUMENT', // use RETRIEVAL_QUERY for user queries
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Embedding API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body);
    final values = json['embedding']['values'] as List<dynamic>;
    return values.map((v) => (v as num).toDouble()).toList();
  }

  // Separate method for query embeddings (different taskType improves retrieval quality)
  Future<List<double>> getQueryEmbedding(String text) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('User must be signed in.');
    final idToken = await user.getIdToken();

    final uri = Uri.parse(
      'https://generativelanguage.googleapis.com/v1beta/models/text-embedding-004:embedContent',
    );

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'model': 'models/text-embedding-004',
        'content': {
          'parts': [
            {'text': text}
          ]
        },
        'taskType': 'RETRIEVAL_QUERY', // different from document embedding
      }),
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Embedding API error ${response.statusCode}: ${response.body}',
      );
    }

    final json = jsonDecode(response.body);
    final values = json['embedding']['values'] as List<dynamic>;
    return values.map((v) => (v as num).toDouble()).toList();
  }
}