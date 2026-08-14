import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

/// Calls the Vercel notify-server endpoint (see notify-server/README.md)
/// right after a pin or message is written to Firestore.
///
/// This replaces the old Firestore-triggered Cloud Functions
/// (notifyOnNewPin / notifyOnNewMessage) — same "look up party members,
/// send a push" logic, just running on Vercel and called explicitly by
/// the client instead of auto-triggering, since Cloud Functions
/// requires the Blaze plan.
///
/// Fire-and-forget by design: a failed or slow push notification should
/// never block or fail the pin/message creation the user is actually
/// waiting on, so every call here swallows its own errors.
class NotifyTrigger {
  /// Paste the URL printed by `vercel --prod` here, e.g.
  /// 'https://spidertrack-notify-server.vercel.app/api/notify'
  static const String _endpoint = 'https://spideytrack.vercel.app/api/notify';

  /// Must match the NOTIFY_SECRET you set with `vercel env add`.
  /// This is a shared secret, not a real credential — it just stops
  /// randoms from hitting your endpoint and spamming your users'
  /// devices with pushes. Fine to ship in the client for a small
  /// private party app like this.
  static const String _secret = '29789668fe66a152de46448101db6cbcf9fc6476f7525bc2fc1d9d988ed132a5';

  static Future<void> firePinCreated({
    required String partyId,
    required String actorUid,
  }) => _fire(type: 'pin', partyId: partyId, actorUid: actorUid);

  static Future<void> fireMessageCreated({
    required String partyId,
    required String actorUid,
  }) => _fire(type: 'message', partyId: partyId, actorUid: actorUid);

  static Future<void> _fire({
    required String type,
    required String partyId,
    required String actorUid,
  }) async {
    debugPrint('[NotifyTrigger] firing $type notify for party=$partyId actor=$actorUid');
    try {
      final response = await http
          .post(
            Uri.parse(_endpoint),
            headers: {
              'Content-Type': 'application/json',
              'x-notify-secret': _secret,
            },
            body: jsonEncode({
              'type': type,
              'partyId': partyId,
              'actorUid': actorUid,
            }),
          )
          .timeout(const Duration(seconds: 8));
      debugPrint('[NotifyTrigger] response ${response.statusCode}: ${response.body}');
    } catch (e) {
      debugPrint('[NotifyTrigger] FAILED: $e');
      // Best-effort only — the pin/message itself already succeeded by
      // the time this is called, so a notify failure shouldn't surface
      // to the user or block anything.
    }
  }
}