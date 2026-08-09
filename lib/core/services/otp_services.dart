import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:firebase_auth/firebase_auth.dart';

class OtpService {
  // IMPORTANT: this MUST be your real deployed notify-server URL, not
  // the placeholder below. Run `vercel --prod` inside notify-server/
  // and paste what it prints. The exact same URL also needs to go in
  // lib/core/storage/b2_upload_service.dart and notify_trigger.dart —
  // all three currently share this same placeholder, so all three will
  // fail identically until you set the real one everywhere.
  static const String _baseUrl = 'https://spideytrack.vercel.app';

  static Future<String?> _authToken() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return null;
    return user.getIdToken();
  }

  /// Turns a raw HTTP response into either a decoded JSON map or a
  /// clear exception — never lets a jsonDecode FormatException escape
  /// raw, since that's meaningless to a user ("Unexpected character at
  /// character 1" tells you nothing about what actually went wrong).
  /// The most common real cause: _baseUrl above is still the
  /// placeholder / a wrong URL, so the server returned an HTML error
  /// page instead of JSON.
  static Map<String, dynamic> _decodeOrThrow(http.Response response) {
    final trimmed = response.body.trim();
    if (trimmed.isEmpty) {
      throw Exception(
        'Server returned an empty response (status ${response.statusCode}). '
        'Check that OtpService._baseUrl points at your real deployed notify-server.',
      );
    }
    if (!trimmed.startsWith('{') && !trimmed.startsWith('[')) {
      throw Exception(
        'Server did not return JSON (status ${response.statusCode}). '
        'This usually means _baseUrl in otp_services.dart is still the placeholder '
        'or otherwise wrong — check it matches your real Vercel deployment URL.',
      );
    }
    try {
      return jsonDecode(trimmed) as Map<String, dynamic>;
    } on FormatException {
      throw Exception('Server returned malformed JSON (status ${response.statusCode}).');
    }
  }

  static Future<void> sendCode(String email) async {
    final token = await _authToken();
    if (token == null) throw Exception('Not signed in');

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_baseUrl/api/otp'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'action': 'send', 'email': email}),
      );
    } catch (e) {
      throw Exception('Could not reach the server — check your internet connection and that _baseUrl is correct. ($e)');
    }

    if (response.statusCode != 200) {
      final body = _decodeOrThrow(response);
      throw Exception(body['error'] ?? 'Failed to send code');
    }
  }

  static Future<void> verifyCode(String code) async {
    final token = await _authToken();
    if (token == null) throw Exception('Not signed in');

    final http.Response response;
    try {
      response = await http.post(
        Uri.parse('$_baseUrl/api/otp'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $token',
        },
        body: jsonEncode({'action': 'verify', 'code': code}),
      );
    } catch (e) {
      throw Exception('Could not reach the server — check your internet connection and that _baseUrl is correct. ($e)');
    }

    if (response.statusCode != 200) {
      final body = _decodeOrThrow(response);
      throw Exception(body['error'] ?? 'Verification failed');
    }
  }
}