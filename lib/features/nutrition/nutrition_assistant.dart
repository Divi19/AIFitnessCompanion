import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_markdown/flutter_markdown.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../services/rag_service.dart';
import '../../services/workout_session_service.dart';

class NutritionAssistantScreen extends StatefulWidget {
  const NutritionAssistantScreen({super.key});

  @override
  State<NutritionAssistantScreen> createState() =>
      _NutritionAssistantScreenState();
}

class _NutritionAssistantScreenState
    extends State<NutritionAssistantScreen> {
  final _ragService     = RagService();
  final _sessionService = WorkoutSessionService();
  final _controller     = TextEditingController();
  final _scrollController = ScrollController();

  final List<Map<String, dynamic>> _messages = [];
  bool _isLoading = false;

  // Selected session for debrief expansion — null means none selected
  WorkoutSession? _expandedSession;

  Future<void> _sendMessage({String? overrideText}) async {
    final question = overrideText ?? _controller.text.trim();
    if (question.isEmpty || _isLoading) return;

    final userId = FirebaseAuth.instance.currentUser?.uid ?? '';

    setState(() {
      _messages.add({'role': 'user', 'text': question, 'isStreaming': false});
      _isLoading = true;
    });

    _controller.clear();
    _scrollToBottom();

    final previousMessages = _messages
        .sublist(0, _messages.length - 1)
        .map((m) => {'role': m['role'] as String, 'text': m['text'] as String})
        .toList();

    try {
      // Fetch recent sessions to inject as context
      final recentSessions = await _sessionService.getRecentSessions(limit: 3);

      final stream = _ragService.query(
        userQuestion:   question,
        userId:         userId,
        chatHistory:    previousMessages,
        recentSessions: recentSessions,
      );

      bool isFirstChunk = true;
      int  chunkCount   = 0;

      await for (final chunk in stream) {
        chunkCount++;
        setState(() {
          if (isFirstChunk) {
            _isLoading = false;
            _messages.add(
                {'role': 'assistant', 'text': chunk, 'isStreaming': true});
            isFirstChunk = false;
          } else {
            final lastIndex  = _messages.length - 1;
            final currentText = _messages[lastIndex]['text'] as String;
            _messages[lastIndex] = {
              'role': 'assistant',
              'text': currentText + chunk,
              'isStreaming': true,
            };
          }
        });
        if (chunkCount <= 7) _scrollToBottom();
      }

      setState(() {
        _messages[_messages.length - 1]['isStreaming'] = false;
      });
    } catch (e) {
      setState(() {
        _isLoading = false;
        _messages.add({
          'role': 'assistant',
          'text': 'Something went wrong. Please try again.\nError: $e',
          'isStreaming': false,
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
        title: const Row(
          children: [
            Icon(Icons.bolt, color: Color(0xFFB9FF2B), size: 26),
            SizedBox(width: 8),
            Text(
              'AI Fitness Coach',
              style: TextStyle(
                color: Color(0xFFB9FF2B),
                fontWeight: FontWeight.w900,
                letterSpacing: 0.5,
              ),
            ),
          ],
        ),
        backgroundColor: const Color(0xFF0D0D0D),
        elevation: 0,
      ),
      body: Column(
        children: [

          // ── Session History Strip ────────────────────────────────────────
          // Shows recent workout sessions as tappable cards at the top.
          // Tapping a card expands the debrief inline and pre-seeds a
          // follow-up question into the chat.
          _SessionHistoryStrip(
            sessionService: _sessionService,
            expandedSession: _expandedSession,
            onSessionTap: (session) {
              setState(() {
                _expandedSession =
                    _expandedSession?.id == session.id ? null : session;
              });
            },
            onAskFollowUp: (session) {
              setState(() => _expandedSession = null);
              _sendMessage(
                overrideText:
                    'Based on my ${session.exerciseDisplayName} session where I did '
                    '${session.reps} reps, ${session.debriefText} '
                    'What should I focus on to improve next time?',
              );
            },
          ),

          // ── Chat Messages ────────────────────────────────────────────────
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Text(
                          'Ask me anything about fitness,\nnutrition, or recovery.',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'Tap a session above to ask about your form',
                          style: TextStyle(
                              color: Colors.white.withOpacity(0.25),
                              fontSize: 13),
                        ),
                      ],
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
                        text:        msg['text']        as String,
                        isUser:      msg['role']        == 'user',
                        isStreaming: msg['isStreaming']  as bool,
                      );
                    },
                  ),
          ),

          // ── Input Bar ────────────────────────────────────────────────────
          Container(
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: const BoxDecoration(
              color: Color(0xFF1A1A1A),
              border: Border(top: BorderSide(color: Colors.white10)),
            ),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    style: const TextStyle(color: Colors.white),
                    decoration: const InputDecoration(
                      hintText:
                          'e.g. Give me 3 alternatives to deadlifts',
                      hintStyle: TextStyle(color: Colors.grey),
                      border: InputBorder.none,
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                Container(
                  decoration: BoxDecoration(
                    color: _isLoading
                        ? Colors.transparent
                        : const Color(0xFFB9FF2B),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    icon: Icon(Icons.send,
                        color:
                            _isLoading ? Colors.grey : Colors.black),
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

// ── Session History Strip ─────────────────────────────────────────────────
class _SessionHistoryStrip extends StatelessWidget {
  final WorkoutSessionService sessionService;
  final WorkoutSession? expandedSession;
  final void Function(WorkoutSession) onSessionTap;
  final void Function(WorkoutSession) onAskFollowUp;

  const _SessionHistoryStrip({
    required this.sessionService,
    required this.expandedSession,
    required this.onSessionTap,
    required this.onAskFollowUp,
  });

  IconData _iconFor(String exercise) {
    switch (exercise) {
      case 'squat':
      case 'lunge_left':
      case 'lunge_right':
        return Icons.directions_run;
      case 'pushup':
        return Icons.fitness_center;
      case 'bicep_curl':
        return Icons.sports_gymnastics;
      case 'jumping_jack':
        return Icons.directions_walk;
      case 'sit_up':
      case 'glute_bridge':
        return Icons.self_improvement;
      case 'plank':
        return Icons.accessibility_new;
      default:
        return Icons.sports;
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<WorkoutSession>>(
      stream: sessionService.sessionsStream(),
      builder: (context, snapshot) {
        final sessions = snapshot.data ?? [];
        if (sessions.isEmpty) return const SizedBox.shrink();

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section header
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
              child: Text(
                'RECENT SESSIONS',
                style: TextStyle(
                  color: Colors.white.withOpacity(0.35),
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                  letterSpacing: 1.5,
                ),
              ),
            ),

            // Horizontal scroll of session cards
            SizedBox(
              height: 88,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                itemCount: sessions.length,
                itemBuilder: (context, index) {
                  final session  = sessions[index];
                  final isExpanded = expandedSession?.id == session.id;

                  return GestureDetector(
                    onTap: () => onSessionTap(session),
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 200),
                      margin: const EdgeInsets.only(right: 10),
                      width: 140,
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isExpanded
                            ? const Color(0xFFFF5E00).withOpacity(0.15)
                            : const Color(0xFF1A1A1A),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: isExpanded
                              ? const Color(0xFFFF5E00)
                              : Colors.white12,
                          width: isExpanded ? 1.5 : 1,
                        ),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(_iconFor(session.exercise),
                                  color: const Color(0xFFB9FF2B), size: 14),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  session.exerciseDisplayName,
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.w700,
                                  ),
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Text(
                            '${session.reps} reps · ${session.durationFormatted}',
                            style: const TextStyle(
                                color: Colors.white54, fontSize: 11),
                          ),
                          const Spacer(),
                          Text(
                            session.timeAgo,
                            style: TextStyle(
                              color: Colors.white.withOpacity(0.3),
                              fontSize: 10,
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),

            // Expanded debrief panel — appears below strip when a card is tapped
            if (expandedSession != null)
              AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                margin: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A1A1A),
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                      color: const Color(0xFFFF5E00).withOpacity(0.4)),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.record_voice_over,
                            color: Color(0xFFFF5E00), size: 16),
                        const SizedBox(width: 8),
                        Text(
                          '${expandedSession!.exerciseDisplayName} Debrief',
                          style: const TextStyle(
                            color: Color(0xFFFF5E00),
                            fontSize: 13,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      expandedSession!.debriefText,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 14,
                        height: 1.6,
                      ),
                    ),
                    const SizedBox(height: 12),
                    // Ask follow-up button
                    GestureDetector(
                      onTap: () => onAskFollowUp(expandedSession!),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 14, vertical: 8),
                        decoration: BoxDecoration(
                          color: const Color(0xFFB9FF2B).withOpacity(0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                              color: const Color(0xFFB9FF2B).withOpacity(0.4)),
                        ),
                        child: const Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.chat_bubble_outline,
                                color: Color(0xFFB9FF2B), size: 14),
                            SizedBox(width: 6),
                            Text(
                              'Ask the coach about this session',
                              style: TextStyle(
                                color: Color(0xFFB9FF2B),
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),

            const Divider(color: Colors.white10, height: 1),
          ],
        );
      },
    );
  }
}

// ── Chat Bubble (unchanged from original) ────────────────────────────────
class _ChatBubble extends StatelessWidget {
  final String text;
  final bool isUser;
  final bool isStreaming;

  const _ChatBubble({
    required this.text,
    required this.isUser,
    required this.isStreaming,
  });

  @override
  Widget build(BuildContext context) {
    final isJsonFormat =
        text.trimLeft().startsWith('[') || text.trimLeft().startsWith('```json');

    if (!isUser && isStreaming && isJsonFormat) {
      return const _CardGenerationPlaceholder();
    }

    if (!isUser && !isStreaming) {
      final cleanedText =
          text.replaceAll('```json', '').replaceAll('```', '').trim();
      if (cleanedText.startsWith('[')) {
        try {
          final List<dynamic> parsed = jsonDecode(cleanedText);
          if (parsed.isNotEmpty && parsed.first is Map) {
            return _CardDeck(cards: parsed.cast<Map<String, dynamic>>());
          }
        } catch (_) {}
      }
    }

    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding:
            const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        decoration: BoxDecoration(
          color: isUser
              ? const Color(0xFFB9FF2B)
              : const Color(0xFF1A1A1A),
          borderRadius: BorderRadius.only(
            topLeft: const Radius.circular(16),
            topRight: const Radius.circular(16),
            bottomLeft: Radius.circular(isUser ? 16 : 4),
            bottomRight: Radius.circular(isUser ? 4 : 16),
          ),
          border: isUser
              ? null
              : Border.all(
                  color: const Color(0xFFFF5E00).withOpacity(0.75),
                  width: 1.2),
          boxShadow: isUser
              ? null
              : [
                  BoxShadow(
                    color: const Color(0xFFFF5E00).withOpacity(0.12),
                    blurRadius: 12,
                    offset: const Offset(0, 4),
                  ),
                ],
        ),
        child: isUser
            ? Text(text,
                style: const TextStyle(
                    color: Colors.black,
                    fontSize: 15,
                    fontWeight: FontWeight.w600))
            : MarkdownBody(
                data: text,
                selectable: true,
                styleSheet: MarkdownStyleSheet(
                  p: const TextStyle(
                      color: Colors.white, fontSize: 15, height: 1.6),
                  h1: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      height: 2),
                  h2: const TextStyle(
                      color: Color(0xFFFF5E00),
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      height: 2),
                  h3: const TextStyle(
                      color: Colors.white,
                      fontSize: 15,
                      fontWeight: FontWeight.w700,
                      height: 1.8),
                  strong: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.w700),
                  em: const TextStyle(
                      color: Colors.white70,
                      fontStyle: FontStyle.italic),
                  listBullet: const TextStyle(
                      color: Color(0xFFFF5E00), fontSize: 15),
                ),
              ),
      ),
    );
  }
}

