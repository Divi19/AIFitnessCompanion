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

  // Each message: {'role': 'user' | 'assistant', 'text': '...'}
  final List<Map<String, String>> _messages = [];
  bool _isLoading = false;

  Future<void> _sendMessage() async {
    final question = _controller.text.trim();
    if (question.isEmpty || _isLoading) return;

    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    setState(() {
      _messages.add({'role': 'user', 'text': question});
      _isLoading = true;
    });

    _controller.clear();
    _scrollToBottom();

    try {
      //Get the stream from the updated RagService
      final stream = _ragService.query(
        userQuestion: question,
        userId: userId,
      );

      bool isFirstChunk = true;

      //Listen to the stream as it arrives over the network
      await for (final chunk in stream) {
        setState(() {
          if (isFirstChunk) {
            // First chunk arrives which turns off loader and creates the assistant bubble
            _isLoading = false;
            _messages.add({'role': 'assistant', 'text': chunk});
            isFirstChunk = false;
          } else {
            // Subsequent chunks which appends text to the existing assistant bubble
            final lastIndex = _messages.length - 1;
            final currentText = _messages[lastIndex]['text']!;
            _messages[lastIndex] = {
              'role': 'assistant',
              'text': currentText + chunk
            };
          }
        });
        
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.add({
          'role': 'assistant',
          'text': 'Something went wrong. Please try again.\nError: $e',
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
      backgroundColor: const Color(0xFF0D0D0D), // Deep Black Background
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
                        text: msg['text']!,
                        isUser: msg['role'] == 'user',
                      );
                    },
                  ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A), // Dark surface for input area
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
                      hintText: 'e.g. How much protein do I need?',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: _isLoading ? Colors.transparent : const Color(0xFFB9FF2B), // Volt Green Button
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.send,
                      color: _isLoading ? Colors.grey : Colors.black, // Black icon for high contrast
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

  const _ChatBubble({required this.text, required this.isUser});

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          // Volt Green for User, Dark Surface for AI
          color: isUser ? const Color(0xFFB9FF2B) : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser ? null : Border.all(color: Colors.white10),
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
                  horizontalRuleDecoration: const BoxDecoration(
                    border: Border(bottom: BorderSide(color: Colors.white12, width: 1)),
                  ),
                ),
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
          color: const Color(0xFF1A1A1A), // Dark surface
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(16),
            topRight: Radius.circular(16),
            bottomLeft: Radius.circular(4),
            bottomRight: Radius.circular(16),
          ),
          border: Border.all(color: Colors.white10),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFB9FF2B), // Volt Green loader
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