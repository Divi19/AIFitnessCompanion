import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/meal_model.dart';

/// Service that handles two responsibilities:
///   1. Fetching nutrition data from Open Food Facts using a barcode
///   2. Logging confirmed meals and snacks to Firestore
///
/// Open Food Facts is a free, open-source food database with millions
/// of products. No API key required completely free to use.
/// Documentation: https://world.openfoodfacts.org/data
class MealService {
  // Firestore instance for logging meals
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // UUID generator for creating unique meal log IDs
  final Uuid _uuid = const Uuid();

  // 
  // BARCODE -> NUTRITION (Open Food Facts)
  // 

  /// Looks up a product by its barcode using the Open Food Facts API.
  ///
  /// Returns a Map with the product name and nutrition values per 100g,
  /// or null if the product is not found in the database.
  ///
  /// [barcode] - the scanned barcode string (EAN-13, UPC-A, etc.)
  ///
  /// The Open Food Facts API endpoint format:
  /// https://world.openfoodfacts.org/api/v0/product/{barcode}.json
  Future<Map<String, dynamic>?> fetchProductByBarcode(String barcode) async {
    try {
      final url = Uri.parse(
        'https://world.openfoodfacts.org/api/v0/product/$barcode.json',
      );

      final response = await http.get(
        url,
        headers: {
          // Open Food Facts requests a meaningful User-Agent to identify the app
          'User-Agent': 'AiFitnessApp/1.0',
        },
      );

      if (response.statusCode != 200) return null;

      final data = jsonDecode(response.body);

      // status = 1 means product was found, 0 means not found
      if (data['status'] != 1) return null;

      final product = data['product'];
      final nutriments = product['nutriments'] ?? {};

      // Extract the fields we need, defaulting to 0 if missing.
      // Open Food Facts stores values per 100g by default.
      return {
        'name': product['product_name'] ?? 'Unknown Product',
        // Per 100g values - we'll adjust for serving size and portion later
        'calories_per_100g': (nutriments['energy-kcal_100g'] ?? 0).toDouble(),
        'protein_per_100g': (nutriments['proteins_100g'] ?? 0).toDouble(),
        'carbs_per_100g': (nutriments['carbohydrates_100g'] ?? 0).toDouble(),
        'fat_per_100g': (nutriments['fat_100g'] ?? 0).toDouble(),
        // Serving size in grams if the product provides it
        'serving_size_g': _parseServingSize(product['serving_size'] ?? '100g'),
      };
    } catch (e) {
      // Network error or malformed JSON - return null so UI can handle it
      return null;
    }
  }

  /// Parses a serving size string like "30g" or "250 ml" into a double.
  /// Falls back to 100g if the format is unrecognised.
  double _parseServingSize(String servingSizeStr) {
    // Extract the first number found in the string using a regex
    final match = RegExp(r'(\d+(\.\d+)?)').firstMatch(servingSizeStr);
    if (match != null) {
      return double.tryParse(match.group(1) ?? '100') ?? 100.0;
    }
    return 100.0; // Safe default
  }

  /// Calculates the actual nutrition values for the consumed portion.
  ///
  /// Open Food Facts gives us values per 100g. We scale by serving size
  /// then apply the user's portion multiplier.
  ///
  /// Example: product has 400 kcal/100g, serving = 30g, portion = 0.5
  ///   -> consumed calories = 400 * (30/100) * 0.5 = 60 kcal
  ///
  /// [productData] - the map returned by [fetchProductByBarcode]
  /// [portionFactor] - 1.0 = full serving, 0.5 = half, etc.
  Map<String, double> calculateNutrition({
    required Map<String, dynamic> productData,
    required double portionFactor,
  }) {
    final servingG = productData['serving_size_g'] as double;
    // Scale factor converts per-100g values to per-serving values
    final scale = servingG / 100.0;

    return {
      'calories': (productData['calories_per_100g'] * scale * portionFactor),
      'protein': (productData['protein_per_100g'] * scale * portionFactor),
      'carbs': (productData['carbs_per_100g'] * scale * portionFactor),
      'fat': (productData['fat_per_100g'] * scale * portionFactor),
    };
  }

  //
  // FIRESTORE LOGGING
  //

  /// Logs a confirmed meal or snack entry to Firestore.
  ///
  /// Firestore structure:
  ///   meals → {userId} → logs → {mealId}
  ///
  /// We use a subcollection under the user's document so we can
  /// query "all logs for this user" efficiently with a collection
  /// group query, and it scales cleanly as logs grow over time.
  ///
  /// [userId] - the currently logged-in user's UID
  /// [name] - confirmed dish or product name
  /// [type] - 'meal' or 'snack'
  /// [calories] - for the consumed portion
  /// [protein] - for the consumed portion
  /// [carbs]  - for the consumed portion
  /// [fat] - for the consumed portion
  /// [portion] - the multiplier used (stored for reference)
  Future<void> logMeal({
    required String userId,
    required String name,
    required String type,
    required double calories,
    required double protein,
    required double carbs,
    required double fat,
    required double portion,
  }) async {
    final mealId = _uuid.v4(); // Generate a unique ID for this log entry

    final meal = MealModel(
      mealId: mealId,
      userId: userId,
      name: name,
      type: type,
      calories: calories,
      protein: protein,
      carbs: carbs,
      fat: fat,
      portion: portion,
      timestamp: Timestamp.now(),
    );

    // Write to Firestore: meals/{userId}/logs/{mealId}
    await _firestore
        .collection('meals')
        .doc(userId)
        .collection('logs')
        .doc(mealId)
        .set(meal.toMap());
  }

  /// Fetches today's meal logs for a given user, ordered by time.
  ///
  /// Used to display the daily summary at the bottom of the tracker screen.
  Future<List<MealModel>> getTodaysLogs(String userId) async {
    // Get the start of today (midnight) as a Timestamp for the query
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final snapshot = await _firestore
        .collection('meals')
        .doc(userId)
        .collection('logs')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .orderBy('timestamp', descending: false)
        .get();

    return snapshot.docs.map((doc) => MealModel.fromMap(doc.data())).toList();
  }
}
