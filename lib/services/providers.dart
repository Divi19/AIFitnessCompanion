import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'auth_service.dart';
import 'firestore_service.dart';
import 'gemini_service.dart';

final authServiceProvider = Provider((ref) => AuthService());
final firestoreServiceProvider = Provider((ref) => FirestoreService());
final geminiServiceProvider = Provider((ref) => GeminiService());