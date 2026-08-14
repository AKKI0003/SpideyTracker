import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../domain/pin_model.dart';
import '../data/pins_repository.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/themed_dialog.dart';
import '../../../core/storage/b2_upload_service.dart';
import '../../../core/widgets/location_tag_chip.dart';
import '../../map_scanner/presentation/widgets/loading_spider_blink.dart';
import 'add_photos_sheet.dart';

/// Opens the pin photo viewer: a pixel-art Spider figure drops in
/// upside-down on a web strand, then holds open a comic-panel frame
/// with the pin's photos. Tapping outside the frame (or the close
/// button) reverses the animation and closes.
Future<void> showPhotoPinViewer(
  BuildContext context, {
  required PinModel pin,
  required String partyId,
  required bool isMine,
  required String ownerLabel,
  String? maskId,
  required String Function(String uid) resolveUploaderName,
  VoidCallback? onPhotosChanged,
}) {
  return Navigator.of(context).push(
    PageRouteBuilder(
      opaque: false,
      barrierColor: Colors.black.withOpacity(0.55),
      transitionDuration: const Duration(milliseconds: 150),
      pageBuilder: (context, animation, secondaryAnimation) {
        return FadeTransition(
          opacity: animation,
          child: PhotoPinViewerScreen(
            pin: pin,
            partyId: partyId,
            isMine: isMine,
            ownerLabel: ownerLabel,
            maskId: maskId,
            resolveUploaderName: resolveUploaderName,
            onPhotosChanged: onPhotosChanged,
          ),
        );
      },
    ),
  );
}

class _WebStrandPainter extends CustomPainter {
  final Offset anchor;
  final Offset end;

  const _WebStrandPainter({required this.anchor, required this.end});

  @override
  void paint(Canvas canvas, Size size) {
    if ((end - anchor).distance < 1) return;

    final mid = Offset((anchor.dx + end.dx) / 2, (anchor.dy + end.dy) / 2);
    final bow = Offset((end.dx - anchor.dx) * 0.5, 0);
    final control = mid + bow;

    final path = Path()
      ..moveTo(anchor.dx, anchor.dy)
      ..quadraticBezierTo(control.dx, control.dy, end.dx, end.dy);

    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withOpacity(0.18)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 4
        ..strokeCap = StrokeCap.round,
    );
    canvas.drawPath(
      path,
      Paint()
        ..color = Colors.white.withOpacity(0.85)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.4
        ..strokeCap = StrokeCap.round,
    );
  }

  @override
  bool shouldRepaint(covariant _WebStrandPainter oldDelegate) =>
      oldDelegate.anchor != anchor || oldDelegate.end != end;
}

class PhotoPinViewerScreen extends StatefulWidget {
  final PinModel pin;
  final String partyId;
  final bool isMine;
  final String ownerLabel;
  final String? maskId;
  final String Function(String uid) resolveUploaderName;
  final VoidCallback? onPhotosChanged;

  const PhotoPinViewerScreen({
    super.key,
    required this.pin,
    required this.partyId,
    required this.isMine,
    required this.ownerLabel,
    required this.maskId,
    required this.resolveUploaderName,
    this.onPhotosChanged,
  });

  @override
  State<PhotoPinViewerScreen> createState() => _PhotoPinViewerScreenState();
}

