import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'pixel_button.dart';

/// Shared frame for every themed dialog: a hard-edged panel with a
/// black outer border, a thin colored inner accent border, and a
/// crisp offset drop shadow (no blur) — the same visual language as
/// PixelButton and PixelBadgeFrame elsewhere in the app. The previous
/// version used soft-blurred glow shadows and rounded corners closer
/// to a stock Material dialog, which read as generic/cheap next to
/// everything else's chunky arcade look; this brings dialogs in line
/// with the rest of the app instead of standing apart from it.
Widget _arcadePanel({
  required Widget child,
  Color accent = Colors.cyanAccent,
}) {
  return Container(
    padding: const EdgeInsets.all(3),
    decoration: BoxDecoration(
      color: accent,
      border: Border.all(color: Colors.black, width: 3),
      boxShadow: const [
        BoxShadow(color: Colors.black, offset: Offset(5, 5), blurRadius: 0),
      ],
    ),
    child: Container(
      padding: const EdgeInsets.all(18),
      color: const Color(0xFF0A1128),
      child: child,
    ),
  );
}

Future<bool> showThemedConfirmDialog(
  BuildContext context, {
  required String title,
  required String message,
  String confirmLabel = 'CONFIRM',
  String cancelLabel = 'CANCEL',
  Color confirmColor = const Color(0xFFFF6B6B),
}) async {
  final result = await showDialog<bool>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: _arcadePanel(
        accent: confirmColor,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.pressStart2p(fontSize: 12, color: Colors.white, height: 1.5),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white70, height: 1.8),
            ),
            const SizedBox(height: 22),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PixelButton(
                  label: cancelLabel,
                  color: const Color(0xFFB0BEC5),
                  onTap: () => Navigator.pop(context, false),
                ),
                const SizedBox(width: 10),
                PixelButton(
                  label: confirmLabel,
                  color: confirmColor,
                  onTap: () => Navigator.pop(context, true),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result ?? false;
}

Future<String?> showThemedTextInputDialog(
  BuildContext context, {
  required String title,
  required String hint,
  String confirmLabel = 'SAVE',
  String? initialValue,
}) async {
  final controller = TextEditingController(text: initialValue ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: _arcadePanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.pressStart2p(fontSize: 12, color: Colors.cyanAccent, height: 1.5),
            ),
            const SizedBox(height: 16),
            Container(
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                border: Border.all(color: Colors.cyanAccent, width: 2),
              ),
              child: TextField(
                controller: controller,
                autofocus: true,
                style: GoogleFonts.pressStart2p(fontSize: 10, color: Colors.white, height: 1.6),
                cursorColor: Colors.cyanAccent,
                decoration: InputDecoration(
                  hintText: hint,
                  hintStyle: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.white30),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
            ),
            const SizedBox(height: 20),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                PixelButton(
                  label: 'CANCEL',
                  color: const Color(0xFFB0BEC5),
                  onTap: () => Navigator.pop(context),
                ),
                const SizedBox(width: 10),
                PixelButton(
                  label: confirmLabel,
                  onTap: () => Navigator.pop(context, controller.text.trim()),
                ),
              ],
            ),
          ],
        ),
      ),
    ),
  );
  return result;
}

Future<void> showThemedInfoDialog(
  BuildContext context, {
  required String title,
  required String message,
}) async {
  await showDialog<void>(
    context: context,
    builder: (context) => Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: _arcadePanel(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              title,
              style: GoogleFonts.pressStart2p(fontSize: 12, color: Colors.cyanAccent, height: 1.5),
            ),
            const SizedBox(height: 14),
            Text(
              message,
              style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white70, height: 1.8),
            ),
            const SizedBox(height: 20),
            Align(
              alignment: Alignment.centerRight,
              child: PixelButton(
                label: 'CLOSE',
                onTap: () => Navigator.pop(context),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
