import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/gemini_service.dart';
import '../services/meal_service.dart';
import '../widgets/nutrition_summary_card.dart';
import '../models/meal_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MEAL TRACKER — REFACTORED FLOW
//
//  PHOTO MEAL (3 steps, clearly separated):
//
//  Step 1 — VALIDATE (Gemini)
//    Is this a food image? If NO → show _InvalidFoodState widget, stop.
//    If YES → continue to step 2.
//
//  Step 2 — IDENTIFY (Gemini)
//    Gemini analyses the food image:
//      - names the dish (up to 3 candidates)
//      - estimates portion weight in grams from visual cues
//      - flags regional dishes (USDA won't have them)
//      - provides fallback macros for that gram weight
//
//  Step 3 — LOOKUP (USDA → Gemini fallback)
//    For each candidate, MealService.enrichCandidate():
//      a. Searches USDA FoodData Central by dish name
//      b. Found → USDA per-100g macros × (grams/100) ← real database, accurate
//      c. Not found → Gemini's own fallback macros (regional foods like nasi lemak)
//    User sees gram field pre-filled with Gemini's estimate.
//    Macros recalculate live as user adjusts grams.
//
//  BARCODE SNACK (unchanged):
//    Scan → Open Food Facts → show nutrition + portion selector → log
// ─────────────────────────────────────────────────────────────────────────────

// Represents which phase of analysis we are in
enum _AnalysisState {
  idle,          // Nothing happening — show camera/gallery buttons
  validating,    // Step 1: Checking if image is food
  notFood,       // Step 1 failed: image is not food
  identifying,   // Step 2: Gemini identifying the dish
  lookingUp,     // Step 3: USDA lookup in progress
  done,          // Results ready — show suggestion cards
}

class MealTrackerScreen extends StatefulWidget {
  const MealTrackerScreen({super.key});

  @override
  State<MealTrackerScreen> createState() => _MealTrackerScreenState();
}

