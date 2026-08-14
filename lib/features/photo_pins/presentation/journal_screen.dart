import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import '../data/pins_repository.dart';
import '../domain/pin_model.dart';
import 'photo_pin_viewer.dart';
import '../../map_scanner/presentation/widgets/grid_overlay.dart';
import '../../map_scanner/presentation/widgets/scan_lines_overlay.dart';
import '../../map_scanner/presentation/widgets/loading_spider_blink.dart';
import '../../map_scanner/presentation/widgets/spider_mask_icon.dart';

/// One flattened (pin, photo) pair — a pin with 3 photos produces 3
/// entries here, one per photo, so the grid is a feed of individual
/// photos rather than of pins.
class _JournalEntry {
  final PinModel pin;
  final PinPhoto photo;
  const _JournalEntry({required this.pin, required this.photo});

  DateTime get sortTime => photo.uploadedAt ?? pin.createdAt ?? DateTime.fromMillisecondsSinceEpoch(0);
}

/// Feature: JOURNAL button.
///
/// Self-contained — fetches its own pins/member data rather than
/// reaching into MapScannerScreen's private state, so wiring it up is
/// just `Navigator.push(... JournalScreen(partyId: widget.partyId))`
/// with nothing else to plumb through. Tapping any preview opens the
/// exact same `showPhotoPinViewer` used when tapping a pin on the map —
/// untouched, unmodified, same Spider-Man-descends-with-a-frame
/// experience.
class JournalScreen extends StatefulWidget {
  final String partyId;
  const JournalScreen({super.key, required this.partyId});

