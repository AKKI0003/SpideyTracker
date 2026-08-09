import 'package:flutter/material.dart';
import '../../../../core/masks/mask_catalog.dart';

class SpiderMaskIcon extends StatelessWidget {
  final double size;

  /// Preferred way to pick a mask now — pass the user's chosen maskId
  /// (from users/{uid}.maskId, defaults to MaskCatalog.defaultMaskId).
  final String? maskId;

  /// Old boolean toggle, kept so existing call sites that only know
  /// "spiderman vs spidergwen" keep working without edits. Ignored
  /// whenever [maskId] is provided.
  final bool isGwenTheme;

  const SpiderMaskIcon({
    super.key,
    this.size = 40,
    this.maskId,
    this.isGwenTheme = false,
  });

  @override
  Widget build(BuildContext context) {
    final resolvedId = maskId ?? (isGwenTheme ? 'spidergwen' : MaskCatalog.defaultMaskId);
    final option = MaskCatalog.byId(resolvedId);
    return Image.asset(
      option.assetPath,
      width: size,
      height: size,
      fit: BoxFit.contain,
    );
  }
}