class _MealTrackerScreenState extends State<MealTrackerScreen>
    with SingleTickerProviderStateMixin {
  final MealGeminiService _geminiService = MealGeminiService();
  final MealService       _mealService   = MealService();
  final ImagePicker       _imagePicker   = ImagePicker();

  late final TabController _tabController = TabController(length: 2, vsync: this);

  // ── Photo tab state ───────────────────────────────────────────────────────
  _AnalysisState _analysisState = _AnalysisState.idle;
  List<Map<String, dynamic>> _mealSuggestions = [];
  Uint8List? _capturedImageBytes;

  // ── Snack scan tab state ──────────────────────────────────────────────────
  bool _isScanning       = true;
  bool _isFetchingProduct = false;
  Map<String, dynamic>? _scannedProduct;
  double _portionFactor  = 1.0;
  bool _scanLock         = false;
  final MobileScannerController _scannerController = MobileScannerController();

  // ── Daily log state ───────────────────────────────────────────────────────
  List<MealModel> _todaysLogs = [];
  final String _userId = FirebaseAuth.instance.currentUser?.uid ?? 'demo_user';

  @override
  void initState() {
    super.initState();
    _loadTodaysLogs();
  }

  @override
  void dispose() {
    _tabController.dispose();
    _scannerController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PHOTO MEAL FLOW
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _takeMealPhoto(ImageSource source) async {
    final picked = await _imagePicker.pickImage(source: source, imageQuality: 85);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();

    // Reset to clean state before starting
    setState(() {
      _analysisState      = _AnalysisState.validating;
      _mealSuggestions    = [];
      _capturedImageBytes = bytes;
    });

    // ── STEP 1: Is this a food image? ──────────────────────────────────────
    final isFood = await _geminiService.validateFoodImage(bytes);

    if (!isFood) {
      // Not food — show the invalid state and stop
      setState(() => _analysisState = _AnalysisState.notFood);
      return;
    }

    // ── STEP 2: Identify the dish + estimate grams ─────────────────────────
    setState(() => _analysisState = _AnalysisState.identifying);
    final geminiResults = await _geminiService.classifyMealWithGrams(bytes);

    // ── STEP 3: USDA lookup or Gemini fallback for each candidate ───────────
    setState(() => _analysisState = _AnalysisState.lookingUp);
    final enriched = <Map<String, dynamic>>[];
    for (final candidate in geminiResults) {
      enriched.add(await _mealService.enrichCandidate(candidate));
    }

    setState(() {
      _analysisState   = _AnalysisState.done;
      _mealSuggestions = enriched;
    });
  }

  void _resetPhotoState() {
    setState(() {
      _analysisState      = _AnalysisState.idle;
      _mealSuggestions    = [];
      _capturedImageBytes = null;
    });
  }

  static double _toDouble(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

  Future<void> _confirmMeal(Map<String, dynamic> suggestion, double grams) async {
    final factor = grams / 100.0;
    await _mealService.logMeal(
      userId:   _userId,
      name:     suggestion['name'],
      type:     'meal',
      calories: _toDouble(suggestion['cal_per_100g']) * factor,
      protein:  _toDouble(suggestion['prot_per_100g']) * factor,
      carbs:    _toDouble(suggestion['carb_per_100g']) * factor,
      fat:      _toDouble(suggestion['fat_per_100g'])  * factor,
      portion:  grams,
    );
    _resetPhotoState();
    await _loadTodaysLogs();
    _showSuccessSnackbar('${suggestion['name']} logged!');
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SNACK SCAN FLOW (unchanged)
  // ─────────────────────────────────────────────────────────────────────────

  Future<void> _onBarcodeDetected(BarcodeCapture capture) async {
    if (_scanLock) return;
    if (capture.barcodes.isEmpty) return;
    final barcode = capture.barcodes.first.rawValue;
    if (barcode == null) return;

    _scanLock = true;
    _scannerController.stop();

    setState(() {
      _isScanning       = false;
      _isFetchingProduct = true;
      _scannedProduct   = null;
      _portionFactor    = 1.0;
    });

    final product = await _mealService.fetchProductByBarcode(barcode);

    setState(() {
      _isFetchingProduct = false;
      _scannedProduct    = product;
    });

    if (product == null) {
      _showErrorSnackbar('Product not found or incomplete data. Try another product.');
      _resetScanner();
    }
  }

  Future<void> _confirmSnack() async {
    if (_scannedProduct == null) return;
    final productName = _scannedProduct!['name'] as String;
    final nutrition   = _mealService.calculateNutrition(
      productData: _scannedProduct!, portionFactor: _portionFactor);
    await _mealService.logMeal(
      userId: _userId, name: productName, type: 'snack',
      calories: nutrition['calories']!, protein: nutrition['protein']!,
      carbs: nutrition['carbs']!, fat: nutrition['fat']!, portion: _portionFactor,
    );
    _resetScanner();
    await _loadTodaysLogs();
    _showSuccessSnackbar('$productName logged!');
  }

  void _resetScanner() {
    _scannerController.stop();
    setState(() { _isScanning = true; _scannedProduct = null; _portionFactor = 1.0; _scanLock = false; });
    Future.delayed(const Duration(milliseconds: 500), () { if (mounted) _scannerController.start(); });
  }

  // ── SHARED ────────────────────────────────────────────────────────────────

  Future<void> _loadTodaysLogs() async {
    final logs = await _mealService.getTodaysLogs(_userId);
    setState(() => _todaysLogs = logs);
  }

  void _showSuccessSnackbar(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.green, duration: const Duration(seconds: 2)));

  void _showErrorSnackbar(String msg) => ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(content: Text(msg), backgroundColor: Colors.red, duration: const Duration(seconds: 3)));

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Meal Tracker', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
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
      body: Column(children: [
        Expanded(child: TabBarView(
          controller: _tabController,
          children: [_buildMealPhotoTab(), _buildSnackScanTab()],
        )),
        NutritionSummaryCard(logs: _todaysLogs),
      ]),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // MEAL PHOTO TAB — driven by _AnalysisState enum
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildMealPhotoTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(children: [

        // Camera / Gallery buttons — always visible so user can retake
        Row(children: [
          Expanded(child: ElevatedButton.icon(
            onPressed: _analysisState == _AnalysisState.idle ||
                       _analysisState == _AnalysisState.notFood ||
                       _analysisState == _AnalysisState.done
                ? () => _takeMealPhoto(ImageSource.camera) : null,
            icon: const Icon(Icons.camera_alt),
            label: const Text('Take Photo'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.greenAccent, foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 12)),
          )),
          const SizedBox(width: 12),
          Expanded(child: ElevatedButton.icon(
            onPressed: _analysisState == _AnalysisState.idle ||
                       _analysisState == _AnalysisState.notFood ||
                       _analysisState == _AnalysisState.done
                ? () => _takeMealPhoto(ImageSource.gallery) : null,
            icon: const Icon(Icons.photo_library),
            label: const Text('From Gallery'),
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.grey[800], foregroundColor: Colors.white,
              padding: const EdgeInsets.symmetric(vertical: 12)),
          )),
        ]),

        const SizedBox(height: 20),

        // ── State-driven content ──────────────────────────────────────
        switch (_analysisState) {
          // Idle — placeholder
          _AnalysisState.idle => const Padding(
            padding: EdgeInsets.symmetric(vertical: 40),
            child: Column(children: [
              Icon(Icons.restaurant, color: Colors.grey, size: 60),
              SizedBox(height: 12),
              Text('Take a photo of your meal\nto get started',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey, fontSize: 14)),
            ]),
          ),

          // Validating — step 1 spinner with photo preview
          _AnalysisState.validating => _buildLoadingState(
            'Checking if this is food...', showPhoto: true),

          // Not food — invalid state with retry
          _AnalysisState.notFood => _buildNotFoodState(),

          // Identifying — step 2 spinner
          _AnalysisState.identifying => _buildLoadingState(
            'Identifying your meal...', showPhoto: true),

          // Looking up — step 3 spinner
          _AnalysisState.lookingUp => _buildLoadingState(
            'Looking up nutrition data...', showPhoto: true),

          // Done — show suggestions
          _AnalysisState.done => _buildSuggestions(),
        },
      ]),
    );
  }

  // ── Loading state (steps 1, 2, 3) ────────────────────────────────────────
  Widget _buildLoadingState(String message, {bool showPhoto = false}) {
    return Column(children: [
      if (showPhoto && _capturedImageBytes != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(_capturedImageBytes!,
              width: double.infinity, height: 200, fit: BoxFit.cover),
        ),
        const SizedBox(height: 16),
      ],
      const CircularProgressIndicator(color: Colors.greenAccent),
      const SizedBox(height: 12),
      Text(message, style: const TextStyle(color: Colors.grey, fontSize: 14)),
    ]);
  }

  // ── Not food state ────────────────────────────────────────────────────────
  // Shown when Gemini determines the image does not contain food.
  Widget _buildNotFoodState() {
    return Column(children: [
      // Show the rejected photo with a red overlay
      if (_capturedImageBytes != null) ...[
        Stack(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Image.memory(_capturedImageBytes!,
                width: double.infinity, height: 200, fit: BoxFit.cover),
          ),
          // Red tint overlay
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: Container(
              width: double.infinity, height: 200,
              color: Colors.red.withOpacity(0.35)),
          ),
          // Error icon centred
          const Positioned.fill(child: Center(child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.no_food, color: Colors.white, size: 48),
              SizedBox(height: 8),
              Text('Not a food image',
                  style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ))),
        ]),
        const SizedBox(height: 20),
      ],

      // Description card
      Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.red.withOpacity(0.08),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: Colors.red.withOpacity(0.35)),
        ),
        child: Column(children: [
          const Icon(Icons.warning_amber_rounded, color: Colors.redAccent, size: 32),
          const SizedBox(height: 10),
          const Text('We couldn\'t detect any food in this photo.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          const Text(
            'Please take a clear photo of a meal or beverage.\n'
            'Make sure the food is the main subject of the image.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5),
          ),
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity, height: 46,
            child: ElevatedButton.icon(
              onPressed: _resetPhotoState,
              icon: const Icon(Icons.camera_alt),
              label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold)),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent, foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
            ),
          ),
        ]),
      ),
    ]);
  }

  // ── Suggestions (step 3 done) ─────────────────────────────────────────────
  Widget _buildSuggestions() {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      // Photo at top
      if (_capturedImageBytes != null) ...[
        ClipRRect(
          borderRadius: BorderRadius.circular(12),
          child: Image.memory(_capturedImageBytes!,
              width: double.infinity, height: 200, fit: BoxFit.cover),
        ),
        const SizedBox(height: 16),
      ],
      const Text('What did you eat? Select your meal:',
          style: TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.bold)),
      const SizedBox(height: 12),
      ..._mealSuggestions.map((s) => _MealSuggestionCard(
        suggestion: s,
        onConfirm: (grams) => _confirmMeal(s, grams),
      )),
      const SizedBox(height: 8),
      // Reset button
      SizedBox(
        width: double.infinity, height: 44,
        child: OutlinedButton.icon(
          onPressed: _resetPhotoState,
          icon: const Icon(Icons.refresh, size: 18),
          label: const Text('Take a different photo'),
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.grey,
            side: const BorderSide(color: Colors.white12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      ),
    ]);
  }

  // ─────────────────────────────────────────────────────────────────────────
  // SNACK SCAN TAB (unchanged from previous version)
  // ─────────────────────────────────────────────────────────────────────────

  Widget _buildSnackScanTab() {
    return Column(children: [
      if (_isScanning) Expanded(child: Stack(children: [
        MobileScanner(controller: _scannerController, onDetect: _onBarcodeDetected),
        const Center(child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Icon(Icons.qr_code_scanner, color: Colors.greenAccent, size: 80),
          SizedBox(height: 8),
          Text('Point at the barcode on the package',
              style: TextStyle(color: Colors.white, backgroundColor: Colors.black54)),
        ])),
      ])),

      if (_isFetchingProduct) const Expanded(child: Center(child: Column(
        mainAxisAlignment: MainAxisAlignment.center, children: [
          CircularProgressIndicator(color: Colors.greenAccent),
          SizedBox(height: 12),
          Text('Looking up product...', style: TextStyle(color: Colors.grey)),
        ],
      ))),

      if (_scannedProduct != null) Expanded(child: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(_scannedProduct!['name'],
              style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold)),
          const SizedBox(height: 4),
          Text('Per serving (${_scannedProduct!['serving_size_g'].toStringAsFixed(0)}g)',
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          const SizedBox(height: 16),
          _nutritionRow('Calories',
              '${_scannedProduct!['calories_per_100g'] * _scannedProduct!['serving_size_g'] / 100 ~/ 1} kcal',
              Colors.orangeAccent),
          _nutritionRow('Protein',
              '${(_scannedProduct!['protein_per_100g'] * _scannedProduct!['serving_size_g'] / 100).toStringAsFixed(1)}g',
              Colors.blueAccent),
          _nutritionRow('Carbs',
              '${(_scannedProduct!['carbs_per_100g'] * _scannedProduct!['serving_size_g'] / 100).toStringAsFixed(1)}g',
              Colors.greenAccent),
          _nutritionRow('Fat',
              '${(_scannedProduct!['fat_per_100g'] * _scannedProduct!['serving_size_g'] / 100).toStringAsFixed(1)}g',
              Colors.pinkAccent),
          const SizedBox(height: 20),
          const Text('How much did you consume?',
              style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          Row(children: [
            _portionButton('Full', 1.0), const SizedBox(width: 8),
            _portionButton('Half', 0.5), const SizedBox(width: 8),
            _portionButton('¼',   0.25),
          ]),
          const SizedBox(height: 12),
          Text('Custom: ${(_portionFactor * 100).toStringAsFixed(0)}%',
              style: const TextStyle(color: Colors.grey)),
          Slider(
            value: _portionFactor, min: 0.1, max: 1.0, divisions: 9,
            activeColor: Colors.greenAccent, inactiveColor: Colors.grey[700],
            onChanged: (v) => setState(() => _portionFactor = v),
          ),
          const SizedBox(height: 16),
          Row(children: [
            Expanded(child: ElevatedButton(
              onPressed: _confirmSnack,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent, foregroundColor: Colors.black,
                padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Log Snack', style: TextStyle(fontWeight: FontWeight.bold)),
            )),
            const SizedBox(width: 12),
            Expanded(child: ElevatedButton(
              onPressed: _resetScanner,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.grey[800], foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 14)),
              child: const Text('Scan Again'),
            )),
          ]),
        ]),
      )),
    ]);
  }

  Widget _nutritionRow(String label, String value, Color color) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
      Text(label, style: const TextStyle(color: Colors.grey, fontSize: 14)),
      Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 14)),
    ]),
  );

  Widget _portionButton(String label, double value) {
    final sel = _portionFactor == value;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _portionFactor = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: sel ? Colors.greenAccent : Colors.grey[800],
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(color: sel ? Colors.black : Colors.white, fontWeight: FontWeight.bold)),
      ),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// MEAL SUGGESTION CARD
