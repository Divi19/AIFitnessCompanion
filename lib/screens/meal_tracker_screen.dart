import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/gemini_service.dart';
import '../services/meal_service.dart';
import '../widgets/meal_result_card.dart';
import '../widgets/nutrition_summary_card.dart';
import '../models/meal_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

/// The main meal tracker screen with two tabs:
///   - Tab 0: Meal Photo - take/pick a photo, Gemini classifies it
///   - Tab 1: Snack Scan - scan a barcode, Open Food Facts returns nutrition
///
/// Both flows end with the user confirming the entry and it being
/// logged to Firestore via [MealService].
///
/// For demo purposes, userId is hardcoded as 'demo_user'.
/// When your teammates finish auth, replace it with the real UID from
/// FirebaseAuth.instance.currentUser?.uid ?? 'demo_user'
class MealTrackerScreen extends StatefulWidget {
  const MealTrackerScreen({super.key});

  @override
  State<MealTrackerScreen> createState() => _MealTrackerScreenState();
}

class _MealTrackerScreenState extends State<MealTrackerScreen>
    with SingleTickerProviderStateMixin {
  // Services 
  final MealGeminiService _geminiService = MealGeminiService();
  final MealService _mealService = MealService();
  final ImagePicker _imagePicker = ImagePicker();

  // Tab controller for Meal / Snack tabs 
  late final TabController _tabController = TabController(
    length: 2,
    vsync: this,
  );

  // ── Meal photo tab state 
  bool _isAnalyzing = false; // True while waiting for Gemini response
  List<Map<String, dynamic>> _mealSuggestions = []; // Gemini's 3 suggestions
  List<int>? _capturedImageBytes; // Raw bytes of the photo taken

  // ── Snack scan tab state ───────────────────────────────────────
  bool _isScanning = true; // Controls barcode scanner visibility
  bool _isFetchingProduct = false; // True while calling Open Food Facts
  Map<String, dynamic>? _scannedProduct; // Product data from Open Food Facts
  double _portionFactor = 1.0; // User's selected portion (0.0–1.0)
  // Barcode scanner controller - manages camera lifecycle for the scanner
  final MobileScannerController _scannerController = MobileScannerController();

  // Daily log state 
  List<MealModel> _todaysLogs = []; // Today's logged entries from Firestore


  final String _userId =FirebaseAuth.instance.currentUser?.uid ?? 'demo_user';

  // Lifecycle

  @override
  void initState() {
    super.initState();
    _loadTodaysLogs(); // Load existing logs when screen opens
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose(); // Release barcode scanner camera
    super.dispose();
  }

  // 
  // MEAL PHOTO FLOW
  // 

  /// Opens the camera (or gallery) and sends the photo to Gemini for analysis.
  /// [source] - ImageSource.camera or ImageSource.gallery
  Future<void> _takeMealPhoto(ImageSource source) async {
    final picked = await _imagePicker.pickImage(
      source: source,
      imageQuality: 85, // Compress slightly to reduce API payload size
    );
    if (picked == null) return; // User cancelled

    final bytes = await picked.readAsBytes();

    setState(() {
      _isAnalyzing = true;
      _mealSuggestions = []; // Clear previous suggestions
      _capturedImageBytes = bytes;
    });

    // Send to Gemini for classification
    final suggestions = await _geminiService.classifyMeal(bytes);

    setState(() {
      _isAnalyzing = false;
      _mealSuggestions = suggestions;
    });
  }

  /// Called when the user taps "This is my meal" on one of the suggestion cards.
  /// Logs the confirmed meal to Firestore and refreshes the daily summary.
  Future<void> _confirmMeal(Map<String, dynamic> suggestion) async {
    await _mealService.logMeal(
      userId: _userId,
      name: suggestion['name'],
      type: 'meal',
      calories: (suggestion['calories'] ?? 0).toDouble(),
      protein: (suggestion['protein'] ?? 0).toDouble(),
      carbs: (suggestion['carbs'] ?? 0).toDouble(),
      fat: (suggestion['fat'] ?? 0).toDouble(),
      portion: 1.0, // Meals are always logged as full portion
    );

    // Reset meal tab state and reload the daily log
    setState(() {
      _mealSuggestions = [];
      _capturedImageBytes = null;
    });

    await _loadTodaysLogs();
    _showSuccessSnackbar('${suggestion['name']} logged!');
  }

  // 
  // SNACK SCAN FLOW
  // 

  /// Called by MobileScanner when a barcode is detected.
  /// Fetches product nutrition from Open Food Facts.
  bool _scanLock = false; 

Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
  // Hard lock — ignore ALL callbacks until this scan is fully complete
  if (_scanLock) return;
  if (capture.barcodes.isEmpty) return;
  final barcode = capture.barcodes.first.rawValue;
  if (barcode == null) return;

  _scanLock = true; // Lock immediately before any async work
  _scannerController.stop();

  setState(() {
    _isScanning = false;
    _isFetchingProduct = true;
    _scannedProduct = null;
    _portionFactor = 1.0;
  });

  final product = await _mealService.fetchProductByBarcode(barcode);

  setState(() {
    _isFetchingProduct = false;
    _scannedProduct = product;
  });

  if (product == null) {
    _showErrorSnackbar('Product not found or incomplete data. Try another product.');
    _resetScanner();
  }

  // Don't release lock here — it stays locked until user taps Scan Again
}

 /// Called when the user confirms the snack log.
