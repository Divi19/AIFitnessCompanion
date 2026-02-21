import 'package:cloud_firestore/cloud_firestore.dart';

class MealModel {
  final String mealId;
  final String userId;
  final List<String> foodItems;
  final int estimatedCalories;
  final Timestamp timestamp;

  MealModel({
    required this.mealId,
    required this.userId,
    required this.foodItems,
    required this.estimatedCalories,
    required this.timestamp,
  });

  Map<String, dynamic> toMap() => {
    'meal_id': mealId,
    'user_id': userId,
    'food_items': foodItems,
    'estimated_calories': estimatedCalories,
    'timestamp': timestamp,
  };

  factory MealModel.fromMap(Map<String, dynamic> map) => MealModel(
    mealId: map['meal_id'] ?? '',
    userId: map['user_id'] ?? '',
    foodItems: List<String>.from(map['food_items'] ?? []),
    estimatedCalories: map['estimated_calories'] ?? 0,
    timestamp: map['timestamp'] ?? Timestamp.now(),
  );
}