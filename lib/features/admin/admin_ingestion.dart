import 'package:flutter/material.dart';
import 'package:file_picker/file_picker.dart';
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

  /// Step 1: Let the user pick a PDF file from their device.
  Future<void> _pickAndIngestPdf() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['pdf'],
      withData: true, // loads file bytes directly into memory
    );

    if (result == null || result.files.single.bytes == null) {
      setState(() => _statusMessage = 'No file selected.');
      return;
    }

    final fileBytes = result.files.single.bytes!;
    final fileName = result.files.single.name;

    setState(() {
      _isProcessing = true;
      _statusMessage = 'Reading PDF: $fileName...';
    });

    await _processPdf(fileBytes: fileBytes, fileName: fileName);
  }

  /// Step 2: Extract text, chunk it, embed each chunk, save to Firestore.
  Future<void> _processPdf({
    required List<int> fileBytes,
    required String fileName,
  }) async {
    try {
      // --- EXTRACT ---
      // Load the PDF document from raw bytes using the Syncfusion package
      final document = PdfDocument(inputBytes: fileBytes);
      final extractor = PdfTextExtractor(document);
      final fullText = extractor.extractText();
      document.dispose();

      setState(() => _statusMessage = 'Text extracted. Splitting into chunks...');

      // --- CHUNK ---
      // Split the full text into paragraphs using double newlines as separators.
      // Filter out chunks shorter than 100 characters to remove headers and noise.
      final rawChunks = fullText
          .split(RegExp(r'\n{2,}'))
          .map((s) => s.trim())
          .where((s) => s.length > 100)
          .toList();

      setState(() {
        _totalChunks = rawChunks.length;
        _statusMessage = 'Found $_totalChunks chunks. Starting embedding...';
      });

      // --- EMBED & STORE ---
      // Loop through every chunk, get its embedding vector, then save to Firestore.
      // Process one at a time to avoid hitting Gemini API rate limits.
      for (int i = 0; i < rawChunks.length; i++) {
        final chunk = rawChunks[i];

        setState(() {
          _processedChunks = i + 1;
          _statusMessage = 'Embedding chunk ${i + 1} of $_totalChunks...';
        });

        // Call Gemini Embedding model to get a vector for this chunk
        final embedding = await _geminiService.getEmbedding(chunk);

        // Save chunk text + vector to Firestore
        await _knowledgeBaseService.saveChunk(
          text: chunk,
          source: fileName,
          category: _inferCategory(chunk),
          embedding: embedding,
        );

        // Small delay to stay within Gemini API rate limits
        await Future.delayed(const Duration(milliseconds: 300));
      }

      setState(() {
        _isProcessing = false;
        _statusMessage =
            '✅ Done! $_totalChunks chunks from "$fileName" saved to Firestore.';
      });
    } catch (e) {
      setState(() {
        _isProcessing = false;
        _statusMessage = '❌ Error: ${e.toString()}';
      });
    }
  }

  /// Tags chunks with a category based on keywords found in the text.
  /// Extend this list to match the topics covered in your specific PDFs.
  String _inferCategory(String text) {
    final lower = text.toLowerCase();
    if (lower.contains('protein') ||
        lower.contains('calorie') ||
        lower.contains('nutrition')) return 'nutrition';
    if (lower.contains('recovery') ||
        lower.contains('rest') ||
        lower.contains('sleep')) return 'recovery';
    if (lower.contains('hypertrophy') || lower.contains('muscle')) {
      return 'hypertrophy';
    }
    if (lower.contains('injury') || lower.contains('rehabilitation')) {
      return 'rehabilitation';
    }
    return 'general';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Admin — PDF Ingestion')),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_isProcessing) ...[
              LinearProgressIndicator(
                value: _totalChunks > 0
                    ? _processedChunks / _totalChunks
                    : null,
              ),
              const SizedBox(height: 16),
            ],
            Text(
              _statusMessage,
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 16),
            ),
            if (_totalChunks > 0 && _isProcessing)
              Text(
                '$_processedChunks / $_totalChunks',
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 14, color: Colors.grey),
              ),
            const SizedBox(height: 40),
            ElevatedButton.icon(
              onPressed: _isProcessing ? null : _pickAndIngestPdf,
              icon: const Icon(Icons.upload_file),
              label: const Text('Select PDF & Ingest'),
              style: ElevatedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 16),
              ),
            ),
            const SizedBox(height: 16),
            const Text(
              'Run this once per PDF before the demo.\nDo not close the app while processing.',
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey, fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }
}