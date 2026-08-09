import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Thin wrapper around AES-256-GCM for encrypting a message's plaintext
/// before it ever leaves the device, and decrypting what comes back
/// down from Firestore. Firestore only ever sees [EncryptedPayload]'s
/// base64 fields — never plaintext.
class EncryptedPayload {
  final String ciphertextB64;
  final String nonceB64;
  final String macB64;

  EncryptedPayload({required this.ciphertextB64, required this.nonceB64, required this.macB64});

  Map<String, dynamic> toMap() => {
        'ciphertext': ciphertextB64,
        'nonce': nonceB64,
        'mac': macB64,
      };

  factory EncryptedPayload.fromMap(Map<String, dynamic> map) => EncryptedPayload(
        ciphertextB64: map['ciphertext'] as String,
        nonceB64: map['nonce'] as String,
        macB64: map['mac'] as String,
      );
}

class MessageCrypto {
  static final _algorithm = AesGcm.with256bits();

  static Future<EncryptedPayload> encrypt(String plaintext, SecretKey key) async {
    final secretBox = await _algorithm.encrypt(utf8.encode(plaintext), secretKey: key);
    return EncryptedPayload(
      ciphertextB64: base64Encode(secretBox.cipherText),
      nonceB64: base64Encode(secretBox.nonce),
      macB64: base64Encode(secretBox.mac.bytes),
    );
  }

  static Future<String> decrypt(EncryptedPayload payload, SecretKey key) async {
    final secretBox = SecretBox(
      base64Decode(payload.ciphertextB64),
      nonce: base64Decode(payload.nonceB64),
      mac: Mac(base64Decode(payload.macB64)),
    );
    final plainBytes = await _algorithm.decrypt(secretBox, secretKey: key);
    return utf8.decode(plainBytes);
  }
}
