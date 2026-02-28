import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single logged meal or snack entry.
///
/// This model covers both sub-features:
///   - Meal photo classification (type = 'meal')
///   - Barcode scanned snack      (type = 'snack')
///
/// Nutrition values are always stored for the FULL portion.
/// The [portion] field (0.0 to 1.0) is applied when displaying
/// or summing daily totals - e.g. portion 0.5 means half the
/// listed calories/macros were consumed.
class MealModel {
  final String mealId; // Unique ID for this log entry
  final String userId; // Links entry to the logged-in user
  final String name; // e.g. "Nasi Lemak" or "Lasagna"
  final String type; // 'meal' | 'snack'
  final double calories; // kcal for full portion
  final double protein; // grams for full portion
  final double carbs; // grams for full portion
  final double fat; // grams for full portion
  final double portion; // 0.0–1.0 (1.0 = full, 0.5 = half, etc.)
  final Timestamp timestamp; // When the entry was logged

  MealModel({
    required this.mealId,
    required this.userId,
    required this.name,
    required this.type,
    required this.calories,
    required this.protein,
    required this.carbs,
    required this.fat,
    required this.portion,
    required this.timestamp,
  });

  /// Calories actually consumed, after applying the portion multiplier.
  double get consumedCalories => calories * portion;

  /// Protein actually consumed, after applying the portion multiplier.
  double get consumedProtein => protein * portion;

  /// Carbs actually consumed, after applying the portion multiplier.
  double get consumedCarbs => carbs * portion;

  /// Fat actually consumed, after applying the portion multiplier.
  double get consumedFat => fat * portion;

  /// Converts this model to a Map for storing in Firestore.
  /// Field names follow the same snake_case convention as WorkoutModel.
  Map<String, dynamic> toMap() => {
    'meal_id': mealId,
    'user_id': userId,
    'name': name,
    'type': type,
    'calories': calories,
    'protein': protein,
    'carbs': carbs,
    'fat': fat,
    'portion': portion,
    'timestamp': timestamp,
  };

  /// Reconstructs a MealModel from a Firestore document snapshot.
  factory MealModel.fromMap(Map<String, dynamic> map) => MealModel(
    mealId: map['meal_id'] ?? '',
    userId: map['user_id'] ?? '',
    name: map['name'] ?? '',
    type: map['type'] ?? 'meal',
    calories: (map['calories'] ?? 0).toDouble(),
    protein: (map['protein'] ?? 0).toDouble(),
    carbs: (map['carbs'] ?? 0).toDouble(),
    fat: (map['fat'] ?? 0).toDouble(),
    portion: (map['portion'] ?? 1.0).toDouble(),
    timestamp: map['timestamp'] ?? Timestamp.now(),
  );
}
