/// A single chat message, always in DECRYPTED form once it exists in
/// memory/local storage. Never serialize this directly to Firestore —
/// that goes through ChatRepository's encryption step instead.
class ChatMessage {
  final String id;
  final String senderUid;
  final String text;
  final DateTime sentAt;
  final List<String> readBy;
  final Map<String, String> reactions; // uid -> emoji

  ChatMessage({
    required this.id,
    required this.senderUid,
    required this.text,
    required this.sentAt,
    this.readBy = const [],
    this.reactions = const {},
  });

  Map<String, dynamic> toLocalJson() => {
        'id': id,
        'senderUid': senderUid,
        'text': text,
        'sentAt': sentAt.toIso8601String(),
        'readBy': readBy,
        'reactions': reactions,
      };

  factory ChatMessage.fromLocalJson(Map<String, dynamic> json) => ChatMessage(
        id: json['id'] as String,
        senderUid: json['senderUid'] as String,
        text: json['text'] as String,
        sentAt: DateTime.parse(json['sentAt'] as String),
        readBy: List<String>.from(json['readBy'] as List? ?? const []),
        reactions: Map<String, String>.from(json['reactions'] as Map? ?? const {}),
      );

  ChatMessage copyWith({List<String>? readBy, Map<String, String>? reactions}) => ChatMessage(
        id: id,
        senderUid: senderUid,
        text: text,
        sentAt: sentAt,
        readBy: readBy ?? this.readBy,
        reactions: reactions ?? this.reactions,
      );
}
