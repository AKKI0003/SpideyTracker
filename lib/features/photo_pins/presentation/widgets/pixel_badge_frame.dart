import 'package:flutter/material.dart';

/// A circular badge with a deliberately blocky/rasterized edge instead
/// of a smooth vector circle — achieved by rendering the circle onto a
/// coarse pixel grid, so the silhouette has the stepped, jagged edge of
/// a low-res sprite rather than perfect anti-aliasing.
///
/// Redesigned from the flat single-color disc: adds a soft inner
/// highlight near the top-left (classic arcade-coin/game-token shading)
/// so it reads as a chunky raised badge instead of a flat sticker, and
/// gives the icon inside much more breathing room — the previous
/// ~26% padding on every side left the spider looking small and lost
/// in the middle of the badge; this drops that to ~14%, so the icon is
/// the dominant thing you see, not the background disc.
class PixelBadgeFrame extends StatelessWidget {
  final double size;
  final Color color;
  final Widget child;

  const PixelBadgeFrame({
    super.key,
    required this.size,
    required this.color,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _PixelCirclePainter(color: color),
        child: Padding(
          padding: EdgeInsets.all(size * 0.14),
          child: child,
        ),
      ),
    );
  }
}

class _PixelCirclePainter extends CustomPainter {
  final Color color;
  _PixelCirclePainter({required this.color});

  @override
  void paint(Canvas canvas, Size size) {
    // Grid resolution: how many "pixels" across the badge. Too coarse
    // (under ~18) and the circle's diagonal steps land symmetrically
    // enough to read as a hexagon/octagon instead of round — 22 keeps
    // it visibly pixel-stepped at typical badge sizes (~36-48px)
    // without losing the actual circle silhouette.
    const gridCount = 22;
    final cell = size.width / gridCount;
    final center = Offset(size.width / 2, size.height / 2);
    final outerRadius = size.width / 2;

    final hsl = HSLColor.fromColor(color);
    final highlightColor =
        hsl.withLightness((hsl.lightness + 0.22).clamp(0.0, 1.0)).toColor();
    final shadeColor =
        hsl.withLightness((hsl.lightness - 0.16).clamp(0.0, 1.0)).toColor();
    // Highlight source sits toward the upper-left, like a token catching
    // light from above — gives the badge actual dimension instead of
    // reading as a flat painted circle.
    final lightSource = Offset(center.dx - outerRadius * 0.42, center.dy - outerRadius * 0.42);

    for (int gx = 0; gx < gridCount; gx++) {
      for (int gy = 0; gy < gridCount; gy++) {
        final cx = gx * cell + cell / 2;
        final cy = gy * cell + cell / 2;
        final point = Offset(cx, cy);
        final dist = (point - center).distance;

        if (dist > outerRadius) continue;

        // Blend toward the highlight/shade based on proximity to the
        // light source vs the opposite (bottom-right) edge, quantized
        // into a few discrete steps rather than a smooth gradient — a
        // smooth gradient here would fight the pixel-grid look.
        final distFromLight = (point - lightSource).distance;
        final t = (distFromLight / (outerRadius * 1.7)).clamp(0.0, 1.0);
        final steppedT = (t * 3).floor() / 3; // 3 discrete shading bands
        final cellColor = Color.lerp(highlightColor, shadeColor, steppedT)!;

        canvas.drawRect(Rect.fromLTWH(gx * cell, gy * cell, cell + 0.5, cell + 0.5), Paint()..color = cellColor);
      }
    }

    // Soft outer glow so it doesn't look flat sitting on the map.
    canvas.drawCircle(
      center,
      outerRadius,
      Paint()
        ..color = color.withOpacity(0.35)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..maskFilter = const MaskFilter.blur(BlurStyle.outer, 3),
    );

    // Thin black outline, drawn as a stepped ring of pixels rather
    // than a smooth stroke, so it stays crisp/pixel-art.
    final outlineThickness = cell * 1.1;
    for (int gx = 0; gx < gridCount; gx++) {
      for (int gy = 0; gy < gridCount; gy++) {
        final cx = gx * cell + cell / 2;
        final cy = gy * cell + cell / 2;
        final dist = (Offset(cx, cy) - center).distance;

        if (dist <= outerRadius && dist > outerRadius - outlineThickness) {
          canvas.drawRect(
            Rect.fromLTWH(gx * cell, gy * cell, cell + 0.5, cell + 0.5),
            Paint()..color = Colors.black,
          );
        }
      }
    }
  }

  @override
  bool shouldRepaint(covariant _PixelCirclePainter oldDelegate) => oldDelegate.color != color;
}
