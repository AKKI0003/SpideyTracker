import 'dart:convert';
import 'dart:typed_data';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;

/// Talks to notify-server's /api/b2 endpoint to get a presigned B2
/// upload URL, PUTs the photo bytes there directly, then hands back
/// everything PinsRepository needs to store on the pin. B2's
/// application key never exists on this side — only a short-lived
/// signed URL does.
class B2UploadService {
  /// Same Vercel deployment as NotifyTrigger — paste your production
  /// URL here once, e.g. 'https://spideytrack.vercel.app'.
  static const String _baseUrl = 'https://spideytrack.vercel.app';

  static Future<String> _idToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) throw StateError('Not signed in');
    final token = await user.getIdToken();
    if (token == null) throw StateError('Could not get an ID token');
    return token;
  }

  /// Uploads [bytes] for a new photo on [pinId] in [partyId], returns
  /// everything needed to build a [PinPhoto]: the 7-day signed
  /// download URL, the permanent B2 object key, and the real pixel
  /// dimensions (decoded here client-side so the viewer can size its
  /// frame to the photo's actual aspect ratio).
  static Future<B2UploadResult> uploadPhoto({
    required String partyId,
    required String pinId,
    required String fileName,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final decoded = img.decodeImage(bytes);
    final width = (decoded?.width ?? 1).toDouble();
    final height = (decoded?.height ?? 1).toDouble();

    final token = await _idToken();
    final presignResponse = await http.post(
      Uri.parse('$_baseUrl/api/b2'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'upload',
        'partyId': partyId,
        'pinId': pinId,
        'fileName': fileName,
        'contentType': contentType,
      }),
    );

    if (presignResponse.statusCode != 200) {
      throw Exception('Presign failed: ${presignResponse.body}');
    }
    final presign = jsonDecode(presignResponse.body) as Map<String, dynamic>;
    final uploadUrl = presign['uploadUrl'] as String;
    final downloadUrl = presign['downloadUrl'] as String;
    final objectKey = presign['objectKey'] as String;

    final putResponse = await http.put(
      Uri.parse(uploadUrl),
      // Deliberately NOT sending a Content-Type header here — B2's
      // presigned PUT signs Content-Type when it's set on the server's
      // PutObjectCommand, and even a byte-identical-looking mismatch
      // (e.g. a charset suffix added by some HTTP stacks) causes a
      // silent 403 SignatureDoesNotMatch that this code used to only
      // report as "failed" with no detail. The server no longer signs
      // Content-Type either (see notify-server/api/b2.js) — the object
      // still round-trips fine since Image.network decodes by magic
      // bytes, not by the stored MIME type.
      body: bytes,
    );
    if (putResponse.statusCode != 200) {
      throw Exception(
        'Upload to B2 failed: HTTP ${putResponse.statusCode} — ${putResponse.body}',
      );
    }

    return B2UploadResult(
      downloadUrl: downloadUrl,
      objectKey: objectKey,
      width: width,
      height: height,
    );
  }

  /// Re-signs a GET url for an existing photo — call this before a
  /// photo's 7-day-old link actually expires (see SelfHealingPinImage),
  /// which is what keeps photos viewable indefinitely instead of
  /// eventually turning into a broken-image icon.
  static Future<String> refreshDownloadUrl({
    required String partyId,
    required String pinId,
    required String objectKey,
  }) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/b2'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'refresh',
        'partyId': partyId,
        'pinId': pinId,
        'objectKey': objectKey,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Refresh failed: ${response.body}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    return data['downloadUrl'] as String;
  }

  /// Deletes a single photo's underlying B2 object. Caller is
  /// responsible for also removing it from the pin's Firestore
  /// `photos` array (see PinsRepository.deletePhotoFromPin) — this
  /// only cleans up the storage side.
  static Future<void> deletePhoto({
    required String partyId,
    required String pinId,
    required String objectKey,
  }) async {
    final token = await _idToken();
    final response = await http.post(
      Uri.parse('$_baseUrl/api/b2'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $token',
      },
      body: jsonEncode({
        'action': 'delete',
        'partyId': partyId,
        'pinId': pinId,
        'objectKey': objectKey,
      }),
    );
    if (response.statusCode != 200) {
      throw Exception('Delete failed: ${response.body}');
    }
  }
}

class B2UploadResult {
  final String downloadUrl;
  final String objectKey;
  final double width;
  final double height;

  const B2UploadResult({
    required this.downloadUrl,
    required this.objectKey,
    required this.width,
    required this.height,
  });
}
