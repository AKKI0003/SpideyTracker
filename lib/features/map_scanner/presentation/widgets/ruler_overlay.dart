import 'package:flutter/material.dart';

/// Thin ruler-tick strips along the top and left edges of the map,
/// purely decorative (gadget/scanner flavor) — doesn't track real
/// coordinates, just a repeating tick pattern with small numbers.
class RulerOverlay extends StatelessWidget {
  const RulerOverlay({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Stack(
        children: [
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            height: 18,
            child: CustomPaint(painter: _RulerPainter(horizontal: true)),
          ),
          Positioned(
            top: 0,
            left: 0,
            bottom: 0,
            width: 18,
            child: CustomPaint(painter: _RulerPainter(horizontal: false)),
          ),
        ],
      ),
    );
  }
}

class _RulerPainter extends CustomPainter {
  final bool horizontal;
  _RulerPainter({required this.horizontal});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.5)
      ..strokeWidth = 1;

    const spacing = 14.0;
    final length = horizontal ? size.width : size.height;

    int tick = 0;
    for (double p = 0; p < length; p += spacing) {
      final isMajor = tick % 5 == 0;
      final tickLen = isMajor ? 8.0 : 4.0;

      if (horizontal) {
        canvas.drawLine(
          Offset(p, size.height),
          Offset(p, size.height - tickLen),
          linePaint,
        );
      } else {
        canvas.drawLine(
          Offset(size.width, p),
          Offset(size.width - tickLen, p),
          linePaint,
        );
      }

      if (isMajor) {
        final textPainter = TextPainter(
          text: TextSpan(
            text: '$tick',
            style: TextStyle(
              color: Colors.cyanAccent.withOpacity(0.6),
              fontSize: 7,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();

        if (horizontal) {
          textPainter.paint(canvas, Offset(p + 2, 1));
        } else {
          textPainter.paint(canvas, Offset(1, p + 2));
        }
      }

      tick++;
    }
  }

  @override
  bool shouldRepaint(covariant _RulerPainter oldDelegate) => false;
}