/// Applies the portion factor to the nutrition values before logging.
Future<void> _confirmSnack() async {
  if (_scannedProduct == null) return;

  // Save the name BEFORE resetting so the snackbar can still use it
  final productName = _scannedProduct!['name'] as String;

  // Calculate actual consumed nutrition using the user's portion selection
  final nutrition = _mealService.calculateNutrition(
    productData:   _scannedProduct!,
    portionFactor: _portionFactor,
  );

  await _mealService.logMeal(
    userId:   _userId,
    name:     productName,
    type:     'snack',
    calories: nutrition['calories']!,
    protein:  nutrition['protein']!,
    carbs:    nutrition['carbs']!,
    fat:      nutrition['fat']!,
    portion:  _portionFactor,
  );

  // Reset AFTER saving the name, not before
  _resetScanner();
  await _loadTodaysLogs();

  // Use saved name instead of _scannedProduct which is now null
  _showSuccessSnackbar('$productName logged!');
}

/// Resets the snack scan tab fully back to scanning state.
/// Also releases the scan lock so the next product can be scanned.
void _resetScanner() {
  // Stop the scanner first to avoid callbacks during state reset
  _scannerController.stop();

  setState(() {
    _isScanning      = true;
    _scannedProduct  = null;
    _portionFactor   = 1.0;
    _scanLock        = false; // 
  });

  // Restart scanner AFTER state is updated
  // Small delay prevents the scanner from immediately re-detecting
  // the same barcode that was just processed
  Future.delayed(const Duration(milliseconds: 500), () {
    if (mounted) _scannerController.start();
  });
}
  // 
  // SHARED HELPERS
  // 

  /// Loads today's meal logs from Firestore for the daily summary.
  Future<void> _loadTodaysLogs() async {
    final logs = await _mealService.getTodaysLogs(_userId);
    setState(() => _todaysLogs = logs);
  }

  void _showSuccessSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 2),
      ),
    );
  }

  void _showErrorSnackbar(String message) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: Colors.red,
        duration: const Duration(seconds: 3),
      ),
    );
  }

  // 
  // BUILD
  // 

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text(
          'Meal Tracker',
          style: TextStyle(color: Colors.white),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
        // Tab bar sits inside the AppBar
        bottom: TabBar(
          controller: _tabController,
          indicatorColor: Colors.greenAccent,
          labelColor: Colors.greenAccent,
          unselectedLabelColor: Colors.grey,
          tabs: const [
            Tab(icon: Icon(Icons.restaurant), text: 'Meal Photo'),
            Tab(icon: Icon(Icons.qr_code_scanner), text: 'Snack Scan'),
          ],
        ),
      ),
      body: Column(
        children: [
          // Tab content takes up all available space above the summary
          Expanded(
            child: TabBarView(
              controller: _tabController,
              children: [_buildMealPhotoTab(), _buildSnackScanTab()],
            ),
          ),
          // Daily nutrition summary always visible at the bottom
          NutritionSummaryCard(logs: _todaysLogs),
        ],
      ),
    );
  }

  // 
  // MEAL PHOTO TAB
  // 

  Widget _buildMealPhotoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Camera / Gallery buttons
          Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _takeMealPhoto(ImageSource.camera),
                  icon: const Icon(Icons.camera_alt),
                  label: const Text('Take Photo'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.greenAccent,
                    foregroundColor: Colors.black,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: () => _takeMealPhoto(ImageSource.gallery),
                  icon: const Icon(Icons.photo_library),
                  label: const Text('From Gallery'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.grey[800],
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),

          const SizedBox(height: 20),

          // Loading indicator while Gemini is analyzing
          if (_isAnalyzing)
            const Column(
              children: [
                CircularProgressIndicator(color: Colors.greenAccent),
                SizedBox(height: 12),
                Text(
                  'Analyzing your meal...',
                  style: TextStyle(color: Colors.grey),
                ),
              ],
            ),

          // Gemini suggestions - shown after analysis completes
          if (_mealSuggestions.isNotEmpty) ...[
            const Text(
              'What did you eat? Select your meal:',
              style: TextStyle(
                color: Colors.white,
                fontSize: 15,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 12),
            // Render one card per suggestion
            ..._mealSuggestions.map(
              (suggestion) => MealResultCard(
                suggestion: suggestion,
                onSelected: () => _confirmMeal(suggestion),
              ),
            ),
          ],

          // Placeholder when nothing has been captured yet
          if (!_isAnalyzing && _mealSuggestions.isEmpty)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 40),
              child: Column(
                children: [
                  Icon(Icons.restaurant, color: Colors.grey, size: 60),
                  SizedBox(height: 12),
                  Text(
                    'Take a photo of your meal\nto get started',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey, fontSize: 14),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  // 
  // SNACK SCAN TAB
  //

  Widget _buildSnackScanTab() {
    return Column(
      children: [
        // Barcode scanner - shown while _isScanning is true
        if (_isScanning)
          Expanded(
            child: Stack(
              children: [
                // Live camera feed with barcode detection
                MobileScanner(
                  controller: _scannerController,
                  onDetect: _onBarcodeDetected,
                ),
                // Scanning overlay hint
                const Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.qr_code_scanner,
                        color: Colors.greenAccent,
                        size: 80,
                      ),
                      SizedBox(height: 8),
                      Text(
                        'Point at the barcode on the package',
                        style: TextStyle(
                          color: Colors.white,
                          backgroundColor: Colors.black54,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

        // Loading indicator while fetching from Open Food Facts
        if (_isFetchingProduct)
          const Expanded(
            child: Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  CircularProgressIndicator(color: Colors.greenAccent),
                  SizedBox(height: 12),
                  Text(
                    'Looking up product...',
                    style: TextStyle(color: Colors.grey),
                  ),
                ],
              ),
            ),
          ),

        // Product found - show nutrition and portion selector
        if (_scannedProduct != null)
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Product name
                  Text(
                    _scannedProduct!['name'],
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    'Per serving (${_scannedProduct!['serving_size_g'].toStringAsFixed(0)}g)',
                    style: const TextStyle(color: Colors.grey, fontSize: 13),
                  ),

                  const SizedBox(height: 16),

                  // Nutrition values per full serving
                  _nutritionRow(
                    'Calories',
                    '${_scannedProduct!['calories_per_100g'] * _scannedProduct!['serving_size_g'] / 100 ~/ 1} kcal',
                    Colors.orangeAccent,
                  ),
                  _nutritionRow(
                    'Protein',
                    '${(_scannedProduct!['protein_per_100g'] * _scannedProduct!['serving_size_g'] / 100).toStringAsFixed(1)}g',
                    Colors.blueAccent,
                  ),
                  _nutritionRow(
                    'Carbs',
                    '${(_scannedProduct!['carbs_per_100g'] * _scannedProduct!['serving_size_g'] / 100).toStringAsFixed(1)}g',
                    Colors.greenAccent,
                  ),
                  _nutritionRow(
                    'Fat',
                    '${(_scannedProduct!['fat_per_100g'] * _scannedProduct!['serving_size_g'] / 100).toStringAsFixed(1)}g',
                    Colors.pinkAccent,
                  ),

                  const SizedBox(height: 20),

                  // Portion selector
                  const Text(
                    'How much did you consume?',
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),

                  // Quick portion buttons
                  Row(
                    children: [
                      _portionButton('Full', 1.0),
                      const SizedBox(width: 8),
                      _portionButton('Half', 0.5),
                      const SizedBox(width: 8),
                      _portionButton('¼', 0.25),
                    ],
                  ),

                  const SizedBox(height: 12),

                  // Custom percentage slider for precise portions
                  Text(
                    'Custom: ${(_portionFactor * 100).toStringAsFixed(0)}%',
                    style: const TextStyle(color: Colors.grey),
                  ),
                  Slider(
                    value: _portionFactor,
                    min: 0.1,
                    max: 1.0,
                    divisions: 9, // 10%, 20%, ... 100%
                    activeColor: Colors.greenAccent,
                    inactiveColor: Colors.grey[700],
                    onChanged: (val) => setState(() => _portionFactor = val),
                  ),

                  const SizedBox(height: 16),

                  // Log and Scan Again buttons
                  Row(
                    children: [
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _confirmSnack,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.greenAccent,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text(
                            'Log Snack',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: _resetScanner,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.grey[800],
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 14),
                          ),
                          child: const Text('Scan Again'),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  /// Helper widget for a single nutrition row in the snack detail view.
  Widget _nutritionRow(String label, String value, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontWeight: FontWeight.bold,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  /// Quick portion button - highlights when its value matches [_portionFactor].
  Widget _portionButton(String label, double value) {
    final isSelected = _portionFactor == value;
    return Expanded(
      child: GestureDetector(
        onTap: () => setState(() => _portionFactor = value),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            color: isSelected ? Colors.greenAccent : Colors.grey[800],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            textAlign: TextAlign.center,
            style: TextStyle(
              color: isSelected ? Colors.black : Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ),
    );
  }
}
