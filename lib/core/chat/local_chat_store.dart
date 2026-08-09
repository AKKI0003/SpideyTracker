import 'dart:convert';
import 'package:hive_flutter/hive_flutter.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../../features/chat/domain/chat_message.dart';

/// Chat history's actual permanent home. Messages are decrypted once
/// (client-side, using the party key from PartyKeyService) and written
/// here — this Hive box is itself encrypted at rest with a key that
/// lives in the OS keychain/keystore (via flutter_secure_storage), so
/// even someone with raw filesystem access to the device can't read
/// chat history without also compromising the OS-level secure storage.
///
/// This is deliberately separate from the party-level AES key used for
/// transit encryption — that key can be re-derived by anyone with the
/// invite code (that's what makes it *shared*), whereas this local
/// storage key is unique per device and never leaves it.
class LocalChatStore {
  static const _secureStorage = FlutterSecureStorage();
  static const _storageKeyName = 'spidertrack_hive_encryption_key';
  static Box<String>? _box;

  static Future<void> init() async {
    await Hive.initFlutter();

    var keyString = await _secureStorage.read(key: _storageKeyName);
    if (keyString == null) {
      final newKey = Hive.generateSecureKey();
      keyString = base64UrlEncode(newKey);
      await _secureStorage.write(key: _storageKeyName, value: keyString);
    }
    final encryptionKey = base64Url.decode(keyString);

    _box = await Hive.openBox<String>(
      'chat_history',
      encryptionCipher: HiveAesCipher(encryptionKey),
    );
  }

  static Box<String> get _requireBox {
    final box = _box;
    if (box == null) {
      throw StateError('LocalChatStore.init() must be called before use (call it in main()).');
    }
    return box;
  }

  /// Stores one decrypted message as JSON, keyed by "partyId:messageId"
  /// so history for different parties never mixes.
  static Future<void> saveMessage({
    required String partyId,
    required String messageId,
    required Map<String, dynamic> decryptedMessageJson,
  }) async {
    await _requireBox.put('$partyId:$messageId', jsonEncode(decryptedMessageJson));
  }

  static List<Map<String, dynamic>> messagesForParty(String partyId) {
    final prefix = '$partyId:';
    return _requireBox.keys
        .where((k) => (k as String).startsWith(prefix))
        .map((k) => jsonDecode(_requireBox.get(k)!) as Map<String, dynamic>)
        .toList();
  }

  static Future<void> deleteMessage(String partyId, String messageId) async {
    await _requireBox.delete('$partyId:$messageId');
  }

  /// Wipes all locally stored chat history for a party — call this when
  /// leaving/deleting a party, since there's no server copy to fall
  /// back on once this is gone.
  static Future<void> clearParty(String partyId) async {
    final prefix = '$partyId:';
    final keys = _requireBox.keys.where((k) => (k as String).startsWith(prefix)).toList();
    await _requireBox.deleteAll(keys);
  }

  // --- Unread tracking ---
  // Tracks when each party's chat was last opened so the CHAT button
  // can show an unread badge without needing any server-side "unread
  // count" concept (which would mean storing per-user read state
  // server-side — unnecessary given messages already live locally).

  static Future<void> markChatOpened(String partyId) async {
    await _requireBox.put('_lastOpened:$partyId', DateTime.now().toIso8601String());
  }

  static bool hasUnread(String partyId, String myUid) {
    final lastOpenedRaw = _requireBox.get('_lastOpened:$partyId');
    final lastOpened = lastOpenedRaw != null ? DateTime.parse(lastOpenedRaw) : DateTime.fromMillisecondsSinceEpoch(0);

    return messagesForParty(partyId).any((json) {
      final msg = ChatMessage.fromLocalJson(json);
      return msg.senderUid != myUid && msg.sentAt.isAfter(lastOpened);
    });
  }
}