class _PhotoPinViewerScreenState extends State<PhotoPinViewerScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _entrance;
  late final Animation<double> _spiderAnim;
  late final Animation<double> _frameAnim;

  late List<PinPhoto> _photos;
  int _focusedIndex = 0;
  bool _closing = false;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _photos = List.of(widget.pin.photos);

    _entrance = AnimationController(vsync: this, duration: const Duration(milliseconds: 580));
    _spiderAnim = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.0, 0.65, curve: Curves.easeOutBack),
    );
    _frameAnim = CurvedAnimation(
      parent: _entrance,
      curve: const Interval(0.55, 1.0, curve: Curves.easeOutBack),
    );
    _entrance.forward();
  }

  @override
  void dispose() {
    _entrance.dispose();
    super.dispose();
  }

  Future<void> _close() async {
    if (_closing) return;
    _closing = true;
    await _entrance.reverse();
    if (mounted) Navigator.of(context).pop();
  }

  void _openFull(int index) {
    Navigator.of(context).push(
      PageRouteBuilder(
        opaque: true,
        transitionDuration: const Duration(milliseconds: 200),
        pageBuilder: (context, animation, secondaryAnimation) => FadeTransition(
          opacity: animation,
          child: _FullScreenPhotoView(
            photos: _photos,
            initialIndex: index,
            isMine: widget.isMine,
            pinCaption: widget.pin.caption,
            ownerLabel: widget.ownerLabel,
            resolveUploaderName: widget.resolveUploaderName,
            onDownload: _handleDownload,
            onDelete: (photo) async {
              await _handleDelete(photo);
              return _photos;
            },
          ),
        ),
      ),
    );
  }

  Future<void> _handleDownload(PinPhoto photo) async {
    final uri = Uri.parse(photo.url);
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _handleDeletePin() async {
    final confirmed = await showThemedConfirmDialog(
      context,
      title: 'DELETE THIS PIN?',
      message: _photos.isEmpty
          ? "This can't be undone."
          : "This also deletes its ${_photos.length} photo${_photos.length == 1 ? '' : 's'}. This can't be undone.",
      confirmLabel: 'DELETE',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await PinsRepository().deletePin(partyId: widget.partyId, pinId: widget.pin.id);
      widget.onPhotosChanged?.call();
      if (mounted) await _close();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _handleDelete(PinPhoto photo) async {
    final confirmed = await showThemedConfirmDialog(
      context,
      title: 'DELETE PHOTO?',
      message: "This can't be undone.",
      confirmLabel: 'DELETE',
    );
    if (!confirmed) return;

    setState(() => _busy = true);
    try {
      await B2UploadService.deletePhoto(
        partyId: widget.partyId,
        pinId: widget.pin.id,
        objectKey: photo.objectKey,
      );
      await PinsRepository().deletePhotoFromPin(
        partyId: widget.partyId,
        pinId: widget.pin.id,
        photoId: photo.id,
      );
      setState(() {
        _photos.removeWhere((p) => p.id == photo.id);
        if (_focusedIndex >= _photos.length && _photos.isNotEmpty) {
          _focusedIndex = _photos.length - 1;
        }
        _busy = false;
      });
      widget.onPhotosChanged?.call();
    } catch (e) {
      setState(() => _busy = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Delete failed: $e')),
        );
      }
    }
  }

  Future<void> _handleAddPhotos() async {
    if (_photos.length >= 5) return;
    await showAddPhotosSheet(
      context,
      partyId: widget.partyId,
      pinId: widget.pin.id,
      existingCount: _photos.length,
    );
    if (!mounted) return;
    final doc = await FirebaseFirestore.instance
        .collection('parties')
        .doc(widget.partyId)
        .collection('pins')
        .doc(widget.pin.id)
        .get();
    final raw = (doc.data()?['photos'] as List?) ?? const [];
    setState(() {
      _photos = raw
          .map((p) => PinPhoto.fromMap(Map<String, dynamic>.from(p as Map)))
          .toList();
    });
    widget.onPhotosChanged?.call();
  }

  @override
  Widget build(BuildContext context) {
    final screenSize = MediaQuery.of(context).size;
    final dropTarget = screenSize.height * 0.30;
    final frameTop = dropTarget + 14;
    final frameMaxHeight = (screenSize.height - frameTop - 24).clamp(200.0, double.infinity);

    return Scaffold(
      backgroundColor: Colors.transparent,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _close,
        child: AnimatedBuilder(
          animation: _entrance,
          builder: (context, child) {
            final t = _spiderAnim.value.clamp(0.0, 1.0);
            final spiderY = t * dropTarget;
            final swingX = sin(t * 3.4 * pi) * (1 - t) * 34;
            const anchorX = 0.0;
            final maskCenterX = screenSize.width / 2 + swingX;
            final maskTop = (spiderY - 24).clamp(0.0, double.infinity);

            return Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: _WebStrandPainter(
                      anchor: Offset(screenSize.width / 2 + anchorX, 0),
                      end: Offset(maskCenterX, spiderY),
                    ),
                  ),
                ),
                Positioned(
                  top: maskTop,
                  left: maskCenterX - 24,
                  child: Opacity(
                    opacity: t,
                    child: Image.asset(
                      'assets/images/viewer/descent_mask.png',
                      width: 48,
                      height: 48,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
                if (_frameAnim.value > 0)
                  Positioned(
                    top: frameTop,
                    left: 0,
                    right: 0,
                    child: Center(
                      child: Opacity(
                        opacity: _frameAnim.value.clamp(0, 1),
                        child: Transform.scale(
                          scale: 0.85 + 0.15 * _frameAnim.value,
                          alignment: Alignment.topCenter,
                          child: GestureDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {},
                            child: _buildFrame(context, screenSize, frameMaxHeight),
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _buildFrame(BuildContext context, Size screenSize, double maxHeight) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxWidth: screenSize.width * 0.9,
        maxHeight: maxHeight,
      ),
      child: Container(
        padding: const EdgeInsets.all(3),
        decoration: const BoxDecoration(
          color: Colors.cyanAccent,
          boxShadow: [
            BoxShadow(color: Colors.black, offset: Offset(5, 5), blurRadius: 0),
          ],
        ),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: const BoxDecoration(
            color: Color(0xFF0A1128),
            border: Border(
              top: BorderSide(color: Color(0xFF1B3A6B), width: 2),
              left: BorderSide(color: Color(0xFF1B3A6B), width: 2),
              right: BorderSide(color: Color(0xFF1B3A6B), width: 2),
              bottom: BorderSide(color: Color(0xFF1B3A6B), width: 2),
            ),
          ),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            child: _buildGridView(context),
          ),
        ),
      ),
    );
  }

  Widget _header(String title, {VoidCallback? onBack, bool showDeletePin = false}) {
    return Row(
      children: [
        if (onBack != null)
          GestureDetector(
            onTap: onBack,
            child: const Padding(
              padding: EdgeInsets.only(right: 8),
              child: Icon(Icons.arrow_back, size: 16, color: Colors.cyanAccent),
            ),
          ),
        Expanded(
          child: Text(
            title,
            style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.cyanAccent, height: 1.4),
          ),
        ),
        if (showDeletePin) ...[
          GestureDetector(
            onTap: _busy ? null : _handleDeletePin,
            child: const Padding(
              padding: EdgeInsets.only(right: 12),
              child: Icon(Icons.delete_outline, size: 16, color: Colors.redAccent),
            ),
          ),
        ],
        GestureDetector(
          onTap: _close,
          child: const Icon(Icons.close, size: 16, color: Colors.white70),
        ),
      ],
    );
  }

  Widget _captionBlock(PinPhoto? photo) {
    final caption = photo?.caption.isNotEmpty == true ? photo!.caption : widget.pin.caption;
    final date = photo?.uploadedAt ?? widget.pin.createdAt;
    final uploader = photo != null
        ? widget.resolveUploaderName(photo.uploadedByUid)
        : widget.ownerLabel;

    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (caption.isNotEmpty)
            Text(caption,
                style: GoogleFonts.pressStart2p(
                    fontSize: 8, color: Colors.white, height: 1.7, letterSpacing: 0.2)),
          const SizedBox(height: 6),
          Text(
            [
              uploader,
              if (date != null) DateFormat('MMM d, HH:mm').format(date),
            ].join('   ·   '),
            style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.white54, height: 1.6),
          ),
        ],
      ),
    );
  }

  Widget _buildGridView(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _header(
          widget.isMine ? 'YOUR PIN' : "${widget.ownerLabel.toUpperCase()}'S PIN",
          showDeletePin: widget.isMine,
        ),
        const SizedBox(height: 10),
        LocationTagChip(location: widget.pin.location),
        const SizedBox(height: 12),
        if (_photos.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text(
              widget.pin.caption.isEmpty ? 'No photos on this pin.' : widget.pin.caption,
              style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.white70, height: 1.7),
            ),
          )
        else ...[
          Wrap(
            spacing: 7,
            runSpacing: 7,
            children: [
              ...List.generate(_photos.length, (i) {
                final p = _photos[i];
                return GestureDetector(
                  onTap: () => _openFull(i),
                  child: Container(
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.white12, width: 1),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: SizedBox(
                      width: 84,
                      height: 84,
                      child: Image.network(
                        p.url,
                        fit: BoxFit.cover,
                        // Was decoding the FULL original photo
                        // resolution (often several thousand px from a
                        // phone camera) just to show an 84x84 square —
                        // on lower-RAM Android devices, a screen with
                        // several of these thumbnails could easily push
                        // memory into OOM-crash territory. Capping the
                        // decode size to roughly what's actually shown
                        // (with headroom for high-DPI screens) fixes
                        // that with zero visible quality change, since
                        // the display size never changes.
                        cacheWidth: 250,
                        cacheHeight: 250,
                        errorBuilder: (context, error, stack) {
                          debugPrint('Pin photo failed to load (${p.url}): $error');
                          return Container(
                            color: Colors.black26,
                            child: const Icon(Icons.broken_image, color: Colors.white38, size: 18),
                          );
                        },
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const ColoredBox(
                            color: Colors.black26,
                            child: Center(child: LoadingSpiderBlink(size: 30)),
                          );
                        },
                      ),
                    ),
                  ),
                );
              }),
              if (widget.isMine && _photos.length < 5)
                GestureDetector(
                  onTap: _handleAddPhotos,
                  child: Container(
                    width: 84,
                    height: 84,
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.6), width: 1.5),
                    ),
                    child: const Icon(Icons.add, color: Colors.cyanAccent, size: 24),
                  ),
                ),
            ],
          ),
          _captionBlock(_photos[_focusedIndex.clamp(0, _photos.length - 1)]),
        ],
      ],
    );
  }
}

