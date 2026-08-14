import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart';

/// One candidate returned by the geocoder, shown as a tappable row in
/// the suggestions list rather than being blindly jumped to.
class _PlaceSuggestion {
  final LatLng location;
  final String primary; // short label, e.g. "Springfield"
  final String secondary; // fuller context, e.g. "Illinois, United States"

  const _PlaceSuggestion({
    required this.location,
    required this.primary,
    required this.secondary,
  });
}

/// A small magnifying-glass icon that expands into a compact search
/// field on tap. Deliberately NOT a permanently-visible search bar —
/// the map's own text (road names, city labels) is already easy to
/// lose against the navy tint, so adding a second layer of always-on
/// text on top of it would make things worse, not better. This only
/// appears when explicitly requested.
///
/// Typing now shows a live dropdown of matching places — like Google
/// Maps — instead of silently jumping to whatever the geocoder's single
/// top result happened to be. That old behavior is exactly why it could
/// "teleport" to a same-named place on the other side of the world:
/// with only one candidate and no bias toward where the user actually
/// is, "Springfield" is as likely to resolve to Illinois as anywhere
/// else. Results are now biased toward [biasCenter] (soft bias, so a
/// deliberately distant search still works, it just doesn't win over a
/// closer match of similar relevance) and the person picks the exact
/// one they meant.
///
/// Geocoding uses OpenStreetMap's free Nominatim service — matches the
/// existing free tile provider, no API key required. Nominatim's usage
/// policy requires a real identifying User-Agent header on requests,
/// which is set below.
class SearchLocationButton extends StatefulWidget {
  final void Function(LatLng location, String label) onLocationFound;

  /// Optional anchor point (typically the user's current position) used
  /// to softly bias results toward nearby places with the same name.
  final LatLng? biasCenter;

  const SearchLocationButton({
    super.key,
    required this.onLocationFound,
    this.biasCenter,
  });

  @override
  State<SearchLocationButton> createState() => _SearchLocationButtonState();
}

class _SearchLocationButtonState extends State<SearchLocationButton> {
  bool _expanded = false;
  bool _isSearching = false;
  String? _error;
  List<_PlaceSuggestion> _suggestions = [];
  final _controller = TextEditingController();
  final _focusNode = FocusNode();
  Timer? _debounce;
  int _requestId = 0; // guards against a slow older request clobbering a newer one

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  void _toggle() {
    setState(() {
      _expanded = !_expanded;
      _error = null;
      if (!_expanded) {
        _suggestions = [];
        _controller.clear();
      }
    });
    if (_expanded) {
      Future.delayed(const Duration(milliseconds: 50), () {
        if (mounted) _focusNode.requestFocus();
      });
    }
  }

