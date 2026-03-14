import 'package:flutter/services.dart';

/// Service that communicates with the native QuickPose Android SDK
/// via Flutter Platform Channels.
class QuickPoseService {
  static const _methodChannel = MethodChannel('com.example.ai_fitness_app/quickpose');
  static const _eventChannel  = EventChannel('com.example.ai_fitness_app/quickpose_events');

  /// Stream of real-time results from QuickPose.
  /// Each event is a Map containing:
  ///   - 'repCount'      : int    — current rep count
  ///   - 'exerciseState' : String — 'up', 'down', 'unknown'
  ///   - 'feedback'      : String — form correction message (may be empty)
  ///   - 'status'        : String — 'success', 'failure', 'loading'
  ///   - 'fps'           : int    — frames per second
  Stream<Map<String, dynamic>> get resultsStream {
    return _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
  }

  /// Tell the native SDK to switch to a different exercise.
  /// [exercise] must be one of the supported strings:
  /// 'squat', 'pushup', 'bicep_curl', 'jumping_jack',
  /// 'lunge_left', 'lunge_right', 'sit_up', 'plank', 'glute_bridge'
  Future<void> switchExercise(String exercise) async {
    await _methodChannel.invokeMethod('switchExercise', {'exercise': exercise});
  }

  /// Stop the camera feed when navigating away.
  Future<void> stopCamera() async {
    await _methodChannel.invokeMethod('stopCamera');
  }
}