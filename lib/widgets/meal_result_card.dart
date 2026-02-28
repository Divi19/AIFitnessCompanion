import 'package:flutter/material.dart';

/// Displays a single meal suggestion returned by Gemini.
///
/// Shows the dish name, confidence level, and estimated macros.
/// The user taps "Select" to confirm this is the correct dish.
///
/// [suggestion] - one item from Gemini's 3-item JSON response
/// [onSelected] - callback fired when the user confirms this dish
class MealResultCard extends StatelessWidget {
  final Map<String, dynamic> suggestion;
  final VoidCallback onSelected;

  const MealResultCard({
    super.key,
    required this.suggestion,
    required this.onSelected,
  });

  /// Returns a color based on how confident Gemini is.
  Color _confidenceColor(String confidence) {
    switch (confidence) {
      case 'High':
        return Colors.green;
      case 'Medium':
        return Colors.orange;
      default:
        return Colors.red;
    }
  }

  @override
  Widget build(BuildContext context) {
    final confidence = suggestion['confidence'] ?? 'Low';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[900],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey[700]!),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Dish name + confidence badge on the same row
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Dish name - allow it to wrap if long
              Expanded(
                child: Text(
                  suggestion['name'] ?? 'Unknown',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              // Confidence badge
              Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 4,
                ),
                decoration: BoxDecoration(
                  color: _confidenceColor(confidence),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: _confidenceColor(confidence)),
                ),
                child: Text(
                  confidence,
                  style: TextStyle(
                    color: _confidenceColor(confidence),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 12),

          // Macro summary row: Calories | Protein | Carbs | Fat
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              _macroChip(
                'Calories',
                '${suggestion['calories']} kcal',
                Colors.orangeAccent,
              ),
              _macroChip(
                'Protein',
                '${suggestion['protein']}g',
                Colors.blueAccent,
              ),
              _macroChip(
                'Carbs',
                '${suggestion['carbs']}g',
                Colors.greenAccent,
              ),
              _macroChip('Fat', '${suggestion['fat']}g', Colors.pinkAccent),
            ],
          ),

          const SizedBox(height: 12),

          // Confirm button
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: onSelected,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent,
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
              child: const Text(
                'This is my meal',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Small pill widget showing one macro label and value.
  Widget _macroChip(String label, String value, Color color) {
    return Column(
      children: [
        Text(
          value,
          style: TextStyle(
            color: color,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 11)),
      ],
    );
  }
}
