import 'dart:math'; // For atan2 and pi used in angle calculation
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// Represents the three basic exercises this tracker currently supports for now(Squats, pushups and bicep curls)
/// Adding a new exercise means adding a value here and a corresponding
/// assess method below.
enum ExerciseType { squat, pushup, bicepCurl }

/// Tracks the rep count for a single exercise.
///
/// A rep is counted using a simple state machine:
///   - "down" state: the joint angle has gone below [downThreshold]
///   - "up" state:   the joint angle has returned above [upThreshold]
/// One full down → up transition = one rep.
///
/// Using two separate thresholds (hysteresis) prevents jitter near the
/// boundary from causing phantom rep counts.
class RepCounter {
  int count = 0;        // Total completed reps
  bool _isDown = false; // Whether currently in the "down" phase

  /// Call this every frame with the current joint angle for this exercise.
  ///
  /// [angle] – the measured joint angle in degrees this frame
  /// [downThreshold] – angle must drop BELOW this to enter "down" state
  /// [upThreshold] – angle must rise ABOVE this to complete a rep
  void update(double angle, double downThreshold, double upThreshold) {
    if (angle < downThreshold && !_isDown) {
      // Joint has bent past the down threshold start of the rep
      _isDown = true;
    } else if (angle > upThreshold && _isDown) {
      // Joint has straightened back past the up threshold rep complete
      _isDown = false;
      count++;
    }
  }

  /// Resets the counter back to zero (e.g. when user taps the Reset button).
  void reset() {
    count = 0;
    _isDown = false;
  }
}

/// A simple data class returned by each form-assessment method.
///
/// [isGoodForm] true = green feedback card, false = red warning card
/// [message] human-readable coaching cue shown on screen
class FormFeedback {
  final bool isGoodForm;
  final String message;
  FormFeedback(this.isGoodForm, this.message);
}

/// Central service that wraps ML Kit's PoseDetector and adds:
///   1. Angle calculation between three landmarks
///   2. Rule-based form assessment for each exercise
///   3. Per-exercise rep counting
///
/// Usage:
///   final service = PoseService();
///   final poses  = await service.detectPose(inputImage);
///   final feedback = service.assessForm(ExerciseType.squat, poses.first);
///   final reps     = service.getRepCount(ExerciseType.squat);
///   service.dispose(); // call in State.dispose()
class PoseService {

  /// ML Kit pose detector running in STREAM mode.
  /// Stream mode is optimised for continuous camera frames it trades
  /// a little accuracy for much lower per-frame latency compared to
  /// SINGLE_IMAGE mode.
  final PoseDetector _poseDetector = PoseDetector(
    options: PoseDetectorOptions(
      mode: PoseDetectionMode.stream,
    ),
  );

  /// One RepCounter instance per exercise so counts are independent.
  final Map<ExerciseType, RepCounter> _repCounters = {
    ExerciseType.squat: RepCounter(),
    ExerciseType.pushup: RepCounter(),
    ExerciseType.bicepCurl: RepCounter(),
  };

  //
  // POSE DETECTION
  //

  /// Sends a camera frame to ML Kit and returns the detected poses.
  /// In most real-world scenarios only one pose is returned (single person).
  /// Returns an empty list if no person is detected in the frame.
  Future<List<Pose>> detectPose(InputImage inputImage) async {
    return await _poseDetector.processImage(inputImage);
  }

  //
  // ANGLE CALCULATION
  //

  /// Calculates the interior angle (in degrees) at landmark [b],
  /// formed by the line segments b→a and b→c.
  ///
  /// Uses the 2-argument arctangent (atan2) to get the signed angle
  /// for each arm, then takes the difference and normalises to [0, 180].
  ///
  ///        a
  ///       /
  ///      b  ← angle measured here
  ///       \
  ///        c
  ///
  /// Example: pass leftHip, leftKnee, leftAnkle to get the knee bend angle.
  double calculateAngle(
    PoseLandmark a,
    PoseLandmark b, // vertex angle is measured at this point
    PoseLandmark c,
  ) {
    // atan2 returns angle of the vector from b to the given point
    double radians =
        atan2(c.y - b.y, c.x - b.x) - atan2(a.y - b.y, a.x - b.x);

    double angle = radians * 180 / pi; // Convert to degrees

    // Normalise into the range [0, 360] then fold to [0, 180]
    if (angle < 0) angle += 360;
    if (angle > 180) angle = 360 - angle;

    return angle;
  }

  // 
  // FORM ASSESSMENT == SQUAT
  // 

  /// Assesses squat form using two angles:
  ///  Knee angle  (hip -> knee -> ankle)  = detects depth
  ///  Back angle  (shoulder -> hip ->knee) = detects forward lean
  ///
  /// Also drives the squat rep counter on every call.
  FormFeedback assessSquat(Pose pose) {
    final landmarks = pose.landmarks;

    // Retrieve the four landmarks we need
    final leftHip      = landmarks[PoseLandmarkType.leftHip];
    final leftKnee     = landmarks[PoseLandmarkType.leftKnee];
    final leftAnkle    = landmarks[PoseLandmarkType.leftAnkle];
    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];

    // If any landmark is missing the person is not fully in frame
    if (leftHip == null || leftKnee == null ||
        leftAnkle == null || leftShoulder == null) {
      return FormFeedback(false, "Move your full body into frame");
    }

