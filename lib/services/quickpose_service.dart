import 'package:flutter/services.dart';

class QuickPoseService {
  static const _methodChannel = MethodChannel('com.example.ai_fitness_app/quickpose');
  static const _eventChannel  = EventChannel('com.example.ai_fitness_app/quickpose_events');

  /// Stream of real-time results from QuickPose.
  Stream<Map<String, dynamic>> get resultsStream {
    return _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
  }

  /// Launch the full-screen QuickPose Activity with the given exercise.
  Future<void> startCamera(String exercise) async {
    await _methodChannel.invokeMethod('startCamera', {'exercise': exercise});
  }

  /// Switch exercise in the running QuickPose Activity.
  Future<void> switchExercise(String exercise) async {
    await _methodChannel.invokeMethod('switchExercise', {'exercise': exercise});
  }

  /// Close the QuickPose Activity.
  Future<void> stopCamera() async {
    await _methodChannel.invokeMethod('stopCamera');
  }
}