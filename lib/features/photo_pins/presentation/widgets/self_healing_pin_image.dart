import 'package:flutter/material.dart';
import '../../domain/pin_model.dart';
import '../../data/pins_repository.dart';
import '../../../../core/storage/b2_upload_service.dart';

/// Drop-in replacement for `Image.network(photo.url)` wherever a
/// [PinPhoto] is displayed. Backblaze B2's download URLs are signed
/// and expire after 7 days (the bucket is private — see
/// notify-server/api/b2.js) — a photo that was fine for a week would
/// then just show a broken-image icon forever, since the stored URL
/// never changed on its own.
///
/// This widget fixes that two ways:
///  - Proactively: if the photo's `signedAt` is older than 6 days, it
///    quietly re-signs a fresh URL as soon as it builds, before the
///    old one actually expires, and persists the new URL back onto
///    the pin (via [PinsRepository.updatePhotoUrl]) so every other
///    viewer benefits too, not just whoever happened to open it first.
///  - Reactively: if the image still fails to load for any reason
///    (clock skew, an older photo with no `signedAt` at all, a link
///    that expired before this ever got a chance to run), it re-signs
///    and retries once automatically instead of leaving the broken-
///    image icon up permanently.
class SelfHealingPinImage extends StatefulWidget {
  final String partyId;
  final String pinId;
  final PinPhoto photo;
  final BoxFit fit;
  final int? cacheWidth;
  final int? cacheHeight;
  final Widget Function(BuildContext context)? loadingPlaceholder;

  const SelfHealingPinImage({
    super.key,
    required this.partyId,
    required this.pinId,
    required this.photo,
    this.fit = BoxFit.cover,
    this.cacheWidth,
    this.cacheHeight,
    this.loadingPlaceholder,
  });

  @override
  State<SelfHealingPinImage> createState() => _SelfHealingPinImageState();
}

class _SelfHealingPinImageState extends State<SelfHealingPinImage> {
  static const _staleAfter = Duration(days: 6); // refresh before the real 7-day expiry
  late String _url;
  bool _refreshing = false;
  bool _refreshFailed = false;

  @override
  void initState() {
    super.initState();
    _url = widget.photo.url;
    _maybeProactiveRefresh();
  }

  @override
  void didUpdateWidget(covariant SelfHealingPinImage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.photo.id != widget.photo.id) {
      _url = widget.photo.url;
      _refreshFailed = false;
      _maybeProactiveRefresh();
    }
  }

  void _maybeProactiveRefresh() {
    final signedAt = widget.photo.signedAt;
    final isStale = signedAt == null || DateTime.now().difference(signedAt) > _staleAfter;
    if (isStale) _refresh();
  }

  Future<void> _refresh() async {
    if (_refreshing) return;
    _refreshing = true;
    try {
      final freshUrl = await B2UploadService.refreshDownloadUrl(
        partyId: widget.partyId,
        pinId: widget.pinId,
        objectKey: widget.photo.objectKey,
      );
      final now = DateTime.now();
      // Best-effort — if this write fails (offline, permission hiccup)
      // the fresh URL still displays for this viewer right now via
      // setState below; it just won't have been persisted for others
      // yet, and will simply retry again the next time anyone opens it.
      // Not awaited (so a slow Firestore write doesn't delay the image
      // appearing), but still logged if it fails rather than silently
      // swallowed.
      PinsRepository().updatePhotoUrl(
        partyId: widget.partyId,
        pinId: widget.pinId,
        photoId: widget.photo.id,
        newUrl: freshUrl,
        newSignedAt: now,
      ).catchError((e) {
        debugPrint('SelfHealingPinImage: failed to persist refreshed url for ${widget.photo.id}: $e');
      });
      if (mounted) setState(() => _url = freshUrl);
    } catch (e) {
      debugPrint('SelfHealingPinImage: refresh failed for ${widget.photo.id}: $e');
      if (mounted) setState(() => _refreshFailed = true);
    } finally {
      _refreshing = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Image.network(
      _url,
      fit: widget.fit,
      cacheWidth: widget.cacheWidth,
      cacheHeight: widget.cacheHeight,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return widget.loadingPlaceholder?.call(context) ??
            const Center(
              child: SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
              ),
            );
      },
      errorBuilder: (context, error, stack) {
        debugPrint('SelfHealingPinImage: load failed for ${widget.photo.id} ($_url): $error');
        // Reactive fallback: attempt exactly one refresh-and-retry
        // rather than immediately giving up. Scheduled for after this
        // frame since errorBuilder runs during build and setState
        // can't be called synchronously from there.
        if (!_refreshFailed && !_refreshing) {
          WidgetsBinding.instance.addPostFrameCallback((_) => _refresh());
        }
        return Container(
          color: Colors.black26,
          alignment: Alignment.center,
          child: _refreshing
              ? const SizedBox(
                  width: 14,
                  height: 14,
                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white38),
                )
              : const Icon(Icons.broken_image, color: Colors.white38, size: 18),
        );
      },
    );
  }
}
