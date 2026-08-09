import 'package:flutter/material.dart';

/// A horizontal full-spectrum hue bar — drag anywhere to pick a color.
/// Kept deliberately simple (hue only, fixed saturation/lightness) since
/// the badge needs a solid, readable background color, not a full
/// HSV picker.
class HueColorBar extends StatelessWidget {
  final double hue; // 0-360
  final ValueChanged<double> onChanged;
  final double height;

  const HueColorBar({
    super.key,
    required this.hue,
    required this.onChanged,
    this.height = 28,
  });

  void _handleDrag(BuildContext context, Offset localPosition, double width) {
    final fraction = (localPosition.dx / width).clamp(0.0, 1.0);
    onChanged(fraction * 360);
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final thumbX = (hue / 360) * width;

        return GestureDetector(
          onPanDown: (d) => _handleDrag(context, d.localPosition, width),
          onPanUpdate: (d) => _handleDrag(context, d.localPosition, width),
          child: SizedBox(
            height: height + 16,
            width: width,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Container(
                  height: height,
                  margin: const EdgeInsets.symmetric(vertical: 8),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(4),
                    border: Border.all(color: Colors.cyanAccent, width: 1.5),
                    gradient: LinearGradient(
                      colors: List.generate(7, (i) => HSVColor.fromAHSV(1, i * 60.0, 1, 1).toColor()),
                    ),
                  ),
                ),
                Positioned(
                  left: (thumbX - 4).clamp(0.0, width - 8),
                  top: 0,
                  child: Container(
                    width: 8,
                    height: height + 16,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      border: Border.all(color: Colors.black, width: 1.5),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Picks a background color that stays clearly visible against either a
/// light or dark badge fill — used to auto-contrast the spider icon and
/// username label per-badge, satisfying "the symbol should remain
/// clearly visible regardless of background."
Color contrastingColorFor(Color background) {
  final luminance = background.computeLuminance();
  return luminance > 0.5 ? Colors.black : Colors.white;
}
