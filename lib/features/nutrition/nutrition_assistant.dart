import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/rag_service.dart';

class NutritionAssistantScreen extends StatefulWidget {
  const NutritionAssistantScreen({super.key});

  @override
  State<NutritionAssistantScreen> createState() =>
      _NutritionAssistantScreenState();
}

class _NutritionAssistantScreenState
    extends State<NutritionAssistantScreen> {
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
      final response = await _ragService.query(
        userQuestion: question,
        userId: userId,
      );

      setState(() {
        _messages.add({'role': 'assistant', 'text': response});
        _isLoading = false;
      });
    } catch (e) {
      setState(() {
        _messages.add({
          'role': 'assistant',
          'text': 'Something went wrong. Please try again.\nError: $e',
        });
        _isLoading = false;
      });
    }

    _scrollToBottom();
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
      appBar: AppBar(
        title: const Text('Fitness & Nutrition Assistant'),
        backgroundColor: Colors.deepPurple,
        foregroundColor: Colors.white,
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? const Center(
                    child: Text(
                      'Ask me anything about fitness,\nnutrition, or recovery.',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.grey),
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
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: const BoxDecoration(
              color: Colors.white,
              boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 4)],
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    decoration: const InputDecoration(
                      hintText: 'e.g. How much protein do I need per day?',
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                IconButton(
                  icon:
                      const Icon(Icons.send, color: Colors.deepPurple),
                  onPressed: _isLoading ? null : _sendMessage,
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
      alignment:
          isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? Colors.deepPurple : Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isUser ? Colors.white : Colors.black87,
            fontSize: 14,
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
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey[200],
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2),
            ),
            SizedBox(width: 8),
            Text('Searching knowledge base...'),
          ],
        ),
      ),
    );
  }
}