import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../../../core/storage/b2_upload_service.dart';
import '../../../core/widgets/pixel_button.dart';
import '../data/pins_repository.dart';
import '../domain/pin_model.dart';

/// Shown right after a pin is created (or from an "add more photos"
/// entry point later): pick up to 5 photos, caption each one, upload.
/// Max-5 is enforced here (grey out picking past the limit) and again
/// server-side in notify-server/api/b2.js + PinsRepository.
Future<void> showAddPhotosSheet(
  BuildContext context, {
  required String partyId,
  required String pinId,
  int existingCount = 0,
}) {
  return showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    isDismissible: false, // avoid an accidental swipe-away mid-upload
    backgroundColor: const Color(0xFF0A1128),
    shape: const RoundedRectangleBorder(
      side: BorderSide(color: Colors.cyanAccent, width: 2),
    ),
    builder: (context) => _AddPhotosSheet(
      partyId: partyId,
      pinId: pinId,
      existingCount: existingCount,
    ),
  );
}

enum _Stage { picked, presigning, uploading, saving, done, failed }

class _PickedPhoto {
  final XFile file;
  Uint8List? bytes;
  String caption = '';
  double progress = 0;
  _Stage stage = _Stage.picked;
  String? error;
  _PickedPhoto(this.file);
}

class _AddPhotosSheet extends StatefulWidget {
  final String partyId;
  final String pinId;
  final int existingCount;

  const _AddPhotosSheet({
    required this.partyId,
    required this.pinId,
    required this.existingCount,
  });

  @override
  State<_AddPhotosSheet> createState() => _AddPhotosSheetState();
}

class _AddPhotosSheetState extends State<_AddPhotosSheet> {
  final _picker = ImagePicker();
  final List<_PickedPhoto> _picked = [];
  bool _uploading = false;
  bool _anyFailed = false;

  int get _remainingSlots =>
      (5 - widget.existingCount - _picked.length).clamp(0, 5);

  Future<void> _pickMore() async {
    if (_remainingSlots <= 0) return;
    final files = await _picker.pickMultiImage(limit: _remainingSlots);
    for (final f in files.take(_remainingSlots)) {
      final bytes = await f.readAsBytes();
      if (!mounted) return;
      setState(() => _picked.add(_PickedPhoto(f)..bytes = bytes));
    }
  }

  Future<void> _uploadOne(_PickedPhoto p, PinsRepository repo, String uid) async {
    try {
      final ext = p.file.name.contains('.') ? p.file.name.split('.').last.toLowerCase() : 'jpg';
      final contentType = const {
            'png': 'image/png',
            'webp': 'image/webp',
            'heic': 'image/heic',
            'jpg': 'image/jpeg',
            'jpeg': 'image/jpeg',
          }[ext] ??
          'image/jpeg';

      if (mounted) setState(() { p.stage = _Stage.presigning; p.progress = 0.15; });
      final result = await B2UploadService.uploadPhoto(
        partyId: widget.partyId,
        pinId: widget.pinId,
        fileName: p.file.name,
        bytes: p.bytes!,
        contentType: contentType,
      );

      if (mounted) setState(() { p.stage = _Stage.saving; p.progress = 0.85; });
      await repo.addPhotoToPin(
        partyId: widget.partyId,
        pinId: widget.pinId,
        photo: PinPhoto(
          id: result.objectKey.split('/').last,
          url: result.downloadUrl,
          objectKey: result.objectKey,
          caption: p.caption,
          uploadedAt: DateTime.now(),
          uploadedByUid: uid,
          width: result.width,
          height: result.height,
        ),
      );

      if (mounted) setState(() { p.stage = _Stage.done; p.progress = 1; });
    } catch (e) {
      _anyFailed = true;
      if (mounted) {
        setState(() {
          p.stage = _Stage.failed;
          p.error = e.toString();
        });
      }
    }
  }