  @override
  State<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends State<JournalScreen> {
  final _pinsRepo = PinsRepository();
  List<PinModel> _pins = [];
  final Map<String, String> _memberNames = {};
  final Map<String, String> _memberMaskIds = {};
  bool _loading = true;

  String get _myUid => FirebaseAuth.instance.currentUser?.uid ?? '';

  @override
  void initState() {
    super.initState();
    _pinsRepo.watchPins(widget.partyId).listen((snapshot) async {
      final pins = snapshot.docs.map((d) => PinModel.fromDoc(d)).toList();

      final ownerUids = pins.map((p) => p.ownerUid).toSet();
      final missingUids = ownerUids.where((uid) => !_memberNames.containsKey(uid)).toList();

      if (missingUids.isNotEmpty) {
        // Fetched in parallel rather than one at a time — with up to 8
        // party members this could otherwise mean 8 sequential
        // round-trips before the journal even finishes loading.
        final docs = await Future.wait(
          missingUids.map((uid) => FirebaseFirestore.instance.collection('users').doc(uid).get()),
        );
        for (int i = 0; i < missingUids.length; i++) {
          final uid = missingUids[i];
          final doc = docs[i];
          _memberNames[uid] = uid == _myUid ? 'You' : (doc.data()?['displayName'] as String? ?? 'Member');
          _memberMaskIds[uid] = doc.data()?['maskId'] as String? ?? 'spiderman';
        }
      }

      if (!mounted) return;
      setState(() {
        _pins = pins;
        _loading = false;
      });
    });
  }

  List<_JournalEntry> get _entries {
    final entries = <_JournalEntry>[];
    for (final pin in _pins) {
      for (final photo in pin.photos) {
        entries.add(_JournalEntry(pin: pin, photo: photo));
      }
    }
    // Newest first — a journal you actually open to see what's new
    // lately, not scroll-to-the-bottom to find it.
    entries.sort((a, b) => b.sortTime.compareTo(a.sortTime));
    return entries;
  }

  void _openViewer(PinModel pin) {
    final isMine = pin.ownerUid == _myUid;
    showPhotoPinViewer(
      context,
      pin: pin,
      partyId: widget.partyId,
      isMine: isMine,
      ownerLabel: isMine ? 'You' : (_memberNames[pin.ownerUid] ?? 'Member'),
      maskId: _memberMaskIds[pin.ownerUid],
      resolveUploaderName: (uid) => uid == _myUid ? 'You' : (_memberNames[uid] ?? 'Member'),
      onPhotosChanged: () {}, // the pins stream above already keeps everything fresh
    );
  }

  String _dateHeaderFor(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    if (day == today) return 'TODAY';
    if (day == today.subtract(const Duration(days: 1))) return 'YESTERDAY';
    return DateFormat('MMM d, yyyy').format(date).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    final entries = _entries;

    return Scaffold(
      backgroundColor: const Color(0xFF0A1128),
      body: SafeArea(
        child: Stack(
          children: [
            const Positioned.fill(child: GridOverlay()),
            const Positioned.fill(child: ScanLinesOverlay()),
            Column(
              children: [
                _JournalHeader(count: entries.length),
                Expanded(
                  child: _loading
                      ? const Center(child: LoadingSpiderBlink(size: 64))
                      : entries.isEmpty
                          ? const _EmptyJournal()
                          : _JournalGrid(
                              entries: entries,
                              dateHeaderFor: _dateHeaderFor,
                              onTapEntry: _openViewer,
                              memberMaskIds: _memberMaskIds,
                            ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _JournalHeader extends StatelessWidget {
  final int count;
  const _JournalHeader({required this.count});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(12, 10, 16, 14),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: Colors.blueAccent.withOpacity(0.4), width: 2)),
        boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.15), blurRadius: 12)],
      ),
      child: Row(
        children: [
          GestureDetector(
            onTap: () => Navigator.of(context).pop(),
            child: Container(
              padding: const EdgeInsets.all(6),
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.5),
                border: Border.all(color: Colors.cyanAccent, width: 1.5),
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Icon(Icons.arrow_back, color: Colors.cyanAccent, size: 18),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  children: [
                    Text(
                      'JOURNAL',
                      style: GoogleFonts.pressStart2p(
                        fontSize: 15,
                        color: Colors.cyanAccent,
                        shadows: [Shadow(color: Colors.cyanAccent.withOpacity(0.6), blurRadius: 10)],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const SpiderMaskIcon(size: 20),
                  ],
                ),
                const SizedBox(height: 2),
                Text(
                  '$count MEMOR${count == 1 ? 'Y' : 'IES'} WEBBED',
                  style: GoogleFonts.pressStart2p(fontSize: 7, color: Colors.white38),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyJournal extends StatelessWidget {
  const _EmptyJournal();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Opacity(opacity: 0.35, child: const SpiderMaskIcon(size: 72)),
          const SizedBox(height: 18),
          Text(
            'NO MEMORIES\nWEBBED YET',
            textAlign: TextAlign.center,
            style: GoogleFonts.pressStart2p(fontSize: 11, color: Colors.white38, height: 1.8),
          ),
          const SizedBox(height: 8),
          const Text(
            'Drop a pin and add photos to start your journal',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white24, fontSize: 12),
          ),
        ],
      ),
    );
  }
}

class _JournalGrid extends StatelessWidget {
  final List<_JournalEntry> entries;
  final String Function(DateTime) dateHeaderFor;
  final void Function(PinModel pin) onTapEntry;
  final Map<String, String> memberMaskIds;

  const _JournalGrid({
    required this.entries,
    required this.dateHeaderFor,
    required this.onTapEntry,
    required this.memberMaskIds,
  });

  @override
  Widget build(BuildContext context) {
    // Group consecutive entries under the same date header, same
    // pattern as the chat's date separators — but built inline here
    // since this screen is deliberately self-contained.
    final sections = <MapEntry<String, List<_JournalEntry>>>[];
    for (final entry in entries) {
      final header = dateHeaderFor(entry.sortTime);
      if (sections.isNotEmpty && sections.last.key == header) {
        sections.last.value.add(entry);
      } else {
        sections.add(MapEntry(header, [entry]));
      }
    }

    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      itemCount: sections.length,
      itemBuilder: (context, sectionIndex) {
        final section = sections[sectionIndex];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: EdgeInsets.only(left: 4, bottom: 8, top: sectionIndex == 0 ? 4 : 18),
              child: Text(
                section.key,
                style: GoogleFonts.pressStart2p(fontSize: 8, color: Colors.cyanAccent.withOpacity(0.7)),
              ),
            ),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 8,
                mainAxisSpacing: 8,
              ),
              itemCount: section.value.length,
              itemBuilder: (context, i) {
                final entry = section.value[i];
                // Staggered pop-in, delay scaled by overall position so
                // the whole grid doesn't animate in one flat wave.
                final globalIndex = entries.indexOf(entry);
                return _JournalTile(
                  entry: entry,
                  delay: Duration(milliseconds: 25 * (globalIndex % 12)),
                  onTap: () => onTapEntry(entry.pin),
                  ownerMaskId: memberMaskIds[entry.pin.ownerUid],
                );
              },
            ),
          ],
        );
      },
    );
  }
}

