import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/quickpose_service.dart';
import '../services/workout_session_service.dart';
import '../services/audio_feedback_service.dart';
import '../widgets/exercise_preview_dialog.dart';

// This screen no longer embeds a native camera view.
// Instead it launches a full-screen native Android Activity (QuickPoseActivity)
// which owns the camera entirely. Results stream back via EventChannel.
// Flutter only renders the overlay UI on top via a transparent window — but
// since QuickPoseActivity is a separate Activity, the overlay is shown here
// as a results/stats screen that sits in front in the back stack.
//
// UX flow:
// 1. User taps the Pose tab
// 2. This screen requests camera permission
// 3. On grant, launches QuickPoseActivity full screen
// 4. Results stream back and are shown here when user returns
// 5. User presses back from QuickPoseActivity to return to Flutter

class WorkoutTrackerScreen extends StatefulWidget {
  const WorkoutTrackerScreen({Key? key}) : super(key: key);

  @override
  State<WorkoutTrackerScreen> createState() => _WorkoutTrackerScreenState();
}

class _WorkoutTrackerScreenState extends State<WorkoutTrackerScreen>
    with WidgetsBindingObserver {

  final QuickPoseService      _quickPoseService = QuickPoseService();
  final WorkoutSessionService _sessionService   = WorkoutSessionService();
  final AudioFeedbackService  _audioService     = AudioFeedbackService();

  bool   _hasPermission    = false;
  bool   _isRunning        = false;
  int    _repCount         = 0;
  String _feedback         = '';
  String _status           = 'idle';
  String _selectedExercise = 'squat';

  // Spinner shown while session is saving to Firestore
  bool _savingSession = false;

  // Timer mode for exercises like plank
  bool _isTimerMode = false;

  // Exercises that use a timer instead of a rep counter
  static const _timerExercises = {'plank'};
  bool _isTimerExercise(String exercise) => _timerExercises.contains(exercise);

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
    WidgetsBinding.instance.addObserver(this);
    _requestPermissionAndListen();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _quickPoseService.stopCamera();
    _audioService.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _isRunning) {
      setState(() => _isRunning = false);
    }
  }

  Future<void> _requestPermissionAndListen() async {
    final status = await Permission.camera.request();
    if (!mounted) return;
    if (status.isGranted) {
      setState(() => _hasPermission = true);
      _listenToResults();
      _listenToSessions();
    }
  }

  /// Formats elapsed seconds into MM:SS display format.
  /// Example: 75 seconds → "01:15"
  String _formatTime(int totalSeconds) {
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    return '${minutes.toString().padLeft(2, '0')}:'
        '${seconds.toString().padLeft(2, '0')}';
  }

  void _listenToResults() {
    _quickPoseService.resultsStream.listen((data) {
      if (!mounted) return;

      final newRepCount = (data['repCount'] as int?)    ?? _repCount;
      final newFeedback = (data['feedback'] as String?) ?? '';
      final newStatus   = (data['status']   as String?) ?? 'loading';
      final newIsTimer  = (data['isTimer']  as bool?)   ?? false;

      // Trigger audio for rep count if it changed
      if (newRepCount != _repCount) {
        _audioService.announceRepCount(newRepCount);
      }

      // Trigger audio for feedback if it changed and is not empty
      if (newFeedback.isNotEmpty && newFeedback != _feedback) {
        _audioService.speak(newFeedback);
      }

      setState(() {
        _repCount    = newRepCount;
        _feedback    = newFeedback;
        _status      = newStatus;
        _isTimerMode = newIsTimer;
      });
    }, onError: (e) => debugPrint('QuickPose error: $e'));
  }

  // ── Listen for valid session summaries from Kotlin ───────────────────────
  void _listenToSessions() {
    _quickPoseService.sessionStream.listen(
      (data) async {
        if (!mounted) return;

        final exercise    = data['exercise']   as String;
        final reps        = data['reps']       as int;
        final durationMs  = data['durationMs'] as int;
        final feedbackMap = Map<String, int>.from(data['feedbackMap'] as Map);

        setState(() => _savingSession = true);

        // Save to Firestore and generate debrief
        final session = await _sessionService.saveSession(
          exercise:    exercise,
          reps:        reps,
          durationMs:  durationMs,
          feedbackMap: feedbackMap,
        );

        if (!mounted) return;
        setState(() => _savingSession = false);

        if (session != null) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Row(
                children: [
                  const Icon(Icons.check_circle,
                      color: Color(0xFFB9FF2B), size: 18),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      'Session saved — ${session.reps} ${session.exerciseDisplayName} reps',
                      style: const TextStyle(color: Colors.white),
                    ),
                  ),
                ],
              ),
              backgroundColor: const Color(0xFF1A1A1A),
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              duration: const Duration(seconds: 3),
            ),
          );
        }
      },
      onError: (e) => debugPrint('Session stream error: $e'),
    );
  }

  Future<void> _startWorkout() async {
    if (!_hasPermission) return;

    // Show exercise preview video before launching camera.
    // Waits until the dialog is dismissed — either by video ending or user tapping X.
    await showExercisePreview(context, _selectedExercise);
    if (!mounted) return;

    setState(() {
      _isRunning   = true;
      _repCount    = 0;
      _feedback    = '';
      _status      = 'loading';
      _isTimerMode = _isTimerExercise(_selectedExercise);
    });
    await _quickPoseService.startCamera(_selectedExercise);
  }

  Future<void> _switchExercise(String exerciseKey) async {
    setState(() {
      _selectedExercise = exerciseKey;
      _repCount         = 0;
      _feedback         = '';
      _status           = 'loading';
      _isTimerMode      = _isTimerExercise(exerciseKey);
    });
    if (_isRunning) {
      await _quickPoseService.switchExercise(exerciseKey);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Header ───────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(
                children: [
                  const Text(
                    'Pose Tracker',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const Spacer(),

                  // Saving spinner — visible while session writes to Firestore
                  if (_savingSession)
                    const Padding(
                      padding: EdgeInsets.only(right: 10),
                      child: SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFB9FF2B)),
                      ),
                    ),

                  // How To — rewatch exercise video at any time
                  GestureDetector(
                    onTap: () =>
                        showExercisePreview(context, _selectedExercise),
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white12),
                      ),
                      child: const Row(
                        children: [
                          Icon(Icons.play_circle_outline,
                              color: Colors.white54, size: 16),
                          SizedBox(width: 6),
                          Text(
                            'How to',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),

                  // Audio toggle button
                  GestureDetector(
                    onTap: () {
                      setState(() {
                        _audioService.setEnabled(!_audioService.isEnabled);
                      });
                    },
                    child: Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: _audioService.isEnabled
                            ? const Color(0xFFB9FF2B).withOpacity(0.15)
                            : Colors.white.withOpacity(0.05),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: _audioService.isEnabled
                              ? const Color(0xFFB9FF2B).withOpacity(0.5)
                              : Colors.white12,
                        ),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            _audioService.isEnabled
                                ? Icons.volume_up
                                : Icons.volume_off,
                            color: _audioService.isEnabled
                                ? const Color(0xFFB9FF2B)
                                : Colors.white38,
                            size: 16,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            _audioService.isEnabled ? 'Audio ON' : 'Audio OFF',
                            style: TextStyle(
                              color: _audioService.isEnabled
                                  ? const Color(0xFFB9FF2B)
                                  : Colors.white38,
                              fontSize: 11,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),

                  // LIVE badge — shown when pose tracking is active
                  if (_status == 'success')
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: const Color(0xFFB9FF2B).withOpacity(0.15),
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                            color: const Color(0xFFB9FF2B).withOpacity(0.5)),
                      ),
                      child: const Text(
                        'LIVE',
                        style: TextStyle(
                          color: Color(0xFFB9FF2B),
                          fontSize: 11,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 1,
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 32),

            // ── Rep / Timer Counter ───────────────────────────────────────
            Center(
              child: Column(
                children: [
                  Text(
                    _isTimerMode
                        ? _formatTime(_repCount) // Shows MM:SS for timer
                        : '$_repCount',          // Shows number for reps
                    style: const TextStyle(
                      color: Color(0xFFB9FF2B),
                      fontSize: 100,
                      fontWeight: FontWeight.w900,
                      height: 1,
                    ),
                  ),
                  Text(
                    _isTimerMode ? 'elapsed' : 'reps',
                    style: const TextStyle(
                        color: Colors.white38, fontSize: 18),
                  ),
                ],
              ),
            ),

            const SizedBox(height: 24),

            // ── Feedback Banner ───────────────────────────────────────────
            if (_feedback.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Container(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5E00).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFFF5E00).withOpacity(0.5)),
                  ),
                  child: Text(
                    _feedback,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        fontWeight: FontWeight.w500),
                  ),
                ),
              ),

            const Spacer(),

            // ── Exercise Selector ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 12),
              child: Text(
                'SELECT EXERCISE',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.3),
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
                padding: const EdgeInsets.symmetric(horizontal: 20),
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
                            : const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(22),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFB9FF2B)
                              : Colors.white12,
                        ),
                      ),
                      child: Text(
                        entry.key,
                        style: TextStyle(
                          color: isSelected ? Colors.black : Colors.white70,
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

            const SizedBox(height: 20),

            // ── Start Button ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: SizedBox(
                height: 56,
                child: ElevatedButton(
                  onPressed: _hasPermission
                      ? (_isRunning ? null : _startWorkout)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF5E00),
                    disabledBackgroundColor: Colors.white12,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(14)),
                    elevation: 0,
                  ),
                  child: _isRunning
                      ? const Text(
                          'Running in Camera View — Press Back to Return',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 13,
                            fontWeight: FontWeight.w500,
                          ),
                          textAlign: TextAlign.center,
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            const Icon(Icons.camera_alt,
                                color: Colors.white, size: 20),
                            const SizedBox(width: 10),
                            Text(
                              _hasPermission
                                  ? 'Start Workout'
                                  : 'Camera Permission Required',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 16,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ],
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}