import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/rag_service.dart';

class NutritionAssistantScreen extends StatefulWidget {
  const NutritionAssistantScreen({super.key});

  @override
  State<NutritionAssistantScreen> createState() =>
      _NutritionAssistantScreenState();
}

class _NutritionAssistantScreenState extends State<NutritionAssistantScreen> {
  final _ragService = RagService();
  final _controller = TextEditingController();
  final _scrollController = ScrollController();

  // Updated to dynamic to hold the 'isStreaming' boolean flag
  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;

  Future<void> _sendMessage() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _isLoading) return;

    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    setState(() {
      _messages.add({'role': 'user', 'text': question, 'isStreaming': false});
      _isLoading = true;
    });

    _controller.clear();
    _scrollToBottom();

    // Extract the conversation history BEFORE the current question
    final previousMessages = _messages.sublist(0, _messages.length - 1)
        .map((m) => {'role': m['role'] as String, 'text': m['text'] as String})
        .toList();

    try {
      final stream = _ragService.query(
        userQuestion: question,
        userId: userId,
        chatHistory: previousMessages,
      );

      bool isFirstChunk = true;
      int chunkCount = 0;

      await for (final chunk in stream) {
        chunkCount++;
        
        setState(() {
          if (isFirstChunk) {
            _isLoading = false;
            // Initialize the assistant message with streaming set to true
            _messages.add({'role': 'assistant', 'text': chunk, 'isStreaming': true});
            isFirstChunk = false;
          } else {
            final lastIndex = _messages.length - 1;
            final currentText = _messages[lastIndex]['text'] as String;
            _messages[lastIndex] = {
              'role': 'assistant',
              'text': currentText + chunk,
              'isStreaming': true // Still streaming
            };
          }
        });

        if (chunkCount <= 7) {
          _scrollToBottom();
        }
      }

      // Stream is fully complete, trigger the UI to parse cards if applicable
      setState(() {
        final lastIndex = _messages.length - 1;
        _messages[lastIndex]['isStreaming'] = false;
      });

    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.add({
          'role': 'assistant',
          'text': 'Something went wrong. Please try again.\nError: $e',
          'isStreaming': false
        });
      });
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0D0D0D),
      appBar: AppBar(
        title: const Text(
          'Fitness & Nutrition Assistant',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: const Color(0xFF0D0D0D),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Ask me anything about fitness,\nnutrition, or recovery.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey, fontSize: 16),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.all(16),
                    itemCount: _messages.length + (_isLoading ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == _messages.length && _isLoading) {
                        return const _TypingIndicator();
                      }
                      final msg = _messages[index];
                      return _ChatBubble(
                        text: msg['text'] as String,
                        isUser: msg['role'] == 'user',
                        isStreaming: msg['isStreaming'] as bool,
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              border: Border(
                top: BorderSide(color: Colors.white10, width: 1),
              ),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText: 'e.g. Give me 3 alternatives to deadlifts',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: _isLoading ? Colors.transparent : const Color(0xFFB9FF2B),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.send,
                      color: _isLoading ? Colors.grey : Colors.black,
                    ),
                    onPressed: _isLoading ? null : _sendMessage,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isStreaming;

  const _ChatBubble({
    required this.text, 
    required this.isUser, 
    required this.isStreaming
  });

  @override
  Widget build(BuildContext context) {
    // 1. Check if the AI is generating JSON output to hide the raw code
    final isJsonFormat = text.trimLeft().startsWith('[') || text.trimLeft().startsWith('```json');
    
    if (!isUser && isStreaming && isJsonFormat) {
      return const _CardGenerationPlaceholder();
    }

    // 2. Once streaming is done, try to parse it as interactive cards
    if (!isUser && !isStreaming) {
      final cleanedText = text.replaceAll('```json', '').replaceAll('```', '').trim();
      if (cleanedText.startsWith('[')) {
        try {
          final List<dynamic> parsed = jsonDecode(cleanedText);
          if (parsed.isNotEmpty && parsed.first is Map) {
            final cardsData = parsed.cast<Map<String, dynamic>>();
            return _CardDeck(cards: cardsData);
          }
        } catch (_) {
          // If JSON parsing fails, fall through to render as standard Markdown
        }
      }
    }

    // 3. Standard Text / Markdown Bubble Fallback
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFB9FF2B) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser 
              ? null 
              : Border.all(color: const Color(0xFFFF5E00).withOpacity(0.75), width: 1.2),
          boxShadow: isUser 
              ? null 
              : [
                  BoxShadow(
                    color: const Color(0xFFFF5E00).withOpacity(0.12),
                    blurRadius: 12,
                    spreadRadius: 0,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: isUser
            ? Text(
                text,
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.w500,
                ),
              )
            : MarkdownBody(
                data: text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p:          const TextStyle(color: Colors.white, fontSize: 15, height: 1.6),
                  h1:         const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800, height: 2),
                  h2:         const TextStyle(color: Color(0xFFFF5E00), fontSize: 16, fontWeight: FontWeight.w700, height: 2),
                  h3:         const TextStyle(color: Colors.white, fontSize: 15, fontWeight: FontWeight.w700, height: 1.8),
                  strong:     const TextStyle(color: Colors.white, fontWeight: FontWeight.w700),
                  em:         const TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
                  listBullet: const TextStyle(color: Color(0xFFB9FF2B), fontSize: 15),
                  code:       const TextStyle(color: Color(0xFFB9FF2B), fontSize: 13, fontFamily: 'monospace'),
                  codeblockDecoration: BoxDecoration(
                    color: const Color(0xFF111111),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  blockquoteDecoration: BoxDecoration(
                    color: const Color(0xFFFF5E00).withOpacity(0.08),
                    borderRadius: BorderRadius.circular(6),
                    border: const Border(left: BorderSide(color: Color(0xFFFF5E00), width: 3)),
                  ),
                  blockquote: const TextStyle(color: Colors.white70, fontSize: 14),
                ),
              ),
      ),
    );
  }
}