  Future<void> _uploadAll() async {
    setState(() { _uploading = true; _anyFailed = false; });
    final repo = PinsRepository();
    final uid = FirebaseAuth.instance.currentUser!.uid;

    for (final p in _picked) {
      if (p.stage == _Stage.done || p.bytes == null) continue;
      setState(() => p.stage = _Stage.uploading);
      await _uploadOne(p, repo, uid);
    }

    if (!mounted) return;
    setState(() => _uploading = false);

    // Only auto-close if every photo genuinely made it into Firestore —
    // closing regardless of failures used to hide the fact that some
    // photos silently never got saved. If anything failed, the sheet
    // stays open with the real error visible and a retry option.
    if (!_anyFailed) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        left: 16,
        right: 16,
        top: 16,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'ADD PHOTOS (${_picked.length + widget.existingCount}/5)',
            style: GoogleFonts.pressStart2p(fontSize: 10, color: Colors.cyanAccent),
          ),
          const SizedBox(height: 16),
          ..._picked.map((p) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: SizedBox(
                        width: 56,
                        height: 56,
                        child: p.bytes != null
                            ? Image.memory(p.bytes!, fit: BoxFit.cover)
                            : const ColoredBox(color: Colors.black26),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          TextField(
                            enabled: !_uploading,
                            style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white),
                            decoration: InputDecoration(
                              hintText: 'Caption for this photo...',
                              hintStyle: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white38),
                              isDense: true,
                              enabledBorder: const UnderlineInputBorder(
                                borderSide: BorderSide(color: Colors.white24),
                              ),
                            ),
                            onChanged: (v) => p.caption = v,
                          ),
                          if (p.stage != _Stage.picked) ...[
                            Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: LinearProgressIndicator(
                                value: p.progress,
                                minHeight: 5,
                                backgroundColor: Colors.white12,
                                color: p.stage == _Stage.failed
                                    ? Colors.redAccent
                                    : p.stage == _Stage.done
                                        ? Colors.greenAccent
                                        : Colors.cyanAccent,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              switch (p.stage) {
                                _Stage.presigning => 'REQUESTING UPLOAD SLOT...',
                                _Stage.uploading => 'UPLOADING...',
                                _Stage.saving => 'SAVING...',
                                _Stage.done => 'DONE',
                                _Stage.failed => 'FAILED — TAP TO RETRY',
                                _Stage.picked => '',
                              },
                              style: GoogleFonts.pressStart2p(
                                fontSize: 6,
                                color: p.stage == _Stage.failed ? Colors.redAccent : Colors.white54,
                              ),
                            ),
                            if (p.stage == _Stage.failed) ...[
                              const SizedBox(height: 2),
                              GestureDetector(
                                onTap: () async {
                                  final repo = PinsRepository();
                                  final uid = FirebaseAuth.instance.currentUser!.uid;
                                  setState(() { p.stage = _Stage.uploading; _uploading = true; });
                                  await _uploadOne(p, repo, uid);
                                  if (mounted) {
                                    setState(() {
                                      _uploading = false;
                                      _anyFailed = _picked.any((x) => x.stage == _Stage.failed);
                                    });
                                  }
                                },
                                child: Text(
                                  p.error ?? 'Unknown error',
                                  style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.redAccent),
                                ),
                              ),
                            ],
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              )),
          if (_remainingSlots > 0)
            GestureDetector(
              onTap: _uploading ? null : _pickMore,
              child: Container(
                width: double.infinity,
                margin: const EdgeInsets.only(top: 4, bottom: 6),
                padding: const EdgeInsets.symmetric(vertical: 14),
                decoration: BoxDecoration(
                  color: _uploading ? const Color(0xFF11213D) : const Color(0xFF132548),
                  border: Border.all(
                    color: _uploading ? Colors.white24 : Colors.cyanAccent,
                    width: 2,
                  ),
                  boxShadow: _uploading
                      ? null
                      : const [BoxShadow(color: Colors.black, offset: Offset(2, 2), blurRadius: 0)],
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.add_photo_alternate,
                        size: 20, color: _uploading ? Colors.white24 : Colors.cyanAccent),
                    const SizedBox(width: 10),
                    Text(
                      'PICK PHOTOS',
                      style: GoogleFonts.pressStart2p(
                        fontSize: 12,
                        color: _uploading ? Colors.white24 : Colors.cyanAccent,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: PixelButton(
                  label: _uploading ? 'UPLOADING...' : 'SKIP',
                  color: const Color(0xFFB0BEC5),
                  onTap: _uploading ? null : () => Navigator.of(context).pop(),
                ),
              ),
              if (_picked.isNotEmpty) ...[
                const SizedBox(width: 10),
                Expanded(
                  child: PixelButton(
                    label: _uploading ? '...' : 'UPLOAD',
                    onTap: _uploading ? null : _uploadAll,
                  ),
                ),
              ],
            ],
          ),
        ],
      ),
    );
  }
}
