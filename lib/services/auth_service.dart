import 'package:firebase_auth/firebase_auth.dart';

class AuthService {
  final FirebaseAuth _auth = FirebaseAuth.instance;

  // Stream to listen to auth state changes (is the user logged in?)
  Stream<User?> get user => _auth.authStateChanges();

  // Sign up with Email
  Future<UserCredential?> signUp(String email, String password) async {
    return await _auth.createUserWithEmailAndPassword(email: email, password: password);
  }

  // Sign in
  Future<UserCredential?> signIn(String email, String password) async {
    return await _auth.signInWithEmailAndPassword(email: email, password: password);
  }

  // Sign out
  Future<void> signOut() async => await _auth.signOut();
}