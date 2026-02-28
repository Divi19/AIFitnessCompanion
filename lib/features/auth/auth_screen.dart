import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

class AuthScreen extends StatefulWidget {
  const AuthScreen({super.key});

  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  final _auth = FirebaseAuth.instance;
  final _db = FirebaseFirestore.instance;

  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nameController = TextEditingController();
  final _goalController = TextEditingController();

  bool _isLogin = true;       // toggles between Login and Sign Up
  bool _isLoading = false;
  String _errorMessage = '';
  bool _obscurePassword = true;

  // Physical limitations — user taps chips to select
  final List<String> _availableLimitations = [
    'Lower back injury',
    'Knee injury',
    'Shoulder / rotator cuff',
    'Wrist / elbow pain',
    'Hip injury',
    'Neck pain',
    'None',
  ];
  final Set<String> _selectedLimitations = {'None'};

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nameController.dispose();
    _goalController.dispose();
    super.dispose();
  }

  // ── SIGN UP ───────────────────────────────────────────────────────────────
  Future<void> _signUp() async {
    if (_nameController.text.trim().isEmpty) {
      setState(() => _errorMessage = 'Please enter your name.');
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      // Create Firebase Auth account
      final credential = await _auth.createUserWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );

      final uid = credential.user!.uid;

      // Build limitations list — exclude 'None' if other things selected
      final limitations = _selectedLimitations.contains('None') &&
              _selectedLimitations.length == 1
          ? <String>[]
          : _selectedLimitations.where((l) => l != 'None').toList();

      // Write user profile to Firestore — this is what the RAG uses
      await _db.collection('users').doc(uid).set({
        'name': _nameController.text.trim(),
        'email': _emailController.text.trim(),
        'fitness_goal': _goalController.text.trim().isEmpty
            ? 'general fitness'
            : _goalController.text.trim(),
        'physical_limitations': limitations,
        'fatigue_score': 5,       // default — can be updated later
        'current_streak': 0,
        'created_at': FieldValue.serverTimestamp(),
      });

      // Navigate to home — StreamBuilder in main.dart handles this automatically
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.code));
    } catch (e) {
      setState(() => _errorMessage = 'Something went wrong: $e');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── LOGIN ─────────────────────────────────────────────────────────────────
  Future<void> _login() async {
    setState(() {
      _isLoading = true;
      _errorMessage = '';
    });

    try {
      await _auth.signInWithEmailAndPassword(
        email: _emailController.text.trim(),
        password: _passwordController.text.trim(),
      );
      // StreamBuilder in main.dart automatically navigates on auth state change
    } on FirebaseAuthException catch (e) {
      setState(() => _errorMessage = _friendlyError(e.code));
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // ── FRIENDLY ERROR MESSAGES ───────────────────────────────────────────────
  String _friendlyError(String code) {
    switch (code) {
      case 'email-already-in-use':
        return 'An account with this email already exists. Try logging in.';
      case 'invalid-email':
        return 'Please enter a valid email address.';
      case 'weak-password':
        return 'Password must be at least 6 characters.';
      case 'user-not-found':
        return 'No account found with this email. Try signing up.';
      case 'wrong-password':
      case 'invalid-credential':
        return 'Incorrect email or password.';
      case 'too-many-requests':
        return 'Too many attempts. Please wait a moment and try again.';
      default:
        return 'Error: $code';
    }
  }

  // ── UI ────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D), // Deep Black
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(horizontal: 28, vertical: 40),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [

              // ── Header ──────────────────────────────────────────────────
              const Icon(
                Icons.fitness_center,
                size: 56,
                color: Color(0xFFB9FF2B), // Volt Green
              ),
              const SizedBox(height: 12),
              Text(
                _isLogin ? 'Welcome Back' : 'Create Account',
                textAlign: TextAlign.center,
                style: const TextStyle(
                  fontSize: 26,
                  fontWeight: FontWeight.bold,
                  color: Colors.white,
                ),
              ),
              Text(
                _isLogin
                    ? 'Sign in to your AI Fitness Companion'
                    : 'Set up your personalised fitness profile',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 14, color: Colors.grey),
              ),

              const SizedBox(height: 36),

              // ── Sign Up only fields ──────────────────────────────────────
              if (!_isLogin) ...[
                _buildTextField(
                  controller: _nameController,
                  label: 'Full Name',
                  icon: Icons.person_outline,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _goalController,
                  label: 'Fitness Goal (e.g. hypertrophy, fat loss)',
                  icon: Icons.flag_outlined,
                ),
                const SizedBox(height: 24),

                // Physical limitations chips
                const Text(
                  'Physical Limitations / Injuries',
                  style: TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  'The AI uses this to personalise recommendations and flag unsafe exercises.',
                  style: TextStyle(fontSize: 12, color: Colors.grey),
                ),
                const SizedBox(height: 12),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: _availableLimitations.map((limitation) {
                    final selected = _selectedLimitations.contains(limitation);
                    return FilterChip(
                      label: Text(
                        limitation,
                        style: TextStyle(
                          color: selected ? Colors.black : Colors.white70,
                          fontWeight: selected ? FontWeight.bold : FontWeight.normal,
                        ),
                      ),
                      selected: selected,
                      backgroundColor: const Color(0xFF1A1A1A), // Dark surface
                      selectedColor: const Color(0xFFB9FF2B), // Volt Green
                      checkmarkColor: Colors.black,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                        side: BorderSide(
                          color: selected ? const Color(0xFFB9FF2B) : Colors.white10,
                        ),
                      ),
                      onSelected: (val) {
                        setState(() {
                          if (limitation == 'None') {
                            _selectedLimitations.clear();
                            _selectedLimitations.add('None');
                          } else {
                            _selectedLimitations.remove('None');
                            if (val) {
                              _selectedLimitations.add(limitation);
                            } else {
                              _selectedLimitations.remove(limitation);
                              if (_selectedLimitations.isEmpty) {
                                _selectedLimitations.add('None');
                              }
                            }
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
                const SizedBox(height: 24),
              ],

              // ── Email ────────────────────────────────────────────────────
              _buildTextField(
                controller: _emailController,
                label: 'Email',
                icon: Icons.email_outlined,
                keyboardType: TextInputType.emailAddress,
              ),
              const SizedBox(height: 16),

              // ── Password ─────────────────────────────────────────────────
              TextField(
                controller: _passwordController,
                obscureText: _obscurePassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Password',
                  labelStyle: TextStyle(color: Colors.grey),
                  prefixIcon: Icon(Icons.lock_outline, color: Colors.grey),
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                      color: Colors.grey,
                    ),
                    onPressed: () =>
                        setState(() => _obscurePassword = !_obscurePassword),
                  ),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: const Color(0xFF1A1A1A), // Dark surface
                ),
              ),

              const SizedBox(height: 16),

              // ── Error message ─────────────────────────────────────────────
              if (_errorMessage.isNotEmpty)
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5E00).withOpacity(0.15), // Electric Orange tint
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: const Color(0xFFFF5E00)),
                  ),
                  child: Text(
                    _errorMessage,
                    style: const TextStyle(color: Color(0xFFFF5E00), fontSize: 13),
                  ),
                ),

              const SizedBox(height: 24),

              // ── Submit button ─────────────────────────────────────────────
              ElevatedButton(
                onPressed: _isLoading
                    ? null
                    : (_isLogin ? _login : _signUp),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFB9FF2B), // Volt Green
                  foregroundColor: Colors.black, // High contrast text
                  padding: const EdgeInsets.symmetric(vertical: 18),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                  disabledBackgroundColor: const Color(0xFF1A1A1A),
                  disabledForegroundColor: Colors.grey,
                ),
                child: _isLoading
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          color: Colors.black,
                          strokeWidth: 2,
                        ),
                      )
                    : Text(
                        _isLogin ? 'Sign In' : 'Create Account',
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
              ),

              const SizedBox(height: 16),

              // ── Toggle login / signup ─────────────────────────────────────
              TextButton(
                onPressed: () {
                  setState(() {
                    _isLogin = !_isLogin;
                    _errorMessage = '';
                  });
                },
                child: Text(
                  _isLogin
                      ? "Don't have an account? Sign Up"
                      : 'Already have an account? Sign In',
                  style: const TextStyle(
                    color: Color(0xFFB9FF2B), // Volt Green link
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── REUSABLE TEXT FIELD ───────────────────────────────────────────────────
  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType keyboardType = TextInputType.text,
  }) {
    return TextField(
      controller: controller,
      keyboardType: keyboardType,
      style: const TextStyle(color: Colors.white),
      decoration: InputDecoration(
        labelText: label,
        labelStyle: TextStyle(color: Colors.grey),
        prefixIcon: Icon(icon, color: Colors.grey),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        filled: true,
        fillColor: const Color(0xFF1A1A1A), // Dark surface
      ),
    );
  }
}