class _FullScreenPhotoView extends StatefulWidget {
  final List<PinPhoto> photos;
  final int initialIndex;
  final bool isMine;
  final String pinCaption;
  final String ownerLabel;
  final String Function(String uid) resolveUploaderName;
  final Future<void> Function(PinPhoto photo) onDownload;
  final Future<List<PinPhoto>> Function(PinPhoto photo) onDelete;

  const _FullScreenPhotoView({
    required this.photos,
    required this.initialIndex,
    required this.isMine,
    required this.pinCaption,
    required this.ownerLabel,
    required this.resolveUploaderName,
    required this.onDownload,
    required this.onDelete,
  });

  @override
  State<_FullScreenPhotoView> createState() => _FullScreenPhotoViewState();
}

class _FullScreenPhotoViewState extends State<_FullScreenPhotoView> {
  late List<PinPhoto> _photos;
  late int _index;
  late final PageController _pageController;
  bool _busy = false;
  bool _chromeVisible = true;

  @override
  void initState() {
    super.initState();
    _photos = List.of(widget.photos);
    _index = widget.initialIndex;
    _pageController = PageController(initialPage: _index);
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  void _toggleChrome() => setState(() => _chromeVisible = !_chromeVisible);

  Future<void> _handleDelete() async {
    final photo = _photos[_index];
    setState(() => _busy = true);
    _photos = await widget.onDelete(photo);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (_photos.isEmpty) {
        Navigator.of(context).pop();
      } else if (_index >= _photos.length) {
        _index = _photos.length - 1;
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final photo = _photos[_index];
    final caption = photo.caption.isNotEmpty ? photo.caption : widget.pinCaption;
    final uploader = widget.resolveUploaderName(photo.uploadedByUid);
    final date = photo.uploadedAt;

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          GestureDetector(
            onTap: _toggleChrome,
            child: PageView.builder(
              controller: _pageController,
              itemCount: _photos.length,
              onPageChanged: (i) => setState(() => _index = i),
              itemBuilder: (context, i) {
                final p = _photos[i];
                return InteractiveViewer(
                  minScale: 1,
                  maxScale: 5,
                  child: Center(
                    child: Image.network(
                      p.url,
                      fit: BoxFit.contain,
                      // This view supports up to 5x pinch-zoom, so it
                      // genuinely needs a much higher-res decode than
                      // the grid thumbnails — but the raw original from
                      // a phone camera (often 3000-4000px+) is still far
                      // more than any phone screen at 5x zoom can
                      // actually resolve. Capping at 2400px (long edge,
                      // aspect ratio preserved automatically since only
                      // width is set) keeps zoom quality indistinguishable
                      // from uncapped while cutting memory substantially.
                      cacheWidth: 2400,
                      errorBuilder: (context, error, stack) => const Icon(
                          Icons.broken_image, color: Colors.white38, size: 40),
                      loadingBuilder: (context, child, progress) {
                        if (progress == null) return child;
                        return const Center(child: LoadingSpiderBlink(size: 48));
                      },
                    ),
                  ),
                );
              },
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _chromeVisible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Container(
                          padding: const EdgeInsets.all(8),
                          decoration: BoxDecoration(
                            color: Colors.black54,
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: const Icon(Icons.close, color: Colors.white, size: 20),
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(
                          color: Colors.black54,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${_index + 1} / ${_photos.length}',
                          style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.cyanAccent),
                        ),
                      ),
                      const Spacer(),
                      const SizedBox(width: 36),
                    ],
                  ),
                ),
              ),
            ),
          ),
          AnimatedOpacity(
            duration: const Duration(milliseconds: 180),
            opacity: _chromeVisible ? 1 : 0,
            child: IgnorePointer(
              ignoring: !_chromeVisible,
              child: SafeArea(
                child: Align(
                  alignment: Alignment.bottomCenter,
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.bottomCenter,
                        end: Alignment.topCenter,
                        colors: [Colors.black.withOpacity(0.85), Colors.transparent],
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (caption.isNotEmpty)
                          Text(caption,
                              style: GoogleFonts.pressStart2p(
                                  fontSize: 8, color: Colors.white, height: 1.7)),
                        const SizedBox(height: 6),
                        Text(
                          [uploader, if (date != null) DateFormat('MMM d, HH:mm').format(date)]
                              .join('   ·   '),
                          style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.white54),
                        ),
                        const SizedBox(height: 14),
                        Row(
                          children: [
                            _circleAction(
                              icon: Icons.download,
                              onTap: _busy ? null : () => widget.onDownload(photo),
                            ),
                            if (widget.isMine) ...[
                              const SizedBox(width: 14),
                              _circleAction(
                                icon: Icons.delete_outline,
                                color: Colors.redAccent,
                                onTap: _busy ? null : _handleDelete,
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _circleAction({required IconData icon, VoidCallback? onTap, Color color = Colors.cyanAccent}) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black54,
          border: Border.all(color: color, width: 1.5),
        ),
        child: Icon(icon, color: color, size: 20),
      ),
    );
  }
}