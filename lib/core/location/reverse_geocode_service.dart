import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// Turns a lat/lng into a short human-readable place name — "Koramangala,
/// Bengaluru" instead of raw coordinates. Uses OpenStreetMap's free
/// Nominatim API: no API key, no billing, just a required User-Agent
/// identifying the app per their usage policy (they rate-limit abusive/
/// unidentified traffic).
///
/// Results are cached in memory keyed to ~11m precision (4 decimal
/// places) since the same pin's location gets looked up every time its
/// viewer opens — no reason to hit the network twice for the same spot
/// in one app session.
class ReverseGeocodeService {
  static final Map<String, String> _cache = {};

  static String _key(LatLng loc) =>
      '${loc.latitude.toStringAsFixed(4)},${loc.longitude.toStringAsFixed(4)}';

  static Future<String> lookup(LatLng location) async {
    final key = _key(location);
    final cached = _cache[key];
    if (cached != null) return cached;

    try {
      final uri = Uri.parse(
        'https://nominatim.openstreetmap.org/reverse'
        '?format=json&lat=${location.latitude}&lon=${location.longitude}&zoom=16&addressdetails=1',
      );
      final response = await http
          .get(uri, headers: {'User-Agent': 'SpideyTracker/1.0 (private party location app)'})
          .timeout(const Duration(seconds: 8));

      if (response.statusCode != 200) {
        throw Exception('HTTP ${response.statusCode}');
      }

      final data = jsonDecode(response.body) as Map<String, dynamic>;
      final address = data['address'] as Map<String, dynamic>?;

      String? label;
      if (address != null) {
        final locality = address['suburb'] ??
            address['neighbourhood'] ??
            address['road'] ??
            address['hamlet'];
        final city = address['city'] ?? address['town'] ?? address['village'] ?? address['county'];
        final parts = [locality, city].whereType<String>().toList();
        if (parts.isNotEmpty) label = parts.join(', ');
      }

      label ??= (data['display_name'] as String?)?.split(',').take(2).join(',').trim();
      label ??= _fallback(location);

      _cache[key] = label;
      return label;
    } catch (_) {
      // No network, rate-limited, or a malformed response — the raw
      // coordinates are still a useful fallback rather than an error
      // state with nothing to show at all.
      return _fallback(location);
    }
  }

  static String _fallback(LatLng location) =>
      '${location.latitude.toStringAsFixed(4)}, ${location.longitude.toStringAsFixed(4)}';
}
