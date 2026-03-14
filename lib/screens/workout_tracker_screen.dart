import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart'; // NEW
import '../services/quickpose_service.dart';

class WorkoutTrackerScreen extends StatefulWidget {
  const WorkoutTrackerScreen({Key? key}) : super(key: key);

  @override
  State<WorkoutTrackerScreen> createState() => _WorkoutTrackerScreenState();
}

class _WorkoutTrackerScreenState extends State<WorkoutTrackerScreen> {

  final QuickPoseService _quickPoseService = QuickPoseService();

  // The native view type — must match VIEW_TYPE in MainActivity.kt
  static const String _viewType = 'com.example.ai_fitness_app/quickpose_view';

  // State
  bool   _hasPermission = false; // NEW
  int    _repCount      = 0;
  String _feedback      = '';
  String _status        = 'loading';
  String _exerciseState = '';
  int    _fps           = 0;

  // Currently selected exercise
  String _selectedExercise = 'squat';

  // Supported exercises — label shown to user : key sent to native
  final Map<String, String> _exercises = {
    'Squat':        'squat',
    'Push Up':      'pushup',
    'Bicep Curl':   'bicep_curl',
    'Jumping Jack': 'jumping_jack',
    'Left Lunge':   'lunge_left',
    'Right Lunge':  'lunge_right',
    'Sit Up':       'sit_up',
    'Plank':        'plank',
    'Glute Bridge': 'glute_bridge',
  };

  @override
  void initState() {
    super.initState();
    _requestCameraPermission(); // NEW: Ask for permission before doing anything
  }

  // NEW: Permission request logic
  Future<void> _requestCameraPermission() async {
    final status = await Permission.camera.request();
    if (status.isGranted) {
      setState(() {
        _hasPermission = true;
      });
      _listenToResults(); // Safe to start listening now
    } else {
      debugPrint('Camera permission denied by user.');
      // Keep _hasPermission as false to prevent the crash
    }
  }

  void _listenToResults() {
    _quickPoseService.resultsStream.listen(
      (data) {
        if (!mounted) return;
        setState(() {
          _repCount      = (data['repCount']      as int?)    ?? _repCount;
          _feedback      = (data['feedback']      as String?) ?? '';
          _status        = (data['status']        as String?) ?? 'loading';
          _exerciseState = (data['exerciseState'] as String?) ?? '';
          _fps           = (data['fps']           as int?)    ?? 0;
        });
      },
      onError: (error) {
        debugPrint('QuickPose stream error: $error');
      },
    );
  }

  Future<void> _switchExercise(String exerciseKey) async {
    setState(() {
      _selectedExercise = exerciseKey;
      _repCount         = 0;         
      _feedback         = '';
      _exerciseState    = '';
    });
    await _quickPoseService.switchExercise(exerciseKey);
  }

  @override
  void dispose() {
    _quickPoseService.stopCamera();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [

          // ── 1. Native QuickPose Camera View (full screen) ───────────────
          // NEW: Only render the AndroidView if permission is granted
          if (_hasPermission)
            Positioned.fill(
              child: AndroidView(
                viewType: _viewType,
                layoutDirection: TextDirection.ltr,
                creationParamsCodec: const StandardMessageCodec(),
              ),
            )
          else
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFB9FF2B)),
                      SizedBox(height: 16),
                      Text('Waiting for camera permission...',
                          style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),

          // ── 2. Top Bar ──────────────────────────────────────────────────
          SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: Colors.black54,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(Icons.arrow_back_ios,
                          color: Colors.white, size: 20),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$_fps fps',
                      style: const TextStyle(color: Colors.white54,
                          fontSize: 12),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // ── 3. Rep Counter (top centre) ─────────────────────────────────
          Positioned(
            top: 80,
            left: 0,
            right: 0,
            child: Column(
              children: [
                Text(
                  '$_repCount',
                  style: const TextStyle(
                    color: Color(0xFFB9FF2B), 
                    fontSize: 80,
                    fontWeight: FontWeight.w900,
                    height: 1,
                  ),
                ),
                const Text(
                  'reps',
                  style: TextStyle(color: Colors.white54, fontSize: 16),
                ),
              ],
            ),
          ),

          // ── 4. Form Feedback Banner ─────────────────────────────────────
          if (_feedback.isNotEmpty)
            Positioned(
              top: 220,
              left: 24,
              right: 24,
              child: Container(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: const Color(0xFFFF5E00).withOpacity(0.85),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  _feedback,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),

          // ── 5. Loading Overlay ──────────────────────────────────────────
          if (_hasPermission && _status == 'loading')
            Positioned.fill(
              child: Container(
                color: Colors.black54,
                child: const Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CircularProgressIndicator(color: Color(0xFFB9FF2B)),
                      SizedBox(height: 16),
                      Text('Starting pose detection...',
                          style: TextStyle(color: Colors.white)),
                    ],
                  ),
                ),
              ),
            ),

          // ── 6. Exercise Selector (bottom) ───────────────────────────────
          Positioned(
            bottom: 0,
            left: 0,
            right: 0,
            child: Container(
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [Colors.transparent, Colors.black.withOpacity(0.8)],
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                ),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Padding(
                    padding: EdgeInsets.only(left: 4, bottom: 10),
                    child: Text(
                      'SELECT EXERCISE',
                      style: TextStyle(
                        color: Colors.white54,
                        fontSize: 11,
                        letterSpacing: 1.5,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(
                    height: 44,
                    child: ListView(
                      scrollDirection: Axis.horizontal,
                      children: _exercises.entries.map((entry) {
                        final isSelected = _selectedExercise == entry.value;
                        return GestureDetector(
                          onTap: () => _switchExercise(entry.value),
                          child: AnimatedContainer(
                            duration: const Duration(milliseconds: 200),
                            margin: const EdgeInsets.only(right: 8),
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 10),
                            decoration: BoxDecoration(
                              color: isSelected
                                  ? const Color(0xFFB9FF2B)
                                  : Colors.white12,
                              borderRadius: BorderRadius.circular(22),
                              border: Border.all(
                                color: isSelected
                                    ? const Color(0xFFB9FF2B)
                                    : Colors.transparent,
                              ),
                            ),
                            child: Text(
                              entry.key,
                              style: TextStyle(
                                color: isSelected
                                    ? Colors.black
                                    : Colors.white70,
                                fontWeight: isSelected
                                    ? FontWeight.w700
                                    : FontWeight.w400,
                                fontSize: 13,
                              ),
                            ),
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}