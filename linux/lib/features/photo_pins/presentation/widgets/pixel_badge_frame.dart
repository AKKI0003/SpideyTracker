import 'package:flutter/material.dart';

/// A circular badge with a deliberately blocky/rasterized edge instead
/// of a smooth vector circle — achieved by rendering the circle onto a
/// coarse pixel grid, so the silhouette has the stepped, jagged edge of
/// a low-res sprite rather than perfect anti-aliasing. Includes a
/// darker ring border (same rasterization) for depth, matching the
/// reference look.
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
          padding: EdgeInsets.all(size * 0.26),
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
    final borderThickness = cell * 2.2;
    final innerRadius = outerRadius - borderThickness;

    final borderColor = HSLColor.fromColor(color).withLightness(
      (HSLColor.fromColor(color).lightness - 0.22).clamp(0.0, 1.0),
    ).toColor();

    for (int gx = 0; gx < gridCount; gx++) {
      for (int gy = 0; gy < gridCount; gy++) {
        final cx = gx * cell + cell / 2;
        final cy = gy * cell + cell / 2;
        final dist = (Offset(cx, cy) - center).distance;

        if (dist > outerRadius) continue;

        final paint = Paint()..color = dist > innerRadius ? borderColor : color;
        canvas.drawRect(Rect.fromLTWH(gx * cell, gy * cell, cell + 0.5, cell + 0.5), paint);
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
    // than a smooth stroke, so it stays crisp/pixel-art instead of
    // looking like a plain vector circle outline sitting on top of the
    // rasterized fill.
    final outlineThickness = cell * 0.9;
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
