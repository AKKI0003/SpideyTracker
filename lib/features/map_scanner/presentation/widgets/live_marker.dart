import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'spider_mask_icon.dart';

/// Wraps a SpiderMaskIcon with a pulsing ring behind it (for live-sharing
/// markers) and an optional small username label underneath, so two
/// people wearing the same mask are still easy to tell apart at a glance.
class LiveMarker extends StatefulWidget {
  final double size;
  final bool isGwenTheme;
  final String? maskId;
  final String? label;

  const LiveMarker({
    super.key,
    this.size = 40,
    this.isGwenTheme = false,
    this.maskId,
    this.label,
  });

  @override
  State<LiveMarker> createState() => _LiveMarkerState();
}

class _LiveMarkerState extends State<LiveMarker> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final resolvedId = widget.maskId ?? (widget.isGwenTheme ? 'spidergwen' : 'spiderman');
    final ringColor = widget.isGwenTheme ? Colors.pinkAccent : Colors.greenAccent;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: widget.size * 2,
          height: widget.size * 2,
          child: Stack(
            alignment: Alignment.center,
            children: [
              AnimatedBuilder(
                animation: _controller,
                builder: (context, _) {
                  final t = _controller.value;
                  return Container(
                    width: widget.size * (1 + t),
                    height: widget.size * (1 + t),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: ringColor.withOpacity(1 - t),
                        width: 2,
                      ),
                    ),
                  );
                },
              ),
              SpiderMaskIcon(size: widget.size, maskId: resolvedId),
              // Connectivity dot removed — it read as detached/floating
              // from the pin at small map zoom levels. The pulsing ring
              // above is the only "this is live" signal now.
            ],
          ),
        ),
        if (widget.label != null && widget.label!.isNotEmpty)
          Container(
            margin: const EdgeInsets.only(top: 2),
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.8),
              border: Border.all(color: ringColor.withOpacity(0.6), width: 0.8),
              borderRadius: BorderRadius.circular(3),
            ),
            child: Text(
              widget.label!,
              maxLines: 1,
              overflow: TextOverflow.visible,
              softWrap: false,
              style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.white),
            ),
          ),
      ],
    );
  }
}