    // Knee angle: large (=170 degrees) when standing, small (=90°) when squatting
    final kneeAngle = calculateAngle(leftHip, leftKnee, leftAnkle);

    // Back angle: how upright the torso is relative to the thigh
    final backAngle = calculateAngle(leftShoulder, leftHip, leftKnee);

    // Update rep counter: a squat "down" is knee angle < 100 degrees, "up" is > 160 degrees
    _repCounters[ExerciseType.squat]!.update(kneeAngle, 100, 160);

    // Rule-based coaching cues
    if (kneeAngle > 160) {
      return FormFeedback(true, "Standing - go lower!");
    }
    if (kneeAngle < 60) {
      return FormFeedback(false, "Too deep - protect your knees");
    }
    if (backAngle < 50) {
      return FormFeedback(false, "Keep your back more upright");
    }

    return FormFeedback(
      true,
      "Good squat form! Knee angle: ${kneeAngle.toStringAsFixed(0)}°",
    );
  }

  // 
  // FORM ASSESSMENT -  PUSH-UP
  // 

  /// Assesses push-up form using two angles:
  ///   Elbow angle (shoulder -> elbow -> wrist) -> detects rep depth                                       
  ///   Body angle  (shoulder -> hip ankle) -> detects plank alignment
  ///
  /// Also drives the push-up rep counter on every call.
  FormFeedback assessPushup(Pose pose) {
    final landmarks = pose.landmarks;

    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow = landmarks[PoseLandmarkType.leftElbow];
    final leftWrist = landmarks[PoseLandmarkType.leftWrist];
    final leftHip = landmarks[PoseLandmarkType.leftHip];
    final leftAnkle = landmarks[PoseLandmarkType.leftAnkle];

    if (leftShoulder == null || leftElbow == null || leftWrist == null ||
        leftHip == null || leftAnkle == null) {
      return FormFeedback(false, "Move your full body into frame");
    }

    // Elbow angle: = 160 degrees at top of push-up, = 90 degrees at bottom
    final elbowAngle = calculateAngle(leftShoulder, leftElbow, leftWrist);

    // Body angle: should stay close to 180 degrees (straight plank line)
    final bodyAngle = calculateAngle(leftShoulder, leftHip, leftAnkle);

    // Update rep counter: "down" when elbow < 90 degrees, "up" when elbow > 160 degrees
    _repCounters[ExerciseType.pushup]!.update(elbowAngle, 90, 160);

    // Coaching cues
    if (bodyAngle < 160) {
      return FormFeedback(
          false, "Keep your body in a straight line - hips too high/low");
    }
    if (elbowAngle < 45) {
      return FormFeedback(false, "Don't go too low - stop at ~90°");
    }

    return FormFeedback(
      true,
      "Good push-up! Elbow angle: ${elbowAngle.toStringAsFixed(0)}°",
    );
  }

  // 
  // FORM ASSESSMENT -> BICEP CURL
  // 

  /// Assesses bicep curl form using one angle:
  ///  Elbow angle (shoulder -> elbow -> wrist) = detects curl range
  ///
  /// Also drives the bicep curl rep counter on every call.
  FormFeedback assessBicepCurl(Pose pose) {
    final landmarks = pose.landmarks;

    final leftShoulder = landmarks[PoseLandmarkType.leftShoulder];
    final leftElbow    = landmarks[PoseLandmarkType.leftElbow];
    final leftWrist    = landmarks[PoseLandmarkType.leftWrist];

    if (leftShoulder == null || leftElbow == null || leftWrist == null) {
      return FormFeedback(false, "Move your upper body into frame");
    }

    // Elbow angle: ≈150° at full extension (arm down), ≈40° at full curl
    final elbowAngle = calculateAngle(leftShoulder, leftElbow, leftWrist);

    // Update rep counter: "down" when angle < 60°, "up" when angle > 150°
    _repCounters[ExerciseType.bicepCurl]!.update(elbowAngle, 60, 150);

    // Coaching cues
    if (elbowAngle > 150) {
      return FormFeedback(true, "Down position - curl up!");
    }
    if (elbowAngle < 40) {
      return FormFeedback(false, "Don't over-curl, keep control");
    }

    return FormFeedback(
      true,
      "Good curl! Angle: ${elbowAngle.toStringAsFixed(0)}°",
    );
  }

  //
  // PUBLIC API
  // 

  /// Routes to the correct assessment method based on [type].
  /// This is the single entry point called by the UI layer every frame.
  FormFeedback assessForm(ExerciseType type, Pose pose) {
    switch (type) {
      case ExerciseType.squat:
        return assessSquat(pose);
      case ExerciseType.pushup:
        return assessPushup(pose);
      case ExerciseType.bicepCurl:
        return assessBicepCurl(pose);
    }
  }

  /// Returns the current rep count for the given exercise.
  int getRepCount(ExerciseType type) => _repCounters[type]!.count;

  /// Resets the rep count for the given exercise back to zero.
  void resetReps(ExerciseType type) => _repCounters[type]!.reset();

  /// Releases the ML Kit detector. Must be called when the screen is disposed
  /// to free native resources and avoid memory leaks.
  void dispose() => _poseDetector.close();
}