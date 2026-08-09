import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

class PixelButton extends StatelessWidget {
  final String label;
  final VoidCallback? onTap;
  final Color color;

  const PixelButton({
    super.key,
    required this.label,
    this.onTap,
    this.color = const Color(0xFFFFC94A),
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
        decoration: BoxDecoration(
          color: color,
          border: Border.all(color: Colors.black, width: 2),
          borderRadius: BorderRadius.circular(4),
          boxShadow: const [
            BoxShadow(
              color: Colors.black,
              offset: Offset(2, 2),
              blurRadius: 0,
            ),
          ],
        ),
        child: Text(
          label,
          textAlign: TextAlign.center,
          style: GoogleFonts.pressStart2p(
            fontSize: 8,
            color: Colors.black,
          ),
        ),
      ),
    );
  }
}