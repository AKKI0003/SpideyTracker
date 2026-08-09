import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' hide Path;

/// A single point as seen by the radar: just enough to plot it, nothing
/// else. Can represent a photo pin, a live-sharing party member, or the
/// viewer's own position.
class RadarPoint {
  final String id;
  final LatLng location;
  final bool isSelf;
  const RadarPoint({
    required this.id,
    required this.location,
    this.isSelf = false,
  });
}

/// Redesigned to match the spideytracker.net reference: a spider-web
/// radar with a continuously rotating sweep beam, faint white blips
/// that briefly brighten as the sweep passes over them.
///
/// The radar now mirrors the map instead of the real world: a point
/// only shows up as a blip while it's actually inside the map's current
/// visible viewport ([visibleBounds]), and it's plotted at the same
/// relative position within that viewport as it is on the map. Pan the
/// map from India to Europe and the India blip disappears while any
/// pins around the new viewport appear — nothing is measured against
/// real GPS distance from the viewer anymore.
///
/// Recenter is no longer triggered by tapping anywhere on the radar
/// (that made the whole dish an accidental tap target); instead a
/// small dedicated button is docked to the radar's bottom-right edge.
class RadarSweep extends StatefulWidget {
  final double size;

  /// The map's current visible viewport. Points outside this simply
  /// don't show up as blips — exactly like they wouldn't be visible on
  /// the map itself.
  final LatLngBounds? visibleBounds;

  final List<RadarPoint> points;

  final VoidCallback onRecenter;

  const RadarSweep({
    super.key,
    this.size = 90,
    this.visibleBounds,
    this.points = const [],
    required this.onRecenter,
  });

  @override
  State<RadarSweep> createState() => _RadarSweepState();
}

class _RadarBlip {
  final double angle; // radians, canvas space (0 = +x axis, clockwise)
  final double radiusFraction; // 0..1, how far out from center
  final bool isSelf;
  const _RadarBlip({
    required this.angle,
    required this.radiusFraction,
    this.isSelf = false,
  });
}

