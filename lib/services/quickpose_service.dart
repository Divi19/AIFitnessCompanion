import 'package:flutter/services.dart';

class QuickPoseService {
  static const _methodChannel  = MethodChannel('com.example.ai_fitness_app/quickpose');
  static const _eventChannel   = EventChannel('com.example.ai_fitness_app/quickpose_events');
  static const _sessionChannel = EventChannel('com.example.ai_fitness_app/quickpose_session');

  /// Stream of real-time frame results (rep count, feedback, status).
  Stream<Map<String, dynamic>> get resultsStream {
    return _eventChannel
        .receiveBroadcastStream()
        .map((event) => Map<String, dynamic>.from(event as Map));
  }

  /// Stream of session summaries — fires once when a valid session ends.
  /// Each event is a Map containing:
  ///   - 'exercise'    : String
  ///   - 'reps'        : int
  ///   - 'durationMs'  : int
  ///   - 'feedbackMap' : Map<String, int> — feedback message → occurrence count
  Stream<Map<String, dynamic>> get sessionStream {
    return _sessionChannel
        .receiveBroadcastStream()
        .map((event) {
          final raw = Map<String, dynamic>.from(event as Map);
          // feedbackMap arrives as Map<String, dynamic> — cast values to int
          final rawFeedback = raw['feedbackMap'] as Map? ?? {};
          final feedbackMap = rawFeedback.map(
            (k, v) => MapEntry(k.toString(), (v as num).toInt()),
          );
          return {
            'exercise':   raw['exercise'],
            'reps':       raw['reps'],
            'durationMs': raw['durationMs'],
            'feedbackMap': feedbackMap,
          };
        });
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