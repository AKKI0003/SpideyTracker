import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// Replaces the plain spider-logo circle: a small idle-animated chibi
/// mascot (gentle bob + occasional blink) with a pixel speech-bubble
/// above it reading "ACTIVITY LOG" plus the current pin count.
class MascotActivityBadge extends StatefulWidget {
  final int count;
  final VoidCallback onTap;

  const MascotActivityBadge({
    super.key,
    required this.count,
    required this.onTap,
  });

  @override
  State<MascotActivityBadge> createState() => _MascotActivityBadgeState();
}

class _MascotActivityBadgeState extends State<MascotActivityBadge>
    with TickerProviderStateMixin {
  late final AnimationController _bobController;
  late final AnimationController _blinkController;

  @override
  void initState() {
    super.initState();
    _bobController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    )..repeat(reverse: true);

    _blinkController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 160),
    );
    _scheduleBlink();
  }

  void _scheduleBlink() async {
    while (mounted) {
      await Future.delayed(Duration(milliseconds: 2400 + (300 * (widget.hashCode % 5))));
      if (!mounted) return;
      await _blinkController.forward();
      if (!mounted) return;
      await _blinkController.reverse();
    }
  }

  @override
  void dispose() {
    _bobController.dispose();
    _blinkController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: widget.onTap,
      child: SizedBox(
        width: 90,
        height: 92,
        child: Stack(
          clipBehavior: Clip.none,
          alignment: Alignment.bottomCenter,
          children: [
            Positioned(
              top: 0,
              child: _SpeechBubble(count: widget.count),
            ),
            Positioned(
              bottom: 0,
              child: AnimatedBuilder(
                animation: _bobController,
                builder: (context, child) {
                  final dy = -3 * _bobController.value;
                  return Transform.translate(offset: Offset(0, dy), child: child);
                },
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    Image.asset(
                      'assets/images/shared/chibi_mascot.png',
                      width: 42,
                    ),
                    AnimatedBuilder(
                      animation: _blinkController,
                      builder: (context, _) {
                        if (_blinkController.value == 0) return const SizedBox();
                        return Positioned(
                          top: 42 * 0.28,
                          child: Container(
                            width: 42 * 0.62,
                            height: 3 * _blinkController.value,
                            decoration: BoxDecoration(
                              color: const Color(0xFFB01E1E),
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                        );
                      },
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _SpeechBubble extends StatelessWidget {
  final int count;
  const _SpeechBubble({required this.count});

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
          decoration: BoxDecoration(
            color: Colors.black.withOpacity(0.75),
            border: Border.all(color: Colors.cyanAccent, width: 1.5),
            borderRadius: BorderRadius.circular(6),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ACTIVITY',
                style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.cyanAccent),
              ),
              Text(
                'LOG',
                style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.cyanAccent),
              ),
              const SizedBox(height: 2),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                decoration: BoxDecoration(
                  color: Colors.redAccent,
                  borderRadius: BorderRadius.circular(3),
                ),
                child: Text(
                  '$count',
                  style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
        CustomPaint(
          size: const Size(10, 5),
          painter: _BubbleTailPainter(),
        ),
      ],
    );
  }
}

class _BubbleTailPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = Colors.cyanAccent;
    final path = Path()
      ..moveTo(size.width / 2 - 4, 0)
      ..lineTo(size.width / 2 + 4, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _BubbleTailPainter oldDelegate) => false;
}