// NEW: Swipeable Card Deck Widget
class _CardDeck extends StatelessWidget {
  final List<Map<String, dynamic>> cards;

  const _CardDeck({required this.cards});

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      height: 240, // Fixed height for the card swiper
      child: PageView.builder(
        controller: PageController(viewportFraction: 0.85),
        padEnds: false,
        itemCount: cards.length,
        itemBuilder: (context, index) {
          final card = cards[index];
          // Flexible key extraction to handle different AI JSON formats
          final title = card['title'] ?? card['name'] ?? card['step'] ?? 'Detail';
          final description = card['description'] ?? card['instruction'] ?? card['details'] ?? '';
          final badge = card['badge'] ?? card['impact'] ?? card['muscle_group'] ?? card['confidence'];

          return Container(
            margin: const EdgeInsets.only(right: 12),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: const Color(0xFF1A1A1A),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFFF5E00).withOpacity(0.8), width: 1.5),
              boxShadow: [
                BoxShadow(
                  color: const Color(0xFFFF5E00).withOpacity(0.15),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                )
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (badge != null) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                    decoration: BoxDecoration(
                      color: const Color(0xFFB9FF2B).withOpacity(0.2),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(color: const Color(0xFFB9FF2B)),
                    ),
                    child: Text(
                      badge.toString().toUpperCase(),
                      style: const TextStyle(color: Color(0xFFB9FF2B), fontSize: 10, fontWeight: FontWeight.bold),
                    ),
                  ),
                  const SizedBox(height: 12),
                ],
                Text(
                  title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Expanded(
                  child: SingleChildScrollView(
                    child: Text(
                      description,
                      style: const TextStyle(color: Colors.white70, fontSize: 14, height: 1.5),
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      '${index + 1} / ${cards.length}',
                      style: const TextStyle(color: Colors.white38, fontSize: 12),
                    ),
                  ],
                )
              ],
            ),
          );
        },
      ),
    );
  }
}

// NEW: Placeholder while JSON is streaming
class _CardGenerationPlaceholder extends StatelessWidget {
  const _CardGenerationPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: const Color(0xFFFF5E00).withOpacity(0.4), width: 1),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.view_carousel, color: Color(0xFFB9FF2B), size: 20),
            SizedBox(width: 12),
            Text(
              'Generating interactive cards...',
              style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF1A1A1A),
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: const Color(0xFFFF5E00).withOpacity(0.75), width: 1.2),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFFFF5E00).withOpacity(0.12),
              blurRadius: 12,
              spreadRadius: 0,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFFF5E00),
              ),
            ),
            SizedBox(width: 12),
            Text(
              'Searching knowledge base...',
              style: TextStyle(color: Colors.grey, fontSize: 14),
            ),
          ],
        ),
      ),
    );
  }
}