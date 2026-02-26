import 'package:flutter/material.dart';
import 'package:google_mlkit_pose_detection/google_mlkit_pose_detection.dart';

/// A [CustomPainter] that draws the detected pose skeleton on top of
/// the live camera preview.
///
/// Flutter's [CustomPaint] widget calls [paint] every frame after
/// pose detection completes, so the overlay stays in sync with the video.
///
/// Coordinate system note:
///   ML Kit returns landmark (x, y) in the coordinate space of the
///   *original camera image* (e.g. 640×480). The canvas is the size of
///   the widget on screen (e.g. 360×640). [_translate] converts between
///   the two using a simple scale factor, and mirrors the x-axis for the
///   front-facing camera so the skeleton doesn't appear flipped.
class PosePainter extends CustomPainter {
  /// The list of detected poses for this frame (usually just one person).
  final List<Pose> poses;

  /// The pixel dimensions of the camera frame that ML Kit processed.
  /// Used to calculate the scale factor when translating to screen coords.
  final Size imageSize;

  /// True when using the front (selfie) camera.
  /// The front camera image is mirrored, so we flip the x translation
  /// to match what the user sees in the preview.
  final bool isFrontCamera;

  PosePainter(this.poses, this.imageSize, {this.isFrontCamera = true});

  @override
  void paint(Canvas canvas, Size size) {
    // Green filled circles drawn at each detected joint
    final jointPaint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 8
      ..style = PaintingStyle.fill;

    // White semi-transparent lines connecting joints (the "bones")
    final bonePaint = Paint()
      ..color = Colors.white
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    // Define which landmark pairs to connect with a bone line.
    // Each inner list is [startLandmark, endLandmark].
    // We cover the full body: shoulders, arms, torso, and legs.
    final connections = [
      // Shoulders
      [PoseLandmarkType.leftShoulder,  PoseLandmarkType.rightShoulder],
      // Left arm
      [PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftElbow],
      [PoseLandmarkType.leftElbow,     PoseLandmarkType.leftWrist],
      // Right arm
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightElbow],
      [PoseLandmarkType.rightElbow,    PoseLandmarkType.rightWrist],
      // Torso
      [PoseLandmarkType.leftShoulder,  PoseLandmarkType.leftHip],
      [PoseLandmarkType.rightShoulder, PoseLandmarkType.rightHip],
      [PoseLandmarkType.leftHip,       PoseLandmarkType.rightHip],
      // Left leg
      [PoseLandmarkType.leftHip,       PoseLandmarkType.leftKnee],
      [PoseLandmarkType.leftKnee,      PoseLandmarkType.leftAnkle],
      // Right leg
      [PoseLandmarkType.rightHip,      PoseLandmarkType.rightKnee],
      [PoseLandmarkType.rightKnee,     PoseLandmarkType.rightAnkle],
    ];

    for (final pose in poses) {
      // Draw bones
      for (final connection in connections) {
        final p1 = pose.landmarks[connection[0]];
        final p2 = pose.landmarks[connection[1]];

        // Only draw if both endpoints were detected this frame
        if (p1 != null && p2 != null) {
          canvas.drawLine(
            _translate(p1.x, p1.y, size),
            _translate(p2.x, p2.y, size),
            bonePaint,
          );
        }
      }

      // Draw joints
      // Iterate over every landmark ML Kit returned and draw a dot
      for (final landmark in pose.landmarks.values) {
        canvas.drawCircle(
          _translate(landmark.x, landmark.y, size),
          5, // radius in logical pixels
          jointPaint,
        );
      }
    }
  }

  /// Converts a landmark position from camera-image coordinates to
  /// on-screen canvas coordinates.
  ///
  /// Steps:
  ///   1. Scale x and y by the ratio of canvas size to image size.
  ///   2. For the front camera, mirror x so it matches the flipped preview.
  Offset _translate(double x, double y, Size canvasSize) {
    final scaleX = canvasSize.width  / imageSize.width;
    final scaleY = canvasSize.height / imageSize.height;

    // Mirror x for front camera (selfie camera image is horizontally flipped)
    final screenX = isFrontCamera
        ? canvasSize.width - (x * scaleX)
        : x * scaleX;

    return Offset(screenX, y * scaleY);
  }

  /// Always repaint when the painter is replaced - we get a new instance
  /// every frame, so we always need to redraw.
  @override
  bool shouldRepaint(PosePainter oldDelegate) => true;
}