//
// Shown after step 3 completes. Features:
//   - Confidence % bar (green/orange/red)
//   - Source badge (📊 USDA = real database, 🤖 AI estimate = Gemini fallback)
//   - Gram input pre-filled with Gemini's visual estimate
//   - Quick gram chips (100g, 150g, 200g, 250g, 300g, 400g)
//   - Live macro recalculation as grams change
//   - Confirm button showing live kcal count
// ─────────────────────────────────────────────────────────────────────────────
class _MealSuggestionCard extends StatefulWidget {
  final Map<String, dynamic> suggestion;
  final void Function(double grams) onConfirm;
  const _MealSuggestionCard({required this.suggestion, required this.onConfirm});

  @override
  State<_MealSuggestionCard> createState() => _MealSuggestionCardState();
}

class _MealSuggestionCardState extends State<_MealSuggestionCard> {
  late double _grams;
  late TextEditingController _gramsController;

  @override
  void initState() {
    super.initState();
    _grams = _n(widget.suggestion['estimated_grams']);
    if (_grams <= 0) _grams = 100;
    _gramsController = TextEditingController(text: _grams.round().toString());
  }

  @override
  void dispose() { _gramsController.dispose(); super.dispose(); }

  static double _n(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

  double get _cal  => (_n(widget.suggestion['cal_per_100g'])  * _grams / 100).roundToDouble();
  double get _prot => double.parse((_n(widget.suggestion['prot_per_100g']) * _grams / 100).toStringAsFixed(1));
  double get _carb => double.parse((_n(widget.suggestion['carb_per_100g']) * _grams / 100).toStringAsFixed(1));
  double get _fat  => double.parse((_n(widget.suggestion['fat_per_100g'])  * _grams / 100).toStringAsFixed(1));

  double get _confidence {
    final raw = widget.suggestion['confidence'];
    if (raw == null) return 0.75;
    final v = raw is num ? raw.toDouble() : double.tryParse(raw.toString()) ?? 0.75;
    return v > 1.0 ? v / 100.0 : v;
  }

  Color  get _confColor  => _confidence >= 0.75 ? Colors.greenAccent : _confidence >= 0.45 ? Colors.orangeAccent : Colors.redAccent;
  String get _confLabel  => _confidence >= 0.75 ? 'High match' : _confidence >= 0.45 ? 'Possible' : 'Low confidence';
  bool   get _isUSDA     => widget.suggestion['source'] == 'USDA';

  void _updateGrams(String val) {
    final g = double.tryParse(val);
    if (g != null && g > 0 && g <= 2000) setState(() => _grams = g);
  }

  @override
  Widget build(BuildContext context) {
    final name     = widget.suggestion['name']      as String? ?? 'Unknown';
    final usdaName = widget.suggestion['usda_name'] as String?;
    final pct      = (_confidence * 100).round();

    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1A1A1A),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _confColor.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // ── Header ─────────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold)),
                if (usdaName != null && usdaName != name)
                  Text('Matched: $usdaName', style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ])),
              // Source badge: USDA = blue (real data), AI estimate = orange (Gemini)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isUSDA ? Colors.blueAccent.withOpacity(0.15) : Colors.orangeAccent.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _isUSDA ? Colors.blueAccent.withOpacity(0.5) : Colors.orangeAccent.withOpacity(0.5)),
                ),
                child: Text(
                  _isUSDA ? '📊 USDA' : '🤖 AI estimate',
                  style: TextStyle(
                    color: _isUSDA ? Colors.blueAccent : Colors.orangeAccent,
                    fontSize: 10, fontWeight: FontWeight.bold),
                ),
              ),
            ]),
            const SizedBox(height: 10),
            // Confidence progress bar
            Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _confidence, backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(_confColor), minHeight: 5),
              )),
              const SizedBox(width: 8),
              Text('$pct%  $_confLabel',
                  style: TextStyle(color: _confColor, fontSize: 10, fontWeight: FontWeight.bold)),
            ]),
          ]),
        ),

        // ── Gram input ──────────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Estimated portion',
                  style: TextStyle(color: Colors.grey, fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white10, borderRadius: BorderRadius.circular(6)),
                child: const Text('Gemini guessed this — adjust if needed',
                    style: TextStyle(color: Colors.white38, fontSize: 9)),
              ),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              SizedBox(
                width: 110,
                child: TextField(
                  controller: _gramsController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    suffixText: 'g', suffixStyle: const TextStyle(color: Colors.grey, fontSize: 16),
                    filled: true, fillColor: Colors.black38,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
                    enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.white12)),
                    focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: const BorderSide(color: Colors.greenAccent, width: 1.5)),
                  ),
                  onChanged: _updateGrams,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(child: SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [100, 150, 200, 250, 300, 400].map((g) {
                  final sel = (_grams - g).abs() < 1;
                  return GestureDetector(
                    onTap: () => setState(() { _grams = g.toDouble(); _gramsController.text = g.toString(); }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? Colors.greenAccent : Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${g}g', style: TextStyle(
                        color: sel ? Colors.black : Colors.white,
                        fontSize: 12, fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                    ),
                  );
                }).toList()),
              )),
            ]),
          ]),
        ),

        const SizedBox(height: 12),

        // ── Live nutrition (recalculates as grams change) ───────────────
        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(color: Colors.black26, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            _nutriCell('${_cal.round()} kcal', 'Calories', Colors.orangeAccent),
            _vDiv(),
            _nutriCell('${_prot}g', 'Protein', Colors.blueAccent),
            _vDiv(),
            _nutriCell('${_carb}g', 'Carbs', Colors.greenAccent),
            _vDiv(),
            _nutriCell('${_fat}g', 'Fat', Colors.pinkAccent),
          ]),
        ),

        // ── Confirm button ──────────────────────────────────────────────
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: SizedBox(
            width: double.infinity, height: 46,
            child: ElevatedButton(
              onPressed: () => widget.onConfirm(_grams),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.greenAccent, foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Log this  •  ${_cal.round()} kcal',
                  style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _nutriCell(String value, String label, Color color) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 12)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
  ]));

  Widget _vDiv() => Container(width: 1, height: 28, color: Colors.white12);
}