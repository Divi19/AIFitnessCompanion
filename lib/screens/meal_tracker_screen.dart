import 'dart:typed_data';
import 'dart:ui' as ui; // Added for RepaintBoundary image extraction
import 'package:flutter/rendering.dart'; // Added for RepaintBoundary
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../services/gemini_service.dart';
import '../services/meal_service.dart';
import '../widgets/nutrition_summary_card.dart';
import '../models/meal_model.dart';
import 'package:firebase_auth/firebase_auth.dart';

// ─────────────────────────────────────────────────────────────────────────────
// MEAL TRACKER — UNIFIED IPHONE-STYLE SCANNER
//
// One screen. Live camera always running.
// • Barcode drifts into frame → banner slides up → tap "Look up"
// • No barcode → big shutter button → Gemini meal flow
// • Gallery icon for picking from photos
// • ⓘ button → fun explainer bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

enum _AnalysisState {
  idle,
  validating,
  notFood,
  identifying,
  lookingUp,
  done,
}

class MealTrackerScreen extends StatefulWidget {
  const MealTrackerScreen({super.key});

  @override
  State<MealTrackerScreen> createState() => _MealTrackerScreenState();
}

class _MealTrackerScreenState extends State<MealTrackerScreen>
    with WidgetsBindingObserver, SingleTickerProviderStateMixin {
  
  final GlobalKey _cameraKey = GlobalKey(); // Added to capture the live feed

  final MealGeminiService _geminiService = MealGeminiService();
  final MealService       _mealService   = MealService();
  final ImagePicker       _imagePicker   = ImagePicker();

  final MobileScannerController _scannerController = MobileScannerController(
    formats: [
      BarcodeFormat.ean13, BarcodeFormat.ean8,
      BarcodeFormat.upcA,  BarcodeFormat.upcE,
      BarcodeFormat.code128, BarcodeFormat.qrCode,
    ],
    // returnImage: true lets us grab the camera frame on capture
    returnImage: true,
  );

  // ── Photo / Gemini state ──────────────────────────────────────────────────
  _AnalysisState _analysisState = _AnalysisState.idle;
  List<Map<String, dynamic>> _mealSuggestions = [];
  Uint8List? _capturedImageBytes;

  // ── Barcode state ─────────────────────────────────────────────────────────
  String?  _detectedBarcode;
  bool     _showBarcodeBanner  = false;
  bool     _isFetchingProduct  = false;
  bool     _scanLock           = false;
  Map<String, dynamic>? _scannedProduct;
  double   _portionFactor      = 1.0;

  // ── Daily log ─────────────────────────────────────────────────────────────
  List<MealModel> _todaysLogs = [];
  final String _userId = FirebaseAuth.instance.currentUser?.uid ?? 'demo_user';

  // ── Torch ─────────────────────────────────────────────────────────────────
  bool _torchOn = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadTodaysLogs();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (_analysisState != _AnalysisState.idle) return;
    if (state == AppLifecycleState.resumed) {
      _scannerController.start();
    } else if (state == AppLifecycleState.paused ||
               state == AppLifecycleState.inactive) {
      _scannerController.stop();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _scannerController.dispose();
    super.dispose();
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BARCODE FLOW
  // ─────────────────────────────────────────────────────────────────────────

  void _onBarcodeDetected(BarcodeCapture capture) {
    // Don't interrupt an active Gemini analysis or product lookup
    if (_analysisState != _AnalysisState.idle) return;
    if (_scanLock || _isFetchingProduct || _scannedProduct != null) return;

    final raw = capture.barcodes.firstOrNull?.rawValue;
    if (raw == null || raw.isEmpty || raw == _detectedBarcode) return;

    HapticFeedback.lightImpact();
    setState(() {
      _detectedBarcode  = raw;
      _showBarcodeBanner = true;
    });
  }

  Future<void> _confirmBarcode() async {
    if (_detectedBarcode == null) return;
    _scanLock = true;
    _scannerController.stop();

    setState(() {
      _showBarcodeBanner = false;
      _isFetchingProduct = true;
    });

    final product = await _mealService.fetchProductByBarcode(_detectedBarcode!);

    setState(() {
      _isFetchingProduct = false;
      _scannedProduct    = product;
      _portionFactor     = 1.0;
      _detectedBarcode   = null;
    });

    if (product == null) {
      _scanLock = false;
      _scannerController.start();
      _showSnack('Product not found. Try another barcode.', isError: true);
    }
  }

  void _dismissBarcodeBanner() {
    setState(() { _showBarcodeBanner = false; _detectedBarcode = null; });
  }

  Future<void> _confirmSnack() async {
    if (_scannedProduct == null) return;
    final nutrition = _mealService.calculateNutrition(
        productData: _scannedProduct!, portionFactor: _portionFactor);
    await _mealService.logMeal(
      userId: _userId, name: _scannedProduct!['name'], type: 'snack',
      calories: nutrition['calories']!, protein: nutrition['protein']!,
      carbs: nutrition['carbs']!, fat: nutrition['fat']!, portion: _portionFactor,
    );
    setState(() { _scannedProduct = null; _portionFactor = 1.0; _scanLock = false; });
    await _loadTodaysLogs();
    _scannerController.start();
    // _showSnack('${_scannedProduct?['name'] ?? 'Snack'} logged! 🎉');
  }

  void _resetToCamera() {
    _scannerController.start();
    setState(() {
      _scannedProduct    = null;
      _portionFactor     = 1.0;
      _scanLock          = false;
      _detectedBarcode   = null;
      _showBarcodeBanner = false;
      _analysisState     = _AnalysisState.idle;
      _mealSuggestions   = [];
      _capturedImageBytes = null;
    });
  }

  // ─────────────────────────────────────────────────────────────────────────
  // PHOTO / GEMINI FLOW
  // ─────────────────────────────────────────────────────────────────────────

  // Called by shutter button — captures a frame from the live MobileScanner feed.
  // No second camera opened; the live feed IS the camera.
  Future<void> _captureFromScanner() async {
    if (_analysisState != _AnalysisState.idle) return;

    try {
      // Find the visual boundary of the camera and convert it to an image
      RenderRepaintBoundary boundary = _cameraKey.currentContext!.findRenderObject() as RenderRepaintBoundary;
      ui.Image image = await boundary.toImage(pixelRatio: 2.0);
      ByteData? byteData = await image.toByteData(format: ui.ImageByteFormat.png);

      if (byteData != null) {
        final Uint8List bytes = byteData.buffer.asUint8List();
        await _scannerController.stop();
        await _runGeminiFlow(bytes);
      } else {
        _showSnack('Could not capture frame — try again.', isError: true);
      }
    } catch (e) {
      _showSnack('Could not capture frame — try again.', isError: true);
    }
  }

  // Called by gallery button — only image_picker gallery, never camera
  Future<void> _pickFromGallery() async {
    await _scannerController.stop();
    final picked = await _imagePicker.pickImage(
        source: ImageSource.gallery, imageQuality: 85, maxWidth: 1200);
    if (picked == null) { _scannerController.start(); return; }
    final bytes = await picked.readAsBytes();
    await _runGeminiFlow(bytes);
  }

  Future<void> _takeMealPhoto(ImageSource source) async {
    if (source == ImageSource.gallery) { await _pickFromGallery(); return; }
    await _captureFromScanner();
  }

  Future<void> _runGeminiFlow(Uint8List bytes) async {

    setState(() {
      _analysisState      = _AnalysisState.validating;
      _mealSuggestions    = [];
      _capturedImageBytes = bytes;
      _showBarcodeBanner  = false;
      _detectedBarcode    = null;
    });

    // Step 1 — validate
    final isFood = await _geminiService.validateFoodImage(bytes);
    if (!isFood) { setState(() => _analysisState = _AnalysisState.notFood); return; }

    // Step 2 — identify
    setState(() => _analysisState = _AnalysisState.identifying);
    final geminiResults = await _geminiService.classifyMealWithGrams(bytes);

    // Step 3 — USDA enrich
    setState(() => _analysisState = _AnalysisState.lookingUp);
    final enriched = <Map<String, dynamic>>[];
    for (final c in geminiResults) enriched.add(await _mealService.enrichCandidate(c));

    setState(() { _analysisState = _AnalysisState.done; _mealSuggestions = enriched; });
  }

  static double _toDouble(dynamic v) =>
      v == null ? 0.0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0.0);

  Future<void> _confirmMeal(Map<String, dynamic> suggestion, double grams) async {
    final factor = grams / 100.0;
    await _mealService.logMeal(
      userId: _userId, name: suggestion['name'], type: 'meal',
      calories: _toDouble(suggestion['cal_per_100g'])  * factor,
      protein:  _toDouble(suggestion['prot_per_100g']) * factor,
      carbs:    _toDouble(suggestion['carb_per_100g']) * factor,
      fat:      _toDouble(suggestion['fat_per_100g'])  * factor,
      portion:  grams,
    );
    _resetToCamera();
    await _loadTodaysLogs();
    // _showSnack('${suggestion['name']} logged! 🔥');
  }

  // ── Shared helpers ────────────────────────────────────────────────────────

  Future<void> _loadTodaysLogs() async {
    final logs = await _mealService.getTodaysLogs(_userId);
    if (mounted) setState(() => _todaysLogs = logs);
  }

  void _showSnack(String msg, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(msg),
      backgroundColor: isError ? const Color(0xFFFF7B6B) : const Color(0xFF1A1A2E), // Updated FitSense theme
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      duration: const Duration(seconds: 2),
    ));
  }

  // ─────────────────────────────────────────────────────────────────────────
  // INFO BOTTOM SHEET
  // ─────────────────────────────────────────────────────────────────────────

  void _showInfoSheet() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (_) => Container(
        padding: const EdgeInsets.fromLTRB(24, 20, 24, 40),
        decoration: const BoxDecoration(
          color: Color(0xFF1A1A2E), // Updated Background
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 24),
              decoration: BoxDecoration(color: Colors.white24, borderRadius: BorderRadius.circular(2)),
            ),
            const Text('How to use the scanner 📱',
              style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w900)),
            const SizedBox(height: 24),
            _infoTile('🍔', 'Snap your meal',
              'Point at any food and hit the big button. AI will name it, guess the portion, and crunch the macros. No menu needed!'),
            _infoTile('📦', 'Scan a barcode',
              'Drifting a snack packet into frame? The camera auto-spots the barcode and pops up a banner. Tap "Look up" — done.'),
            _infoTile('📸', 'Use your gallery',
              'Already ate? Tap the gallery icon, pick a photo of your plate, and let AI do the detective work.'),
            _infoTile('⚖️', 'Adjust the grams',
              'AI guesses the portion size visually. If your plate was more of a mountain than a hill, just slide or type the real amount.'),
            _infoTile('💡', 'Pro tip',
              'Natural lighting = better AI results. Step away from dramatic shadows for a sec before snapping!'),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _infoTile(String emoji, String title, String body) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(emoji, style: const TextStyle(fontSize: 28)),
          const SizedBox(width: 14),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: const TextStyle(
                  color: Color(0xFFC5F135), fontSize: 14, fontWeight: FontWeight.w800)), // Lime
              const SizedBox(height: 3),
              Text(body, style: const TextStyle(
                  color: Colors.white60, fontSize: 13, height: 1.5)),
            ],
          )),
        ],
      ),
    );
  }

  // ─────────────────────────────────────────────────────────────────────────
  // BUILD
  // ─────────────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final showCamera = _analysisState == _AnalysisState.idle &&
                       _scannedProduct == null &&
                       !_isFetchingProduct;

    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D), // Solid Black background
      body: Stack(
        children: [

          // ── LAYER 1: live camera (REMOVED 'if (showCamera)' SO IT NEVER CRASHES) ──
          Positioned.fill(
            child: RepaintBoundary( 
              key: _cameraKey,
              child: MobileScanner(
                controller: _scannerController,
                onDetect: _onBarcodeDetected,
              ),
            ),
          ),

          // ── LAYER 1.5: Dark background to cover the camera when analysing ──
          if (!showCamera)
            Positioned.fill(child: Container(color: const Color(0xFF0D0D0D))),

          // ── LAYER 2: content overlay ───────────────────────────────────
          Positioned.fill(
            child: Column(
              children: [
                // Safe-area top bar
                SafeArea(
                  bottom: false,
                  child: _buildTopBar(),
                ),

                // Main content area
                Expanded(
                  child: _buildMainContent(),
                ),

                // Daily nutrition summary at bottom
                NutritionSummaryCard(logs: _todaysLogs),

                const SizedBox(height: 8),
              ],
            ),
          ),

          // ── LAYER 3: barcode banner (slides up from bottom of camera area)
          if (showCamera)
            Positioned(
              left: 0, right: 0,
              bottom: _todaysLogs.isEmpty ? 120 : 180,
              child: AnimatedSlide(
                offset: _showBarcodeBanner ? Offset.zero : const Offset(0, 1.5),
                duration: const Duration(milliseconds: 320),
                curve: Curves.easeOutCubic,
                child: AnimatedOpacity(
                  opacity: _showBarcodeBanner ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 200),
                  child: _BarcodeBanner(
                    barcode: _detectedBarcode ?? '',
                    onConfirm: _confirmBarcode,
                    onDismiss: _dismissBarcodeBanner,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  // ── Top bar ───────────────────────────────────────────────────────────────
  Widget _buildTopBar() {
    final showCamera = _analysisState == _AnalysisState.idle &&
                       _scannedProduct == null &&
                       !_isFetchingProduct;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      child: Row(
        children: [
          // Back / close button when not in camera mode
          if (!showCamera)
            GestureDetector(
              onTap: _resetToCamera,
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.white10,
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.white12),
                ),
                child: const Icon(Icons.arrow_back_ios_new_rounded,
                    color: Colors.white, size: 16),
              ),
            )
          else
            // Torch toggle
            GestureDetector(
              onTap: () {
                _scannerController.toggleTorch();
                setState(() => _torchOn = !_torchOn);
              },
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: _torchOn
                      ? const Color(0xFFC5F135).withOpacity(0.15)
                      : Colors.black45,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: _torchOn
                        ? const Color(0xFFC5F135).withOpacity(0.5)
                        : Colors.white12),
                ),
                child: Icon(
                  _torchOn ? Icons.flashlight_on_rounded : Icons.flashlight_off_rounded,
                  color: _torchOn ? const Color(0xFFC5F135) : Colors.white,
                  size: 18,
                ),
              ),
            ),

          const Spacer(),

          // Title
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(
              color: Colors.black54,
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.bolt, color: Color(0xFFC5F135), size: 16),
                const SizedBox(width: 4),
                Text(
                  showCamera ? 'Meal Scanner' : _topBarLabel(),
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ],
            ),
          ),

          const Spacer(),

          // Info button
          GestureDetector(
            onTap: _showInfoSheet,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black45,
                shape: BoxShape.circle,
                border: Border.all(color: Colors.white12),
              ),
              child: const Icon(Icons.info_outline_rounded,
                  color: Colors.white70, size: 18),
            ),
          ),
        ],
      ),
    );
  }

  String _topBarLabel() {
    if (_isFetchingProduct) return 'Looking up...';
    if (_scannedProduct != null) return 'Product found';
    return switch (_analysisState) {
      _AnalysisState.validating  => 'Checking image...',
      _AnalysisState.notFood     => 'Not food!',
      _AnalysisState.identifying => 'Identifying...',
      _AnalysisState.lookingUp   => 'Fetching nutrition...',
      _AnalysisState.done        => 'Pick your meal',
      _AnalysisState.idle        => 'Meal Scanner',
    };
  }

  // ── Main content switcher ─────────────────────────────────────────────────
  Widget _buildMainContent() {
    // Product card after barcode lookup
    if (_scannedProduct != null) return _buildProductCard();

    // Fetching product spinner
    if (_isFetchingProduct) return _buildSpinner('Looking up product...', emoji: '📦');

    return switch (_analysisState) {
      _AnalysisState.idle        => _buildCameraIdleOverlay(),
      _AnalysisState.validating  => _buildAnalysisLoading('Checking if this is food...', '🔍', _capturedImageBytes),
      _AnalysisState.notFood     => _buildNotFoodState(),
      _AnalysisState.identifying => _buildAnalysisLoading('Identifying your meal...', '🍽️', _capturedImageBytes),
      _AnalysisState.lookingUp   => _buildAnalysisLoading('Fetching nutrition data...', '📊', _capturedImageBytes),
      _AnalysisState.done        => _buildSuggestions(),
    };
  }

  // ── Camera idle overlay (viewfinder + shutter + gallery) ─────────────────
  Widget _buildCameraIdleOverlay() {
    return Stack(
      children: [
        // Scan frame hint in centre
        Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Corner bracket frame
              SizedBox(
                width: 220, height: 160,
                child: CustomPaint(painter: _BracketPainter(
                    color: _showBarcodeBanner
                        ? const Color(0xFFC5F135)
                        : Colors.white38)),
              ),
              const SizedBox(height: 14),
              AnimatedOpacity(
                opacity: _showBarcodeBanner ? 0.0 : 1.0,
                duration: const Duration(milliseconds: 200),
                child: Text(
                  'Point at food or a barcode',
                  style: TextStyle(
                    color: Colors.white.withOpacity(0.5),
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ),
            ],
          ),
        ),

        // Bottom controls: gallery | shutter | flip
        Positioned(
          left: 0, right: 0, bottom: 24,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 48),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                // Gallery
                _CamButton(
                  icon: Icons.photo_library_rounded,
                  onTap: _pickFromGallery,
                  label: 'Gallery',
                ),

                // Shutter — captures from the live MobileScanner feed, no second camera
                GestureDetector(
                  onTap: _captureFromScanner,
                  child: Container(
                    width: 76, height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: const Color(0xFFC5F135),
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFC5F135).withOpacity(0.4),
                          blurRadius: 22, spreadRadius: 4,
                        ),
                      ],
                    ),
                    child: const Icon(Icons.camera_alt_rounded,
                        color: Colors.black, size: 32),
                  ),
                ),

                // Flip
                _CamButton(
                  icon: Icons.cameraswitch_rounded,
                  onTap: _scannerController.switchCamera,
                  label: 'Flip',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  // ── Analysis loading (steps 1-3) ──────────────────────────────────────────
  Widget _buildAnalysisLoading(String msg, String emoji, Uint8List? photo) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        if (photo != null) ...[
          ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Image.memory(photo,
                width: double.infinity, height: 220, fit: BoxFit.cover),
          ),
          const SizedBox(height: 20),
        ],
        Text(emoji, style: const TextStyle(fontSize: 40)),
        const SizedBox(height: 14),
        const CircularProgressIndicator(
            strokeWidth: 2.5, color: Color(0xFFC5F135)),
        const SizedBox(height: 12),
        Text(msg, style: const TextStyle(
            color: Colors.white70, fontSize: 15, fontWeight: FontWeight.w600)),
      ]),
    );
  }

  Widget _buildSpinner(String msg, {String emoji = '⏳'}) {
    return Center(child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(emoji, style: const TextStyle(fontSize: 44)),
        const SizedBox(height: 16),
        const CircularProgressIndicator(strokeWidth: 2.5, color: Color(0xFFC5F135)),
        const SizedBox(height: 12),
        Text(msg, style: const TextStyle(color: Colors.white54, fontSize: 14)),
      ],
    ));
  }

  // ── Not food ──────────────────────────────────────────────────────────────
  Widget _buildNotFoodState() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(children: [
        if (_capturedImageBytes != null) ...[
          Stack(children: [
            ClipRRect(borderRadius: BorderRadius.circular(16),
              child: Image.memory(_capturedImageBytes!,
                  width: double.infinity, height: 220, fit: BoxFit.cover)),
            ClipRRect(borderRadius: BorderRadius.circular(16),
              child: Container(width: double.infinity, height: 220,
                  color: const Color(0xFFFF7B6B).withOpacity(0.35))), // Coral
            const Positioned.fill(child: Center(child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.no_food, color: Colors.white, size: 48),
                SizedBox(height: 8),
                Text('Hmm, that doesn\'t look like food',
                    style: TextStyle(color: Colors.white,
                        fontSize: 15, fontWeight: FontWeight.bold)),
              ],
            ))),
          ]),
          const SizedBox(height: 20),
        ],
        Container(
          padding: const EdgeInsets.all(20),
          decoration: BoxDecoration(
            color: const Color(0xFFFF7B6B).withOpacity(0.08),
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFFF7B6B).withOpacity(0.35)),
          ),
          child: Column(children: [
            const Text('We couldn\'t spot any food here.',
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.w700)),
            const SizedBox(height: 8),
            const Text(
              'Try making the food the main subject,\n'
              'in good lighting, without too much clutter.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 13, height: 1.5)),
            const SizedBox(height: 16),
            SizedBox(width: double.infinity, height: 46,
              child: ElevatedButton.icon(
                onPressed: _resetToCamera,
                icon: const Icon(Icons.camera_alt),
                label: const Text('Try Again', style: TextStyle(fontWeight: FontWeight.bold)),
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFC5F135),
                  foregroundColor: Colors.black,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
              ),
            ),
          ]),
        ),
      ]),
    );
  }

  // ── Meal suggestions ──────────────────────────────────────────────────────
  Widget _buildSuggestions() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        if (_capturedImageBytes != null) ...[
          ClipRRect(borderRadius: BorderRadius.circular(14),
            child: Image.memory(_capturedImageBytes!,
                width: double.infinity, height: 190, fit: BoxFit.cover)),
          const SizedBox(height: 16),
        ],
        const Text('Which one is your meal?',
            style: TextStyle(color: Colors.white,
                fontSize: 16, fontWeight: FontWeight.w800)),
        const SizedBox(height: 12),
        ..._mealSuggestions.map((s) => _MealSuggestionCard(
          suggestion: s,
          onConfirm: (grams) => _confirmMeal(s, grams),
        )),
        const SizedBox(height: 8),
        SizedBox(width: double.infinity, height: 44,
          child: OutlinedButton.icon(
            onPressed: _resetToCamera,
            icon: const Icon(Icons.camera_alt_rounded, size: 16),
            label: const Text('Take a different photo'),
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey,
              side: const BorderSide(color: Colors.white12),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Product card (barcode flow) ───────────────────────────────────────────
  Widget _buildProductCard() {
    final p = _scannedProduct!;
    final servG = p['serving_size_g'] as double;

    double macro(String key) =>
        (p['${key}_per_100g'] as double) * servG / 100 * _portionFactor;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        // Product name + source
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF1A1A2E), // Dark Surface
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: const Color(0xFFC5F135).withOpacity(0.3)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('📦', style: TextStyle(fontSize: 22)),
              const SizedBox(width: 10),
              Expanded(child: Text(p['name'],
                  style: const TextStyle(color: Colors.white,
                      fontSize: 17, fontWeight: FontWeight.w800))),
            ]),
            const SizedBox(height: 6),
            Text('Per serving  ${servG.toStringAsFixed(0)}g',
                style: const TextStyle(color: Colors.white38, fontSize: 12)),

            const SizedBox(height: 16),

            // Macros row
            Row(children: [
              _macroCell('${macro('calories').round()} kcal', 'Calories', Colors.white), // White for Calories
              _macroCell('${macro('protein').toStringAsFixed(1)}g', 'Protein', const Color(0xFF9B8FFF)), // Purple for Protein
              _macroCell('${macro('carbs').toStringAsFixed(1)}g', 'Carbs', const Color(0xFFC5F135)), // Lime for Carbs
              _macroCell('${macro('fat').toStringAsFixed(1)}g', 'Fat', const Color(0xFFFF7B6B)), // Coral for Fat
            ]),

            const SizedBox(height: 20),

            const Text('How much did you eat?',
                style: TextStyle(color: Colors.white70,
                    fontSize: 13, fontWeight: FontWeight.w700)),
            const SizedBox(height: 10),

            // Portion chips
            Row(children: [
              _portionChip('Full', 1.0),
              const SizedBox(width: 8),
              _portionChip('Half', 0.5),
              const SizedBox(width: 8),
              _portionChip('¼', 0.25),
            ]),

            const SizedBox(height: 10),

            Slider(
              value: _portionFactor, min: 0.1, max: 1.0, divisions: 9,
              activeColor: const Color(0xFFC5F135),
              inactiveColor: Colors.white12,
              onChanged: (v) => setState(() => _portionFactor = v),
            ),
            Text('${(_portionFactor * 100).round()}% of a serving',
                style: const TextStyle(color: Colors.white38, fontSize: 11)),
          ]),
        ),

        const SizedBox(height: 14),

        Row(children: [
          Expanded(child: ElevatedButton(
            onPressed: _confirmSnack,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFC5F135), foregroundColor: Colors.black,
              padding: const EdgeInsets.symmetric(vertical: 14),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: Text('Log  •  ${macro('calories').round()} kcal',
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
          )),
          const SizedBox(width: 12),
          OutlinedButton(
            onPressed: _resetToCamera,
            style: OutlinedButton.styleFrom(
              foregroundColor: Colors.grey,
              side: const BorderSide(color: Colors.white12),
              padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('Scan again'),
          ),
        ]),
      ]),
    );
  }

  Widget _macroCell(String value, String label, Color color) => Expanded(child: Column(children: [
    Text(value, style: TextStyle(color: color, fontWeight: FontWeight.bold, fontSize: 13)),
    const SizedBox(height: 2),
    Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
  ]));

  Widget _portionChip(String label, double value) {
    final sel = (_portionFactor - value).abs() < 0.01;
    return Expanded(child: GestureDetector(
      onTap: () => setState(() => _portionFactor = value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 9),
        decoration: BoxDecoration(
          color: sel ? const Color(0xFFC5F135) : Colors.white10,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(label, textAlign: TextAlign.center,
            style: TextStyle(
              color: sel ? Colors.black : Colors.white,
              fontWeight: sel ? FontWeight.bold : FontWeight.normal,
              fontSize: 13,
            )),
      ),
    ));
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// BARCODE BANNER
// ─────────────────────────────────────────────────────────────────────────────
class _BarcodeBanner extends StatelessWidget {
  final String barcode;
  final VoidCallback onConfirm;
  final VoidCallback onDismiss;

  const _BarcodeBanner({
    required this.barcode,
    required this.onConfirm,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A2E), // Dark Surface
          borderRadius: BorderRadius.circular(18),
          border: Border.all(
              color: const Color(0xFFC5F135).withOpacity(0.6), width: 1.5),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFC5F135).withOpacity(0.12),
              blurRadius: 20, spreadRadius: 2,
            ),
          ],
        ),
        child: Row(children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFFC5F135).withOpacity(0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(Icons.qr_code_scanner_rounded,
                color: Color(0xFFC5F135), size: 20),
          ),
          const SizedBox(width: 10),
          Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            const Text('Barcode detected!',
                style: TextStyle(color: Color(0xFFC5F135),
                    fontSize: 12, fontWeight: FontWeight.w800)),
            Text(barcode,
                style: TextStyle(color: Colors.white.withOpacity(0.45),
                    fontSize: 10, fontFamily: 'monospace'),
                maxLines: 1, overflow: TextOverflow.ellipsis),
          ])),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onDismiss,
            child: const Icon(Icons.close_rounded, color: Colors.white30, size: 18)),
          const SizedBox(width: 8),
          GestureDetector(
            onTap: onConfirm,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: const Color(0xFFC5F135),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Text('Look up',
                  style: TextStyle(color: Colors.black,
                      fontSize: 13, fontWeight: FontWeight.w800)),
            ),
          ),
        ]),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// SMALL CAMERA BUTTON (gallery / flip)
