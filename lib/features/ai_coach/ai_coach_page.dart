import 'package:flutter/material.dart';

import '../../theme/volt_theme.dart';
import '../running/models/run_session.dart';
import '../running/services/run_history_repository.dart';
import 'ai_coach_service.dart';

class AiCoachPage extends StatefulWidget {
  const AiCoachPage({super.key});

  @override
  State<AiCoachPage> createState() => _AiCoachPageState();
}

class _AiCoachPageState extends State<AiCoachPage> {
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  final AiCoachService _service = const AiCoachService();
  final RunHistoryRepository _history = RunHistoryRepository.instance;

  final List<_ChatBubbleData> _visibleMessages = <_ChatBubbleData>[
    const _ChatBubbleData(
      role: 'assistant',
      text:
          'Saya VoltStride Coach lokal. Saya bisa membahas pace, split, konsistensi, '
          'target lomba, dan latihan berdasarkan data yang tersimpan di perangkat. '
          'Mode ini tidak membutuhkan internet atau API berbayar dan bukan pengganti tenaga kesehatan.',
    ),
  ];
  final List<AiCoachMessage> _conversation = <AiCoachMessage>[];

  bool _isSending = false;

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _sendMessage([String? suggestedText]) async {
    if (_isSending) return;

    final String text = (suggestedText ?? _inputController.text).trim();
    if (text.isEmpty) return;

    _inputController.clear();
    final List<AiCoachMessage> nextConversation = <AiCoachMessage>[
      ..._conversation,
      AiCoachMessage(role: 'user', text: text),
    ];

    setState(() {
      _visibleMessages.add(_ChatBubbleData(role: 'user', text: text));
      _isSending = true;
    });
    _scrollToBottom();

    try {
      final List<RunSession> recentRuns = await _history.getAll(limit: 8);
      final String reply = await _service.sendMessage(
        conversation: nextConversation,
        recentRuns: recentRuns,
      );

      _conversation
        ..clear()
        ..addAll(nextConversation)
        ..add(AiCoachMessage(role: 'assistant', text: reply));
      if (mounted) {
        setState(() {
          _visibleMessages.add(
            _ChatBubbleData(role: 'assistant', text: reply),
          );
        });
      }
    } catch (error) {
      if (mounted) {
        setState(() {
          _visibleMessages.add(
            _ChatBubbleData(
              role: 'error',
              text: 'Pesan belum terkirim. $error',
            ),
          );
        });
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
      _scrollToBottom();
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 220),
        curve: Curves.easeOut,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('VoltStride Coach'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Percakapan baru',
            onPressed: _isSending
                ? null
                : () {
                    setState(() {
                      _conversation.clear();
                      _visibleMessages
                        ..clear()
                        ..add(
                          const _ChatBubbleData(
                            role: 'assistant',
                            text:
                                'Percakapan baru dimulai. Saya akan memakai '
                                'ringkasan lari lokal yang tersedia. Saya bekerja secara offline dengan aturan dan perhitungan, bukan model generatif seperti ChatGPT.',
                          ),
                        );
                    });
                  },
            icon: const Icon(Icons.add_comment_outlined),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: <Widget>[
            Expanded(
              child: ListView.builder(
                controller: _scrollController,
                padding: const EdgeInsets.fromLTRB(14, 16, 14, 16),
                itemCount: _visibleMessages.length + (_isSending ? 1 : 0),
                itemBuilder: (BuildContext context, int index) {
                  if (_isSending && index == _visibleMessages.length) {
                    return const _TypingIndicator();
                  }
                  return _ChatBubble(message: _visibleMessages[index]);
                },
              ),
            ),
            if (_visibleMessages.length == 1)
              _suggestionChips(),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _suggestionChips() {
    final List<String> suggestions = <String>[
      'Analisis lari terakhir saya',
      'Bantu rencanakan 10K sub-50',
      'Bagaimana membaca split saya?',
    ];

    return SizedBox(
      height: 46,
      child: ListView.separated(
        padding: const EdgeInsets.symmetric(horizontal: 12),
        scrollDirection: Axis.horizontal,
        itemCount: suggestions.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (BuildContext context, int index) {
          return ActionChip(
            label: Text(suggestions[index]),
            onPressed: _isSending ? null : () => _sendMessage(suggestions[index]),
          );
        },
      ),
    );
  }

  Widget _composer() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: <Widget>[
          Expanded(
            child: TextField(
              controller: _inputController,
              minLines: 1,
              maxLines: 5,
              textCapitalization: TextCapitalization.sentences,
              enabled: !_isSending,
              onSubmitted: (_) => _sendMessage(),
              decoration: InputDecoration(
                hintText: 'Tanyakan soal latihan, pace, split, atau target lomba...',
                filled: true,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(20),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 13,
                ),
              ),
            ),
          ),
          const SizedBox(width: 8),
          IconButton.filled(
            onPressed: _isSending ? null : () => _sendMessage(),
            icon: _isSending
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.send_rounded),
          ),
        ],
      ),
    );
  }
}

class _ChatBubbleData {
  const _ChatBubbleData({required this.role, required this.text});

  final String role;
  final String text;
}

class _ChatBubble extends StatelessWidget {
  const _ChatBubble({required this.message});

  final _ChatBubbleData message;

  @override
  Widget build(BuildContext context) {
    final bool isUser = message.role == 'user';
    final bool isError = message.role == 'error';
    final CrossAxisAlignment alignment =
        isUser ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final Color background = isUser
        ? VoltWarna.aksen.withValues(alpha: 0.18)
        : isError
            ? VoltWarna.merah.withValues(alpha: 0.12)
            : VoltWarna.kartu;

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: alignment,
        children: <Widget>[
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.sizeOf(context).width * 0.84,
            ),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: background,
              borderRadius: BorderRadius.circular(18).copyWith(
                bottomRight: isUser ? const Radius.circular(4) : null,
                bottomLeft: isUser ? null : const Radius.circular(4),
              ),
              border: Border.all(
                color: isError
                    ? VoltWarna.merah.withValues(alpha: 0.35)
                    : VoltWarna.surface,
              ),
            ),
            child: SelectableText(message.text),
          ),
        ],
      ),
    );
  }
}

class _TypingIndicator extends StatelessWidget {
  const _TypingIndicator();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(bottom: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Card(
          child: Padding(
            padding: EdgeInsets.all(14),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
                SizedBox(width: 10),
                Text('Coach sedang berpikir...'),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