class _RadarSweepState extends State<RadarSweep> with TickerProviderStateMixin {
  late final AnimationController _sweepController;
  late final AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _sweepController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 4),
    )..repeat();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _sweepController.dispose();
    _pulseController.dispose();
    super.dispose();
  }

  /// Only points actually inside [RadarSweep.visibleBounds] (i.e. inside
  /// the map's current viewport) make it onto the radar, plotted at the
  /// same relative position within that viewport that they occupy on
  /// the map — so panning/zooming the map and watching the radar update
  /// in lockstep is the whole point.
  List<_RadarBlip> _computeBlips() {
    final bounds = widget.visibleBounds;
    if (bounds == null) return const [];

    final centerLat = (bounds.north + bounds.south) / 2;
    final centerLng = (bounds.east + bounds.west) / 2;
    final halfLat = (bounds.north - bounds.south) / 2;
    final halfLng = (bounds.east - bounds.west) / 2;
    if (halfLat <= 0 || halfLng <= 0) return const [];

    final blips = <_RadarBlip>[];
    for (final point in widget.points) {
      if (!bounds.contains(point.location)) continue; // off-screen on the map

      // Normalized offset from viewport center, -1..1 on each axis.
      final dx = (point.location.longitude - centerLng) / halfLng;
      // Screen/canvas y increases downward but latitude increases
      // northward (upward), so flip it.
      final dy = -(point.location.latitude - centerLat) / halfLat;

      var magnitude = sqrt(dx * dx + dy * dy);
      var ux = dx;
      var uy = dy;
      if (magnitude > 1) {
        // Viewport is rectangular but the dish is round — points near a
        // corner of the viewport are clamped onto the dish's edge
        // rather than spilling outside it, keeping their direction.
        ux = dx / magnitude;
        uy = dy / magnitude;
        magnitude = 1;
      }

      final canvasAngle = atan2(uy, ux);
      final radiusFraction = magnitude.clamp(0.05, 0.95);

      blips.add(_RadarBlip(
        angle: canvasAngle,
        radiusFraction: radiusFraction,
        isSelf: point.isSelf,
      ));
    }
    return blips;
  }

  @override
  Widget build(BuildContext context) {
    final blips = _computeBlips();

    // The recenter button sits along the same 45° line as one of the
    // web's own spokes (spoke index 1 of 8, angle = 2π/8) and is drawn
    // as a continuation of that spoke rather than a separate bracket —
    // so it reads as part of the web instead of clashing with the
    // rings/spokes converging at that corner.
    const strutAngle = pi / 4;
    final dishRadius = widget.size / 2;
    const strutLength = 22.0;
    const buttonSize = 24.0;

    // Dish stays pinned to the box's top-left corner (same as before
    // the antenna existed) so the whole widget still sits flush in
    // its docked corner of the screen. Only extra room is added on
    // the bottom-right, exactly where the antenna/button stick out —
    // centering the dish in a symmetrically padded box was pushing it
    // away from the corner, which is what looked "off".
    final center = Offset(dishRadius, dishRadius);
    final edgePoint = Offset(
      center.dx + dishRadius * cos(strutAngle),
      center.dy + dishRadius * sin(strutAngle),
    );
    final buttonCenter = Offset(
      center.dx + (dishRadius + strutLength) * cos(strutAngle),
      center.dy + (dishRadius + strutLength) * sin(strutAngle),
    );
    final boxWidth = buttonCenter.dx + buttonSize / 2;
    final boxHeight = buttonCenter.dy + buttonSize / 2;

    return SizedBox(
      width: boxWidth,
      height: boxHeight,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            width: widget.size,
            height: widget.size,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: Colors.black.withOpacity(0.65),
              border: Border.all(color: Colors.cyanAccent, width: 2),
              boxShadow: [
                BoxShadow(color: Colors.cyanAccent.withOpacity(0.25), blurRadius: 12, spreadRadius: 1),
              ],
            ),
            child: AnimatedBuilder(
              animation: Listenable.merge([_sweepController, _pulseController]),
              builder: (context, _) {
                return CustomPaint(
                  painter: _RadarPainter(
                    sweepAngle: _sweepController.value * 2 * pi,
                    pulse: _pulseController.value,
                    blips: blips,
                  ),
                  size: Size(widget.size, widget.size),
                );
              },
            ),
          ),

          // Single antenna line continuing that spoke out to the
          // button, plus a small rivet where it meets the dish rim.
          Positioned.fill(
            child: CustomPaint(
              painter: _AntennaPainter(from: edgePoint, to: buttonCenter),
            ),
          ),

          Positioned(
            left: buttonCenter.dx - buttonSize / 2,
            top: buttonCenter.dy - buttonSize / 2,
            child: GestureDetector(
              onTap: widget.onRecenter,
              child: Container(
                width: buttonSize,
                height: buttonSize,
                decoration: BoxDecoration(
                  color: const Color(0xFF0A1128),
                  shape: BoxShape.circle,
                  border: Border.all(color: Colors.redAccent, width: 2),
                  boxShadow: const [
                    BoxShadow(color: Colors.cyanAccent, offset: Offset(0, 0), blurRadius: 4),
                    BoxShadow(color: Colors.black, offset: Offset(1.5, 1.5), blurRadius: 0),
                  ],
                ),
                child: const Icon(
                  Icons.gps_fixed,
                  size: 13,
                  color: Colors.redAccent,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Draws the single line that continues the web's own 45° spoke out to
/// the recenter button, with a small rivet where it meets the rim.
class _AntennaPainter extends CustomPainter {
  final Offset from;
  final Offset to;

  _AntennaPainter({required this.from, required this.to});

  @override
  void paint(Canvas canvas, Size size) {
    final linePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.8)
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;
    canvas.drawLine(from, to, linePaint);

    canvas.drawCircle(from, 2.5, Paint()..color = Colors.cyanAccent);
  }

  @override
  bool shouldRepaint(covariant _AntennaPainter oldDelegate) =>
      oldDelegate.from != from || oldDelegate.to != to;
}

class _RadarPainter extends CustomPainter {
  final double sweepAngle;
  final double pulse;
  final List<_RadarBlip> blips;

  _RadarPainter({required this.sweepAngle, required this.pulse, required this.blips});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = size.width / 2 - 4;

    // Web spokes + rings — kept subtle so the sweep/blips stay the
    // visual focus instead of a busy web dominating the dish.
    final webPaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.18)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 0.75;

    const spokeCount = 8;
    for (int i = 0; i < spokeCount; i++) {
      final angle = (2 * pi / spokeCount) * i;
      final end = Offset(center.dx + radius * cos(angle), center.dy + radius * sin(angle));
      canvas.drawLine(center, end, webPaint);
    }

    const ringCount = 3;
    for (int r = 1; r <= ringCount; r++) {
      final ringRadius = radius * (r / ringCount);
      final path = Path();
      for (int i = 0; i <= spokeCount; i++) {
        final angle = (2 * pi / spokeCount) * i;
        final point = Offset(center.dx + ringRadius * cos(angle), center.dy + ringRadius * sin(angle));
        if (i == 0) {
          path.moveTo(point.dx, point.dy);
        } else {
          path.lineTo(point.dx, point.dy);
        }
      }
      canvas.drawPath(path, webPaint);
    }

    // Rotating sweep beam — a soft wedge fading out from the leading edge.
    final sweepPaint = Paint()
      ..shader = SweepGradient(
        center: Alignment.center,
        startAngle: sweepAngle - 0.9,
        endAngle: sweepAngle,
        colors: [
          Colors.cyanAccent.withOpacity(0.0),
          Colors.cyanAccent.withOpacity(0.35),
        ],
      ).createShader(Rect.fromCircle(center: center, radius: radius));
    canvas.drawCircle(center, radius, sweepPaint);

    final beamLinePaint = Paint()
      ..color = Colors.cyanAccent.withOpacity(0.9)
      ..strokeWidth = 1.5;
    canvas.drawLine(
      center,
      Offset(center.dx + radius * cos(sweepAngle), center.dy + radius * sin(sweepAngle)),
      beamLinePaint,
    );

    // White blips for nearby (in-range) pins only. Each brightens when
    // the sweep passes near its real bearing, mimicking a radar ping.
    for (final blip in blips) {
      final blipPos = Offset(
        center.dx + radius * blip.radiusFraction * cos(blip.angle),
        center.dy + radius * blip.radiusFraction * sin(blip.angle),
      );

      double angleDiff = (sweepAngle - blip.angle) % (2 * pi);
      if (angleDiff < 0) angleDiff += 2 * pi;
      final proximity = angleDiff < 0.6 ? (1 - angleDiff / 0.6) : 0.0;

      final baseOpacity = 0.35 + proximity * 0.65;
      final blipRadius = (blip.isSelf ? 2.6 : 2.0) + proximity * 2.5;

      if (proximity > 0.1) {
        canvas.drawCircle(
          blipPos,
          blipRadius + 3,
          Paint()..color = Colors.white.withOpacity(proximity * 0.3),
        );
      }
      canvas.drawCircle(blipPos, blipRadius, Paint()..color = Colors.white.withOpacity(baseOpacity));

      // Self gets a thin cyan ring around its white dot so it reads as
      // "you" among any other blips sharing the dish.
      if (blip.isSelf) {
        canvas.drawCircle(
          blipPos,
          blipRadius + 2.5,
          Paint()
            ..color = Colors.cyanAccent.withOpacity(0.6 + 0.3 * pulse)
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1,
        );
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RadarPainter oldDelegate) => true;
}