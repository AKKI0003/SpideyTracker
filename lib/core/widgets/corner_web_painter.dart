import 'package:flutter/material.dart';
import 'dart:math';

/// A procedurally-drawn corner cobweb — no image assets, so it can
/// never go missing/broken the way a bundled PNG can. Anchored at the
/// canvas's top-right corner: a handful of radial strands sweep from
/// straight-down to straight-left (filling that corner's quadrant),
/// with a couple of connecting "rungs" bowed slightly INWARD (toward
/// the corner) between them — like a simple hand-drawn web sketch
/// rather than a dense, glowing radar-style mesh.
///
/// Deliberately sparse and mostly flat/white, matching a plain ink
/// cobweb illustration: a soft glow is still there for readability
/// against the map, but kept subtle rather than neon.
///
/// Used in two places: the map's pin-filter web (brighter, interactive)
/// and the chat screen's decorative corner (very low opacity) — same
/// painter, same visual language.
class CornerWebPainter extends CustomPainter {
  final Color color;
  final double opacity;
  final int strandCount;
  final int ringCount;

  const CornerWebPainter({
    this.color = Colors.white,
    this.opacity = 1.0,
    this.strandCount = 5,
    this.ringCount = 3,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final corner = Offset(size.width, 0);

    final ends = <Offset>[];
    for (int i = 0; i <= strandCount; i++) {
      final t = i / strandCount;
      final angle = pi / 2 + t * (pi / 2); // straight-down -> straight-left
      final end = corner + Offset(cos(angle), sin(angle)) * size.width;
      ends.add(end);
    }

    // Glow kept small and soft rather than a bright neon halo — this
    // is what "less glowy" comes down to: lower opacity, tighter blur,
    // thinner stroke.
    final glowPaint = Paint()
      ..color = color.withOpacity(0.35 * opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.6
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    final linePaint = Paint()
      ..color = color.withOpacity(opacity)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.1
      ..strokeCap = StrokeCap.round;

    void drawJitteredSegment(Offset a, Offset b) {
      const steps = 4;
      final dir = b - a;
      final len = dir.distance;
      if (len == 0) return;
      final normal = Offset(-dir.dy, dir.dx) / len;

      Offset prev = a;
      for (int s = 1; s <= steps; s++) {
        final t = s / steps;
        final base = Offset.lerp(a, b, t)!;
        // Small deterministic wobble (sine-based, not random) so every
        // strand reads as slightly hand-drawn rather than ruler-straight.
        final jitter = s == steps ? 0.0 : sin(t * pi * 2.5 + a.dx * 0.05) * 0.9;
        final point = base + normal * jitter;
        canvas.drawLine(prev, point, glowPaint);
        canvas.drawLine(prev, point, linePaint);
        prev = point;
      }
    }

    for (final end in ends) {
      drawJitteredSegment(corner, end);
    }

    // Rungs between strands bow slightly INWARD (toward the corner)
    // instead of outward — a subtle concave sag rather than puffing
    // out into the screen.
    for (int r = 1; r <= ringCount; r++) {
      final frac = r / (ringCount + 1);
      Offset? prevPoint;
      for (int i = 0; i < ends.length; i++) {
        final point = Offset.lerp(corner, ends[i], frac)!;
        if (prevPoint != null) {
          final mid = Offset((prevPoint.dx + point.dx) / 2, (prevPoint.dy + point.dy) / 2);
          final towardCorner = corner - mid;
          final bowed = mid + towardCorner * 0.10;
          final path = Path()
            ..moveTo(prevPoint.dx, prevPoint.dy)
            ..quadraticBezierTo(bowed.dx, bowed.dy, point.dx, point.dy);
          canvas.drawPath(path, glowPaint);
          canvas.drawPath(path, linePaint);
        }
        prevPoint = point;
      }
    }
  }

  @override
  bool shouldRepaint(covariant CornerWebPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.opacity != opacity ||
      oldDelegate.strandCount != strandCount ||
      oldDelegate.ringCount != ringCount;
}

/// A short thread (the strand a spider/logo hangs from, or a filter
/// chip's connecting strand), drawn with the same small jitter as
/// [CornerWebPainter]'s strands instead of one flat line — and, like
/// the rest of this painter, kept subtle rather than glowing.
class PixelThreadPainter extends CustomPainter {
  final Color color;
  final Axis axis;

  const PixelThreadPainter({this.color = Colors.white, this.axis = Axis.vertical});

  @override
  void paint(Canvas canvas, Size size) {
    final a = Offset.zero;
    final b = axis == Axis.vertical ? Offset(0, size.height) : Offset(size.width, 0);

    final glowPaint = Paint()
      ..color = color.withOpacity(0.3)
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round
      ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1);
    final linePaint = Paint()
      ..color = color.withOpacity(0.85)
      ..strokeWidth = 1
      ..strokeCap = StrokeCap.round;

    const steps = 6;
    final dir = b - a;
    final len = dir.distance;
    final normal = len == 0 ? const Offset(1, 0) : Offset(-dir.dy, dir.dx) / len;

    Offset prev = a;
    for (int s = 1; s <= steps; s++) {
      final t = s / steps;
      final base = Offset.lerp(a, b, t)!;
      final jitter = s == steps ? 0.0 : sin(t * pi * 4) * 0.8;
      final point = base + normal * jitter;
      canvas.drawLine(prev, point, glowPaint);
      canvas.drawLine(prev, point, linePaint);
      prev = point;
    }
  }

  @override
  bool shouldRepaint(covariant PixelThreadPainter oldDelegate) =>
      oldDelegate.color != color || oldDelegate.axis != axis;
}