import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

import '../services/pose_service.dart'; // Our angle/rep/form logic
import '../widgets/pose_painter.dart';  // Skeleton overlay painter

/// The main workout tracking screen.
///
/// Responsibilities:
///   1. Initialise and manage the device camera
///   2. Stream camera frames into ML Kit via [PoseService]
///   3. Render the live preview with a skeleton overlay ([PosePainter])
///   4. Display real-time rep count and form feedback to the user
///   5. Let the user switch between exercises via a top pill-selector
class WorkoutTrackerScreen extends StatefulWidget {
  const WorkoutTrackerScreen({super.key});

  @override
  State<WorkoutTrackerScreen> createState() => _WorkoutTrackerScreenState();
}

class _WorkoutTrackerScreenState extends State<WorkoutTrackerScreen> {

  // Camera state 
  CameraController? _cameraController;
  List<CameraDescription> _cameras = []; // All available cameras on the device
  bool _isCameraInitialized = false;     // Guards the preview widget build

  /// Index of the active camera.
  /// 0 = rear camera, 1 = front (selfie) camera.
  /// Default to front camera so the user can see themselves working out.
  int _selectedCameraIndex = 1;

  // Pose detection state 
  final PoseService _poseService = PoseService();

  /// The latest set of poses returned by ML Kit for the current frame.
  List<Pose> _poses = [];

  /// The pixel dimensions of the camera image last processed by ML Kit.
  /// Needed by PosePainter to scale landmarks to screen coordinates.
  Size _imageSize = Size.zero;

  /// Prevents queueing multiple ML Kit calls simultaneously.
  /// If the detector is still processing the previous frame we skip the
  /// current frame rather than building up a backlog that causes lag.
  bool _isDetecting = false;

  // ── Exercise / feedback state 
  ExerciseType _selectedExercise = ExerciseType.squat; // Active exercise
  FormFeedback? _lastFeedback;  // Most recent coaching message
  int _repCount = 0;            // Displayed rep count

  // Convenience list for building the exercise selector UI
  final List<ExerciseType> _exercises = ExerciseType.values;

  // Lifecycle 

  @override
  void initState() {
    super.initState();
    _initCamera(); // Start camera as soon as the screen is created
  }

  /// Discovers available cameras, picks the desired one, initialises the
  /// controller, then starts the image stream for ML Kit.
  Future<void> _initCamera() async {
    _cameras = await availableCameras();
    if (_cameras.isEmpty) return; // Safety: no camera available

    // Clamp index so it never exceeds the number of cameras on this device
    final camera = _cameras[_selectedCameraIndex.clamp(0, _cameras.length - 1)];

    _cameraController = CameraController(
      camera,
      ResolutionPreset.medium, // 720p — balances quality vs ML Kit speed
      enableAudio: false,       // We don't need audio
      // NV21 is the format ML Kit expects on Android
      imageFormatGroup: ImageFormatGroup.nv21,
    );

    await _cameraController!.initialize();
    if (!mounted) return; // Widget may have been disposed while we awaited

    setState(() => _isCameraInitialized = true);

    // Begin streaming frames — _processCameraImage is called for every frame
    _cameraController!.startImageStream(_processCameraImage);
  }

  /// Called by the camera plugin for every frame.
  ///
  /// Flow:
  ///   1. Skip if ML Kit is still busy with the previous frame
  ///   2. Wrap the raw frame bytes in an [InputImage] that ML Kit understands
  ///   3. Run pose detection via [PoseService]
  ///   4. Update UI state with the new poses, feedback, and rep count
  void _processCameraImage(CameraImage image) async {
    // Skip this frame if the detector hasn't finished the previous one
    if (_isDetecting) return;
    _isDetecting = true;

    try {
      final camera = _cameras[_selectedCameraIndex.clamp(0, _cameras.length - 1)];

      // Convert the raw sensor rotation value to the ML Kit enum
      final rotation =
          InputImageRotationValue.fromRawValue(camera.sensorOrientation)
          ?? InputImageRotation.rotation0deg;

      // Build the InputImage from the raw NV21 bytes in the first camera plane
      final inputImage = InputImage.fromBytes(
        bytes: image.planes[0].bytes,
        metadata: InputImageMetadata(
          size: Size(image.width.toDouble(), image.height.toDouble()),
          rotation: rotation,
          format: InputImageFormat.nv21,
          bytesPerRow: image.planes[0].bytesPerRow,
        ),
      );

      // Run ML Kit pose detection
      final poses = await _poseService.detectPose(inputImage);

      // Update the UI on the main thread
      if (mounted) {
        setState(() {
          _poses     = poses;
          _imageSize = Size(image.width.toDouble(), image.height.toDouble());

          if (poses.isNotEmpty) {
            // Assess form and update rep count for the selected exercise
            _lastFeedback = _poseService.assessForm(_selectedExercise, poses.first);
            _repCount     = _poseService.getRepCount(_selectedExercise);
          }
        });
      }
    } finally {
      // Always release the lock so the next frame can be processed
      _isDetecting = false;
    }
  }

