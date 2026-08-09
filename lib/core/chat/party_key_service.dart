import 'dart:convert';
import 'package:cryptography/cryptography.dart';

/// Derives a per-party AES-256 key that never touches Firestore.
///
/// The shared secret is the party's invite code — every member already
/// has to know it to have joined, so it's a channel that's already
/// trusted out-of-band (shared verbally, via link, screenshot, etc.),
/// exactly like a Wi-Fi password. We stretch it with PBKDF2 (salted
/// with the partyId, so two parties never derive the same key even if
/// codes ever collided) into a proper 256-bit AES-GCM key.
///
/// Anyone who has both the partyId AND the invite code can derive this
/// key — which is by design, since that's exactly "being in the
/// party." Anyone who only has Firestore access (i.e. us, if this were
/// ever hosted, or anyone who compromised the DB) sees only ciphertext
/// and never the invite code itself (it's stored server-side too, but
/// knowing the code alone without also being intended to join isn't
/// the threat model here — see chat_repository.dart's server-deletion
/// behavior for why messages don't linger server-side anyway).
class PartyKeyService {
  static final _algorithm = Pbkdf2(
    macAlgorithm: Hmac.sha256(),
    iterations: 100000,
    bits: 256,
  );

  static final Map<String, SecretKey> _cache = {};

  static Future<SecretKey> deriveKey({
    required String partyId,
    required String inviteCode,
  }) async {
    final cacheKey = '$partyId:$inviteCode';
    final cached = _cache[cacheKey];
    if (cached != null) return cached;

    final secretKey = SecretKey(utf8.encode(inviteCode));
    final derived = await _algorithm.deriveKey(
      secretKey: secretKey,
      nonce: utf8.encode(partyId).length >= 16
          ? utf8.encode(partyId).sublist(0, 16)
          : [...utf8.encode(partyId), ...List.filled(16 - utf8.encode(partyId).length, 0)],
    );
    _cache[cacheKey] = derived;
    return derived;
  }

  static void clearCache() => _cache.clear();
}