// ─────────────────────────────────────────────────────────────────────────────
class _CamButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback onTap;
  final String label;

  const _CamButton({required this.icon, required this.onTap, required this.label});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 52, height: 52,
            decoration: BoxDecoration(
              color: Colors.black45,
              shape: BoxShape.circle,
              border: Border.all(color: Colors.white24),
            ),
            child: Icon(icon, color: Colors.white, size: 22),
          ),
          const SizedBox(height: 5),
          Text(label, style: TextStyle(
              color: Colors.white.withOpacity(0.55), fontSize: 11)),
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// CORNER BRACKET PAINTER
// ─────────────────────────────────────────────────────────────────────────────
class _BracketPainter extends CustomPainter {
  final Color color;
  _BracketPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;

    const r = 10.0;
    const l = 24.0;
    final w = size.width;
    final h = size.height;

    // top-left
    canvas.drawLine(Offset(r, 0), Offset(l, 0), paint);
    canvas.drawLine(Offset(0, r), Offset(0, l), paint);
    // top-right
    canvas.drawLine(Offset(w - r, 0), Offset(w - l, 0), paint);
    canvas.drawLine(Offset(w, r), Offset(w, l), paint);
    // bottom-left
    canvas.drawLine(Offset(0, h - r), Offset(0, h - l), paint);
    canvas.drawLine(Offset(r, h), Offset(l, h), paint);
    // bottom-right
    canvas.drawLine(Offset(w, h - r), Offset(w, h - l), paint);
    canvas.drawLine(Offset(w - r, h), Offset(w - l, h), paint);
  }

  @override
  bool shouldRepaint(_BracketPainter old) => old.color != color;
}

