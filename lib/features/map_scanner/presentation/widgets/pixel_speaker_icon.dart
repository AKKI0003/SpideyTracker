import 'package:flutter/material.dart';

/// Hand-authored 8-bit speaker glyph, drawn as blocky square "pixels"
/// on a fixed grid instead of a smooth Material icon — matches the
/// arcade/CRT look of the rest of the HUD without tipping into messy
/// or hard-to-read territory (the shape is deliberately simple and
/// symmetric so it stays legible at 18-20px).
///
/// Two states share the same speaker-body pixels; only the right-hand
/// side switches between two curved "sound wave" arcs and a small "X"
/// when muted.
class PixelSpeakerIcon extends StatelessWidget {
  final double size;
  final bool isMuted;
  final Color color;

  const PixelSpeakerIcon({
    super.key,
    required this.isMuted,
    required this.color,
    this.size = 18,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PixelSpeakerPainter(isMuted: isMuted, color: color),
      ),
    );
  }
}

class _PixelSpeakerPainter extends CustomPainter {
  static const int gridWidth = 12;
  static const int gridHeight = 10;

  // The speaker body: a small diamond-ish cone, the same in both states.
  static const List<Point2i> _body = [
    Point2i(3, 0), Point2i(4, 0),
    Point2i(2, 1), Point2i(3, 1), Point2i(4, 1),
    Point2i(1, 2), Point2i(2, 2), Point2i(3, 2), Point2i(4, 2),
    Point2i(0, 3), Point2i(1, 3), Point2i(2, 3), Point2i(3, 3), Point2i(4, 3),
    Point2i(0, 4), Point2i(1, 4), Point2i(2, 4), Point2i(3, 4), Point2i(4, 4),
    Point2i(0, 5), Point2i(1, 5), Point2i(2, 5), Point2i(3, 5), Point2i(4, 5),
    Point2i(0, 6), Point2i(1, 6), Point2i(2, 6), Point2i(3, 6), Point2i(4, 6),
    Point2i(1, 7), Point2i(2, 7), Point2i(3, 7), Point2i(4, 7),
    Point2i(2, 8), Point2i(3, 8), Point2i(4, 8),
    Point2i(3, 9), Point2i(4, 9),
  ];

  // Two blocky "sound wave" arcs, unmuted only.
  static const List<Point2i> _waves = [
    Point2i(7, 3), Point2i(7, 4), Point2i(7, 5), Point2i(7, 6),
    Point2i(8, 2), Point2i(8, 7),
    Point2i(10, 3), Point2i(10, 4), Point2i(10, 5), Point2i(10, 6),
    Point2i(9, 2), Point2i(9, 7),
  ];

  // Small pixel "X", muted only.
  static const List<Point2i> _mutedX = [
    Point2i(7, 2), Point2i(11, 2),
    Point2i(8, 3), Point2i(10, 3),
    Point2i(9, 4),
    Point2i(9, 5),
    Point2i(8, 6), Point2i(10, 6),
    Point2i(7, 7), Point2i(11, 7),
  ];

  final bool isMuted;
  final Color color;

  _PixelSpeakerPainter({required this.isMuted, required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    final px = size.width / gridWidth;
    final py = size.height / gridHeight;

    final bodyPaint = Paint()..color = color;
    for (final p in _body) {
      canvas.drawRect(
        Rect.fromLTWH(p.x * px, p.y * py, px, py),
        bodyPaint,
      );
    }

    final accentPaint = Paint()
      ..color = isMuted ? color : color.withOpacity(0.9);
    for (final p in (isMuted ? _mutedX : _waves)) {
      canvas.drawRect(
        Rect.fromLTWH(p.x * px, p.y * py, px, py),
        accentPaint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _PixelSpeakerPainter oldDelegate) =>
      oldDelegate.isMuted != isMuted || oldDelegate.color != color;
}

class Point2i {
  final int x;
  final int y;
  const Point2i(this.x, this.y);
}