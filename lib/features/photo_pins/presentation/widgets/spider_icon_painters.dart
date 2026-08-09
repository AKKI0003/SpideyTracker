import 'dart:math';
import 'package:flutter/material.dart';

/// A set of ORIGINAL, generic spider silhouettes drawn from scratch for
/// this app's memory-pin badges. None of these are based on, traced
/// from, or intended to resemble any comic/film/game character mark —
/// they're just spider shapes (round body variants, different leg
/// counts/curvature) distinguished by silhouette so pins stay visually
/// distinct from each other.
///
/// To add a new one: write a painter class here implementing
/// [SpiderIconPainter], then register it in SpiderIconCatalog.
abstract class SpiderIconPainter extends CustomPainter {
  final Color color;
  const SpiderIconPainter(this.color);
}

/// Round compact body, 8 straight-ish legs evenly radiating out.
class RoundBodySpider extends SpiderIconPainter {
  const RoundBodySpider(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final legPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(
      Rect.fromCenter(center: center, width: size.width * 0.42, height: size.height * 0.5),
      paint,
    );
    canvas.drawCircle(Offset(center.dx, center.dy - size.height * 0.28), size.width * 0.14, paint);

    for (int i = 0; i < 8; i++) {
      final angle = (pi / 8) + i * (pi / 4) - pi / 2;
      final legLen = size.width * 0.42;
      final start = Offset(center.dx + cos(angle) * size.width * 0.15, center.dy + sin(angle) * size.height * 0.15);
      final mid = Offset(center.dx + cos(angle) * legLen * 0.6, center.dy + sin(angle) * legLen * 0.6);
      final end = Offset(center.dx + cos(angle) * legLen, center.dy + sin(angle) * legLen);
      final path = Path()..moveTo(start.dx, start.dy)..quadraticBezierTo(mid.dx, mid.dy, end.dx, end.dy);
      canvas.drawPath(path, legPaint);
    }
  }

  @override
  bool shouldRepaint(covariant RoundBodySpider oldDelegate) => oldDelegate.color != color;
}

/// Elongated body, long thin sweeping legs.
class LongLegsSpider extends SpiderIconPainter {
  const LongLegsSpider(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final legPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.045
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(
      Rect.fromCenter(center: center, width: size.width * 0.28, height: size.height * 0.55),
      paint,
    );
    canvas.drawCircle(Offset(center.dx, center.dy - size.height * 0.3), size.width * 0.1, paint);

    for (int side in [-1, 1]) {
      for (int i = 0; i < 4; i++) {
        final t = i / 3;
        final startY = center.dy - size.height * 0.18 + t * size.height * 0.36;
        final start = Offset(center.dx + side * size.width * 0.1, startY);
        final end = Offset(center.dx + side * size.width * 0.48, startY - size.height * 0.15 + t * size.height * 0.3);
        final control = Offset(center.dx + side * size.width * 0.3, startY - size.height * 0.08);
        final path = Path()..moveTo(start.dx, start.dy)..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        canvas.drawPath(path, legPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant LongLegsSpider oldDelegate) => oldDelegate.color != color;
}

/// Angular, faceted body with sharply bent legs (a more "armored" look).
class AngularSpider extends SpiderIconPainter {
  const AngularSpider(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final legPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.055
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.miter;

    final bodyPath = Path()
      ..moveTo(center.dx, center.dy - size.height * 0.32)
      ..lineTo(center.dx + size.width * 0.16, center.dy - size.height * 0.05)
      ..lineTo(center.dx + size.width * 0.13, center.dy + size.height * 0.28)
      ..lineTo(center.dx - size.width * 0.13, center.dy + size.height * 0.28)
      ..lineTo(center.dx - size.width * 0.16, center.dy - size.height * 0.05)
      ..close();
    canvas.drawPath(bodyPath, paint);

    for (int side in [-1, 1]) {
      for (int i = 0; i < 4; i++) {
        final t = i / 3;
        final startY = center.dy - size.height * 0.15 + t * size.height * 0.35;
        final start = Offset(center.dx + side * size.width * 0.12, startY);
        final bend = Offset(center.dx + side * size.width * 0.32, startY - size.height * 0.06);
        final end = Offset(center.dx + side * size.width * 0.46, startY + size.height * 0.12);
        final path = Path()..moveTo(start.dx, start.dy)..lineTo(bend.dx, bend.dy)..lineTo(end.dx, end.dy);
        canvas.drawPath(path, legPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant AngularSpider oldDelegate) => oldDelegate.color != color;
}

/// Small round body, legs curled inward (a "resting" pose).
class CurledSpider extends SpiderIconPainter {
  const CurledSpider(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final legPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, size.width * 0.22, paint);

    for (int i = 0; i < 8; i++) {
      final angle = (pi / 8) + i * (pi / 4) - pi / 2;
      final start = Offset(center.dx + cos(angle) * size.width * 0.2, center.dy + sin(angle) * size.height * 0.2);
      final curlAngle = angle + (i.isEven ? 0.6 : -0.6);
      final end = Offset(center.dx + cos(curlAngle) * size.width * 0.4, center.dy + sin(curlAngle) * size.height * 0.4);
      final control = Offset(center.dx + cos(angle) * size.width * 0.38, center.dy + sin(angle) * size.height * 0.38);
      final path = Path()..moveTo(start.dx, start.dy)..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
      canvas.drawPath(path, legPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CurledSpider oldDelegate) => oldDelegate.color != color;
}

/// Broad flat body, short stubby legs (a "crab-like" wide stance).
class BroadBodySpider extends SpiderIconPainter {
  const BroadBodySpider(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final legPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.065
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(
      Rect.fromCenter(center: center, width: size.width * 0.55, height: size.height * 0.34),
      paint,
    );

    for (int side in [-1, 1]) {
      for (int i = 0; i < 4; i++) {
        final t = i / 3;
        final startX = center.dx + side * size.width * 0.2;
        final startY = center.dy - size.height * 0.1 + t * size.height * 0.2;
        final end = Offset(center.dx + side * size.width * 0.48, startY + (t - 0.5) * size.height * 0.25);
        canvas.drawLine(Offset(startX, startY), end, legPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant BroadBodySpider oldDelegate) => oldDelegate.color != color;
}

/// Slim vertical body with legs sweeping backward (a "running" pose).
class RunnerSpider extends SpiderIconPainter {
  const RunnerSpider(super.color);

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final paint = Paint()..color = color..style = PaintingStyle.fill;
    final legPaint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = size.width * 0.05
      ..strokeCap = StrokeCap.round;

    canvas.drawOval(
      Rect.fromCenter(center: center, width: size.width * 0.24, height: size.height * 0.48),
      paint,
    );

    for (int side in [-1, 1]) {
      for (int i = 0; i < 4; i++) {
        final t = i / 3;
        final startY = center.dy - size.height * 0.2 + t * size.height * 0.4;
        final start = Offset(center.dx + side * size.width * 0.08, startY);
        final end = Offset(center.dx + side * size.width * 0.45, startY + size.height * 0.22);
        final control = Offset(center.dx + side * size.width * 0.3, startY + size.height * 0.02);
        final path = Path()..moveTo(start.dx, start.dy)..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);
        canvas.drawPath(path, legPaint);
      }
    }
  }

  @override
  bool shouldRepaint(covariant RunnerSpider oldDelegate) => oldDelegate.color != color;
}
