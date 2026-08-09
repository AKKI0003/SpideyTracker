import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../../../../core/pins/spider_icon_catalog.dart';
import '../../../../core/widgets/corner_web_painter.dart';
import '../../../photo_pins/presentation/widgets/pixel_badge_frame.dart';

class PinFilterChip extends StatelessWidget {
  final String label;
  final String spiderIconId;
  final Color color;
  final bool isVisible;
  final VoidCallback onTap;

  const PinFilterChip({
    super.key,
    required this.label,
    required this.spiderIconId,
    required this.color,
    required this.isVisible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedOpacity(
        opacity: isVisible ? 1.0 : 0.35,
        duration: const Duration(milliseconds: 150),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 20,
              height: 14,
              child: CustomPaint(
                painter: const PixelThreadPainter(color: Colors.white, axis: Axis.horizontal),
              ),
            ),
            AnimatedScale(
              scale: isVisible ? 1.0 : 0.85,
              duration: const Duration(milliseconds: 150),
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  PixelBadgeFrame(size: 26, color: color, child: _iconFor(color)),
                  if (!isVisible)
                    Positioned.fill(
                      child: Center(
                        child: Container(
                          width: 20,
                          height: 2,
                          color: Colors.black,
                          transform: Matrix4.rotationZ(0.78),
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              softWrap: false,
              style: GoogleFonts.pressStart2p(
                fontSize: 7,
                color: Colors.white,
                shadows: const [
                  Shadow(color: Colors.black, offset: Offset(1, 1), blurRadius: 2),
                  Shadow(color: Colors.black, offset: Offset(-1, -1), blurRadius: 2),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _iconFor(Color background) {
    final icon = SpiderIconCatalog.byId(spiderIconId);
    final luminance = background.computeLuminance();
    return icon.buildIcon(luminance > 0.5 ? Colors.black : Colors.white);
  }
}

/// The "FILTER" tag now sits angled directly over the web's own lower
/// strands, like a scrap of paper caught in it, instead of floating
/// as a separate label underneath.
class _FilterHintLabel extends StatelessWidget {
  const _FilterHintLabel();

  @override
  Widget build(BuildContext context) {
    return Transform.rotate(
      angle: -0.14,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 3),
        decoration: BoxDecoration(
          color: Colors.black.withOpacity(0.7),
          borderRadius: BorderRadius.circular(3),
          border: Border.all(color: Colors.cyanAccent.withOpacity(0.8), width: 1),
        ),
        child: Text(
          'FILTER',
          style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white),
        ),
      ),
    );
  }
}

class PinFilterRail extends StatefulWidget {
  final List<String> memberUids;
  final String myUid;
  final Map<String, String> memberNames;
  final Map<String, String> memberSpiderIds;
  final Map<String, int> memberColors;
  final String mySpiderId;
  final int myColorValue;
  final Set<String> hiddenUids;
  final void Function(String uid) onToggle;

  const PinFilterRail({
    super.key,
    required this.memberUids,
    required this.myUid,
    required this.memberNames,
    required this.memberSpiderIds,
    required this.memberColors,
    required this.mySpiderId,
    required this.myColorValue,
    required this.hiddenUids,
    required this.onToggle,
  });

  static String labelFor(String uid, String myUid, Map<String, String> memberNames) {
    if (uid == myUid) return 'You';
    final name = memberNames[uid]?.trim();
    return (name == null || name.isEmpty) ? 'Member' : name;
  }

  @override
  State<PinFilterRail> createState() => _PinFilterRailState();
}

class _PinFilterRailState extends State<PinFilterRail>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _drop;
  bool _expanded = false;

  // Web canvas size AND hitbox AND thread/spider anchor all key off
  // this ONE number now, all pinned flush at (right: 0, top: 0) —
  // no separate "shift" constant anywhere, so nothing can drift out
  // of sync with anything else again. Sized up from the old 44/58 mix
  // so it visibly fills the corner against the frame border, while
  // staying comfortably clear of SoundControlButton's `right: 54`
  // position in map_scanner_screen.dart (48 < 54, so their hit
  // regions never share any x-range).
  static const double _webSize = 70;
  static const double _threadWidth = 6;
  static const double _spiderLogoSize = 26;

  static const double _maxExtraDrop = 130;
  static const int _fullPartySize = 8;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
    );
    _drop = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  double get _extraDropLength {
    final count = widget.memberUids.length.clamp(1, _fullPartySize);
    return 26 + (_maxExtraDrop - 26) * (count / _fullPartySize);
  }

  void _toggle() {
    setState(() => _expanded = !_expanded);
    if (_expanded) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: _webSize + 160,
      height: 220,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // Web: flush at the true corner, no transform, no offset —
          // this is now the single anchor everything else measures
          // itself against.
          Positioned(
            top: 0,
            right: 0,
            child: Material(
              color: Colors.transparent,
              child: InkWell(
                borderRadius: BorderRadius.circular(8),
                onTap: _toggle,
                child: SizedBox(
                  width: _webSize,
                  height: _webSize,
                  child: CustomPaint(
                    size: const Size(_webSize, _webSize),
                    painter: const CornerWebPainter(opacity: 0.9),
                  ),
                ),
              ),
            ),
          ),

          // FILTER tag, angled, overlapping the web's own lower-left
          // strands rather than floating separately below it.
          if (!_expanded)
            Positioned(
              top: _webSize - 40,
              right: 20,
              child: GestureDetector(
                onTap: _toggle,
                behavior: HitTestBehavior.opaque,
                child: const _FilterHintLabel(),
              ),
            ),

          // Thread: right: 0 — same literal edge as the web above it,
          // so there is no measurable gap between where the web's
          // down-strand ends and where the thread begins.
          AnimatedBuilder(
            animation: _drop,
            builder: (context, child) {
              final progress = _drop.value.clamp(0.0, 1.0);
              final extraLength = _extraDropLength * progress;
              return Positioned(
                top: _webSize - 3,
                right: 15.7,
                child: SizedBox(
                  width: _threadWidth,
                  height: extraLength,
                  child: const CustomPaint(painter: PixelThreadPainter(color: Colors.white)),
                ),
              );
            },
          ),

          // Spider: right edge also flush at 0, same corner as
          // everything else — its right edge sits exactly under the
          // thread's right edge, with the thread visually passing
          // just past its right side (matches how the reference art
          // has the spider hanging slightly left of dead-center under
          // the strand, not stacked with mathematical precision on a
          // separate offset that can go stale).
          AnimatedBuilder(
            animation: _drop,
            builder: (context, child) {
              final progress = _drop.value.clamp(0.0, 1.0);
              final extraLength = _extraDropLength * progress;
              return Positioned(
                top: _webSize - (_spiderLogoSize * 0.3) + extraLength - 3,
                right: -(_spiderLogoSize / 2) + _threadWidth + 15.7,
                child: child!,
              );
            },
            child: ColorFiltered(
              colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
              child: Image.asset(
                'assets/images/shared/spider_logo.png',
                width: _spiderLogoSize,
                height: _spiderLogoSize,
              ),
            ),
          ),

          AnimatedBuilder(
            animation: _drop,
            builder: (context, child) {
              final progress = _drop.value.clamp(0.0, 1.0);
              final extraLength = _extraDropLength * progress;
              return Positioned(
                top: _webSize + extraLength * 0.15,
                right: 20,
                child: child!,
              );
            },
            child: AnimatedOpacity(
              opacity: _expanded ? 1 : 0,
              duration: const Duration(milliseconds: 250),
              child: AnimatedSlide(
                offset: _expanded ? Offset.zero : const Offset(-0.4, 0),
                duration: const Duration(milliseconds: 250),
                curve: Curves.easeOut,
                child: IgnorePointer(
                  ignoring: !_expanded,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (final uid in widget.memberUids)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 7),
                          child: PinFilterChip(
                            label: PinFilterRail.labelFor(uid, widget.myUid, widget.memberNames),
                            spiderIconId: uid == widget.myUid
                                ? widget.mySpiderId
                                : (widget.memberSpiderIds[uid] ?? 'round_body'),
                            color: Color(uid == widget.myUid
                                ? widget.myColorValue
                                : (widget.memberColors[uid] ?? 0xFFFF5252)),
                            isVisible: !widget.hiddenUids.contains(uid),
                            onTap: () => widget.onToggle(uid),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}