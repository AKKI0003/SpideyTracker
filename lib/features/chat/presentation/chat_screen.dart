import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/chat_repository.dart';
import '../domain/chat_message.dart';
import '../../../core/chat/local_chat_store.dart';
import '../../map_scanner/presentation/widgets/spider_mask_icon.dart';
import '../../../core/widgets/corner_web_painter.dart';
import 'widgets/chat_bubble.dart';
import 'widgets/date_separator.dart';
import 'widgets/typing_dots.dart';

/// Feature 3 - Chat.
///
/// Automatically presents as a group chat header/avatar-stack whenever
/// the party has more than 2 members (you + 1 other = simple 1:1 feel;
/// 3+ = group feel), matching "if multiple people are in the party then
/// it should be a group chat."
class ChatScreen extends StatefulWidget {
  final String partyId;

  const ChatScreen({super.key, required this.partyId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _chatRepo = ChatRepository();
  final _textController = TextEditingController();
  final _scrollController = ScrollController();

  StreamSubscription? _syncSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _partyDocSub;
  StreamSubscription<List<String>>? _typingSub;

  String _partyName = '';
  String _inviteCode = '';
  List<String> _memberUids = [];
  Map<String, String> _memberNames = {};
  Map<String, String> _memberMaskIds = {};
  List<String> _typingUids = [];

  final Map<String, ChatMessage> _messages = {}; // id -> message
  bool _isSending = false;
  Timer? _typingDebounce;

  String get _myUid => FirebaseAuth.instance.currentUser!.uid;

  @override
  void initState() {
    super.initState();
    _loadLocalHistory();
    _listenParty();
    LocalChatStore.markChatOpened(widget.partyId);
  }

  void _loadLocalHistory() {
    final local = LocalChatStore.messagesForParty(widget.partyId);
    for (final json in local) {
      final msg = ChatMessage.fromLocalJson(json);
      _messages[msg.id] = msg;
    }
    if (mounted) setState(() {});
  }

  void _listenParty() {
    _partyDocSub = FirebaseFirestore.instance
        .collection('parties')
        .doc(widget.partyId)
        .snapshots()
        .listen((doc) async {
      final data = doc.data();
      if (data == null) return;

      final memberUids = List<String>.from(data['memberUids'] as List? ?? []);
      final inviteCode = data['inviteCode'] as String? ?? '';
      final partyName = data['name'] as String? ?? '';

      final names = <String, String>{};
      final maskIds = <String, String>{};
      for (final uid in memberUids) {
        final memberDoc = await FirebaseFirestore.instance.collection('users').doc(uid).get();
        names[uid] = uid == _myUid ? 'You' : (memberDoc.data()?['displayName'] as String? ?? 'Member');
        maskIds[uid] = memberDoc.data()?['maskId'] as String? ?? 'spiderman';
      }

      if (!mounted) return;
      setState(() {
        _partyName = partyName;
        _inviteCode = inviteCode;
        _memberUids = memberUids;
        _memberNames = names;
        _memberMaskIds = maskIds;
      });

      // Only start the message sync once we actually have the invite
      // code (needed to derive the decryption key) and member list
      // (needed to know when a message is fully delivered and can be
      // pruned server-side).
      _syncSub ??= _chatRepo.listenAndSync(
        partyId: widget.partyId,
        inviteCode: inviteCode,
        myUid: _myUid,
        partyMemberUids: memberUids,
        onMessage: (message) {
          if (!mounted) return;
          setState(() => _messages[message.id] = message);
          _chatRepo.markRead(partyId: widget.partyId, messageId: message.id, uid: _myUid);
          _scrollToBottomSoon();
        },
      );

      _typingSub ??= _chatRepo.watchTypingUids(widget.partyId, excludeUid: _myUid).listen((uids) {
        if (mounted) setState(() => _typingUids = uids);
      });
    });
  }

  void _scrollToBottomSoon() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
        );
      }
    });
  }

  void _onTextChanged(String text) {
    _typingDebounce?.cancel();
    _chatRepo.setTyping(partyId: widget.partyId, uid: _myUid, isTyping: text.isNotEmpty);
    _typingDebounce = Timer(const Duration(seconds: 3), () {
      _chatRepo.setTyping(partyId: widget.partyId, uid: _myUid, isTyping: false);
    });
  }

  Future<void> _send() async {
    final text = _textController.text.trim();
    if (text.isEmpty || _isSending) return;

    setState(() => _isSending = true);
    _textController.clear();
    _chatRepo.setTyping(partyId: widget.partyId, uid: _myUid, isTyping: false);

    try {
      await _chatRepo.sendMessage(
        partyId: widget.partyId,
        inviteCode: _inviteCode,
        senderUid: _myUid,
        text: text,
      );
      _scrollToBottomSoon();
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  @override
  void dispose() {
    _syncSub?.cancel();
    _partyDocSub?.cancel();
    _typingSub?.cancel();
    _typingDebounce?.cancel();
    _chatRepo.setTyping(partyId: widget.partyId, uid: _myUid, isTyping: false);
    _textController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  bool get _isGroupChat => _memberUids.length > 2;

  @override
  Widget build(BuildContext context) {
    final sortedMessages = _messages.values.toList()..sort((a, b) => a.sentAt.compareTo(b.sentAt));
    final otherMemberUids = _memberUids.where((u) => u != _myUid).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1128),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0A1128),
        elevation: 0,
        titleSpacing: 0,
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(1.5),
          child: Container(
            height: 1.5,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  Colors.cyanAccent.withOpacity(0.6),
                  Colors.cyanAccent.withOpacity(0.05),
                ],
              ),
            ),
          ),
        ),
        title: Row(
          children: [
            _AvatarStack(uids: otherMemberUids, maskIds: _memberMaskIds),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    _isGroupChat ? _partyName.toUpperCase() : (_memberNames[otherMemberUids.firstOrNull] ?? '').toUpperCase(),
                    style: GoogleFonts.pressStart2p(fontSize: 10, color: Colors.cyanAccent),
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.lock, size: 9, color: Colors.greenAccent.withOpacity(0.8)),
                      const SizedBox(width: 3),
                      Text(
                        _isGroupChat ? '${_memberUids.length} MEMBERS · E2E SECURED' : 'END-TO-END SECURED',
                        style: TextStyle(color: Colors.white38, fontSize: 9, letterSpacing: 0.3),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
      body: Stack(
        children: [
          // Faint corner web, purely decorative — same procedural
          // cobweb used for the map's pin filter, just very low
          // opacity here so it reads as texture rather than competing
          // with the messages. One shared painter = one consistent
          // "web" look across the whole app.
          Positioned(
            top: 0,
            right: 0,
            child: IgnorePointer(
              child: CustomPaint(
                size: const Size(170, 170),
                painter: const CornerWebPainter(opacity: 0.22),
              ),
            ),
          ),
          Column(
            children: [
          Expanded(
            child: sortedMessages.isEmpty
                ? Center(
                    child: Text(
                      'NO MESSAGES YET.\nSAY HI!',
                      textAlign: TextAlign.center,
                      style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.white24),
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: sortedMessages.length,
                    itemBuilder: (context, i) {
                      final message = sortedMessages[i];
                      final prev = i > 0 ? sortedMessages[i - 1] : null;
                      final isMine = message.senderUid == _myUid;
                      final showDateSeparator = prev == null || !_isSameDay(prev.sentAt, message.sentAt);
                      // Sender name now always shows above the first
                      // message in a run from that person — including
                      // 1:1 chats, not just groups — since knowing who
                      // sent what shouldn't depend on party size.
                      final showSenderName = !isMine &&
                          (prev == null || prev.senderUid != message.senderUid);

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          if (showDateSeparator) DateSeparator(date: message.sentAt),
                          ChatBubble(
                            isMine: isMine,
                            text: message.text,
                            time: message.sentAt,
                            senderName: showSenderName ? (_memberNames[message.senderUid] ?? 'Member') : null,
                            senderUid: message.senderUid,
                            avatarMaskId: !isMine ? (_memberMaskIds[message.senderUid] ?? 'spiderman') : null,
                            isRead: isMine && message.readBy.length > 1,
                          ),
                        ],
                      );
                    },
                  ),
          ),
          if (_typingUids.isNotEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Row(
                children: [
                  Text(
                    _typingUids.length == 1
                        ? '${_memberNames[_typingUids.first] ?? 'Someone'} is typing'
                        : '${_typingUids.length} people are typing',
                    style: const TextStyle(color: Colors.white38, fontSize: 11),
                  ),
                  const SizedBox(width: 6),
                  const RepaintBoundary(child: TypingDots()),
                ],
              ),
            ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.45),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 1.3),
                        boxShadow: [
                          BoxShadow(color: Colors.cyanAccent.withOpacity(0.08), blurRadius: 8),
                        ],
                      ),
                      child: TextField(
                        controller: _textController,
                        onChanged: _onTextChanged,
                        onSubmitted: (_) => _send(),
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        maxLines: 4,
                        minLines: 1,
                        decoration: const InputDecoration(
                          border: InputBorder.none,
                          hintText: 'Message...',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 13),
                          isDense: true,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  GestureDetector(
                    onTap: _send,
                    child: Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.cyanAccent,
                        border: Border.all(color: Colors.black, width: 2),
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: const [
                          BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
                        ],
                      ),
                      child: _isSending
                          ? const Padding(
                              padding: EdgeInsets.all(11),
                              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
                            )
                          : const Icon(Icons.send_rounded, color: Colors.black, size: 18),
                    ),
                  ),
                ],
              ),
            ),
          ),
            ],
          ),
        ],
      ),
    );
  }

  bool _isSameDay(DateTime a, DateTime b) => a.year == b.year && a.month == b.month && a.day == b.day;
}

extension _FirstOrNull<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}

class _AvatarStack extends StatelessWidget {
  final List<String> uids;
  final Map<String, String> maskIds;

  const _AvatarStack({required this.uids, required this.maskIds});

  @override
  Widget build(BuildContext context) {
    final shown = uids.take(3).toList();
    return SizedBox(
      width: 28 + (shown.length - 1) * 14.0,
      height: 32,
      child: Stack(
        children: [
          for (int i = 0; i < shown.length; i++)
            Positioned(
              left: i * 14.0,
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF0A1128),
                  border: Border.all(color: Colors.blueAccent, width: 1),
                ),
                child: SpiderMaskIcon(size: 24, maskId: maskIds[shown[i]] ?? 'spiderman'),
              ),
            ),
        ],
      ),
    );
  }
}