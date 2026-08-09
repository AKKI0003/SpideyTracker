import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/pins/spider_icon_catalog.dart';
import '../../../core/widgets/hue_color_picker.dart';
import '../../../core/widgets/themed_snackbar.dart';
import '../../photo_pins/presentation/widgets/memory_pin_badge.dart';

/// Call from wherever your settings sheet lives, e.g.:
///   showPinCustomizationSheet(context);
///
/// Stores users/{uid}.pinSpiderId and users/{uid}.pinColorValue (an ARGB
/// int, via Color.value) — separate fields from maskId/maskId's live
/// mask, since Feature 1 requires the memory-pin spider and the
/// live-location mask to be independently chosen.
Future<void> showPinCustomizationSheet(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
  final snap = await userRef.get();
  final currentIconId = snap.data()?['pinSpiderId'] as String? ?? SpiderIconCatalog.defaultIconId;
  final currentColorValue = snap.data()?['pinColorValue'] as int? ?? Colors.redAccent.value;

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF0A1128),
    shape: const RoundedRectangleBorder(
      side: BorderSide(color: Colors.blueAccent, width: 3),
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    isScrollControlled: true,
    builder: (context) {
      String selectedIconId = currentIconId;
      double hue = HSVColor.fromColor(Color(currentColorValue)).hue;

      return StatefulBuilder(
        builder: (context, setState) {
          final previewColor = HSVColor.fromAHSV(1, hue, 0.85, 0.95).toColor();

          return Padding(
            padding: EdgeInsets.only(
              left: 20,
              right: 20,
              top: 20,
              bottom: 20 + MediaQuery.of(context).viewInsets.bottom,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('CUSTOMIZE YOUR PIN',
                    style: GoogleFonts.pressStart2p(fontSize: 12, color: Colors.cyanAccent)),
                const SizedBox(height: 16),

                // Live preview, same widget used on the actual map.
                Center(
                  child: MemoryPinBadge(
                    size: 48,
                    spiderIconId: selectedIconId,
                    backgroundColor: previewColor,
                    username: 'YOU',
                  ),
                ),
                const SizedBox(height: 20),

                Text('SPIDER', style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.white54)),
                const SizedBox(height: 10),
                GridView.count(
                  crossAxisCount: 5,
                  shrinkWrap: true,
                  mainAxisSpacing: 10,
                  crossAxisSpacing: 10,
                  childAspectRatio: 1,
                  children: SpiderIconCatalog.all.map((icon) {
                    final selected = icon.id == selectedIconId;
                    return GestureDetector(
                      onTap: () => setState(() => selectedIconId = icon.id),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          border: Border.all(
                            color: selected ? Colors.greenAccent : Colors.blueAccent.withOpacity(0.4),
                            width: selected ? 2.5 : 1.5,
                          ),
                          borderRadius: BorderRadius.circular(6),
                          color: Colors.black.withOpacity(0.4),
                        ),
                        child: icon.buildIcon(Colors.white),
                      ),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),

                Text('PIN COLOR', style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.white54)),
                HueColorBar(
                  hue: hue,
                  onChanged: (h) => setState(() => hue = h),
                ),
                const SizedBox(height: 16),

                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.cyanAccent,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                    ),
                    onPressed: () async {
                      await userRef.update({
                        'pinSpiderId': selectedIconId,
                        'pinColorValue': previewColor.value,
                      });
                      if (context.mounted) {
                        Navigator.pop(context);
                        showThemedSnack(context, 'PIN UPDATED', tone: SnackTone.success);
                      }
                    },
                    child: Text('SAVE', style: GoogleFonts.pressStart2p(fontSize: 10, color: Colors.black)),
                  ),
                ),
              ],
            ),
          );
        },
      );
    },
  );
}
