import 'package:cloud_firestore/cloud_firestore.dart';

/// Represents a single logged meal or snack entry.
///
/// This model covers both sub-features:
///   - Meal photo classification (type = 'meal')
///   - Barcode scanned snack      (type = 'snack')
///
/// IMPORTANT SCHEMA NOTE:
/// Older documents in Firestore used snake_case keys (meal_id, user_id).
/// Going forward, toMap() uses camelCase keys (mealId). 
/// The fromMap() factory safely handles BOTH so old and new documents load correctly.
class MealModel {
  /// Unique ID for this log entry
  final String mealId; 
  
  /// Links entry to the logged-in user
  final String userId; 
  
  /// e.g., "Nasi Lemak", "Lasagna", or "Snickers Bar"
  final String name; 
  
  /// 'meal' (from photo/Gemini) or 'snack' (from barcode scanner)
  final String type; 
  
  /// Total kcal consumed (already calculated for the gram weight/portion)
  final double calories; 
  
  /// Total protein in grams consumed
  final double protein; 
  
  /// Total carbs in grams consumed
  final double carbs; 
  
  /// Total fat in grams consumed
  final double fat; 
  
  /// The total grams consumed (for meals) or the portion multiplier (for barcode snacks)
  final double portion; 
  
  /// When the entry was logged
  final Timestamp timestamp;

  const MealModel({
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

  // ── FROM FIRESTORE ────────────────────────────────────────────────────────
  
  /// Reconstructs a MealModel from a Firestore document snapshot.
  /// Handles both snake_case (old documents) and camelCase (new documents).
  /// Falls back gracefully on any missing or malformed fields to prevent crashes.
  factory MealModel.fromMap(Map<String, dynamic> map) {
    return MealModel(
      // Safely checks for old meal_id or new mealId
      mealId    : (map['meal_id']  ?? map['mealId']  ?? '') as String,
      userId    : (map['user_id']  ?? map['userId']  ?? '') as String,
      name      : (map['name']     ?? 'Unknown')            as String,
      type      : (map['type']     ?? 'meal')               as String,
      
      // Use helper to safely parse ints, doubles, or strings from DB
      calories  : _toDouble(map['calories']),
      protein   : _toDouble(map['protein']),
      carbs     : _toDouble(map['carbs']),
      fat       : _toDouble(map['fat']),
      portion   : _toDouble(map['portion']),
      
      // Ensure timestamp is actually a Timestamp, fallback to now if broken
      timestamp : map['timestamp'] is Timestamp
          ? map['timestamp'] as Timestamp
          : Timestamp.now(),
    );
  }

  // ── TO FIRESTORE ──────────────────────────────────────────────────────────
  
  /// Converts this model to a Map for storing in Firestore.
  /// New documents are written with camelCase keys going forward.
  Map<String, dynamic> toMap() => {
    'mealId'   : mealId,
    'userId'   : userId,
    'name'     : name,
    'type'     : type,
    'calories' : calories,
    'protein'  : protein,
    'carbs'    : carbs,
    'fat'      : fat,
    'portion'  : portion,
    'timestamp': timestamp,
  };

  // ── HELPERS ───────────────────────────────────────────────────────────────

  /// Safe conversion — handles String, int, double, and null without crashing
  static double _toDouble(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);
}