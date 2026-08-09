import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../../../core/masks/mask_catalog.dart';
import '../../../core/widgets/themed_snackbar.dart';
import '../../map_scanner/presentation/widgets/spider_mask_icon.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../../core/audio/voice_line_player.dart';
import '../../../core/utils/haptics.dart';

/// Call this from wherever your settings sheet lives, e.g.:
///   showMaskPickerSheet(context);
Future<void> showMaskPickerSheet(BuildContext context) async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final userRef = FirebaseFirestore.instance.collection('users').doc(user.uid);
  final snap = await userRef.get();
  final currentMaskId = snap.data()?['maskId'] as String? ?? MaskCatalog.defaultMaskId;

  if (!context.mounted) return;

  await showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF0A1128),
    shape: const RoundedRectangleBorder(
      side: BorderSide(color: Colors.blueAccent, width: 3),
      borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
    ),
    builder: (context) => Padding(
      padding: const EdgeInsets.all(20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('CHOOSE YOUR MASK',
              style: GoogleFonts.pressStart2p(fontSize: 12, color: Colors.cyanAccent)),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 5,
            shrinkWrap: true,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            childAspectRatio: 1,
            children: MaskCatalog.all.map((mask) {
              final selected = mask.id == currentMaskId;
              return GestureDetector(
                onTap: () async {
                  Haptics.confirm();
                  await userRef.update({'maskId': mask.id});
                  if (context.mounted) {
                    Navigator.pop(context);
                    ProviderScope.containerOf(context, listen: false)
                        .read(voiceLinePlayerProvider)
                        .play(VoiceLine.maskChange);
                  }
                },
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
                  child: SpiderMaskIcon(size: 30, maskId: mask.id),
                ),
              );
            }).toList(),
          ),
        ],
      ),
    ),
  );
}