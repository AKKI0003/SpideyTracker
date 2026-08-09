import 'package:flutter/material.dart';
import '../../features/photo_pins/presentation/widgets/spider_icon_painters.dart';

/// `id` is what gets stored on the user doc (users/{uid}.pinSpiderId) —
/// never rename an existing id once people have picked it.
///
/// An icon is EITHER a code-drawn painter (`painterOf`) OR an image
/// asset (`assetPath`) — exactly one should be set per entry. Whichever
/// is used, [buildIcon] renders it tinted to [color] via a color-filter,
/// so the spider always stays contrasted against whatever badge color
/// it's sitting on — including PNGs that were drawn in black, white, or
/// any other color originally.
class SpiderIconOption {
  final String id;
  final String label;
  final CustomPainter Function(Color color)? painterOf;
  final String? assetPath;

  const SpiderIconOption({
    required this.id,
    required this.label,
    this.painterOf,
    this.assetPath,
  }) : assert(
          (painterOf != null) != (assetPath != null),
          'Provide exactly one of painterOf or assetPath',
        );

  Widget buildIcon(Color color, {double? size}) {
    if (painterOf != null) {
      final painter = CustomPaint(painter: painterOf!(color));
      return size != null ? SizedBox(width: size, height: size, child: painter) : painter;
    }
    // ColorFiltered + srcIn tints the whole PNG (including any color or
    // gradient in the source art) to a single flat contrasting color,
    // the same way the code-drawn painters always render as one solid
    // color. Requires the PNG to have a transparent background — solid
    // background pixels would get tinted too.
    return ColorFiltered(
      colorFilter: ColorFilter.mode(color, BlendMode.srcIn),
      child: Image.asset(assetPath!, fit: BoxFit.contain),
    );
  }
}

class SpiderIconCatalog {
  static const String defaultIconId = 'round_body';

  static final List<SpiderIconOption> all = [
    // Original code-drawn icons (safe fallback set, always available).
    SpiderIconOption(id: 'round_body', label: 'Round Body', painterOf: (c) => RoundBodySpider(c)),
    SpiderIconOption(id: 'long_legs', label: 'Long Legs', painterOf: (c) => LongLegsSpider(c)),
    SpiderIconOption(id: 'angular', label: 'Angular', painterOf: (c) => AngularSpider(c)),
    SpiderIconOption(id: 'curled', label: 'Curled', painterOf: (c) => CurledSpider(c)),
    SpiderIconOption(id: 'broad_body', label: 'Broad Body', painterOf: (c) => BroadBodySpider(c)),
    SpiderIconOption(id: 'runner', label: 'Runner', painterOf: (c) => RunnerSpider(c)),

    // Your 10 PNGs go here — drop each file in
    // assets/images/pin_spiders/ named spider_01.png through
    // spider_10.png (or rename these assetPath values to match
    // whatever you actually name them), and register the same 10 paths
    // in pubspec.yaml's `assets:` list. Give each a real label once you
    // know which symbol is which.
    SpiderIconOption(id: 'custom_01', label: 'Custom 1', assetPath: 'assets/images/pin_spiders/spider_01.png'),
    SpiderIconOption(id: 'custom_02', label: 'Custom 2', assetPath: 'assets/images/pin_spiders/spider_02.png'),
    SpiderIconOption(id: 'custom_03', label: 'Custom 3', assetPath: 'assets/images/pin_spiders/spider_03.png'),
    SpiderIconOption(id: 'custom_04', label: 'Custom 4', assetPath: 'assets/images/pin_spiders/spider_04.png'),
    SpiderIconOption(id: 'custom_05', label: 'Custom 5', assetPath: 'assets/images/pin_spiders/spider_05.png'),
    SpiderIconOption(id: 'custom_06', label: 'Custom 6', assetPath: 'assets/images/pin_spiders/spider_06.png'),
    SpiderIconOption(id: 'custom_07', label: 'Custom 7', assetPath: 'assets/images/pin_spiders/spider_07.png'),
    SpiderIconOption(id: 'custom_08', label: 'Custom 8', assetPath: 'assets/images/pin_spiders/spider_08.png'),
    SpiderIconOption(id: 'custom_09', label: 'Custom 9', assetPath: 'assets/images/pin_spiders/spider_09.png'),
    SpiderIconOption(id: 'custom_10', label: 'Custom 10', assetPath: 'assets/images/pin_spiders/spider_10.png'),
  ];

  static SpiderIconOption byId(String? id) {
    return all.firstWhere((s) => s.id == id, orElse: () => all.first);
  }
}
