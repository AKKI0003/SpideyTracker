import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../../../../core/widgets/location_tag_chip.dart';
import '../../../../core/widgets/pixel_button.dart';

/// Tapping a live location marker (yourself sharing, or another party
/// member) used to do nothing at all — this gives it the same "where
/// actually is this" answer that tapping a static pin already gives,
/// just styled around the live/green identity instead of a saved pin.
Future<void> showLiveLocationSheet(
  BuildContext context, {
  required String label,
  required LatLng location,
}) {
  return showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (context) => Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          color: Colors.greenAccent,
          boxShadow: [
            BoxShadow(color: Colors.black, offset: Offset(5, 5), blurRadius: 0),
          ],
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.all(18),
          decoration: const BoxDecoration(
            color: Color(0xFF0A1128),
            border: Border(
              top: BorderSide(color: Color(0xFF1B3A6B), width: 2),
              left: BorderSide(color: Color(0xFF1B3A6B), width: 2),
              right: BorderSide(color: Color(0xFF1B3A6B), width: 2),
              bottom: BorderSide(color: Color(0xFF1B3A6B), width: 2),
            ),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 8,
                    height: 8,
                    decoration: const BoxDecoration(
                      color: Colors.greenAccent,
                      shape: BoxShape.circle,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '${label.toUpperCase()} \u00b7 LIVE',
                      style: GoogleFonts.pressStart2p(fontSize: 11, color: Colors.greenAccent),
                    ),
                  ),
                  GestureDetector(
                    onTap: () => Navigator.pop(context),
                    child: const Icon(Icons.close, size: 16, color: Colors.white70),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              LocationTagChip(location: location, accent: Colors.greenAccent),
              const SizedBox(height: 20),
              PixelButton(
                label: 'CLOSE',
                color: Colors.greenAccent,
                fullWidth: true,
                onTap: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
