import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

enum SnackTone { success, error, info }

void showThemedSnack(BuildContext context, String message, {SnackTone tone = SnackTone.info}) {
  final color = switch (tone) {
    SnackTone.success => Colors.greenAccent,
    SnackTone.error => Colors.redAccent,
    SnackTone.info => Colors.cyanAccent,
  };

  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      duration: const Duration(seconds: 2),
      backgroundColor: const Color(0xFF0A1128),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(3),
        side: BorderSide(color: color, width: 2),
      ),
      behavior: SnackBarBehavior.floating,
      content: Row(
        children: [
          Icon(Icons.bolt, color: color, size: 14),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message,
              style: GoogleFonts.pressStart2p(fontSize: 9, color: color),
            ),
          ),
        ],
      ),
    ),
  );
}