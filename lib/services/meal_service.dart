import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/meal_model.dart';
import 'dart:async';

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
  // Try up to 2 times in case of transient network issues
  for (int attempt = 1; attempt <= 2; attempt++) {
    try {
      print('=== FETCH ATTEMPT $attempt for barcode: $barcode ===');

      // v2 API with fields filter — faster and more stable than v0
      // Only requesting the fields we actually need reduces response size
      final url = Uri.parse(
        'https://world.openfoodfacts.org/api/v2/product/$barcode?fields=product_name,nutriments,serving_size,serving_quantity',
      );

      final response = await http.get(
        url,
        headers: {
          // Open Food Facts requires a descriptive User-Agent
          // or requests get throttled/blocked
          'User-Agent': 'AiFitnessApp - Flutter - Hackathon - dev@example.com',
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
        },
      ).timeout(
        const Duration(seconds: 15),
        onTimeout: () {
          print('=== TIMEOUT on attempt $attempt ===');
          throw Exception('Request timed out');
        },
      );

      print('=== HTTP STATUS: ${response.statusCode} ===');

      if (response.statusCode != 200) {
        print('=== HTTP ERROR: ${response.statusCode} ===');
        continue; // Try again on next attempt
      }

      final data = jsonDecode(response.body);

      // status = 1 means product was found, 0 means not in database
      if (data['status'] != 1) {
        print('=== PRODUCT NOT IN DATABASE ===');
        return null; // No point retrying — product genuinely not found
      }

      final product    = data['product'];
      final nutriments = product['nutriments'] ?? {};

      // --- Calories ---
      // Open Food Facts stores calories inconsistently across products.
      // We try kcal fields first, then fall back to kJ and convert (÷ 4.184).
      double calories = 0;
      if (nutriments.containsKey('energy-kcal_100g')) {
        calories = (nutriments['energy-kcal_100g'] ?? 0).toDouble();
      } else if (nutriments.containsKey('energy-kcal')) {
        calories = (nutriments['energy-kcal'] ?? 0).toDouble();
      } else if (nutriments.containsKey('energy_100g')) {
        // energy_100g is in kJ — convert to kcal by dividing by 4.184
        calories = ((nutriments['energy_100g'] ?? 0) / 4.184).toDouble();
      } else if (nutriments.containsKey('energy')) {
        calories = ((nutriments['energy'] ?? 0) / 4.184).toDouble();
      }

      // --- Protein ---
      // Try both 'proteins' (European naming) and 'protein'
      double protein = 0;
      if (nutriments.containsKey('proteins_100g')) {
        protein = (nutriments['proteins_100g'] ?? 0).toDouble();
      } else if (nutriments.containsKey('protein_100g')) {
        protein = (nutriments['protein_100g'] ?? 0).toDouble();
      } else if (nutriments.containsKey('proteins')) {
        protein = (nutriments['proteins'] ?? 0).toDouble();
      }

      // --- Carbs ---
      double carbs = 0;
      if (nutriments.containsKey('carbohydrates_100g')) {
        carbs = (nutriments['carbohydrates_100g'] ?? 0).toDouble();
      } else if (nutriments.containsKey('carbohydrates')) {
        carbs = (nutriments['carbohydrates'] ?? 0).toDouble();
      }

      // --- Fat ---
      double fat = 0;
      if (nutriments.containsKey('fat_100g')) {
        fat = (nutriments['fat_100g'] ?? 0).toDouble();
      } else if (nutriments.containsKey('fat')) {
        fat = (nutriments['fat'] ?? 0).toDouble();
      }

      // --- Serving size ---
      // Prefer 'serving_quantity' (already a number in grams) over
      // parsing the 'serving_size' string which can be inconsistent
      double servingG = 100.0;
      if (product['serving_quantity'] != null) {
        servingG = (product['serving_quantity'] is String)
            ? double.tryParse(product['serving_quantity']) ?? 100.0
            : (product['serving_quantity'] as num).toDouble();
      } else {
        servingG = _parseServingSize(product['serving_size'] ?? '100g');
      }

      // If all core nutrition fields are zero the database entry
      // is incomplete — return null so UI shows a helpful message
      if (calories == 0 && protein == 0 && carbs == 0 && fat == 0) {
        print('=== INCOMPLETE DATA for ${product['product_name']} ===');
        return null;
      }

      // Success — log the parsed values for verification
      print('=== SUCCESS: ${product['product_name']} ===');
      print('Cal: $calories | P: $protein | C: $carbs | F: $fat | Serving: ${servingG}g');

      return {
        'name':              product['product_name'] ?? 'Unknown Product',
        'calories_per_100g': calories,
        'protein_per_100g':  protein,
        'carbs_per_100g':    carbs,
        'fat_per_100g':      fat,
        'serving_size_g':    servingG,
      };

    } catch (e) {
      print('=== FETCH ERROR attempt $attempt: $e ===');
      if (attempt == 2) return null; // Both attempts failed — give up
      // Wait 1 second before retrying to give network time to recover
      await Future.delayed(const Duration(seconds: 1));
    }
  }
  return null;
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
