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
    final storageStatus = await Permission.storage.request();
    final mediaStatus = await Permission.manageExternalStorage.request();

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
        withData: true,
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

  // ── STEP 1.5: CHARACTER-BASED CHUNKING (FIXES "NO SPACES" BUG) ────────────
  List<String> _cleanAndChunkText(String fullText) {
    // 1. Clean the noise (TOC dots, URLs, Page headers, extra spaces)
    String cleaned = fullText
        .replaceAll(RegExp(r'\.{5,}'), ' ') 
        .replaceAll(RegExp(r'Page [ivx0-9]+ \|.*'), ' ') 
        .replaceAll(RegExp(r'https?://[^\s]+'), ' ') 
        .replaceAll(RegExp(r'\s+'), ' ') 
        .trim();

    List<String> chunks = [];
    
    // 2. Chunk by CHARACTERS instead of WORDS to bypass font-encoding glitches
    const int chunkSize = 1500; // Roughly equivalent to 300 words
    const int overlap = 250;    // Roughly equivalent to 50 words overlap

    for (int i = 0; i < cleaned.length; i += (chunkSize - overlap)) {
      int end = (i + chunkSize < cleaned.length) ? i + chunkSize : cleaned.length;
      String chunk = cleaned.substring(i, end);

      // Filter out garbage/legal-heavy chunks based on letter ratio
      final letters = chunk.replaceAll(RegExp(r'[^a-zA-Z]'), '').length;
      final ratio = letters / chunk.length;
      
      if (chunk.length > 150 && ratio > 0.6) {
        chunks.add(chunk);
      }

      // Stop if we've reached the end of the document
      if (end == cleaned.length) break;
    }

    return chunks;
  }

  // ── STEP 2: EXTRACT → CHUNK → EMBED → STORE ───────────────────────────────
  Future<void> _processPdf({
    required List<int> fileBytes,
    required String fileName,
  }) async {
    try {
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

      setState(() => _statusMessage = 'Text extracted. Cleaning & chunking...');

      final readyChunks = _cleanAndChunkText(fullText);

      if (readyChunks.isEmpty) {
        setState(() {
          _isProcessing = false;
          _statusMessage =
              'No usable chunks found in "$fileName" after cleaning.\n'
              'The PDF might be purely legal disclaimers or formatting noise.';
        });
        return;
      }

      setState(() {
        _totalChunks = readyChunks.length;
        _processedChunks = 0;
        _statusMessage = 'Found $_totalChunks optimized chunks. Starting embedding...';
      });

      for (int i = 0; i < readyChunks.length; i++) {
        final chunk = readyChunks[i];

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

        await Future.delayed(const Duration(milliseconds: 300));
      }

      _completedFiles.add('$fileName — $_totalChunks chunks');

      setState(() {
        _isProcessing = false;
        _totalChunks = 0;
        _processedChunks = 0;
        _statusMessage =
            'Done! Optimized chunks from "$fileName" saved.\n'
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
    if (lower.contains('protein') || lower.contains('calorie') || lower.contains('macro') || lower.contains('nutrition') || lower.contains('dietary')) return 'nutrition';
    if (lower.contains('recovery') || lower.contains('rest') || lower.contains('sleep') || lower.contains('fatigue')) return 'recovery';
    if (lower.contains('hypertrophy') || lower.contains('muscle') || lower.contains('strength') || lower.contains('resistance')) return 'hypertrophy';
    if (lower.contains('injury') || lower.contains('rehabilitation') || lower.contains('pain') || lower.contains('therapy')) return 'rehabilitation';
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
            if (_isProcessing) ...[
              LinearProgressIndicator(
                value: _totalChunks > 0 ? _processedChunks / _totalChunks : null,
                backgroundColor: Colors.grey[200],
                color: Colors.deepPurple,
              ),
              const SizedBox(height: 8),
              Text(
                _totalChunks > 0 ? '$_processedChunks / $_totalChunks chunks' : 'Processing...',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 12),
            ],
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
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _pickAndIngestPdf,
              icon: const Icon(Icons.upload_file),
              label: Text(_isProcessing ? 'Processing...' : 'Select PDF & Ingest'),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.deepPurple,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 16),
                disabledBackgroundColor: Colors.grey[300],
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: const Text(
                '💡 If PDFs don\'t appear in the picker:\nRun on your laptop terminal:\nadb push yourfile.pdf /sdcard/Download/\n\nThen tap ☰ menu in the picker → select Downloads',
                style: TextStyle(fontSize: 12, color: Colors.blue),
              ),
            ),
            const SizedBox(height: 24),
            if (_completedFiles.isNotEmpty) ...[
              const Text('Completed this session:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: _completedFiles.length,
                  itemBuilder: (context, index) => Padding(
                    padding: const EdgeInsets.symmetric(vertical: 3),
                    child: Text(_completedFiles[index], style: const TextStyle(fontSize: 13)),
                  ),
                ),
              ),
            ] else
              const Expanded(child: SizedBox()),
            const Text(
              'Run once per PDF. Do not close the app while processing.\nVerify in Firebase Console → Firestore → knowledge_base.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 11),
            ),
          ],
        ),
      ),
    );
  }
}