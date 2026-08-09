import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../../core/audio/ambient_sound_controller.dart';
import 'pixel_speaker_icon.dart';

/// Sits where the old top-right recenter button used to be — recenter
/// now lives on the radar itself, which freed up this slot for Feature
/// 10's sound control.
///
/// Tap: toggle mute. Long-press: reveals a small volume slider popover.
///
/// The icon is drawn as blocky 8-bit pixel art (no smooth Material
/// icon) and the frame matches the same hard-edged, drop-shadowed
/// arcade look as [PixelButton] elsewhere in the app.
class SoundControlButton extends ConsumerStatefulWidget {
  const SoundControlButton({super.key});

  @override
  ConsumerState<SoundControlButton> createState() => _SoundControlButtonState();
}

class _SoundControlButtonState extends ConsumerState<SoundControlButton> {
  OverlayEntry? _volumePopover;
  final _layerLink = LayerLink();

  void _toggleMute() {
    final controller = ref.read(ambientSoundProvider);
    controller.toggleMute().then((_) => setState(() {}));
  }

  void _showVolumePopover(BuildContext context) {
    _volumePopover?.remove();
    final controller = ref.read(ambientSoundProvider);

    _volumePopover = OverlayEntry(
      builder: (context) {
        return Positioned(
          width: 52,
          child: CompositedTransformFollower(
            link: _layerLink,
            showWhenUnlinked: false,
            offset: const Offset(-6, 40),
            child: Material(
              color: Colors.transparent,
              child: StatefulBuilder(
                builder: (context, setPopoverState) {
                  final pct = (controller.volume * 100).round();
                  return Container(
                    width: 52,
                    height: 168,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                    decoration: BoxDecoration(
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [Color(0xFF160029), Color(0xFF0A1128)],
                      ),
                      border: Border.all(color: Colors.redAccent, width: 2),
                      boxShadow: [
                        BoxShadow(color: Colors.redAccent.withOpacity(0.55), blurRadius: 14, spreadRadius: 1),
                        const BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
                      ],
                    ),
                    child: Stack(
                      alignment: Alignment.topCenter,
                      children: [
                        // Cyan inner hairline for a layered "web HUD"
                        // frame instead of one flat border.
                        Positioned.fill(
                          child: Container(
                            margin: const EdgeInsets.all(2),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 1),
                            ),
                          ),
                        ),
                        // Tiny corner rivets, arcade-panel style.
                        for (final align in [
                          Alignment.topLeft,
                          Alignment.topRight,
                          Alignment.bottomLeft,
                          Alignment.bottomRight,
                        ])
                          Align(
                            alignment: align,
                            child: Padding(
                              padding: const EdgeInsets.all(3),
                              child: Container(
                                width: 3,
                                height: 3,
                                color: Colors.cyanAccent,
                              ),
                            ),
                          ),
                        Column(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const SizedBox(height: 4),
                            Text(
                              '$pct',
                              style: const TextStyle(
                                color: Colors.cyanAccent,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                                fontFamily: 'monospace',
                              ),
                            ),
                            Expanded(
                              child: RotatedBox(
                                quarterTurns: 3,
                                child: SliderTheme(
                                  data: SliderTheme.of(context).copyWith(
                                    trackHeight: 4,
                                    activeTrackColor: Colors.redAccent,
                                    inactiveTrackColor: const Color(0xFF1D3461),
                                    thumbColor: Colors.redAccent,
                                    thumbShape: const _SpiderThumbShape(),
                                    overlayShape: SliderComponentShape.noOverlay,
                                    tickMarkShape: const _WebTickMarkShape(),
                                    activeTickMarkColor: Colors.white70,
                                    inactiveTickMarkColor: Colors.cyanAccent.withOpacity(0.4),
                                  ),
                                  child: Slider(
                                    value: controller.volume,
                                    divisions: 10,
                                    onChanged: (v) {
                                      controller.setVolume(v);
                                      setPopoverState(() {});
                                    },
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 4),
                          ],
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
          ),
        );
      },
    );

    Overlay.of(context).insert(_volumePopover!);

    Future.delayed(const Duration(seconds: 3), () {
      _volumePopover?.remove();
      _volumePopover = null;
    });
  }

  @override
  void dispose() {
    _volumePopover?.remove();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = ref.watch(ambientSoundProvider);

    return CompositedTransformTarget(
      link: _layerLink,
      child: GestureDetector(
        onTap: _toggleMute,
        onLongPress: () => _showVolumePopover(context),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: const Color(0xFF0A1128),
            border: Border.all(color: Colors.black, width: 2),
            boxShadow: const [
              BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0),
            ],
          ),
          child: PixelSpeakerIcon(
            size: 18,
            isMuted: controller.isMuted,
            color: controller.isMuted ? Colors.redAccent : Colors.cyanAccent,
          ),
        ),
      ),
    );
  }
}

/// A small glowing "web-dot" thumb instead of the plain Material
/// circle — a soft red halo behind a solid core with a thin cyan ring,
/// matching the Spider-Man red/cyan HUD palette.
class _SpiderThumbShape extends SliderComponentShape {
  const _SpiderThumbShape();

  @override
  Size getPreferredSize(bool isEnabled, bool isDiscrete) => const Size(18, 18);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required Animation<double> activationAnimation,
    required Animation<double> enableAnimation,
    required bool isDiscrete,
    required TextPainter labelPainter,
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required TextDirection textDirection,
    required double value,
    required double textScaleFactor,
    required Size sizeWithOverflow,
  }) {
    final canvas = context.canvas;

    canvas.drawCircle(center, 9, Paint()..color = Colors.redAccent.withOpacity(0.35));
    canvas.drawCircle(center, 6, Paint()..color = Colors.redAccent);
    canvas.drawCircle(
      center,
      6,
      Paint()
        ..color = Colors.cyanAccent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
    canvas.drawCircle(center, 1.6, Paint()..color = Colors.white);
  }
}

/// Small square pixel tick marks instead of Material's default dots,
/// keeping the same blocky arcade language as the rest of the HUD.
class _WebTickMarkShape extends SliderTickMarkShape {
  const _WebTickMarkShape();

  @override
  Size getPreferredSize({
    required SliderThemeData sliderTheme,
    required bool isEnabled,
  }) => const Size(3, 3);

  @override
  void paint(
    PaintingContext context,
    Offset center, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required Offset thumbCenter,
    required bool isEnabled,
    required TextDirection textDirection,
  }) {
    final isActive = (textDirection == TextDirection.ltr)
        ? center.dx <= thumbCenter.dx
        : center.dx >= thumbCenter.dx;
    final paint = Paint()
      ..color = isActive
          ? (sliderTheme.activeTickMarkColor ?? Colors.white70)
          : (sliderTheme.inactiveTickMarkColor ?? Colors.white24);
    context.canvas.drawRect(
      Rect.fromCenter(center: center, width: 3, height: 3),
      paint,
    );
  }
}