// ─────────────────────────────────────────────────────────────────────────────
// MEAL SUGGESTION CARD (unchanged logic, same as before)
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

  Color  get _confColor => _confidence >= 0.75 ? const Color(0xFFC5F135) : _confidence >= 0.45 ? const Color(0xFFFF7B6B) : const Color(0xFFFF7B6B);
  String get _confLabel => _confidence >= 0.75 ? 'High match' : _confidence >= 0.45 ? 'Possible' : 'Low confidence';
  bool   get _isUSDA    => widget.suggestion['source'] == 'USDA';

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
        color: const Color(0xFF1A1A2E), // Dark Surface
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: _confColor.withOpacity(0.35)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [

        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(name, style: const TextStyle(color: Colors.white,
                    fontSize: 16, fontWeight: FontWeight.bold)),
                if (usdaName != null && usdaName != name)
                  Text('Matched: $usdaName',
                      style: const TextStyle(color: Colors.white38, fontSize: 11)),
              ])),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: _isUSDA
                      ? const Color(0xFF9B8FFF).withOpacity(0.15)
                      : const Color(0xFFFF7B6B).withOpacity(0.15),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: _isUSDA
                      ? const Color(0xFF9B8FFF).withOpacity(0.5)
                      : const Color(0xFFFF7B6B).withOpacity(0.5)),
                ),
                child: Text(_isUSDA ? '📊 USDA' : '🤖 AI estimate',
                    style: TextStyle(
                      color: _isUSDA ? const Color(0xFF9B8FFF) : const Color(0xFFFF7B6B),
                      fontSize: 10, fontWeight: FontWeight.bold)),
              ),
            ]),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: LinearProgressIndicator(
                  value: _confidence, backgroundColor: Colors.white12,
                  valueColor: AlwaysStoppedAnimation(_confColor), minHeight: 5),
              )),
              const SizedBox(width: 8),
              Text('$pct%  $_confLabel',
                  style: TextStyle(color: _confColor,
                      fontSize: 10, fontWeight: FontWeight.bold)),
            ]),
          ]),
        ),

        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              const Text('Estimated portion',
                  style: TextStyle(color: Colors.grey,
                      fontSize: 12, fontWeight: FontWeight.bold)),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(color: Colors.white10,
                    borderRadius: BorderRadius.circular(6)),
                child: const Text('Adjust if needed',
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
                  style: const TextStyle(color: Colors.white,
                      fontSize: 18, fontWeight: FontWeight.bold),
                  decoration: InputDecoration(
                    suffixText: 'g',
                    suffixStyle: const TextStyle(color: Colors.grey, fontSize: 16),
                    filled: true, fillColor: Colors.black38,
                    contentPadding: const EdgeInsets.symmetric(
                        horizontal: 14, vertical: 10),
                    border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12)),
                    enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(color: Colors.white12)),
                    focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(10),
                        borderSide: const BorderSide(
                            color: Color(0xFFC5F135), width: 1.5)),
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
                    onTap: () => setState(() {
                      _grams = g.toDouble();
                      _gramsController.text = g.toString();
                    }),
                    child: Container(
                      margin: const EdgeInsets.only(right: 6),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: sel ? const Color(0xFFC5F135) : Colors.grey[800],
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text('${g}g', style: TextStyle(
                          color: sel ? Colors.black : Colors.white,
                          fontSize: 12,
                          fontWeight: sel ? FontWeight.bold : FontWeight.normal)),
                    ),
                  );
                }).toList()),
              )),
            ]),
          ]),
        ),

        const SizedBox(height: 12),

        Container(
          margin: const EdgeInsets.symmetric(horizontal: 12),
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 8),
          decoration: BoxDecoration(
              color: Colors.black26, borderRadius: BorderRadius.circular(12)),
          child: Row(children: [
            _nutriCell('${_cal.round()} kcal', 'Calories', Colors.white), // Calories White
            _vDiv(),
            _nutriCell('${_prot}g', 'Protein', const Color(0xFF9B8FFF)), // Protein Purple
            _vDiv(),
            _nutriCell('${_carb}g', 'Carbs', const Color(0xFFC5F135)), // Carbs Lime
            _vDiv(),
            _nutriCell('${_fat}g', 'Fat', const Color(0xFFFF7B6B)), // Fat Coral
          ]),
        ),

        Padding(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 14),
          child: SizedBox(
            width: double.infinity, height: 46,
            child: ElevatedButton(
              onPressed: () => widget.onConfirm(_grams),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFFC5F135),
                foregroundColor: Colors.black,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12)),
                elevation: 0,
              ),
              child: Text('Log this  •  ${_cal.round()} kcal',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 14)),
            ),
          ),
        ),
      ]),
    );
  }

  Widget _nutriCell(String value, String label, Color color) =>
      Expanded(child: Column(children: [
        Text(value, style: TextStyle(color: color,
            fontWeight: FontWeight.bold, fontSize: 12)),
        const SizedBox(height: 2),
        Text(label, style: const TextStyle(color: Colors.grey, fontSize: 10)),
      ]));

  Widget _vDiv() => Container(width: 1, height: 28, color: Colors.white12); 
}