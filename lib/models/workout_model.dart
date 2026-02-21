import 'package:cloud_firestore/cloud_firestore.dart';

class WorkoutModel {
  final String workoutId;
  final String userId;
  final String type; // 'Strength', 'Mobility', 'HIIT', 'Active Recovery'
  final List<Map<String, dynamic>> exercises; // {name, target_reps, completed_reps}
  final Timestamp scheduledDate;
  final bool isCompleted;

  WorkoutModel({
    required this.workoutId,
    required this.userId,
    required this.type,
    required this.exercises,
    required this.scheduledDate,
    required this.isCompleted,
  });

  Map<String, dynamic> toMap() => {
    'workout_id': workoutId,
    'user_id': userId,
    'type': type,
    'exercises': exercises,
    'scheduled_date': scheduledDate,
    'is_completed': isCompleted,
  };

  factory WorkoutModel.fromMap(Map<String, dynamic> map) => WorkoutModel(
    workoutId: map['workout_id'] ?? '',
    userId: map['user_id'] ?? '',
    type: map['type'] ?? '',
    exercises: List<Map<String, dynamic>>.from(map['exercises'] ?? []),
    scheduledDate: map['scheduled_date'] ?? Timestamp.now(),
    isCompleted: map['is_completed'] ?? false,
  );
}