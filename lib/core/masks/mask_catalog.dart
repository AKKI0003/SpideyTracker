/// Central list of every selectable mask. `assetPath` must match what's
/// registered in pubspec.yaml. `id` is what gets stored on the user doc
/// (users/{uid}.maskId) — never rename an existing id once people have
/// picked it, or their saved choice will silently fall back to default.
class MaskOption {
  final String id;
  final String label;
  final String assetPath;

  const MaskOption({required this.id, required this.label, required this.assetPath});
}

class MaskCatalog {
  static const String defaultMaskId = 'spiderman';

  static const List<MaskOption> all = [
    MaskOption(id: 'spiderman', label: 'Spider-Man', assetPath: 'assets/images/spiderman/mask.png'),
    MaskOption(id: 'spidergwen', label: 'Spider-Gwen', assetPath: 'assets/images/spidergwen/mask.png'),
    MaskOption(id: 'venom_style', label: 'Venom', assetPath: 'assets/images/masks/venom_style.png'),
    MaskOption(id: 'stealth_black', label: 'Stealth', assetPath: 'assets/images/masks/stealth_black.png'),
    MaskOption(id: 'ironspider', label: 'Iron-Spider', assetPath: 'assets/images/masks/ironspider.png'),
    MaskOption(id: 'white_ghost', label: 'Ghost', assetPath: 'assets/images/masks/white_ghost.png'),
    MaskOption(id: 'ironspider_alt', label: 'Iron-Spider II', assetPath: 'assets/images/masks/ironspider_alt.png'),
    MaskOption(id: 'matte_black', label: 'Matte Black', assetPath: 'assets/images/masks/matte_black.png'),
    MaskOption(id: 'scorched_grey', label: 'Scorched', assetPath: 'assets/images/masks/scorched_grey.png'),
    MaskOption(id: 'cosmic_web', label: 'Cosmic', assetPath: 'assets/images/masks/cosmic_web.png'),
  ];

  static MaskOption byId(String? id) {
    return all.firstWhere((m) => m.id == id, orElse: () => all.first);
  }
}