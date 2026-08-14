import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cryptography/cryptography.dart';
import '../../../core/chat/party_key_service.dart';
import '../../../core/chat/message_crypto.dart';
import '../../../core/chat/local_chat_store.dart';
import '../../../core/notifications/notify_trigger.dart';
import '../domain/chat_message.dart';

/// Firestore's messages subcollection is a TRANSIENT RELAY, not
/// storage. The lifecycle for one message:
///
///  1. Sender encrypts locally, uploads ciphertext to
///     parties/{partyId}/messages/{id}.
///  2. Every other member's client picks it up via the live listener,
///     decrypts it locally, and writes the plaintext into
///     LocalChatStore (encrypted at rest on their device).
///  3. Each recipient marks themselves in `deliveredTo` on the
///     Firestore doc once they've saved it locally.
///  4. Once `deliveredTo` covers every party member, ANY client (the
///     one that notices it first) deletes the Firestore doc — the
///     message now only exists as encrypted-at-rest local copies on
///     each member's device, matching "we don't have the need for
///     storage of those chats" server-side.
///
/// A member who is offline when a message is sent will simply never
/// see it and it will be pruned once everyone else has it — a
/// deliberate trade-off given the "don't keep it server-side" goal
/// (there is no true offline-mailbox guarantee here).
class ChatRepository {
  final _firestore = FirebaseFirestore.instance;

  CollectionReference<Map<String, dynamic>> _messagesRef(String partyId) =>
      _firestore.collection('parties').doc(partyId).collection('messages');

  DocumentReference<Map<String, dynamic>> _typingRef(String partyId, String uid) =>
      _firestore.collection('parties').doc(partyId).collection('typing').doc(uid);

  Future<SecretKey> _keyFor(String partyId, String inviteCode) =>
      PartyKeyService.deriveKey(partyId: partyId, inviteCode: inviteCode);

  Future<void> sendMessage({
    required String partyId,
    required String inviteCode,
    required String senderUid,
    required String text,
  }) async {
    final key = await _keyFor(partyId, inviteCode);
    final payload = await MessageCrypto.encrypt(text, key);
    final docRef = _messagesRef(partyId).doc();

    await docRef.set({
      'senderUid': senderUid,
      ...payload.toMap(),
      'sentAt': FieldValue.serverTimestamp(),
      'deliveredTo': <String>[senderUid], // sender already "has" it locally
      'readBy': <String>[senderUid],
    });

    // Fire-and-forget, same as pin creation — never blocks sending,
    // and the notify server only ever receives partyId + senderUid,
    // never the message text (which is why it's encrypted at all).
    NotifyTrigger.fireMessageCreated(partyId: partyId, actorUid: senderUid);

    // Sender also saves their own plaintext locally immediately, rather
    // than waiting on the round-trip.
    await LocalChatStore.saveMessage(
      partyId: partyId,
      messageId: docRef.id,
      decryptedMessageJson: ChatMessage(
        id: docRef.id,
        senderUid: senderUid,
        text: text,
        sentAt: DateTime.now(),
        readBy: [senderUid],
      ).toLocalJson(),
    );
  }

  /// Listens for new/updated ciphertext, decrypts, persists locally,
  /// marks delivered, and prunes fully-delivered messages server-side.
  /// Call once per open chat screen; cancel the subscription on
  /// dispose.
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>> listenAndSync({
    required String partyId,
    required String inviteCode,
    required String myUid,
    required List<String> partyMemberUids,
    required void Function(ChatMessage message) onMessage,
  }) {
    return _messagesRef(partyId).snapshots().listen((snapshot) async {
      final key = await _keyFor(partyId, inviteCode);

      for (final change in snapshot.docChanges) {
        final doc = change.doc;
        final data = doc.data();
        if (data == null) continue;

        if (change.type == DocumentChangeType.removed) continue;

        final deliveredTo = List<String>.from(data['deliveredTo'] as List? ?? const []);
        final alreadyHaveLocally = deliveredTo.contains(myUid);

        String plaintext;
        if (alreadyHaveLocally) {
          // We've decrypted this one before; pull from local store to
          // avoid re-decrypting on every single snapshot (e.g. when
          // readBy/reactions update but text hasn't changed).
          final local = LocalChatStore.messagesForParty(partyId).where((m) => m['id'] == doc.id);
          if (local.isNotEmpty) {
            plaintext = local.first['text'] as String;
          } else {
            plaintext = await MessageCrypto.decrypt(EncryptedPayload.fromMap(data), key);
          }
        } else {
          plaintext = await MessageCrypto.decrypt(EncryptedPayload.fromMap(data), key);
        }

        final message = ChatMessage(
          id: doc.id,
          senderUid: data['senderUid'] as String,
          text: plaintext,
          sentAt: (data['sentAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
          readBy: List<String>.from(data['readBy'] as List? ?? const []),
        );

        await LocalChatStore.saveMessage(
          partyId: partyId,
          messageId: doc.id,
          decryptedMessageJson: message.toLocalJson(),
        );

        onMessage(message);

        if (!alreadyHaveLocally) {
          await doc.reference.update({
            'deliveredTo': FieldValue.arrayUnion([myUid]),
          });
        }

        // Prune once everyone in the party has a local copy.
        final updatedDelivered = {...deliveredTo, myUid};
        if (partyMemberUids.every((uid) => updatedDelivered.contains(uid))) {
          doc.reference.delete().catchError((_) {
            // Another client may have already deleted it — fine either way.
          });
        }
      }
    });
  }

  Future<void> markRead({required String partyId, required String messageId, required String uid}) async {
    await _messagesRef(partyId).doc(messageId).update({
      'readBy': FieldValue.arrayUnion([uid]),
    }).catchError((_) {
      // Doc may have already been pruned server-side — that's fine,
      // read state for pruned messages only matters locally from here.
    });
  }

  Future<void> setTyping({required String partyId, required String uid, required bool isTyping}) async {
    if (isTyping) {
      await _typingRef(partyId, uid).set({'typingAt': FieldValue.serverTimestamp()});
    } else {
      await _typingRef(partyId, uid).delete().catchError((_) {});
    }
  }

  /// Members whose typing doc is fresher than 5 seconds ago — a doc
  /// older than that is treated as stale (client likely closed without
  /// clearing it) rather than "still typing forever."
  Stream<List<String>> watchTypingUids(String partyId, {required String excludeUid}) {
    return _firestore
        .collection('parties')
        .doc(partyId)
        .collection('typing')
        .snapshots()
        .map((snap) {
      final now = DateTime.now();
      return snap.docs
          .where((d) => d.id != excludeUid)
          .where((d) {
            final ts = (d.data()['typingAt'] as Timestamp?)?.toDate();
            return ts != null && now.difference(ts).inSeconds < 5;
          })
          .map((d) => d.id)
          .toList();
    });
  }
}
