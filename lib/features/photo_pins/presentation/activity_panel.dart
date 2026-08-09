import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:latlong2/latlong.dart';
import '../domain/pin_model.dart';
import '../data/pins_repository.dart';
import '../../../core/widgets/themed_dialog.dart';
import '../../../core/widgets/themed_snackbar.dart';

class ActivityLogSheet extends StatefulWidget {
  final List<PinModel> pins;
  final String? currentUid;
  final Map<String, String> memberNames;
  final String partyId;

  /// Called with a pin's location when the user taps that pin's entry
  /// in the log — lets the caller close the sheet and pan the map to
  /// it instead of the log being purely informational.
  final void Function(LatLng location)? onPinSelected;

  const ActivityLogSheet({
    super.key,
    required this.pins,
    required this.currentUid,
    required this.memberNames,
    required this.partyId,
    this.onPinSelected,
  });

  @override
  State<ActivityLogSheet> createState() => _ActivityLogSheetState();
}

class _ActivityLogSheetState extends State<ActivityLogSheet> {
  final _pinsRepo = PinsRepository();
  bool _isClearing = false;

  String _timeAgo(DateTime? dt) {
    if (dt == null) return '';
    final diff = DateTime.now().difference(dt);
    if (diff.inMinutes < 1) return 'now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m';
    if (diff.inHours < 24) return '${diff.inHours}h';
    return '${diff.inDays}d';
  }

  Future<void> _confirmDeleteOne(PinModel pin) async {
    final confirmed = await showThemedConfirmDialog(
      context,
      title: 'DELETE THIS PIN?',
      message: pin.photos.isEmpty
          ? "This can't be undone."
          : "This also deletes its ${pin.photos.length} photo${pin.photos.length == 1 ? '' : 's'}. This can't be undone.",
      confirmLabel: 'DELETE',
    );
    if (!confirmed) return;

    await _pinsRepo.deletePin(partyId: widget.partyId, pinId: pin.id);
    if (context.mounted) {
      showThemedSnack(context, 'PIN DELETED', tone: SnackTone.success);
    }
  }

  Future<void> _confirmClear() async {
    final confirmed = await showThemedConfirmDialog(
      context,
      title: 'CLEAR ALL PINS?',
      message:
          "This deletes every pin you've dropped. Other members' pins are untouched. This can't be undone.",
      confirmLabel: 'CLEAR',
    );

    if (!confirmed) return;

    setState(() => _isClearing = true);
    await _pinsRepo.deleteAllMyPins(
      partyId: widget.partyId,
      ownerUid: widget.currentUid!,
    );
    setState(() => _isClearing = false);
    if (context.mounted) {
      Navigator.pop(context);
      showThemedSnack(context, 'PINS CLEARED', tone: SnackTone.success);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sorted = [...widget.pins]
      ..sort((a, b) =>
          (b.createdAt ?? DateTime(0)).compareTo(a.createdAt ?? DateTime(0)));

    return Container(
      constraints:
          BoxConstraints(maxHeight: MediaQuery.of(context).size.height * 0.6),
      decoration: BoxDecoration(
        color: const Color(0xFF0A1128),
        border: const Border(
          top: BorderSide(color: Colors.blueAccent, width: 4),
          left: BorderSide(color: Colors.blueAccent, width: 4),
          right: BorderSide(color: Colors.blueAccent, width: 4),
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        boxShadow: [
          BoxShadow(
            color: Colors.blueAccent.withOpacity(0.4),
            blurRadius: 20,
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'SPIDER LOG',
              style: GoogleFonts.pressStart2p(fontSize: 12, color: Colors.cyanAccent),
            ),
            const SizedBox(height: 12),
            Flexible(
              child: sorted.isEmpty
                  ? Padding(
                      padding: const EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          'NO SIGHTINGS YET',
                          style: GoogleFonts.pressStart2p(
                              fontSize: 9, color: Colors.white38),
                        ),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      itemCount: sorted.length,
                      itemBuilder: (context, i) {
                        final pin = sorted[i];
                        final isMine = pin.ownerUid == widget.currentUid;
                        final ownerLabel = isMine
                            ? 'YOU'
                            : (widget.memberNames[pin.ownerUid]?.toUpperCase() ?? 'MEMBER');
                        return Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(
                              child: Material(
                                color: Colors.transparent,
                                child: InkWell(
                                  onTap: widget.onPinSelected == null
                                      ? null
                                      : () => widget.onPinSelected!(pin.location),
                                  borderRadius: BorderRadius.circular(6),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 4),
                                    child: Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Icon(Icons.location_on,
                                            size: 14,
                                            color: isMine ? Colors.redAccent : Colors.pinkAccent),
                                        const SizedBox(width: 8),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                ownerLabel,
                                                style: GoogleFonts.pressStart2p(
                                                    fontSize: 7,
                                                    color: isMine ? Colors.redAccent : Colors.pinkAccent),
                                              ),
                                              const SizedBox(height: 3),
                                              Text(
                                                pin.caption,
                                                style: GoogleFonts.pressStart2p(
                                                    fontSize: 7,
                                                    color: widget.onPinSelected == null
                                                        ? Colors.white70
                                                        : Colors.cyanAccent,
                                                    height: 1.6,
                                                    decoration: widget.onPinSelected == null
                                                        ? TextDecoration.none
                                                        : TextDecoration.underline,
                                                    decorationColor: Colors.cyanAccent.withOpacity(0.5),
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        const SizedBox(width: 6),
                                        Text(
                                          _timeAgo(pin.createdAt).toUpperCase(),
                                          style: GoogleFonts.pressStart2p(
                                              fontSize: 6, color: Colors.white38),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),
                            // Deliberately OUTSIDE the InkWell above (not
                            // nested inside its child tree) — nesting a
                            // small tap target inside a large InkWell put
                            // both in the same gesture arena, and the
                            // InkWell's much bigger hit area was winning
                            // almost every tap meant for delete. Being a
                            // sibling with its own Material/InkResponse
                            // and a generous 40x40 tap target fixes that
                            // completely; there's no longer any overlap
                            // to contend for.
                            if (isMine)
                              Material(
                                color: Colors.transparent,
                                child: InkResponse(
                                  onTap: () => _confirmDeleteOne(pin),
                                  radius: 20,
                                  child: const SizedBox(
                                    width: 40,
                                    height: 40,
                                    child: Icon(Icons.delete_outline,
                                        size: 16, color: Colors.redAccent),
                                  ),
                                ),
                              ),
                          ],
                        );
                      },
                    ),
            ),
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: OutlinedButton(
                onPressed: _isClearing ? null : _confirmClear,
                style: OutlinedButton.styleFrom(
                  side: const BorderSide(color: Colors.redAccent, width: 2),
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(6)),
                ),
                child: _isClearing
                    ? const SizedBox(
                        height: 16,
                        width: 16,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.redAccent))
                    : Text(
                        'CLEAR MY PINS',
                        style: GoogleFonts.pressStart2p(
                            fontSize: 9, color: Colors.redAccent),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}