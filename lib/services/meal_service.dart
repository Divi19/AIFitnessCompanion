import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:uuid/uuid.dart';
import '../models/meal_model.dart';
import 'dart:async';

/// Service that handles THREE data sources:
///
///   1. USDA FoodData Central → photo meal lookup by dish name (NEW)
///      Free API — get your key at https://fdc.nal.usda.gov/api-key-signup
///      Best for: chicken breast, pasta, eggs, salads, standard Western foods.
///      Returns per-100g macros. We multiply by Gemini's gram estimate.
///
///   2. Open Food Facts → barcode scan (unchanged from original)
///      Free, no key needed. Returns per-100g macros + serving size.
///
///   3. Gemini fallback → when USDA doesn't have the dish (regional foods)
///      Used for: nasi lemak, rendang, laksa, char kway teow, roti canai etc.
///      Gemini estimates macros for the gram weight it already guessed.
///
/// PHOTO MEAL FLOW:
///   Photo → Gemini identifies dish + estimates grams (classifyMealWithGrams)
///        → enrichCandidate() tries USDA by dish name
///        → USDA found:     real per-100g macros × (grams / 100)  ← accurate
///        → USDA not found: Gemini fallback macros (already for that weight)
///        → User adjusts grams in card → macros recalculate live
///        → User confirms → logMeal() writes to Firestore
class MealService {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final Uuid _uuid = const Uuid();

  // Replace 'DEMO_KEY' with your real key from fdc.nal.usda.gov/api-key-signup
  // DEMO_KEY works but is rate-limited to ~30 req/hour — fine for testing.
  static const String _usdaApiKey = 'DEMO_KEY';