// ── Card Deck (unchanged from original) ──────────────────────────────────
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

  void _resetCards() =>
      setState(() => _currentCards = List.from(widget.cards));

  @override
  Widget build(BuildContext context) {
    if (_currentCards.isEmpty) {
      return Container(
        margin: const EdgeInsets.symmetric(vertical: 16),
        alignment: Alignment.centerLeft,
        child: TextButton.icon(
          onPressed: _resetCards,
          icon: const Icon(Icons.refresh, color: Color(0xFFFF5E00)),
          label: const Text('Review Cards Again',
              style: TextStyle(
                  color: Color(0xFFFF5E00),
                  fontWeight: FontWeight.bold)),
          style: TextButton.styleFrom(
            backgroundColor: const Color(0xFFFF5E00).withOpacity(0.1),
            padding:
                const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12)),
          ),
        ),
      );
    }

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 12),
      height: 380,
      child: Stack(
        alignment: Alignment.center,
        children: _currentCards.asMap().entries.map((entry) {
          final index = entry.key;
          final card  = entry.value;
          if (index > 2) return const SizedBox.shrink();
          final scale  = 1.0 - (index * 0.05);
          final offset = index * 14.0;
          Widget inner = Transform.scale(
            scale: scale,
            alignment: Alignment.topCenter,
            child: _buildCardContent(card),
          );
          if (index == 0) {
            inner = Dismissible(
              key: UniqueKey(),
              onDismissed: (_) =>
                  setState(() => _currentCards.removeAt(0)),
              child: inner,
            );
          }
          return Positioned(
            top: offset, bottom: 0,
            left: index * 8.0, right: index * 8.0,
            child: inner,
          );
        }).toList().reversed.toList(),
      ),
    );
  }

  Widget _buildCardContent(Map<String, dynamic> card) {
    final title       = card['title']       ?? card['name']   ?? card['step']   ?? 'Detail';
    final description = card['description'] ?? card['instruction'] ?? card['details'] ?? '';
    final badge       = card['badge']       ?? card['impact'] ?? card['muscle_group'] ?? card['confidence'];

    return Container(
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [Color(0xFF2E1200), Color(0xFF110500)],
        ),
        borderRadius: BorderRadius.circular(24),
        border: Border.all(color: const Color(0xFFFF5E00), width: 2),
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
                  padding: const EdgeInsets.symmetric(
                      horizontal: 14, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF5E00),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    badge.toString().toUpperCase(),
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 0.5),
                  ),
                ),
              const Icon(Icons.local_fire_department,
                  color: Color(0xFFFF5E00), size: 28),
            ],
          ),
          const SizedBox(height: 20),
          Text(title,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 26,
                  fontWeight: FontWeight.w900,
                  height: 1.1)),
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Divider(color: Colors.white24, height: 1),
          ),
          Expanded(
            child: SingleChildScrollView(
              physics: const BouncingScrollPhysics(),
              child: Text(description,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      height: 1.6,
                      fontWeight: FontWeight.w500)),
            ),
          ),
          const SizedBox(height: 12),
          const Center(
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.keyboard_double_arrow_left,
                    color: Colors.white38, size: 16),
                SizedBox(width: 8),
                Text('SWIPE TO DISMISS',
                    style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1)),
                SizedBox(width: 8),
                Icon(Icons.keyboard_double_arrow_right,
                    color: Colors.white38, size: 16),
              ],
            ),
          ),
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
          border: Border.all(
              color: const Color(0xFFFF5E00).withOpacity(0.5), width: 1.5),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 18,
              height: 18,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFFF5E00)),
            ),
            SizedBox(width: 16),
            Text('Designing custom deck...',
                style: TextStyle(
                    color: Colors.white70,
                    fontStyle: FontStyle.italic,
                    fontSize: 15)),
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
          border: Border.all(
              color: const Color(0xFFFF5E00).withOpacity(0.75), width: 1.2),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                  strokeWidth: 2, color: Color(0xFFFF5E00)),
            ),
            SizedBox(width: 12),
            Text('Searching knowledge base...',
                style: TextStyle(color: Colors.grey, fontSize: 14)),
          ],
        ),
      ),
    );
  }
}