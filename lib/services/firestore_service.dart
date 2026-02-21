import 'package:cloud_firestore/cloud_firestore.dart';

class FirestoreService {
  final FirebaseFirestore _db = FirebaseFirestore.instance;

  // Save a generated workout
  Future<void> saveWorkout(String userId, Map<String, dynamic> workoutData) async {
    await _db.collection('users').doc(userId).collection('workouts').add({
      ...workoutData,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  // Get user profile (for your Accountability Contract logic)
  Stream<DocumentSnapshot> getUserProfile(String userId) {
    return _db.collection('users').doc(userId).snapshots();
  }
}