import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../location/reverse_geocode_service.dart';

/// Small pixel-styled chip showing a human-readable place name for a
/// coordinate ("LOCATING..." while the lookup is in flight, then the
/// resolved place) — used anywhere a pin's or a live location's
/// position should be shown to the user instead of raw lat/lng.
class LocationTagChip extends StatefulWidget {
  final LatLng location;
  final Color accent;

  const LocationTagChip({
    super.key,
    required this.location,
    this.accent = Colors.cyanAccent,
  });

  @override
  State<LocationTagChip> createState() => _LocationTagChipState();
}

class _LocationTagChipState extends State<LocationTagChip> {
  String? _label;

  @override
  void initState() {
    super.initState();
    _resolve();
  }

  @override
  void didUpdateWidget(covariant LocationTagChip oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.location != widget.location) {
      setState(() => _label = null);
      _resolve();
    }
  }

  Future<void> _resolve() async {
    final label = await ReverseGeocodeService.lookup(widget.location);
    if (mounted) setState(() => _label = label);
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.black.withOpacity(0.45),
        border: Border.all(color: widget.accent.withOpacity(0.7), width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.location_on, size: 12, color: widget.accent),
          const SizedBox(width: 6),
          Flexible(
            child: Text(
              _label ?? 'LOCATING...',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white70, height: 1.4),
            ),
          ),
        ],
      ),
    );
  }
}