  // ─────────────────────────────────────────────────────────────────────────
  // 1. USDA LOOKUP BY DISH NAME
  //
  // Called by enrichCandidate() after Gemini identifies the dish name.
  // Returns per-100g macros so the card can multiply by any gram value.
  //
  // dataType filter explanation:
  //   Foundation     = raw agricultural foods (e.g. "Chicken, broilers")
  //   SR Legacy      = classic USDA reference database (most complete)
  //   Survey (FNDDS) = mixed dishes as eaten (e.g. "Chicken fried rice") ← best for meals
  // ─────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> lookupNutritionByName(String dishName) async {
    try {
      final url = Uri.parse(
        'https://api.nal.usda.gov/fdc/v1/foods/search'
        '?query=${Uri.encodeComponent(dishName)}'
        '&dataType=Foundation,SR%20Legacy,Survey%20(FNDDS)'
        '&pageSize=1'
        '&api_key=$_usdaApiKey',
      );

      final res = await http.get(
        url,
        headers: {'Content-Type': 'application/json'},
      ).timeout(const Duration(seconds: 8));

      if (res.statusCode != 200) {
        print('USDA HTTP error: ${res.statusCode}');
        return null;
      }

      final body  = jsonDecode(res.body) as Map<String, dynamic>;
      final foods = body['foods'] as List?;

      if (foods == null || foods.isEmpty) {
        print('USDA: "$dishName" not found');
        return null;
      }

      final food      = foods.first as Map<String, dynamic>;
      final nutrients = food['foodNutrients'] as List? ?? [];

      // Find a nutrient value by USDA nutrient ID.
      // IDs: 1008 = Energy (kcal), 1003 = Protein, 1005 = Carbs, 1004 = Fat
      double per100(int nutrientId) {
        for (final n in nutrients) {
          if ((n['nutrientId'] as int?) == nutrientId) {
            return _safeDouble(n['value']);
          }
        }
        return 0.0;
      }

      final cal100  = per100(1008);
      final prot100 = per100(1003);
      final carb100 = per100(1005);
      final fat100  = per100(1004);

      // Reject USDA entries that have no nutrient data (empty/incomplete rows)
      if (cal100 == 0 && prot100 == 0 && carb100 == 0 && fat100 == 0) {
        print('USDA: entry for "$dishName" has no nutrient data');
        return null;
      }

      print('USDA ✓ ${food['description']} | '
            'Cal: $cal100 | P: $prot100 | C: $carb100 | F: $fat100 per 100g');

      return {
        'source'        : 'USDA',
        'usda_name'     : food['description'] as String? ?? dishName,
        'cal_per_100g'  : cal100,
        'prot_per_100g' : prot100,
        'carb_per_100g' : carb100,
        'fat_per_100g'  : fat100,
      };

    } catch (e) {
      print('USDA lookup error: $e');
      return null;
    }
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 2. ENRICH GEMINI CANDIDATE
  //
  // Takes one raw Gemini candidate (from classifyMealWithGrams) and returns
  // it enriched with final per-100g macros from either USDA or Gemini fallback.
  //
  // Called once per candidate in meal_tracker_screen._takeMealPhoto():
  //   for (final candidate in geminiResults) {
  //     enriched.add(await _mealService.enrichCandidate(candidate));
  //   }
  // ─────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>> enrichCandidate(
      Map<String, dynamic> candidate) async {
    final name  = candidate['name'] as String? ?? '';
    final grams = _safeDouble(candidate['estimated_grams']);
    final g     = grams > 0 ? grams : 100.0;

    // Try USDA first
    final usda = await lookupNutritionByName(name);

    if (usda != null) {
      // USDA found — use its accurate per-100g values.
      // Pre-calculate for the Gemini-estimated grams so the card
      // renders correct numbers immediately before the user adjusts.
      return {
        ...candidate,
        'source'        : 'USDA',
        'usda_name'     : usda['usda_name'],
        'cal_per_100g'  : usda['cal_per_100g'],
        'prot_per_100g' : usda['prot_per_100g'],
        'carb_per_100g' : usda['carb_per_100g'],
        'fat_per_100g'  : usda['fat_per_100g'],
        // Pre-calculated display values for the estimated gram weight
        'calories'      : _round0(usda['cal_per_100g']  * g / 100),
        'protein'       : _round1(usda['prot_per_100g'] * g / 100),
        'carbs'         : _round1(usda['carb_per_100g'] * g / 100),
        'fat'           : _round1(usda['fat_per_100g']  * g / 100),
      };
    }

    // USDA not found — use Gemini's fallback macros.
    // Gemini calculated these FOR the estimated gram weight, so we convert
    // them back to per-100g so the card can recalculate for any gram value.
    final fallbackCal  = _safeDouble(candidate['fallback_calories']);
    final fallbackProt = _safeDouble(candidate['fallback_protein']);
    final fallbackCarb = _safeDouble(candidate['fallback_carbs']);
    final fallbackFat  = _safeDouble(candidate['fallback_fat']);

    print('Gemini fallback for "$name": ${fallbackCal}kcal for ${g}g');

    return {
      ...candidate,
      'source'        : 'Gemini estimate',
      // Convert back to per-100g so gram slider can recalculate
      'cal_per_100g'  : g > 0 ? fallbackCal  / g * 100 : 0.0,
      'prot_per_100g' : g > 0 ? fallbackProt / g * 100 : 0.0,
      'carb_per_100g' : g > 0 ? fallbackCarb / g * 100 : 0.0,
      'fat_per_100g'  : g > 0 ? fallbackFat  / g * 100 : 0.0,
      // Pre-calculated display values (same as fallback since grams match)
      'calories'      : fallbackCal,
      'protein'       : fallbackProt,
      'carbs'         : fallbackCarb,
      'fat'           : fallbackFat,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 3. BARCODE → OPEN FOOD FACTS (unchanged from your original)
  //
  // Scans a product barcode and returns nutrition per 100g + serving size.
  // Used in the Snack Scan tab. Not used for photo meals.
  // ─────────────────────────────────────────────────────────────────────────
  Future<Map<String, dynamic>?> fetchProductByBarcode(String barcode) async {
    // Try up to 2 times in case of transient network issues
    for (int attempt = 1; attempt <= 2; attempt++) {
      try {
        print('=== FETCH ATTEMPT $attempt for barcode: $barcode ===');

        // v2 API with fields filter — faster and more stable than v0
        // Only requesting the fields we actually need reduces response size
        final url = Uri.parse(
          'https://world.openfoodfacts.org/api/v2/product/$barcode'
          '?fields=product_name,nutriments,serving_size,serving_quantity',
        );

        final response = await http.get(url, headers: {
          // Open Food Facts requires a descriptive User-Agent
          // or requests get throttled/blocked
          'User-Agent': 'AiFitnessApp - Flutter - Hackathon - dev@example.com',
          'Accept': 'application/json',
          'Accept-Encoding': 'gzip',
        }).timeout(
          const Duration(seconds: 15),
          onTimeout: () {
            print('=== TIMEOUT on attempt $attempt ===');
            throw Exception('Request timed out');
          },
        );

        print('=== HTTP STATUS: ${response.statusCode} ===');

        if (response.statusCode != 200) {
          print('=== HTTP ERROR: ${response.statusCode} ===');
          continue;
        }

        final data = jsonDecode(response.body);

        // status = 1 means product was found, 0 means not in database
        if (data['status'] != 1) {
          print('=== PRODUCT NOT IN DATABASE ===');
          return null;
        }

        final product    = data['product'];
        final nutriments = product['nutriments'] ?? {};

        // --- Calories ---
        // Open Food Facts stores calories inconsistently across products.
        // We try kcal fields first, then fall back to kJ and convert (÷ 4.184).
        double calories = 0;
        if (nutriments.containsKey('energy-kcal_100g')) {
          calories = _safeDouble(nutriments['energy-kcal_100g']);
        } else if (nutriments.containsKey('energy-kcal')) {
          calories = _safeDouble(nutriments['energy-kcal']);
        } else if (nutriments.containsKey('energy_100g')) {
          // energy_100g is in kJ — convert to kcal by dividing by 4.184
          calories = _safeDouble(nutriments['energy_100g']) / 4.184;
        } else if (nutriments.containsKey('energy')) {
          calories = _safeDouble(nutriments['energy']) / 4.184;
        }

        // --- Protein ---
        // Try both 'proteins' (European naming) and 'protein'
        double protein = 0;
        if (nutriments.containsKey('proteins_100g')) {
          protein = _safeDouble(nutriments['proteins_100g']);
        } else if (nutriments.containsKey('protein_100g')) {
          protein = _safeDouble(nutriments['protein_100g']);
        } else if (nutriments.containsKey('proteins')) {
          protein = _safeDouble(nutriments['proteins']);
        }

        // --- Carbs ---
        double carbs = 0;
        if (nutriments.containsKey('carbohydrates_100g')) {
          carbs = _safeDouble(nutriments['carbohydrates_100g']);
        } else if (nutriments.containsKey('carbohydrates')) {
          carbs = _safeDouble(nutriments['carbohydrates']);
        }

        // --- Fat ---
        double fat = 0;
        if (nutriments.containsKey('fat_100g')) {
          fat = _safeDouble(nutriments['fat_100g']);
        } else if (nutriments.containsKey('fat')) {
          fat = _safeDouble(nutriments['fat']);
        }

        // --- Serving size ---
        // Prefer 'serving_quantity' (already a number in grams) over
        // parsing the 'serving_size' string which can be inconsistent
        double servingG = 100.0;
        if (product['serving_quantity'] != null) {
          servingG = (product['serving_quantity'] is String)
              ? double.tryParse(product['serving_quantity']) ?? 100.0
              : _safeDouble(product['serving_quantity']);
        } else {
          servingG = _parseServingSize(product['serving_size'] ?? '100g');
        }

        // If all core nutrition fields are zero the database entry
        // is incomplete — return null so UI shows a helpful message
        if (calories == 0 && protein == 0 && carbs == 0 && fat == 0) {
          print('=== INCOMPLETE DATA for ${product['product_name']} ===');
          return null;
        }

        print('=== SUCCESS: ${product['product_name']} ===');
        print('Cal: $calories | P: $protein | C: $carbs | F: $fat | Serving: ${servingG}g');

        return {
          'name'             : product['product_name'] ?? 'Unknown Product',
          'calories_per_100g': calories,
          'protein_per_100g' : protein,
          'carbs_per_100g'   : carbs,
          'fat_per_100g'     : fat,
          'serving_size_g'   : servingG,
        };

      } catch (e) {
        print('=== FETCH ERROR attempt $attempt: $e ===');
        if (attempt == 2) return null;
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
    return 100.0;
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
      'calories': productData['calories_per_100g'] * scale * portionFactor,
      'protein' : productData['protein_per_100g']  * scale * portionFactor,
      'carbs'   : productData['carbs_per_100g']    * scale * portionFactor,
      'fat'     : productData['fat_per_100g']      * scale * portionFactor,
    };
  }

  // ─────────────────────────────────────────────────────────────────────────
  // 4. FIRESTORE LOGGING (unchanged from your original)
  // ─────────────────────────────────────────────────────────────────────────

  /// Logs a confirmed meal or snack entry to Firestore.
  ///
  /// Firestore structure: meals → {userId} → logs → {mealId}
  ///
  /// [userId]   - the currently logged-in user's UID
  /// [name]     - confirmed dish or product name
  /// [type]     - 'meal' or 'snack'
  /// [calories] - for the consumed portion
  /// [protein]  - for the consumed portion
  /// [carbs]    - for the consumed portion
  /// [fat]      - for the consumed portion
  /// [portion]  - gram weight consumed (stored for reference)
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
    final mealId = _uuid.v4();

    final meal = MealModel(
      mealId:    mealId,
      userId:    userId,
      name:      name,
      type:      type,
      calories:  calories,
      protein:   protein,
      carbs:     carbs,
      fat:       fat,
      portion:   portion,
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
  /// Used to display the daily nutrition summary at the bottom of the screen.
  Future<List<MealModel>> getTodaysLogs(String userId) async {
    // Get start of today (midnight) as a Timestamp for the Firestore query
    final now   = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);

    final snapshot = await _firestore
        .collection('meals')
        .doc(userId)
        .collection('logs')
        .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(today))
        .orderBy('timestamp', descending: false)
        .get();

    return snapshot.docs
        .map((doc) => MealModel.fromMap(doc.data()))
        .toList();
  }

  // ── PRIVATE HELPERS ───────────────────────────────────────────────────────

  /// Safely converts any value (num, String, null) to a double.
  /// Prevents type cast crashes when Gemini returns numbers as strings.
  static double _safeDouble(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

  static double _round0(double v) => double.parse(v.toStringAsFixed(0));
  static double _round1(double v) => double.parse(v.toStringAsFixed(1));
}