class _JournalTile extends StatefulWidget {
  final _JournalEntry entry;
  final Duration delay;
  final VoidCallback onTap;
  final String? ownerMaskId;

  const _JournalTile({
    required this.entry,
    required this.delay,
    required this.onTap,
    required this.ownerMaskId,
  });

  @override
  State<_JournalTile> createState() => _JournalTileState();
}

class _JournalTileState extends State<_JournalTile> with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _scale;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 320));
    _scale = CurvedAnimation(parent: _controller, curve: Curves.easeOutBack);
    _fade = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    Future.delayed(widget.delay, () {
      if (mounted) _controller.forward();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final photo = widget.entry.photo;
    final pin = widget.entry.pin;
    final photoCount = pin.photos.length;

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) => Opacity(
        opacity: _fade.value,
        child: Transform.scale(scale: 0.8 + 0.2 * _scale.value, child: child),
      ),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AspectRatio(
          aspectRatio: 1,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(6),
              border: Border.all(color: Colors.blueAccent.withOpacity(0.5), width: 1.5),
              boxShadow: [BoxShadow(color: Colors.blueAccent.withOpacity(0.15), blurRadius: 6)],
            ),
            clipBehavior: Clip.antiAlias,
            child: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  photo.url,
                  fit: BoxFit.cover,
                  // Same reasoning as the pin photo grid: this tile is
                  // roughly a third of the screen width, not the
                  // original camera resolution. With a journal
                  // potentially showing dozens of these at once, this
                  // was very likely the actual cause of crashes on
                  // lower-RAM Android devices — each uncapped decode
                  // could be tens of MB in memory, and they all add up
                  // simultaneously in a grid.
                  cacheWidth: 250,
                  cacheHeight: 250,
                  loadingBuilder: (context, child, progress) =>
                      progress == null ? child! : const Center(child: LoadingSpiderBlink(size: 28)),
                  errorBuilder: (context, error, stack) => Container(
                    color: Colors.black26,
                    child: const Icon(Icons.broken_image, color: Colors.white24, size: 20),
                  ),
                ),
                // Bottom gradient + caption, Instagram-grid-style — a
                // quick reminder of what the memory was about without
                // needing to open it.
                if (pin.caption.isNotEmpty)
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(5, 10, 5, 4),
                      decoration: const BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, Colors.black87],
                        ),
                      ),
                      child: Text(
                        pin.caption,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.white),
                      ),
                    ),
                  ),
                // Owner attribution — tiny mask icon, bottom-right
                // corner, so you can tell whose memory this is at a
                // glance without opening it.
                Positioned(
                  bottom: pin.caption.isNotEmpty ? 22 : 4,
                  right: 4,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.55),
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.cyanAccent.withOpacity(0.4), width: 1),
                    ),
                    child: SpiderMaskIcon(size: 14, maskId: widget.ownerMaskId),
                  ),
                ),
                if (photoCount > 1)
                  Positioned(
                    top: 4,
                    left: 4,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withOpacity(0.6),
                        borderRadius: BorderRadius.circular(3),
                        border: Border.all(color: Colors.cyanAccent.withOpacity(0.5), width: 1),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.collections, size: 8, color: Colors.cyanAccent),
                          const SizedBox(width: 2),
                          Text(
                            '$photoCount',
                            style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.cyanAccent),
                          ),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
