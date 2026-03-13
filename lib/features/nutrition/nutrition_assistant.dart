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
            _messages.add({'role': 'assistant', 'text': chunk, 'isStreaming': true});
            isFirstChunk = false;
          } else {
            final lastIndex = _messages.length - 1;
            final currentText = _messages[lastIndex]['text'] as String;
            _messages[lastIndex] = {
              'role': 'assistant',
              'text': currentText + chunk,
              'isStreaming': true 
            };
          }
        });

        if (chunkCount <= 7) {
          _scrollToBottom();
        }
      }

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
                    color: _isLoading ? Colors.transparent : const Color(0xFFFF5E00), // Updated to Orange
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(
                      Icons.send,
                      color: _isLoading ? Colors.grey : Colors.white,
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
    final isJsonFormat = text.trimLeft().startsWith('[') || text.trimLeft().startsWith('```json');
    
    if (!isUser && isStreaming && isJsonFormat) {
      return const _CardGenerationPlaceholder();
    }

    if (!isUser && !isStreaming) {
      final cleanedText = text.replaceAll('```json', '').replaceAll('```', '').trim();
      if (cleanedText.startsWith('[')) {
        try {
          final List<dynamic> parsed = jsonDecode(cleanedText);
          if (parsed.isNotEmpty && parsed.first is Map) {
            final cardsData = parsed.cast<Map<String, dynamic>>();
            return _CardDeck(cards: cardsData);
          }
        } catch (_) {}
      }
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser ? const Color(0xFFFF5E00) : const Color(0xFF1A1A1A), // Orange user bubble
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
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
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
                  listBullet: const TextStyle(color: Color(0xFFFF5E00), fontSize: 15),
                ),
              ),
      ),
    );
  }
}

// ── NEW: TINDER-STYLE SWIPEABLE CARD DECK ────────────────────────────
class _CardDeck extends StatefulWidget {
  final List<Map<String, dynamic>> cards;

  const _CardDeck({required this.cards});

  @override
  State<_CardDeck> createState() => _CardDeckState();
}

class _CardDeckState extends State<_CardDeck> {
  late List<Map<String, dynamic>> _currentCards;

  @override
  void initState() {
    super.initState();
    _currentCards = List.from(widget.cards);
  }

  void _resetCards() {
    setState(() {
      _currentCards = List.from(widget.cards);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_currentCards.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _resetCards,
          icon: const Icon(Icons.refresh, color: Color(0xFFFF5E00)),
          label: const Text(
            'Review Cards Again', 
            style: TextStyle(color: Color(0xFFFF5E00), fontWeight: FontWeight.bold)
          ),
          style: TextButton.styleFrom(
            backgroundColor: const Color(0xFFFF5E00).withOpacity(0.1),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      height: 380, // Taller canvas for the physical deck feel
      child: Stack(
        alignment: Alignment.center,
        // Reverse the list so the first item renders on top of the stack
        children: _currentCards.asMap().entries.map((entry) {
          final index = entry.key;
          final card = entry.value;

          // Prevent rendering a massive stack; only show top 3 layers
          if (index > 2) return const SizedBox.shrink();

          // Calculate offset and scale to create the 3D stacking visual
          final scale = 1.0 - (index * 0.05);
          final offset = index * 14.0;

          final cardWidget = Positioned(
            top: offset,
            bottom: 0,
            left: index * 8.0,
            right: index * 8.0,
            child: Transform.scale(
              scale: scale,
              alignment: Alignment.topCenter,
              child: _buildCardContent(card),
            ),
          );

          // Wrap only the absolute top card (index 0) in the swipe detector
          if (index == 0) {
            return Dismissible(
              key: UniqueKey(), // Forces a clean rebuild when swiped
              onDismissed: (direction) {
                setState(() {
                  _currentCards.removeAt(0);
                });
              },
              child: cardWidget,
            );
          }

          return cardWidget;
        }).toList().reversed.toList(),
      ),
    );
  }

  Widget _buildCardContent(Map<String, dynamic> card) {
    final title = card['title'] ?? card['name'] ?? card['step'] ?? 'Detail';
    final description = card['description'] ?? card['instruction'] ?? card['details'] ?? '';
    final badge = card['badge'] ?? card['impact'] ?? card['muscle_group'] ?? card['confidence'];

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color(0xFF2E1200), // Deep tinted Orange/Brown
            Color(0xFF110500), // Near black
          ],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFF5E00), width: 2), // Heavy Orange Border
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFFF5E00).withOpacity(0.25),
            blurRadius: 15,
            offset: const Offset(0, 8),
          )
        ],
      ),
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              if (badge != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5E00), // Solid Orange
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge.toString().toUpperCase(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12, 
                      fontWeight: FontWeight.w900,
                      letterSpacing: 0.5,
                    ),
                  ),
                ),
              const Icon(Icons.local_fire_department, color: Color(0xFFFF5E00), size: 28),
            ],
          ),
          const SizedBox(height: 20),
          Text(
            title,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: const TextStyle(
              color: Colors.white, 
              fontSize: 26, 
              fontWeight: FontWeight.w900,
              height: 1.1,
            ),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: Colors.white24, height: 1),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Text(
                description,
                style: const TextStyle(
                  color: Colors.white, 
                  fontSize: 16, 
                  height: 1.6,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          // Subtle hint at the bottom to remind them to swipe
          const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard_double_arrow_left, color: Colors.white38, size: 16),
                SizedBox(width: 8),
                Text(
                  'SWIPE TO DISMISS',
                  style: TextStyle(color: Colors.white38, fontSize: 11, fontWeight: FontWeight.w800, letterSpacing: 1),
                ),
                SizedBox(width: 8),
                Icon(Icons.keyboard_double_arrow_right, color: Colors.white38, size: 16),
              ],
            ),
          )
        ],
      ),
    );
  }
}

class _CardGenerationPlaceholder extends StatelessWidget {
  const _CardGenerationPlaceholder();

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 12),
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF2E1200), Color(0xFF110500)],
          ),
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0xFFFF5E00).withOpacity(0.5), width: 1.5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF5E00)),
            ),
            SizedBox(width: 16),
            Text(
              'Designing custom deck...',
              style: TextStyle(color: Colors.white70, fontStyle: FontStyle.italic, fontSize: 15),
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
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Color(0xFFFF5E00)),
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