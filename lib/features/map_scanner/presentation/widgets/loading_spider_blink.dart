import 'package:flutter/material.dart';

/// Replaces the old CircularProgressIndicator spinner shown while
/// waiting for the current location / map to be ready: the app's
/// spider logo, tinted as a flat silhouette and pulsing between light
/// gray and black on a loop.
///
/// BlendMode.srcIn recolors every opaque pixel of the source image to
/// a single flat color (using the source's alpha as the shape mask),
/// so the logo's own colors don't matter here — only its silhouette —
/// which is what lets it cleanly animate between two solid colors.
class LoadingSpiderBlink extends StatefulWidget {
  final double size;
  const LoadingSpiderBlink({super.key, this.size = 72});

  @override
  State<LoadingSpiderBlink> createState() => _LoadingSpiderBlinkState();
}

class _LoadingSpiderBlinkState extends State<LoadingSpiderBlink>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<Color?> _colorAnim;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    )..repeat(reverse: true);

    _colorAnim = ColorTween(
      begin: Colors.grey[400],
      end: Colors.black,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeInOut));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _colorAnim,
      builder: (context, _) {
        return ColorFiltered(
          colorFilter: ColorFilter.mode(_colorAnim.value!, BlendMode.srcIn),
          child: Image.asset(
            'assets/images/shared/spider_logo.png',
            width: widget.size,
            height: widget.size,
            fit: BoxFit.contain,
          ),
        );
      },
    );
  }
}
