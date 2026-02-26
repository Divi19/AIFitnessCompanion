import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';
import '../../services/gemini_service.dart';
import '../../services/knowledge_base_service.dart';

class AdminIngestionScreen extends StatefulWidget {
  const AdminIngestionScreen({super.key});

  @override
  State<AdminIngestionScreen> createState() => _AdminIngestionScreenState();
}

class _AdminIngestionScreenState extends State<AdminIngestionScreen> {
  final _geminiService = GeminiService();
  final _knowledgeBaseService = KnowledgeBaseService();

  bool _isProcessing = false;
  String _statusMessage = 'No file selected. Tap the button to begin.';
  int _totalChunks = 0;
  int _processedChunks = 0;
  final List<String> _completedFiles = [];

  // ── STEP 1: REQUEST PERMISSION THEN OPEN FILE PICKER ──────────────────────
  Future<void> _pickAndIngestPdf() async {
    // Request storage permission — required to access Downloads on Android
    final storageStatus = await Permission.storage.request();
    final mediaStatus = await Permission.manageExternalStorage.request();

    // On Android 13+ storage permission is auto-granted, so we proceed even
    // if it says denied (the newer READ_MEDIA_* permissions take over)
    if (storageStatus.isPermanentlyDenied && mediaStatus.isPermanentlyDenied) {
      setState(() {
        _statusMessage =
            'Storage permission permanently denied.\n'
            'Go to App Settings → Permissions → Storage and enable it.';
      });
      await openAppSettings();
      return;
    }

    FilePickerResult? result;
    try {
      result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['pdf'],
        withData: true,         // load bytes directly into memory
        allowMultiple: false,
        allowCompression: false,
      );
    } catch (e) {
      setState(() => _statusMessage = 'File picker error: $e');
      return;
    }

    if (result == null || result.files.isEmpty) {
      setState(() => _statusMessage = 'No file selected.');
      return;
    }

    final file = result.files.single;

    if (file.bytes == null) {
      setState(() {
        _statusMessage =
            'Could not read file bytes.\n'
            'Try using adb to push the PDF:\n'
            'adb push yourfile.pdf /sdcard/Download/';
      });
      return;
    }

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Reading PDF: ${file.name}...';
    });

    await _processPdf(fileBytes: file.bytes!, fileName: file.name);
  }

  // ── STEP 2: EXTRACT → CHUNK → EMBED → STORE ───────────────────────────────
  Future<void> _processPdf({
    required List<int> fileBytes,
    required String fileName,
  }) async {
    try {
      // EXTRACT — pull all text out of the PDF
      final document = PdfDocument(inputBytes: fileBytes);
      final extractor = PdfTextExtractor(document);
      final fullText = extractor.extractText();
      document.dispose();

      if (fullText.trim().isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'No text extracted from "$fileName".\n'
              'This PDF may be scanned/image-based and cannot be processed.';
        });
        return;
      }

      setState(() => _statusMessage = 'Text extracted. Splitting into chunks...');

      // CHUNK — split on double newlines, drop anything too short to be useful
      final rawChunks = fullText
          .split(RegExp(r'\n{2,}'))
          .map((s) => s.trim())
          .where((s) {
            // Filter out chunks that look like garbled OCR output —
            // real English text has a much higher ratio of letters to symbols
            final letters = s.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
            final ratio = letters / s.length;
            return s.length > 150 && ratio > 0.4; // at least 40% must be real letters
          })          
          .toList();

      if (rawChunks.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'No usable chunks found in "$fileName".\n'
              'The PDF may not have paragraph breaks. Try a different file.';
        });
        return;
      }

      setState(() {
        _totalChunks = rawChunks.length;
        _processedChunks = 0;
        _statusMessage = 'Found $_totalChunks chunks. Starting embedding...';
      });

      // EMBED & STORE — one chunk at a time to stay within Gemini rate limits
      for (int i = 0; i < rawChunks.length; i++) {
        final chunk = rawChunks[i];

        setState(() {
          _processedChunks = i + 1;
          _statusMessage =
              '[$fileName]\nEmbedding chunk ${i + 1} of $_totalChunks...';
        });

        final embedding = await _geminiService.getEmbedding(chunk);

        await _knowledgeBaseService.saveChunk(
          text: chunk,
          source: fileName,
          category: _inferCategory(chunk),
          embedding: embedding,
        );

        // Polite delay — avoids Gemini free tier rate limit (1500 req/min)
        await Future.delayed(const Duration(milliseconds: 300));
      }

      _completedFiles.add('$fileName — $_totalChunks chunks');

      setState(() {
        _isProcessing = false;
        _totalChunks = 0;
        _processedChunks = 0;
        _statusMessage =
            'Done! Chunks from "$fileName" saved.\n'
            'You can now select another PDF.';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = 'Error processing "$fileName":\n${e.toString()}';
      });
    }
  }

  // ── CATEGORY INFERENCE ─────────────────────────────────────────────────────
  String _inferCategory(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('protein') ||
        lower.contains('calorie') ||
        lower.contains('macro') ||
        lower.contains('nutrition') ||
        lower.contains('dietary')) return 'nutrition';
    if (lower.contains('recovery') ||
        lower.contains('rest') ||
        lower.contains('sleep') ||
        lower.contains('fatigue')) return 'recovery';
    if (lower.contains('hypertrophy') ||
        lower.contains('muscle') ||
        lower.contains('strength') ||
        lower.contains('resistance')) return 'hypertrophy';
    if (lower.contains('injury') ||
        lower.contains('rehabilitation') ||
        lower.contains('pain') ||
        lower.contains('therapy')) return 'rehabilitation';
    return 'general';
  }

  // ── UI ─────────────────────────────────────────────────────────────────────
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Admin — PDF Ingestion'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [

            // ── Progress bar ──────────────────────────────────────────────
            if (_isProcessing) ...[
              LinearProgressIndicator(
                value: _totalChunks > 0
                    ? _processedChunks / _totalChunks
                    : null,
                backgroundColor: Colors.grey[200],
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 8),
              Text(
                _totalChunks > 0
                    ? '$_processedChunks / $_totalChunks chunks'
                    : 'Processing...',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
            ],

            // ── Status message ────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(8),
              ),
              child: Text(
                _statusMessage,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14),
              ),
            ),

            const SizedBox(height: 24),

            // ── Select PDF button ─────────────────────────────────────────
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _pickAndIngestPdf,
              icon: const Icon(Icons.upload_file),
              label: Text(
                _isProcessing ? 'Processing...' : 'Select PDF & Ingest',
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: Colors.grey[300],
              ),
            ),

            const SizedBox(height: 12),

            // ── ADB tip box ───────────────────────────────────────────────
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Text(
                '💡 If PDFs don\'t appear in the picker:\n'
                'Run on your laptop terminal:\n'
                'adb push yourfile.pdf /sdcard/Download/\n\n'
                'Then tap ☰ menu in the picker → select Downloads',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ),

            const SizedBox(height: 24),

            // ── Completed files log ───────────────────────────────────────
            if (_completedFiles.isNotEmpty) ...[
              const Text(
                'Completed this session:',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _completedFiles.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(
                      _completedFiles[index],
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ),
            ] else
              const Expanded(child: SizedBox()),

            // ── Footer ────────────────────────────────────────────────────
            const Text(
              'Run once per PDF. Do not close the app while processing.\n'
              'Verify in Firebase Console → Firestore → knowledge_base.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}