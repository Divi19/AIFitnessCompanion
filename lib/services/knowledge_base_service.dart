import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

class KnowledgeBaseService {
  final _db = FirebaseFirestore.instance;
  static const _collection = 'knowledge_base';

  // ── WRITE ──────────────────────────────────────────────────────────────────
  // Writing vectors via the REST API because FieldValue.vector() also doesn't
  // exist in the Flutter SDK yet.
  Future<void> saveChunk({
    required String text,
    required String source,
    required String category,
    required List<double> embedding,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Must be signed in.');

    final idToken = await user.getIdToken();
    final projectId = await _getProjectId();

    // Build a Firestore REST document with a mapValue containing all fields.
    // The vector embedding is stored as an 'arrayValue' of doubleValues —
    // this is the correct REST representation for a vector field.
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
      throw Exception('Firestore write failed ${response.statusCode}: ${response.body}');
    }
  }

  // ── VECTOR SEARCH ──────────────────────────────────────────────────────────
  // Uses the Firestore REST runQuery endpoint with a FindNearest clause —
  // this IS supported in the REST API even though it isn't in the Flutter SDK.
  Future<List<Map<String, dynamic>>> searchSimilarChunks({
    required List<double> queryVector,
    int limit = 3,
  }) async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw Exception('Must be signed in.');

    final idToken = await user.getIdToken();
    final projectId = await _getProjectId();

    final uri = Uri.parse(
      'https://firestore.googleapis.com/v1/projects/$projectId'
      '/databases/(default)/documents:runQuery',
    );

    // Firestore REST structured query with findNearest
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
      throw Exception('Vector search failed ${response.statusCode}: ${response.body}');
    }

    final List<dynamic> results = jsonDecode(response.body);

    // Parse the REST response format back into simple maps
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

  // ── HELPER ─────────────────────────────────────────────────────────────────
  // Gets the Firebase project ID from the Firestore instance app config.
  Future<String> _getProjectId() async {
    return _db.app.options.projectId;
  }
}