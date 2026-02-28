import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class KnowledgeBaseService {
  final _db = FirebaseFirestore.instance;
  static const _collection = 'knowledge_base';

  // ── WRITE ──────────────────────────────────────────────────────────────────
  // Uses Firestore REST because the Flutter SDK doesn't expose vector types yet.
  // Firebase ID token (from logged-in user) is the correct auth for Firestore REST.
  Future<void> saveChunk({
    required String text,
    required String source,
    required String category,
    required List<double> embedding,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Must be signed in to save chunks.');

    final idToken = await user.getIdToken();
    final projectId = _db.app.options.projectId;

    final body = jsonEncode({
      'fields': {
        'text': {'stringValue': text},
        'source': {'stringValue': source},
        'category': {'stringValue': category},
        'embedding': {
          'mapValue': {
            'fields': {
              '__type__': {'stringValue': '__vector__'},
              'value': {
                'arrayValue': {
                  'values': embedding
                      .map((v) => {'doubleValue': v})
                      .toList(),
                }
              }
            }
          }
        },
      }
    });

    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId'
      '/databases/(default)/documents/$_collection',
    );

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Firestore write error ${response.statusCode}: ${response.body}',
      );
    }
  }

  // ── VECTOR SEARCH ──────────────────────────────────────────────────────────
  // Firestore REST runQuery with findNearest.
  // Supported in the REST API even though the Flutter SDK doesn't expose it yet.
  Future<List<Map<String, dynamic>>> searchSimilarChunks({
    required List<double> queryVector,
    int limit = 3,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Must be signed in to search.');

    final idToken = await user.getIdToken();
    final projectId = _db.app.options.projectId;

    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId'
      '/databases/(default)/documents:runQuery',
    );

    final body = jsonEncode({
      'structuredQuery': {
        'from': [
          {'collectionId': _collection}
        ],
        'findNearest': {
          'vectorField': {'fieldPath': 'embedding'},
          'queryVector': {
            'mapValue': {
              'fields': {
                '__type__': {'stringValue': '__vector__'},
                'value': {
                  'arrayValue': {
                    'values': queryVector
                        .map((v) => {'doubleValue': v})
                        .toList(),
                  }
                }
              }
            }
          },
          'distanceMeasure': 'COSINE',
          'limit': limit,
        },
      }
    });

    final response = await http.post(
      uri,
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: body,
    );

    if (response.statusCode != 200) {
      throw Exception(
        'Vector search error ${response.statusCode}: ${response.body}',
      );
    }

    final List<dynamic> results = jsonDecode(response.body);

    return results
        .where((r) => r['document'] != null)
        .map((r) {
          final fields = r['document']['fields'] as Map<String, dynamic>;
          return {
            'text': fields['text']?['stringValue'] ?? '',
            'source': fields['source']?['stringValue'] ?? '',
            'category': fields['category']?['stringValue'] ?? '',
          };
        })
        .toList();
  }
}