import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import '../services/quickpose_service.dart';
import '../services/workout_session_service.dart';
import '../services/audio_feedback_service.dart';
import '../widgets/exercise_preview_dialog.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../features/profile/profile_screen.dart';


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


// ─────────────────────────────────────────────────────────────────────────────
// CUSTOM CACHE MANAGER
// Limits disk cache to 20 files, 7-day expiry.
// Singleton so only one instance manages all exercise image caching.
// ─────────────────────────────────────────────────────────────────────────────
class ExerciseCacheManager extends CacheManager with ImageCacheManager {
  static const key = 'exerciseImageCache';

  static final ExerciseCacheManager _instance = ExerciseCacheManager._();
  factory ExerciseCacheManager() => _instance;

  ExerciseCacheManager._()
      : super(Config(
          key,
          stalePeriod: const Duration(days: 7),
          maxNrOfCacheObjects: 20,
          repo: JsonCacheInfoRepository(databaseName: key),
          fileService: HttpFileService(),
        ));
}

class WorkoutTrackerScreen extends StatefulWidget {
  const WorkoutTrackerScreen({Key? key}) : super(key: key);

  @override
  State<WorkoutTrackerScreen> createState() => _WorkoutTrackerScreenState();
}

class _WorkoutTrackerScreenState extends State<WorkoutTrackerScreen>
    with WidgetsBindingObserver {
  final QuickPoseService _quickPoseService = QuickPoseService();
  final WorkoutSessionService _sessionService = WorkoutSessionService();
  final AudioFeedbackService _audioService = AudioFeedbackService();

  bool _hasPermission = false;
  bool _isRunning = false;
  int _repCount = 0;
  String _feedback = '';
  String _status = 'idle';
  String _selectedExercise = 'squat';

  // Spinner shown while session is saving to Firestore
  bool _savingSession = false;

  // Timer mode for exercises like plank
  bool _isTimerMode = false;

  static const _timerExercises = {'plank'};
  bool _isTimerExercise(String exercise) => _timerExercises.contains(exercise);

  // FIX 1: Images are stored as static const — defined once, never rebuilt.
  // resolution (w=400) reduces memory per image significantly.
  static const List<Map<String, String>> _exerciseVisuals = [
    {
      'name': 'Squat',
      'key': 'squat',
      'image': 'https://images.pexels.com/photos/4384679/pexels-photo-4384679.jpeg?auto=compress&cs=tinysrgb&w=1000&q=80'
    },
    {
      'name': 'Push Up',
      'key': 'pushup',
      'image': 'https://images.pexels.com/photos/4853921/pexels-photo-4853921.jpeg?auto=compress&cs=tinysrgb&w=1000&q=80'
    },
    {
      'name': 'Bicep Curl',
      'key': 'bicep_curl',
      'image': 'https://images.unsplash.com/photo-1581009146145-b5ef050c2e1e?w=1000&q=80&fit=crop'
    },
    {
      'name': 'Jumping Jack',
      'key': 'jumping_jack',
      'image': 'https://images.pexels.com/photos/4971058/pexels-photo-4971058.jpeg?auto=compress&cs=tinysrgb&w=1000&q=80'
    },
    {
      'name': 'Left Lunge',
      'key': 'lunge_left',
      'image': 'https://images.unsplash.com/photo-1613685044678-0a9ae422cf5a?auto=format&fit=crop&w=1000&q=80'
    },
    {
      'name': 'Right Lunge',
      'key': 'lunge_right',
      'image': 'https://images.pexels.com/photos/4971063/pexels-photo-4971063.jpeg?auto=compress&cs=tinysrgb&w=1000&q=80'
    },
    {
      'name': 'Sit Up',
      'key': 'sit_up',
      'image': 'https://images.unsplash.com/photo-1571019613454-1cb2f99b2d8b?auto=format&fit=crop&w=1000&q=80'
    },
    {
      'name': 'Plank',
      'key': 'plank',
      'image': 'https://images.unsplash.com/photo-1727712763476-f4e4e183ca4e?auto=format&fit=crop&w=1000&q=80'
    },
    {
      'name': 'Glute Bridge',
      'key': 'glute_bridge',
      'image': 'https://images.pexels.com/photos/4534643/pexels-photo-4534643.jpeg?auto=compress&cs=tinysrgb&w=1000&q=80'
    },
  ];

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
    return '${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
  }

  void _listenToResults() {
    _quickPoseService.resultsStream.listen((data) {
      if (!mounted) return;

      final newRepCount = (data['repCount'] as int?) ?? _repCount;
      final newFeedback = (data['feedback'] as String?) ?? '';
      final newStatus = (data['status'] as String?) ?? 'loading';
      final newIsTimer = (data['isTimer'] as bool?) ?? false;

      // Trigger audio for rep count if it changed
      if (newRepCount != _repCount) {
        _audioService.announceRepCount(newRepCount);
      }
      // Trigger audio for feedback if it changed and is not empty
      if (newFeedback.isNotEmpty && newFeedback != _feedback) {
        _audioService.speak(newFeedback);
      }

      setState(() {
        _repCount = newRepCount;
        _feedback = newFeedback;
        _status = newStatus;
        _isTimerMode = newIsTimer;
      });
    }, onError: (e) => debugPrint('QuickPose error: $e'));
  }

  // ── Listen for valid session summaries from Kotlin ───────────────────────
  void _listenToSessions() {
    _quickPoseService.sessionStream.listen((data) async {
      if (!mounted) return;

        final exercise      = data['exercise']      as String;
        final reps          = data['reps']          as int;
        final durationMs    = data['durationMs']    as int;
        final feedbackMap   = Map<String, int>.from(data['feedbackMap'] as Map);
        // avgJointAngle is null when landmarks weren't visible — handled gracefully
        final avgJointAngle = data['avgJointAngle'] as double?;

      setState(() => _savingSession = true);

        // Save to Firestore and generate debrief
        final session = await _sessionService.saveSession(
          exercise:      exercise,
          reps:          reps,
          durationMs:    durationMs,
          feedbackMap:   feedbackMap,
          avgJointAngle: avgJointAngle,
        );

      if (!mounted) return;
      setState(() => _savingSession = false);

      if (session != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Row(children: [
            const Icon(Icons.check_circle, color: Color(0xFFC5F135), size: 18),
            const SizedBox(width: 10),
            Expanded(child: Text(
              'Session saved — ${session.reps} ${session.exerciseDisplayName} reps',
              style: const TextStyle(color: Colors.white),
            )),
          ]),
          backgroundColor: const Color(0xFF1A1A2E),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          duration: const Duration(seconds: 3),
        ));
      }
    }, onError: (e) => debugPrint('Session stream error: $e'));
  }

  Future<void> _startWorkout() async {
    if (!_hasPermission) return;
    // Show exercise preview video before launching camera.
    // Waits until the dialog is dismissed — either by video ending or user tapping X.
    await showExercisePreview(context, _selectedExercise);
    if (!mounted) return;

    setState(() {
      _isRunning = true;
      _repCount = 0;
      _feedback = '';
      _status = 'loading';
      _isTimerMode = _isTimerExercise(_selectedExercise);
    });
    await _quickPoseService.startCamera(_selectedExercise);
  }

  Future<void> _switchExercise(String exerciseKey) async {
    setState(() {
      _selectedExercise = exerciseKey;
      _repCount = 0;
      _feedback = '';
      _status = 'loading';
      _isTimerMode = _isTimerExercise(exerciseKey);
    });
    if (_isRunning) await _quickPoseService.switchExercise(exerciseKey);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Header ────────────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Row(children: [
                const Text('Pose Tracker',
                    style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.w800)),
                const Spacer(),
                if (_savingSession)
                  const Padding(
                    padding: EdgeInsets.only(right: 16),
                    child: SizedBox(width: 16, height: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Color(0xFFC5F135))),
                  ),
                if (_status == 'success')
                  Container(
                    margin: const EdgeInsets.only(right: 16),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFC5F135).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                          color: const Color(0xFFC5F135).withOpacity(0.5)),
                    ),
                    child: const Text('LIVE',
                        style: TextStyle(
                            color: Color(0xFFC5F135),
                            fontSize: 11,
                            fontWeight: FontWeight.w800,
                            letterSpacing: 1)),
                  ),

                // Profile avatar uses initials only — no network image.
                // Network images in headers re-fetch on every rebuild and
                // cause memory spikes. The initials approach is crash-proof.
                GestureDetector(
                  onTap: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const ProfileScreen())),
                  child: Container(
                    width: 38, height: 38,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFF1A1A2E),
                      border: Border.all(
                          color: const Color(0xFFC5F135), width: 2),
                    ),
                    child: const Center(
                      child: Icon(Icons.person,
                          color: Color(0xFFC5F135), size: 20),
                    ),
                  ),
                ),
              ]),
            ),

            const SizedBox(height: 32),

            // ── Rep / Timer Counter ───────────────────────────────────────
            Center(
              child: Column(children: [
                Text(
                  _isTimerMode ? _formatTime(_repCount) // Shows MM:SS for timer
                  : '$_repCount', // Shows number for reps
                  style: const TextStyle(
                      color: Color(0xFFC5F135),
                      fontSize: 110,
                      fontWeight: FontWeight.w900,
                      letterSpacing: -2,
                      height: 1),
                ),
                Text(
                  _isTimerMode ? 'elapsed' : 'reps completed',
                  style: const TextStyle(
                      color: Color(0xFF6B6B8A),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      letterSpacing: 1.2),
                ),
              ]),
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
                    color: const Color(0xFFFF7B6B).withOpacity(0.15),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: const Color(0xFFFF7B6B).withOpacity(0.5)),
                  ),
                  child: Text(_feedback,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 14,
                          fontWeight: FontWeight.w600)),
                ),
              ),

            const Spacer(),

            // ── How To + Audio Buttons ───────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
              child: Row(children: [
                // How To button
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        showExercisePreview(context, _selectedExercise),
                    child: Container(
                      height: 52,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(color: Colors.white10),
                      ),
                      child: const Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.play_circle_fill,
                              color: Color(0xFF9B8FFF), size: 20),
                          SizedBox(width: 8),
                          Text('How To',
                              style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.w700)),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: GestureDetector(
                    onTap: () =>
                        setState(() => _audioService.setEnabled(!_audioService.isEnabled)),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      height: 52,
                      decoration: BoxDecoration(
                        color: _audioService.isEnabled
                            ? const Color(0xFFC5F135).withOpacity(0.15)
                            : const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: _audioService.isEnabled
                              ? const Color(0xFFC5F135)
                              : Colors.white10,
                          width: 1.5,
                        ),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            _audioService.isEnabled
                                ? Icons.volume_up
                                : Icons.volume_off,
                            color: _audioService.isEnabled
                                ? const Color(0xFFC5F135)
                                : Colors.white54,
                            size: 20,
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _audioService.isEnabled ? 'Audio ON' : 'Audio OFF',
                            style: TextStyle(
                              color: _audioService.isEnabled
                                  ? const Color(0xFFC5F135)
                                  : Colors.white54,
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ]),
            ),

            // ── Exercise Selector ─────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.only(left: 20, bottom: 12),
              child: Text('AVAILABLE WORKOUTS',
                  style: TextStyle(
                      color: Colors.white.withOpacity(0.4),
                      fontSize: 11,
                      letterSpacing: 1.5,
                      fontWeight: FontWeight.w700)),
            ),

            SizedBox(
              height: 140,
              // FIX 3: addRepaintBoundaries + addAutomaticKeepAlives = false
              // prevents Flutter from keeping all 9 image widgets alive in memory.
              // Only visible items are rendered; others are disposed.
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 20),
                itemCount: _exerciseVisuals.length,
                addAutomaticKeepAlives: false,  // ← don't keep offscreen items alive
                addRepaintBoundaries: true,
                itemBuilder: (context, index) {
                  final exercise  = _exerciseVisuals[index];
                  final isSelected = _selectedExercise == exercise['key'];

                  return GestureDetector(
                    onTap: () => _switchExercise(exercise['key']!),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 12),
                      width: 120,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(
                        color: const Color(0xFF1A1A2E),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: isSelected
                              ? const Color(0xFFC5F135)
                              : Colors.transparent,
                          width: 2.5,
                        ),
                        boxShadow: isSelected
                            ? [BoxShadow(
                                color: const Color(0xFFC5F135).withOpacity(0.3),
                                blurRadius: 12)]
                            : [],
                      ),
                      child: Stack(
                        fit: StackFit.expand,
                        children: [

                          // FIX 4: Use ExerciseCacheManager so images are
                          // written to disk once and reused — no re-download
                          // on every rebuild. memCacheWidth/Height cap the
                          // in-memory decoded bitmap to 120×140 px max.
                          CachedNetworkImage(
                            imageUrl: exercise['image']!,
                            cacheManager: ExerciseCacheManager(),
                            fit: BoxFit.cover,
                            memCacheWidth: 360,   // ← exact widget width
                            memCacheHeight: 420,  // ← exact widget height
                            fadeInDuration: const Duration(milliseconds: 200),
                            placeholder: (context, url) => Container(
                              color: const Color(0xFF2A2A2A),
                              child: const Center(
                                child: SizedBox(
                                  width: 16, height: 16,
                                  child: CircularProgressIndicator(
                                      color: Color(0xFF6B6B8A),
                                      strokeWidth: 1.5),
                                ),
                              ),
                            ),
                            errorWidget: (context, url, error) => Container(
                              color: const Color(0xFF1A1A2A),
                              child: const Icon(Icons.fitness_center,
                                  color: Color(0xFF6B6B8A), size: 32),
                            ),
                          ),

                          // Gradient overlay
                          Container(
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  Colors.black.withOpacity(0.8),
                                  Colors.transparent,
                                ],
                                begin: Alignment.bottomCenter,
                                end: Alignment.topCenter,
                              ),
                            ),
                          ),

                          // Exercise name
                          Positioned(
                            bottom: 10, left: 10, right: 10,
                            child: Text(exercise['name']!,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.w800,
                                    fontSize: 12,
                                    height: 1.1)),
                          ),

                          // Selected checkmark
                          if (isSelected)
                            const Positioned(
                              top: 8, right: 8,
                              child: Icon(Icons.check_circle,
                                  color: Color(0xFFC5F135), size: 18),
                            ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            const SizedBox(height: 20),

            // ── Start Button ──────────────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 32),
              child: SizedBox(
                height: 60,
                child: ElevatedButton(
                  onPressed: _hasPermission
                      ? (_isRunning ? null : _startWorkout)
                      : null,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFC5F135),
                    disabledBackgroundColor: const Color(0xFF1A1A2E),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(20)),
                    elevation: 0,
                  ),
                  child: _isRunning
                      ? const Text(
                          'Running in Camera View — Press Back to Return',
                          style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                              fontWeight: FontWeight.w600),
                          textAlign: TextAlign.center,
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.camera_alt,
                                color: _hasPermission
                                    ? const Color(0xFF2D4A00)
                                    : Colors.white24,
                                size: 22),
                            const SizedBox(width: 10),
                            Text(
                              _hasPermission
                                  ? 'Start Workout'
                                  : 'Camera Permission Required',
                              style: TextStyle(
                                color: _hasPermission
                                    ? const Color(0xFF2D4A00)
                                    : Colors.white54,
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
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