  // Exercise switching 

  /// Switches the active exercise and clears stale feedback.
  /// Rep counts for the previously selected exercise are preserved
  /// so the user can switch back without losing their count.
  void _switchExercise(ExerciseType type) {
    setState(() {
      _selectedExercise = type;
      _lastFeedback     = null; // Clear old feedback until next detection
      _repCount         = _poseService.getRepCount(type); // Restore saved count
    });
  }

  /// Resets the rep counter for the current exercise to zero.
  void _resetReps() {
    _poseService.resetReps(_selectedExercise);
    setState(() => _repCount = 0);
  }

  /// Returns a display-friendly name for each exercise type.
  String _exerciseName(ExerciseType type) {
    switch (type) {
      case ExerciseType.squat:     return 'Squat';
      case ExerciseType.pushup:    return 'Push-up';
      case ExerciseType.bicepCurl: return 'Bicep Curl';
    }
  }

  // Cleanup 

  @override
  void dispose() {
    // Stop streaming frames before disposing the controller to avoid
    // callbacks arriving after the widget is gone
    _cameraController?.stopImageStream();
    _cameraController?.dispose();

    // Release the native ML Kit detector resources
    _poseService.dispose();

    super.dispose();
  }

  // Build 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0D0D0D),
        title: const Text(
          'Workout Tracker',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Column(
        children: [

          // Exercise selector (horizontal pill row) 
          // Lets the user pick which exercise to track without leaving
          // the camera screen
          SizedBox(
            height: 44,
            child: ListView(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              children: _exercises.map((ex) {
                final isSelected = ex == _selectedExercise;
                return GestureDetector(
                  onTap: () => _switchExercise(ex),
                  child: Container(
                    margin: const EdgeInsets.only(right: 8),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 16, vertical: 4),
                    decoration: BoxDecoration(
                      // Highlight the active exercise in green
                      color: isSelected
                          ? const Color(0xFFB9FF2B)
                          : const Color(0xFF1A1A1A),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      _exerciseName(ex),
                      style: TextStyle(
                        color: isSelected ? Colors.black : Colors.white,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                );
              }).toList(),
            ),
          ),

          //  Camera preview + skeleton overlay 
          Expanded(
            child: _isCameraInitialized
                ? LayoutBuilder(
                    builder: (context, constraints) {
                      return Stack(
                        fit: StackFit.expand,
                        children: [
                          // Layer 1: live camera feed
                          CameraPreview(_cameraController!),

                          // Layer 2: skeleton overlay
                          // Only painted when we have poses and a valid image size
                          if (_poses.isNotEmpty && _imageSize != Size.zero)
                            CustomPaint(
                              painter: PosePainter(
                                _poses,
                                _imageSize,
                                // Tell the painter whether to mirror x coords
                                isFrontCamera: _selectedCameraIndex == 1,
                              ),
                            ),
                        ],
                      );
                    },
                  )
                : const Center(
                    // Shown while the camera controller is initialising
                    child: CircularProgressIndicator(
                        color: Color(0xFFB9FF2B)),
                  ),
          ),

          // Rep counter + form feedback panel 
          // Docked at the bottom of the screen so it's always visible
          Container(
            color: const Color(0xFF1A1A1A),
            padding:
                const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
            child: Row(
              children: [

                // Left side: large rep number with reset button
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'REPS',
                      style: TextStyle(color: Colors.grey, fontSize: 12),
                    ),
                    Text(
                      '$_repCount',
                      style: const TextStyle(
                        color: Color(0xFFB9FF2B),
                        fontSize: 48,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    GestureDetector(
                      onTap: _resetReps,
                      child: const Text(
                        'Reset',
                        style: TextStyle(
                            color: Color(0xFFFF5E00), fontSize: 12),
                      ),
                    ),
                  ],
                ),

                const SizedBox(width: 20),

                // Right side: coaching feedback card
                // Card border and background change colour based on form quality
                Expanded(
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      // Green tint = good form, orange tint = needs correction
                      color: _lastFeedback == null
                          ? Colors.transparent
                          : _lastFeedback!.isGoodForm
                              ? const Color(0xFFB9FF2B).withOpacity(0.1)
                              : const Color(0xFFFF5E00).withOpacity(0.15),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _lastFeedback == null
                            ? Colors.white10
                            : _lastFeedback!.isGoodForm
                                ? const Color(0xFFB9FF2B)
                                : const Color(0xFFFF5E00),
                      ),
                    ),
                    child: Text(
                      // Default message before a person is detected
                      _lastFeedback?.message ??
                          'Get into position to start...',
                      style: const TextStyle(
                          color: Colors.white, fontSize: 14),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),

        ],
      ),
    );
  }
}