  void _onTextChanged(String value) {
    _debounce?.cancel();
    if (value.trim().isEmpty) {
      setState(() {
        _suggestions = [];
        _error = null;
        _isSearching = false;
      });
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 400), () => _fetchSuggestions(value.trim()));
  }

  Future<void> _fetchSuggestions(String query) async {
    final thisRequest = ++_requestId;
    setState(() {
      _isSearching = true;
      _error = null;
    });

    try {
      final params = {
        'q': query,
        'format': 'json',
        'limit': '5',
        'addressdetails': '1',
      };

      // Soft bias only (no `bounded=1`) — nudges ranking toward the
      // user's area without excluding a genuinely distant place they
      // meant to search for.
      final center = widget.biasCenter;
      if (center != null) {
        const span = 2.0; // roughly a couple hundred km box, generous on purpose
        params['viewbox'] =
            '${center.longitude - span},${center.latitude + span},${center.longitude + span},${center.latitude - span}';
      }

      final uri = Uri.parse('https://nominatim.openstreetmap.org/search')
          .replace(queryParameters: params);
      final response = await http.get(
        uri,
        headers: {'User-Agent': 'SpideyTrackerApp/1.0 (personal-use)'},
      );

      if (thisRequest != _requestId || !mounted) return; // a newer keystroke already superseded this

      if (response.statusCode != 200) {
        throw Exception('Search failed');
      }

      final results = jsonDecode(response.body) as List;
      final suggestions = results.map((r) {
        final map = r as Map<String, dynamic>;
        final displayName = (map['display_name'] as String?) ?? query;
        final parts = displayName.split(',').map((p) => p.trim()).toList();
        return _PlaceSuggestion(
          location: LatLng(
            double.parse(map['lat'] as String),
            double.parse(map['lon'] as String),
          ),
          primary: parts.isNotEmpty ? parts.first : displayName,
          secondary: parts.length > 1 ? parts.skip(1).take(3).join(', ') : '',
        );
      }).toList();

      setState(() {
        _isSearching = false;
        _suggestions = suggestions;
        _error = suggestions.isEmpty ? 'No results found' : null;
      });
    } catch (e) {
      if (thisRequest != _requestId || !mounted) return;
      setState(() {
        _isSearching = false;
        _error = 'Search failed — try again';
      });
    }
  }

  void _select(_PlaceSuggestion s) {
    widget.onLocationFound(s.location, s.primary);
    setState(() {
      _isSearching = false;
      _expanded = false;
      _suggestions = [];
      _controller.clear();
    });
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: _toggle,
          child: Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.6),
              border: Border.all(
                color: _expanded ? Colors.greenAccent : Colors.cyanAccent,
                width: 1.5,
              ),
              borderRadius: BorderRadius.circular(6),
            ),
            child: CustomPaint(
              painter: _MagnifierPainter(
                color: _expanded ? Colors.greenAccent : Colors.cyanAccent,
              ),
            ),
          ),
        ),
        if (_expanded)
          Container(
            margin: const EdgeInsets.only(top: 8),
            width: 220,
            constraints: const BoxConstraints(maxHeight: 280),
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: const Color(0xFF0A1128).withOpacity(0.97),
              border: Border.all(color: Colors.cyanAccent, width: 2),
              borderRadius: BorderRadius.circular(6),
              boxShadow: [
                BoxShadow(color: Colors.cyanAccent.withOpacity(0.2), blurRadius: 10),
              ],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        focusNode: _focusNode,
                        onChanged: _onTextChanged,
                        style: const TextStyle(color: Colors.white, fontSize: 13),
                        decoration: const InputDecoration(
                          isDense: true,
                          hintText: 'Search a place...',
                          hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                          border: InputBorder.none,
                          contentPadding: EdgeInsets.symmetric(vertical: 6),
                        ),
                      ),
                    ),
                    if (_isSearching)
                      const SizedBox(
                        width: 14,
                        height: 14,
                        child: CircularProgressIndicator(strokeWidth: 2, color: Colors.cyanAccent),
                      ),
                  ],
                ),
                if (_error != null)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text(
                      _error!,
                      style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.redAccent),
                    ),
                  ),
                if (_suggestions.isNotEmpty)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(top: 6),
                      child: ListView.separated(
                        shrinkWrap: true,
                        padding: EdgeInsets.zero,
                        itemCount: _suggestions.length,
                        separatorBuilder: (_, __) => Divider(
                          height: 1,
                          color: Colors.cyanAccent.withOpacity(0.15),
                        ),
                        itemBuilder: (context, i) {
                          final s = _suggestions[i];
                          return InkWell(
                            onTap: () => _select(s),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(vertical: 7),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Padding(
                                    padding: EdgeInsets.only(top: 2, right: 6),
                                    child: Icon(Icons.place, size: 13, color: Colors.cyanAccent),
                                  ),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          s.primary,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontSize: 12.5,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                        if (s.secondary.isNotEmpty)
                                          Text(
                                            s.secondary,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                            style: const TextStyle(color: Colors.white54, fontSize: 10.5),
                                          ),
                                      ],
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// A clean, stroke-drawn magnifying glass — a circle with a handle —
/// instead of the previous filled pixel-grid blob, which read as a
/// shapeless clump at small sizes rather than a recognizable icon.
class _MagnifierPainter extends CustomPainter {
  final Color color;
  const _MagnifierPainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0
      ..strokeCap = StrokeCap.square;

    final lensRadius = size.width * 0.24;
    final lensCenter = Offset(size.width * 0.42, size.height * 0.42);

    canvas.drawCircle(lensCenter, lensRadius, paint);

    final handleStart = Offset(
      lensCenter.dx + lensRadius * 0.75,
      lensCenter.dy + lensRadius * 0.75,
    );
    final handleEnd = Offset(size.width * 0.78, size.height * 0.78);
    canvas.drawLine(handleStart, handleEnd, paint);
  }

  @override
  bool shouldRepaint(covariant _MagnifierPainter oldDelegate) => oldDelegate.color != color;
}
