import 'package:flutter/material.dart';
import '../models/meal_model.dart';

/// Displays a summary of all meals and snacks logged today.
///
/// Calculates and shows:
///   - Total calories consumed today
///   - Total protein, carbs, and fat
///   - A scrollable list of individual log entries
///
/// [logs] - list of today's MealModel entries fetched from Firestore
class NutritionSummaryCard extends StatelessWidget {
  final List<MealModel> logs;

  const NutritionSummaryCard({super.key, required this.logs});

  @override
  Widget build(BuildContext context) {
    // Calculate daily totals by summing consumed values across all logs.
    // Calories/Protein etc. already apply the portion factor.
    final totalCalories = logs.fold(0.0, (sum, m) => sum + m.calories);
    final totalProtein = logs.fold(0.0, (sum, m) => sum + m.protein);
    final totalCarbs = logs.fold(0.0, (sum, m) => sum + m.carbs);
    final totalFat = logs.fold(0.0, (sum, m) => sum + m.fat);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Section title
          const Text(
            "Today's Nutrition",
            style: TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),

          const SizedBox(height: 12),

          // Total macros row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _totalChip(
                'Calories',
                '${totalCalories.toStringAsFixed(0)} kcal',
                Colors.orangeAccent,
              ),
              _totalChip(
                'Protein',
                '${totalProtein.toStringAsFixed(1)}g',
                Colors.blueAccent,
              ),
              _totalChip(
                'Carbs',
                '${totalCarbs.toStringAsFixed(1)}g',
                Colors.greenAccent,
              ),
              _totalChip(
                'Fat',
                '${totalFat.toStringAsFixed(1)}g',
                Colors.pinkAccent,
              ),
            ],
          ),

          const SizedBox(height: 16),

          // Individual log entries list
          if (logs.isEmpty)
            const Center(
              child: Text(
                'No meals logged today yet',
                style: TextStyle(color: Colors.grey),
              ),
            )
          else
            // Constrain height so this doesn't push other widgets off screen
            SizedBox(
              height: 150,
              child: ListView.builder(
                itemCount: logs.length,
                itemBuilder: (context, index) {
                  final log = logs[index];
                  return Padding(
                    padding: const EdgeInsets.only(bottom: 8),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        // Meal/snack icon + name
                        Row(
                          children: [
                            Icon(
                              // Different icon for meal vs snack
                              log.type == 'snack'
                                  ? Icons.cookie_outlined
                                  : Icons.restaurant,
                              color: Colors.grey,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              log.name,
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 13,
                              ),
                            ),
                          ],
                        ),
                        // Consumed calories for this entry
                        Text(
                          '${log.calories.toStringAsFixed(0)} kcal',
                          style: const TextStyle(
                            color: Colors.orangeAccent,
                            fontSize: 13,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
        ],
      ),
    );
  }

  /// Small column widget showing one macro total.
  Widget _totalChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 14,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}
