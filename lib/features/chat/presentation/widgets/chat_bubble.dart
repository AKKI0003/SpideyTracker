import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import '../../../map_scanner/presentation/widgets/spider_mask_icon.dart';

/// Stable, non-clashing accent color per sender, derived from their uid
/// so it never changes between messages/sessions but still gives each
/// person in a group chat their own identity color for their name +
/// bubble border + avatar ring.
const List<Color> _senderPalette = [
  Colors.cyanAccent,
  Colors.pinkAccent,
  Colors.amberAccent,
  Colors.greenAccent,
  Colors.deepPurpleAccent,
  Colors.orangeAccent,
  Colors.lightBlueAccent,
  Colors.redAccent,
];

Color _colorForSender(String? uid) {
  if (uid == null || uid.isEmpty) return Colors.blueAccent;
  final hash = uid.codeUnits.fold<int>(0, (acc, c) => acc + c);
  return _senderPalette[hash % _senderPalette.length];
}

/// Deliberately small text (13px body, 9px meta) — readable but not
/// oversized, per spec. Bubble styling uses soft pixel-rounded corners,
/// a per-sender accent glow, and small pixel corner accents rather than
/// plain flat Material bubbles, to match the app's arcade aesthetic
/// instead of looking like a generic chat app.
class ChatBubble extends StatelessWidget {
  final bool isMine;
  final String text;
  final DateTime time;
  final String? senderName;
  final String? senderUid;
  final String? avatarMaskId;
  final bool isRead;

  const ChatBubble({
    super.key,
    required this.isMine,
    required this.text,
    required this.time,
    this.senderName,
    this.senderUid,
    this.avatarMaskId,
    this.isRead = false,
  });

  @override
  Widget build(BuildContext context) {
    final accent = isMine ? Colors.cyanAccent : _colorForSender(senderUid);
    final align = isMine ? CrossAxisAlignment.end : CrossAxisAlignment.start;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isMine)
            Padding(
              padding: const EdgeInsets.only(right: 6, bottom: 2),
              child: Container(
                padding: const EdgeInsets.all(2),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: accent.withOpacity(0.7), width: 1.3),
                  boxShadow: [
                    BoxShadow(color: accent.withOpacity(0.25), blurRadius: 5),
                  ],
                ),
                child: SpiderMaskIcon(size: 22, maskId: avatarMaskId ?? 'spiderman'),
              ),
            ),
          Flexible(
            child: Column(
              crossAxisAlignment: align,
              children: [
                if (senderName != null)
                  Padding(
                    padding: const EdgeInsets.only(left: 10, bottom: 3),
                    child: Text(
                      senderName!,
                      style: GoogleFonts.pressStart2p(fontSize: 7, color: accent.withOpacity(0.9)),
                    ),
                  ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
                  constraints: const BoxConstraints(maxWidth: 260),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: isMine
                          ? [const Color(0xFF1B4FA0), const Color(0xFF123A7A)]
                          : [const Color(0xFF19233F), const Color(0xFF141B30)],
                    ),
                    borderRadius: BorderRadius.only(
                      topLeft: const Radius.circular(12),
                      topRight: const Radius.circular(12),
                      bottomLeft: Radius.circular(isMine ? 12 : 2),
                      bottomRight: Radius.circular(isMine ? 2 : 12),
                    ),
                    border: Border.all(color: accent.withOpacity(0.45), width: 1.2),
                    boxShadow: [
                      BoxShadow(color: accent.withOpacity(0.18), blurRadius: 8),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        text,
                        style: const TextStyle(color: Colors.white, fontSize: 13, height: 1.35),
                      ),
                      const SizedBox(height: 3),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            DateFormat('h:mm a').format(time),
                            style: TextStyle(color: Colors.white.withOpacity(0.45), fontSize: 9),
                          ),
                          if (isMine) ...[
                            const SizedBox(width: 3),
                            Icon(
                              isRead ? Icons.done_all : Icons.done,
                              size: 11,
                              color: isRead ? Colors.cyanAccent : Colors.white.withOpacity(0.45),
                            ),
                          ],
                        ],
                      ),
                    ],
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
