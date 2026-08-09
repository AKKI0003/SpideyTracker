import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/pins/spider_icon_catalog.dart';
import '../../../../core/widgets/hue_color_picker.dart';
import 'pixel_badge_frame.dart';

/// Feature 1 - Static Memory Pins.
///
/// Renders a saved pin as a chunky pixel-art notched badge (not a plain
/// circle) with the owner's chosen spider icon inside, auto-contrasted
/// against the background, and a small pixel-font username underneath.
/// Sized to match LiveMarker's footprint so live and static pins read
/// as the same "weight" on the map — the visual difference is entirely
/// the badge-vs-mask look and the live pulse ring, not size.
class MemoryPinBadge extends StatelessWidget {
  final double size;
  final String spiderIconId;
  final Color backgroundColor;
  final String? username;

  const MemoryPinBadge({
    super.key,
    this.size = 42, // slightly larger than before — the badge was
    // reading small/cramped on the map at 36px, especially once the
    // icon inside got more room from PixelBadgeFrame's reduced padding
    required this.spiderIconId,
    required this.backgroundColor,
    this.username,
  });

  @override
  Widget build(BuildContext context) {
    final icon = SpiderIconCatalog.byId(spiderIconId);
    final iconColor = contrastingColorFor(backgroundColor);

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        PixelBadgeFrame(
          size: size,
          color: backgroundColor,
          child: icon.buildIcon(iconColor),
        ),
        if (username != null && username!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            constraints: BoxConstraints(maxWidth: size * 1.6),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.65),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              username!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.white),
            ),
          ),
      ],
    );
  }
}