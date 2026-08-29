import 'dart:async';
import 'package:flutter_map_vector_tiles/flutter_map_vector_tiles.dart' as vt;
import 'dart:io';
import '../../settings/presentation/mask_picker_sheet.dart';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive_flutter/hive_flutter.dart';
import 'widgets/loading_spider_blink.dart';
import 'widgets/scan_lines_overlay.dart';
import 'widgets/radar_sweep.dart';
import 'widgets/grid_overlay.dart';
import 'widgets/spider_mask_icon.dart';
import '../../photo_pins/presentation/widgets/memory_pin_badge.dart';
import '../../settings/presentation/pin_customization_sheet.dart';
import '../../chat/presentation/chat_screen.dart';
import '../../../core/chat/local_chat_store.dart';
import 'widgets/live_marker.dart';
import 'widgets/sound_control_button.dart';
import '../../../core/widgets/pixel_button.dart';
import '../../../core/widgets/themed_dialog.dart';
import '../../../core/widgets/themed_snackbar.dart';
import '../../../core/audio/ambient_sound_controller.dart';
import '../../photo_pins/data/pins_repository.dart';
import '../../photo_pins/domain/pin_model.dart';
import '../../photo_pins/presentation/activity_panel.dart';
import '../../live_location/data/live_location_repository.dart';
import '../../party/data/party_repository.dart';
import 'widgets/ruler_overlay.dart';
import '../../photo_pins/presentation/mascot_activity_badge.dart';
import '../../photo_pins/presentation/photo_pin_viewer.dart';
import '../../photo_pins/presentation/journal_screen.dart';
import '../../photo_pins/presentation/add_photos_sheet.dart';
import '../../../core/audio/voice_line_player.dart';
import 'widgets/live_location_sheet.dart';
import 'widgets/pin_filter_rail.dart';
import '../../../core/utils/haptics.dart';
import 'widgets/search_location_button.dart';


/// A member's animated live-location state, tracked per-uid now that a
/// party can have up to 8 members sharing location simultaneously
/// instead of exactly one partner.
class _MemberLiveState {
  bool sharing = false;
  LatLng? displayLocation;
  Animation<double>? latAnim;
  Animation<double>? lngAnim;
  final AnimationController controller;
  // When this member's last location write actually happened (server
  // time, not device time — avoids any clock-skew weirdness). Used by
  // the staleness check in _loadParty: if too much time passes with no
  // new write, we stop trusting `sharing` even though Firestore's own
  // sharingEnabled flag is still true — see that check for why.
  DateTime? lastUpdated;

  _MemberLiveState(this.controller);
}

/// Anything that can be dropped on the map as a marker and might end up
/// sharing a spot with another marker: a photo pin or a live-sharing
/// member's mask. Both kinds are spread apart together so a pin and a
/// live mask sitting on the same spot fan out just like two pins would.
enum _MapItemKind { pin, live, self }

class _MapItem {
  final _MapItemKind kind;
  final String id;
  final LatLng location;
  final PinModel? pin; // set when kind == pin
  final bool isGwenTheme; // set when kind == live

  _MapItem.pin(this.pin)
      : kind = _MapItemKind.pin,
        id = 'pin:${_MapItem._pinId(pin)}',
        location = _MapItem._pinLoc(pin),
        isGwenTheme = false;

  _MapItem.live(String uid, this.location, this.isGwenTheme)
      : kind = _MapItemKind.live,
        id = 'live:$uid',
        pin = null;

  _MapItem.self(this.location)
      : kind = _MapItemKind.self,
        id = 'self',
        pin = null,
        isGwenTheme = false;

  static String _pinId(PinModel? p) => p!.id;
  static LatLng _pinLoc(PinModel? p) => p!.location;
}

/// A map item paired with where it should actually be drawn on screen —
/// same as its true location unless it shares a spot with another item,
/// in which case this is the fanned-out display position.
class _PositionedItem {
  final _MapItem item;
  final LatLng displayLocation;
  const _PositionedItem(this.item, this.displayLocation);
}

/// OpenFreeMap's Positron style — free forever, no key, no signup, no
/// request limits, and it's the same pale/grey cartography Carto's
/// light_all used, so switching doesn't change how the map looks.
/// Unlike the Carto key workaround, this also has no zoom-range gap
/// (Carto's light_all only serves z0–20 even with a key, so extreme
/// zoom still showed the watermark on out-of-range tiles).
const String _openFreeMapPositronStyleUrl =
    'https://tiles.openfreemap.org/styles/positron';

class MapScannerScreen extends StatefulWidget {
  final String partyId;
  final VoidCallback? onSwitchParty;

  const MapScannerScreen({super.key, required this.partyId, this.onSwitchParty});

  @override
  State<MapScannerScreen> createState() => _MapScannerScreenState();
}

class _MapScannerScreenState extends State<MapScannerScreen>
    with TickerProviderStateMixin, WidgetsBindingObserver {
  final MapController _mapController = MapController();
  final PinsRepository _pinsRepo = PinsRepository();
  final LiveLocationRepository _liveRepo = LiveLocationRepository();
  final PartyRepository _partyRepo = PartyRepository();

  LatLng? _currentPosition;
  String? _errorMessage;
  bool _isPinningMode = false;
  List<PinModel> _pins = [];

  // The map's current viewport, split into two independently-updated
  // notifiers instead of one plain state field. This is the fix for the
  // lag your friend saw: the old version called setState() on every
  // single onPositionChanged tick (which fires dozens of times per
  // second during a drag/pinch), rebuilding the ENTIRE screen — chat
  // listeners, party state, every widget — just because the map moved
  // a few pixels. On a fast device that's invisible; on a mid-range
  // phone it's exactly what "laggy" feels like.
  //
  // Now: panning only notifies [_boundsNotifier], which just feeds the
  // radar (cheap — plotting existing points against a rectangle, no
  // per-frame distance math). Zoom changes additionally notify
  // [_zoomNotifier], which is the only thing that should ever re-run
  // the marker spread/clustering pass — and pinch-zooming fires far
  // less often than plain panning does. Nothing else in the screen
  // (chat, party listeners, buttons) rebuilds because of camera
  // movement anymore.
  final ValueNotifier<LatLngBounds?> _boundsNotifier = ValueNotifier(null);
  final ValueNotifier<double> _zoomNotifier = ValueNotifier(16);

  String _partyName = '';
  Map<String, String> _memberNames = {}; // uid -> displayName, excludes self
  Map<String, String> _memberMaskIds = {}; // uid -> maskId, excludes self
  String _myMaskId = 'spiderman';
  bool _hasLoadedPinsOnce = false; // suppress the sound on the very first snapshot (existing pins, not new)
  bool _hasUnseenSighting = false; // new pin from someone else arrived, but not yet acknowledged by opening the log
  Map<String, String> _memberPinSpiderIds = {}; // uid -> pinSpiderId, excludes self
  Map<String, int> _memberPinColors = {}; // uid -> pinColorValue, excludes self
  String _myPinSpiderId = 'round_body';
  int _myPinColorValue = 0xFFFF5252; // Colors.redAccent
  List<String> _memberUids = []; // includes self, used to drive the filter rail
  final Set<String> _hiddenOwnerUids = {}; // pins from these uids are hidden from the map

  bool _isSharingLive = false;
  StreamSubscription<Position>? _positionSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _membersLocSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _pinsSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _partyDocSub;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _myUserDocSub;

  final Map<String, _MemberLiveState> _memberLive = {};
  final Set<String> _prevSharingUids = {};
  // Whether ANYONE in the party was live as of the last snapshot — the
  // link sound compares against this instead of per-person state, so
  // it plays exactly once when the party goes from nobody-live to
  // somebody-live, no matter how many people are involved.
  bool _wasAnyoneLive = false;

  // Bug fix: a member's live pin used to stay marked "live" forever
  // once their app stopped actually sending updates (backgrounded,
  // killed, lost network, etc.) — Firestore's own `sharingEnabled` flag
  // stays true since nothing ever explicitly turned it off, and since
  // nothing changed there's no new snapshot event to react to either,
  // so the UI just froze at their last position while still showing
  // the pulsing "live" indicator forever. This timer re-checks
  // freshness on its own schedule instead of waiting for a snapshot
  // that will never come, so a stalled member correctly drops out of
  // "live" after a short grace period even though no one ever tapped
  // the LIVE button off.
  Timer? _staleCheckTimer;
  static const _staleAfter = Duration(seconds: 90);

  // Loaded once and reused for every rebuild — re-fetching/parsing the
  // style.json on every build would be wasteful and would also flash
  // the map blank on each rebuild while it re-reads.
  vt.Style? _mapStyle;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _getCurrentLocation();
    _loadParty();
    _staleCheckTimer = Timer.periodic(const Duration(seconds: 20), (_) => _dropStaleMembers());
    vt.StyleReader(uri: _openFreeMapPositronStyleUrl).read().then((style) {
      if (mounted) setState(() => _mapStyle = style);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await Future.delayed(const Duration(milliseconds: 400));
      if (mounted) {
        ProviderScope.containerOf(context, listen: false)
            .read(voiceLinePlayerProvider)
            .play(VoiceLine.appStart);
      }
    });
  }

  void _dropStaleMembers() {
    if (!mounted) return;
    final now = DateTime.now();
    var changed = false;

    for (final entry in _memberLive.entries) {
      final state = entry.value;
      if (!state.sharing) continue;
      final lastUpdated = state.lastUpdated;
      if (lastUpdated != null && now.difference(lastUpdated) > _staleAfter) {
        state.sharing = false;
        state.displayLocation = null;
        _prevSharingUids.remove(entry.key);
        changed = true;
      }
    }

    if (changed) {
      final anyoneLiveNow = _prevSharingUids.isNotEmpty;
      if (anyoneLiveNow != _wasAnyoneLive) {
        _showLinkMessage(anyoneLiveNow);
        _wasAnyoneLive = anyoneLiveNow;
      }
      setState(() {});
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _staleCheckTimer?.cancel();
    _positionSub?.cancel();
    _membersLocSub?.cancel();
    _pinsSub?.cancel();
    _partyDocSub?.cancel();
    _myUserDocSub?.cancel();
    _boundsNotifier.dispose();
    _zoomNotifier.dispose();
    for (final state in _memberLive.values) {
      state.controller.dispose();
    }
    _mapStyle?.dispose();
    super.dispose();
  }

  /// Feeds both camera notifiers from a single MapCamera without ever
  /// calling setState — see the comment on the notifier fields for why
  /// that matters. Zoom is only pushed to its notifier when it's
  /// actually changed (pinch/double-tap), not on plain panning, so the
  /// relatively expensive marker-spread recompute stays rare.
  void _onCameraChanged(MapCamera camera) {
    _boundsNotifier.value = camera.visibleBounds;
    if ((_zoomNotifier.value - camera.zoom).abs() > 0.01) {
      _zoomNotifier.value = camera.zoom;
    }
  }

  /// Ambient sound should never keep playing once the app isn't visible
  /// — including when it's simply minimized/backgrounded, not just when
  /// it's closed. [inactive]/[hidden] cover the brief in-between states
  /// (e.g. the app switcher) on top of the actual [paused] background
  /// state, so sound cuts out the moment the map stops being on screen.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final container = ProviderScope.containerOf(context, listen: false);
    final ambient = container.read(ambientSoundProvider);
    final voice = container.read(voiceLinePlayerProvider);
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        ambient.pauseForBackground();
        voice.pauseForBackground();
        break;
      case AppLifecycleState.resumed:
        ambient.resumeFromBackground();
        voice.resumeFromBackground();
        break;
    }
  }

  Future<void> _loadParty() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    _myUserDocSub = FirebaseFirestore.instance
        .collection('users')
        .doc(user.uid)
        .snapshots()
        .listen((doc) {
      if (mounted) {
        setState(() {
          _myMaskId = doc.data()?['maskId'] as String? ?? 'spiderman';
          _myPinSpiderId = doc.data()?['pinSpiderId'] as String? ?? 'round_body';
          _myPinColorValue = doc.data()?['pinColorValue'] as int? ?? 0xFFFF5252;
        });
      }
    });

    _pinsSub = _pinsRepo.watchPins(widget.partyId).listen((snapshot) {
      final newPins = snapshot.docs.map((d) => PinModel.fromDoc(d)).toList();

      // Compares the actual set of pin IDs (the "activity log") against
      // what we had a moment ago, purely in memory — no
      // SharedPreferences round-trip, so there's no async gap where a
      // second snapshot could race the first. Any id that's newly
      // present and NOT owned by us is a genuinely new sighting from
      // another party member.
      final oldIds = _pins.map((p) => p.id).toSet();
      final newIds = newPins.map((p) => p.id).toSet();
      final addedIds = newIds.difference(oldIds);

      final newFromOthers = newPins.where(
        (p) => addedIds.contains(p.id) && p.ownerUid != user.uid,
      );

      // TEMP DEBUG — remove once new_sighting is confirmed working.
      // Run with `flutter run` (not release) and watch the console when
      // the other account drops a pin.
      debugPrint(
        '[newSighting] snapshot fired. myUid=${user.uid} '
        'totalPins=${newPins.length} addedIds=$addedIds '
        'newFromOthersCount=${newFromOthers.length} '
        'hasLoadedPinsOnce=$_hasLoadedPinsOnce',
      );

      // Plays the moment a genuinely new sighting from someone else
      // arrives — not gated behind opening the activity log. The
      // voice-line queue (see voice_line_player.dart) means this can
      // never cut off or get cut off by another line; it just takes
      // its turn.
      if (_hasLoadedPinsOnce && newFromOthers.isNotEmpty) {
        _hasUnseenSighting = true;
        if (mounted) {
          debugPrint('[newSighting] calling voice.play(newSighting) now');
          ProviderScope.containerOf(context, listen: false)
              .read(voiceLinePlayerProvider)
              .play(VoiceLine.newSighting);
        } else {
          debugPrint('[newSighting] SKIPPED — widget not mounted');
        }
      }
      _hasLoadedPinsOnce = true;

      if (mounted) setState(() => _pins = newPins);
    });

    _partyDocSub = FirebaseFirestore.instance
        .collection('parties')
        .doc(widget.partyId)
        .snapshots()
        .listen((doc) async {
      final data = doc.data();
      if (data == null) return;
      setState(() => _partyName = data['name'] as String? ?? '');

      final memberUids = List<String>.from(data['memberUids'] as List? ?? []);
      final otherUids = memberUids.where((id) => id != user.uid).toList();
      if (mounted) setState(() => _memberUids = memberUids);

      final names = <String, String>{};
      final maskIds = <String, String>{};
      final pinSpiderIds = <String, String>{};
      final pinColors = <String, int>{};
      for (final uid in otherUids) {
        final memberDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(uid)
            .get();
        names[uid] = memberDoc.data()?['displayName'] as String? ?? 'Member';
        maskIds[uid] = memberDoc.data()?['maskId'] as String? ?? 'spiderman';
        pinSpiderIds[uid] = memberDoc.data()?['pinSpiderId'] as String? ?? 'round_body';
        pinColors[uid] = memberDoc.data()?['pinColorValue'] as int? ?? 0xFFFF5252;
      }
      if (mounted) {
        setState(() {
          _memberNames = names;
          _memberMaskIds = maskIds;
          _memberPinSpiderIds = pinSpiderIds;
          _memberPinColors = pinColors;
        });
      }
    });

    _membersLocSub =
        _liveRepo.watchAllLocations(widget.partyId).listen((snapshot) {
      final seenUids = <String>{};

      for (final doc in snapshot.docs) {
        final uid = doc.id;
        if (uid == user.uid) continue; // never render our own live pin twice
        seenUids.add(uid);

        final data = doc.data();
        final isSharing = data['sharingEnabled'] == true &&
            data['lat'] != null &&
            data['lng'] != null;

        final state = _memberLive.putIfAbsent(
          uid,
          () => _MemberLiveState(
            AnimationController(
              vsync: this,
              duration: const Duration(milliseconds: 1200),
            ),
          ),
        );

        if (isSharing) {
          final loc = LatLng(
            (data['lat'] as num).toDouble(),
            (data['lng'] as num).toDouble(),
          );
          _animateMemberTo(uid, state, loc);
        }

        // `lastUpdated` can briefly be null right after a write, before
        // the server timestamp round-trips back — treat that as "just
        // happened" rather than "unknown/stale" so a person doesn't
        // flicker to not-live for a moment every time they move.
        final serverTime = (data['lastUpdated'] as Timestamp?)?.toDate();
        state.lastUpdated = serverTime ?? DateTime.now();

        if (isSharing) {
          _prevSharingUids.add(uid);
        } else {
          _prevSharingUids.remove(uid);
        }

        state.sharing = isSharing;
        if (!isSharing) state.displayLocation = null;
      }

      // Members who stopped sharing entirely (doc removed / not in query
      // results) should drop off the map too.
      _memberLive.removeWhere((uid, _) => !seenUids.contains(uid));

      // Fires at most once per snapshot, based on whether ANYONE is
      // live overall — not once per person. It used to fire per-uid, so
      // with several members it could play multiple times back to back
      // for a single snapshot, and kept re-firing any time one person
      // toggled while others were already live.
      final anyoneLiveNow = _prevSharingUids.isNotEmpty;
      if (anyoneLiveNow != _wasAnyoneLive) {
        _showLinkMessage(anyoneLiveNow);
        _wasAnyoneLive = anyoneLiveNow;
      }

      if (mounted) setState(() {});
    });
  }

  void _showLinkMessage(bool connected) {
    if (!mounted) return;
    final voice = ProviderScope.containerOf(context, listen: false).read(voiceLinePlayerProvider);
    voice.play(connected ? VoiceLine.linkEstablished : VoiceLine.signalLost);
  }

  void _animateMemberTo(String uid, _MemberLiveState state, LatLng newLoc) {
    final start = state.displayLocation ?? newLoc;
    state.latAnim = Tween<double>(begin: start.latitude, end: newLoc.latitude)
        .animate(state.controller);
    state.lngAnim =
        Tween<double>(begin: start.longitude, end: newLoc.longitude)
            .animate(state.controller);
    state.controller
      ..removeListener(() => _onMemberTick(uid, state))
      ..addListener(() => _onMemberTick(uid, state))
      ..forward(from: 0);
  }

  void _onMemberTick(String uid, _MemberLiveState state) {
    if (state.latAnim == null || state.lngAnim == null) return;
    if (!mounted) return;
    setState(() {
      state.displayLocation =
          LatLng(state.latAnim!.value, state.lngAnim!.value);
    });
  }

  Future<void> _getCurrentLocation() async {
    try {
      final permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        final requested = await Geolocator.requestPermission();
        if (requested == LocationPermission.denied ||
            requested == LocationPermission.deniedForever) {
          setState(() => _errorMessage = 'Location permission denied.');
          return;
        }
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _errorMessage = 'Location services are off.');
        return;
      }

      final position = await Geolocator.getCurrentPosition();
      setState(() {
        _currentPosition = LatLng(position.latitude, position.longitude);
      });
    } catch (e) {
      setState(() => _errorMessage = 'Error getting location: $e');
    }
  }

  void _recenter() {
    if (_currentPosition != null) {
      _mapController.move(_currentPosition!, 16);
    }
  }

  /// Opens the activity log. The new_sighting voice line now plays the
  /// moment a sighting actually arrives (see the pins listener above),
  /// so this just clears the "unseen" flag rather than re-triggering
  /// the sound — avoids playing it twice for the same event.
  void _openActivityLog(BuildContext context, String? currentUid) {
    _hasUnseenSighting = false;

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (sheetContext) => ActivityLogSheet(
        pins: _pins,
        currentUid: currentUid,
        memberNames: _memberNames,
        partyId: widget.partyId,
        onPinSelected: (location) {
          Navigator.pop(sheetContext);
          _mapController.move(location, 17);
        },
      ),
    );
  }

  /// Rough meters-per-pixel at a given zoom/latitude for the standard
  /// web-mercator tile scheme, used to convert a "keep these N pixels
  /// apart on screen" goal into a real lat/lng offset that still holds
  /// up after zooming.
  double _metersPerPixel(double latitude, double zoom) {
    return 156543.03392 * cos(latitude * pi / 180) / pow(2, zoom);
  }

  /// Plain-Dart great-circle distance in meters — used instead of
  /// Geolocator.distanceBetween here so this clustering pass never has
  /// to cross a platform channel. It only runs on zoom changes now (see
  /// _spreadOverlappingItems), but there's no reason to pay for a
  /// native round-trip for basic Pythagorean-ish math either.
  double _haversineMeters(double lat1, double lng1, double lat2, double lng2) {
    const earthRadius = 6371000.0;
    final dLat = (lat2 - lat1) * pi / 180;
    final dLng = (lng2 - lng1) * pi / 180;
    final a = sin(dLat / 2) * sin(dLat / 2) +
        cos(lat1 * pi / 180) * cos(lat2 * pi / 180) * sin(dLng / 2) * sin(dLng / 2);
    final c = 2 * atan2(sqrt(a), sqrt(1 - a));
    return earthRadius * c;
  }

  /// Pins/live masks dropped at (or very near) the same spot used to
  /// render as one Marker stacked exactly on top of another, so only the
  /// topmost was ever tappable — and because the old fan-out used a
  /// fixed 6m offset, zooming out far enough still squashed them back
  /// into a single pixel. This clusters items that are close together
  /// **on screen at the current zoom** (not just exact-same coordinate)
  /// and nudges each one apart by a fixed ~16px radius recomputed for
  /// the current zoom, so overlapping items fan out side by side and
  /// stay visibly separate no matter how far out the map is. Only the
  /// on-screen marker position changes — the stored pin location is
  /// untouched.
  ///
  /// Only ever invoked when the zoom level changes (see the
  /// ValueListenableBuilder around the MarkerLayer) — not on every pan
  /// tick — so this being O(n²) is fine given how few items a party
  /// realistically has.
  List<_PositionedItem> _spreadOverlappingItems(
    List<_MapItem> items,
    double zoom,
  ) {
    if (items.isEmpty) return const [];

    const clusterPixels = 90.0;
    const spreadPixels = 14.0;

    final n = items.length;
    final parent = List<int>.generate(n, (i) => i);
    int find(int x) => parent[x] == x ? x : parent[x] = find(parent[x]);
    void union(int a, int b) {
      final ra = find(a), rb = find(b);
      if (ra != rb) parent[ra] = rb;
    }

    for (int i = 0; i < n; i++) {
      final mpp = _metersPerPixel(items[i].location.latitude, zoom);
      final clusterThresholdMeters = clusterPixels * mpp;
      for (int j = i + 1; j < n; j++) {
        final distance = _haversineMeters(
          items[i].location.latitude,
          items[i].location.longitude,
          items[j].location.latitude,
          items[j].location.longitude,
        );
        if (distance < clusterThresholdMeters) union(i, j);
      }
    }

    final groups = <int, List<int>>{};
    for (int i = 0; i < n; i++) {
      groups.putIfAbsent(find(i), () => []).add(i);
    }

    final result = <_PositionedItem>[];
    for (final idxs in groups.values) {
      if (idxs.length == 1) {
        final item = items[idxs.first];
        result.add(_PositionedItem(item, item.location));
        continue;
      }

      double latSum = 0, lngSum = 0;
      for (final i in idxs) {
        latSum += items[i].location.latitude;
        lngSum += items[i].location.longitude;
      }
      final centroidLat = latSum / idxs.length;
      final centroidLng = lngSum / idxs.length;
      final radiusMeters = spreadPixels * _metersPerPixel(centroidLat, zoom);

      for (int k = 0; k < idxs.length; k++) {
        final angle = (2 * pi / idxs.length) * k;
        final lat = centroidLat + (radiusMeters / 111320) * sin(angle);
        final lng = centroidLng +
            (radiusMeters / (111320 * cos(centroidLat * pi / 180))) *
                cos(angle);
        result.add(_PositionedItem(items[idxs[k]], LatLng(lat, lng)));
      }
    }
    return result;
  }

  Future<void> _toggleLiveSharing() async {
    final user = FirebaseAuth.instance.currentUser!;

    if (_isSharingLive) {
      await _positionSub?.cancel();
      _positionSub = null;
      await _liveRepo.disableSharing(partyId: widget.partyId, uid: user.uid);
      setState(() => _isSharingLive = false);
      if (mounted) {
        ProviderScope.containerOf(context, listen: false)
            .read(voiceLinePlayerProvider)
            .play(VoiceLine.liveOff);
      }
    } else {
      // "Live" is supposed to mean live until YOU turn it off — not
      // "live until you switch apps." That requires location updates
      // to keep flowing while backgrounded, which needs the OS's
      // "Always" location permission rather than just "While Using the
      // App" (the latter is paused by the OS the moment the app isn't
      // in the foreground, which is exactly what caused the stuck-pin
      // bug). This upgrades the request; if the person only grants
      // While-Using anyway, sharing still works fine in the
      // foreground/briefly backgrounded — it just won't survive being
      // backgrounded for long or the app being force-closed, and the
      // staleness check in _dropStaleMembers() makes sure viewers see
      // that honestly instead of a pin frozen in place forever.
      final current = await Geolocator.checkPermission();
      if (current == LocationPermission.whileInUse) {
        await Geolocator.requestPermission(); // re-prompts asking to upgrade to Always, on platforms that support it
      }

      setState(() => _isSharingLive = true);
      if (mounted) {
        ProviderScope.containerOf(context, listen: false)
            .read(voiceLinePlayerProvider)
            .play(VoiceLine.liveOn);
      }
      _positionSub = Geolocator.getPositionStream(
        locationSettings: Platform.isIOS
            ? AppleSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 10,
                activityType: ActivityType.other,
                // Without these two, iOS pauses updates automatically
                // once it decides the phone doesn't seem to be moving
                // and/or the app goes to the background — which is
                // exactly how the pin ended up stuck at the last known
                // spot while still showing as "live" upstream.
                pauseLocationUpdatesAutomatically: false,
                allowBackgroundLocationUpdates: true,
                // Required by Apple whenever an app uses location in
                // the background — shows the blue "app is using your
                // location" bar. This is expected, standard UX for any
                // legitimate background-location app, not a bug.
                showBackgroundLocationIndicator: true,
              )
            : AndroidSettings(
                accuracy: LocationAccuracy.high,
                distanceFilter: 10,
                intervalDuration: const Duration(seconds: 10),
                // Modern Android requires a visible foreground-service
                // notification for any app that keeps requesting
                // location updates while backgrounded — without one,
                // the OS suspends location callbacks within
                // seconds-to-minutes of the app leaving the
                // foreground, which is the other half of why this was
                // getting stuck. See the note in this repo's
                // README/AndroidManifest about the extra permissions
                // this needs declared there.
                foregroundNotificationConfig: const ForegroundNotificationConfig(
                  notificationTitle: 'SpideyTracker',
                  notificationText: 'Sharing your live location with your party',
                  enableWakeLock: true,
                ),
              ),
      ).listen((pos) {
        _liveRepo.updateLocation(
          partyId: widget.partyId,
          uid: user.uid,
          lat: pos.latitude,
          lng: pos.longitude,
          heading: pos.heading,
          speed: pos.speed,
        );
      });
    }
  }

  Future<void> _handleMapTap(LatLng point) async {
    if (!_isPinningMode) return;

    final caption = await showThemedTextInputDialog(
      context,
      title: 'NEW PIN',
      hint: 'Add a caption...',
      confirmLabel: 'SAVE',
    );

    if (caption == null || caption.isEmpty) return;

    final pinId = await _pinsRepo.createPin(
      partyId: widget.partyId,
      location: point,
      caption: caption,
    );

    Haptics.success();

    if (mounted) {
      ProviderScope.containerOf(context, listen: false)
          .read(voiceLinePlayerProvider)
          .play(VoiceLine.pinDropped);
    }

    setState(() => _isPinningMode = false);

    // Photos are optional and uploaded after the pin doc exists (the B2
    // presign endpoint needs a real pinId to build each photo's object
    // key) — this sheet lets the user skip straight away with no photos.
    if (mounted) {
      await showAddPhotosSheet(
        context,
        partyId: widget.partyId,
        pinId: pinId,
      );
    }
  }


  void _showSettingsSheet(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser!;
    showModalBottomSheet(
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
          children: [
            Text('SETTINGS',
                style: GoogleFonts.pressStart2p(fontSize: 12, color: Colors.cyanAccent)),
            const SizedBox(height: 20),
            ListTile(
              leading: const Icon(Icons.face_retouching_natural, color: Colors.cyanAccent),
              title: Text('CHANGE MASK',
                  style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.cyanAccent)),
              onTap: () {
                Navigator.pop(context);
                showMaskPickerSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.bug_report, color: Colors.cyanAccent),
              title: Text('CUSTOMIZE PIN',
                  style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.cyanAccent)),
              onTap: () {
                Navigator.pop(context);
                showPinCustomizationSheet(context);
              },
            ),
            ListTile(
              leading: const Icon(Icons.edit, color: Colors.cyanAccent),
              title: Text('CHANGE USERNAME',
                  style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.cyanAccent)),
              onTap: () async {
                Navigator.pop(context);
                final newName = await showThemedTextInputDialog(
                  context,
                  title: 'NEW CODENAME',
                  hint: 'Enter username',
                );
                if (newName != null && newName.isNotEmpty) {
                  await FirebaseFirestore.instance.collection('users').doc(user.uid).update({
                    'displayName': newName,
                  });
                  if (context.mounted) {
                    ProviderScope.containerOf(context, listen: false)
                        .read(voiceLinePlayerProvider)
                        .play(VoiceLine.usernameUpdated);
                  }
                }
              },
            ),
            ListTile(
              leading: const Icon(Icons.group, color: Colors.cyanAccent),
              title: Text('SWITCH PARTY',
                  style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.cyanAccent)),
              onTap: () {
                Navigator.pop(context);
                widget.onSwitchParty?.call();
              },
            ),
            ListTile(
              leading: const Icon(Icons.exit_to_app, color: Colors.redAccent),
              title: Text('LEAVE THIS PARTY',
                  style: GoogleFonts.pressStart2p(fontSize: 9, color: Colors.redAccent)),
              onTap: () async {
                Navigator.pop(context);
                final confirmed = await showThemedConfirmDialog(
                  context,
                  title: 'LEAVE PARTY?',
                  message:
                      "You'll lose access to this party's pins, chat, and live locations unless you rejoin with an invite code.",
                  confirmLabel: 'LEAVE',
                );
                if (confirmed) {
                  await _partyRepo.leaveParty(uid: user.uid, partyId: widget.partyId);
                }
              },
            ),
            const SizedBox(height: 18),
            Text(
              'SPIDEYTRACKER — MADE BY AAKARSHAN',
              textAlign: TextAlign.center,
              style: GoogleFonts.pressStart2p(fontSize: 6, color: Colors.white24),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    final sharingMembers =
        _memberLive.entries.where((e) => e.value.sharing).toList();

    return Scaffold(
      backgroundColor: const Color(0xFF0A1128),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        title: _partyName.isEmpty
            ? null
            : Text(
                _partyName.toUpperCase(),
                style: GoogleFonts.pressStart2p(fontSize: 10, color: Colors.white70),
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings, color: Colors.cyanAccent),
            onPressed: () => _showSettingsSheet(context),
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.cyanAccent),
            onPressed: () => FirebaseAuth.instance.signOut(),
          ),
        ],
      ),
      body: TickerMode(
        // Every AnimationController on this screen (radar sweep, cobweb
        // thread, scan lines, live-marker pulse rings, mascot bob/blink,
        // sound button waveform) stops ticking the instant this screen
        // is no longer the topmost route — e.g. while Chat or Journal is
        // pushed on top of it — instead of continuing to repaint every
        // frame underneath a screen you can't even see. That competing,
        // invisible work was very likely the real source of the
        // "laggy switching" feeling, separate from the white-flash fix.
        enabled: ModalRoute.of(context)?.isCurrent ?? true,
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const SpiderMaskIcon(size: 28),
                    const SizedBox(width: 10),
                    Text(
                      'SPIDEYTRACKER',
                      style: GoogleFonts.pressStart2p(
                        fontSize: 14,
                        color: Colors.cyanAccent,
                      ),
                    ),
                  ],
                ),
              ),
              if (_isPinningMode)
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: Colors.redAccent.withOpacity(0.2),
                    border: Border.all(color: Colors.redAccent),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'TAP THE MAP TO DROP A PIN',
                    textAlign: TextAlign.center,
                    style: GoogleFonts.pressStart2p(
                      fontSize: 9,
                      color: Colors.redAccent,
                    ),
                  ),
                ),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border.all(color: Colors.blueAccent, width: 4),
                    borderRadius: BorderRadius.circular(12),
                    color: Colors.black,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.blueAccent.withOpacity(0.5),
                        blurRadius: 20,
                        spreadRadius: 2,
                      ),
                    ],
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: Stack(
                    children: [
                      if (_errorMessage != null)
                        Center(
                          child: Text(
                            _errorMessage!,
                            style: const TextStyle(color: Colors.white),
                          ),
                        )
                      else if (_currentPosition == null)
                        const Center(
                          child: LoadingSpiderBlink(size: 72),
                        )
                      else
                        FlutterMap(
                          mapController: _mapController,
                          options: MapOptions(
                            initialCenter: _currentPosition!,
                            initialZoom: 16,
                            // OpenFreeMap's Positron tiles only exist up to
                            // z14 natively (they're over-zoomed by the
                            // client past that) and the vector decoder
                            // starts struggling with the flood of tile
                            // requests a fast pinch fires once you're near
                            // the edges of that range — that's what was
                            // showing up as shaking/duplicated pins and,
                            // on a slower phone, an outright crash.
                            // Clamping the range keeps every zoom level
                            // inside what the source and decoder can
                            // actually keep up with.
                            minZoom: 3,
                            maxZoom: 19,
                            onTap: (tapPosition, point) =>
                                _handleMapTap(point),
                            onMapReady: () {
                              _onCameraChanged(_mapController.camera);
                            },
                            onPositionChanged: (camera, hasGesture) {
                              _onCameraChanged(camera);
                            },
                          ),
                          children: [
                            if (_mapStyle == null)
                              Container(color: const Color(0xFFE8E8E8)),
                            if (_mapStyle != null)
                              vt.VectorTileLayer(
                                theme: _mapStyle!.theme,
                                tileProviders: _mapStyle!.providers,
                                sprites: _mapStyle!.sprites,
                                // Fewer tiles being decoded in parallel
                                // during a fast zoom burst is the actual
                                // fix for the crash/shake — the isolate
                                // pool was getting flooded on rapid
                                // pinch gestures. Small memory + disk
                                // caches mean a tile that was already
                                // decoded once (e.g. zooming back out to
                                // where you just were) doesn't have to
                                // be redecoded, which is most of what
                                // made zoom feel laggy in the first
                                // place. tileFadeDuration is the actual
                                // "smooth zoom" — new tiles cross-fade in
                                // instead of popping, and the old tile
                                // keeps rendering underneath until the
                                // new one's ready instead of flashing a
                                // gap (which is what read as "duplicate
                                // pins" — markers over a half-drawn tile
                                // grid mid-swap).
                                concurrency: 2,
                                memoryCacheMaxBytes: 16 * 1024 * 1024,
                                diskCacheMaximumSizeInBytes: 30 * 1024 * 1024,
                                diskCacheTtl: const Duration(days: 14),
                                tileFadeDuration:
                                    const Duration(milliseconds: 200),
                              ),
                            IgnorePointer(
                              child: Container(
                                color: const Color(0xFF1B3A8F).withOpacity(0.735),
                              ),
                            ),
                            // Self, live-sharing members, and photo pins
                            // are all spread together — the self marker
                            // used to be drawn as its own fixed Marker
                            // outside this group, so it could sit
                            // exactly on top of a pin or a live mask and
                            // hide it. Folding self into the same
                            // fan-out means it always separates from
                            // anything sharing its spot, at any zoom
                            // level.
                            //
                            // The whole marker layer is rebuilt only
                            // when zoom actually changes (via
                            // _zoomNotifier), not on every pan tick —
                            // panning used to re-run this whole O(n²)
                            // spread/clustering pass dozens of times a
                            // second, which is what made the app feel
                            // laggy on slower devices.
                            ValueListenableBuilder<double>(
                              valueListenable: _zoomNotifier,
                              builder: (context, zoom, _) {
                                return MarkerLayer(
                                  markers: _spreadOverlappingItems(
                                    [
                                      _MapItem.self(_currentPosition!),
                                      for (final entry in sharingMembers)
                                        if (entry.value.displayLocation != null)
                                          _MapItem.live(
                                            entry.key,
                                            entry.value.displayLocation!,
                                            true,
                                          ),
                                      for (final pin in _pins)
                                        if (!_hiddenOwnerUids.contains(pin.ownerUid)) _MapItem.pin(pin),
                                    ],
                                    zoom,
                                  ).map((entry) {
                                    final item = entry.item;
                                    if (item.kind == _MapItemKind.self) {
                                      return Marker(
                                        point: entry.displayLocation,
                                        width: _isSharingLive ? 90 : 60,
                                        height: _isSharingLive ? 100 : 70,
                                        child: GestureDetector(
                                          onTap: () => showLiveLocationSheet(
                                            context,
                                            label: 'You',
                                            location: entry.displayLocation,
                                          ),
                                          child: _isSharingLive
                                              ? RepaintBoundary(
                                                  child: LiveMarker(
                                                    size: 36,
                                                    maskId: _myMaskId,
                                                    label: 'You',
                                                  ),
                                                )
                                              : Column(
                                                  mainAxisSize: MainAxisSize.min,
                                                  children: [
                                                    SpiderMaskIcon(
                                                      size: 36,
                                                      maskId: _myMaskId,
                                                    ),
                                                    Container(
                                                      margin: const EdgeInsets.only(top: 2),
                                                      padding: const EdgeInsets.symmetric(
                                                          horizontal: 4, vertical: 1),
                                                      decoration: BoxDecoration(
                                                        color: Colors.black.withOpacity(0.65),
                                                        borderRadius: BorderRadius.circular(3),
                                                      ),
                                                      child: Text(
                                                        'You',
                                                        style: GoogleFonts.pressStart2p(
                                                            fontSize: 6, color: Colors.white),
                                                      ),
                                                    ),
                                                  ],
                                                ),
                                        ),
                                      );
                                    }
                                    if (item.kind == _MapItemKind.live) {
                                      final memberUid = item.id.replaceFirst('live:', '');
                                      return Marker(
                                        point: entry.displayLocation,
                                        width: 90,
                                        height: 100,
                                        child: GestureDetector(
                                          onTap: () => showLiveLocationSheet(
                                            context,
                                            label: _memberNames[memberUid] ?? 'Member',
                                            location: entry.displayLocation,
                                          ),
                                          child: RepaintBoundary(
                                            child: LiveMarker(
                                              size: 36,
                                              maskId: _memberMaskIds[memberUid],
                                              label: _memberNames[memberUid],
                                            ),
                                          ),
                                        ),
                                      );
                                    }
                                    final pin = item.pin!;
                                    final isMine = pin.ownerUid == user?.uid;
                                    final ownerLabel = isMine ? 'You' : (_memberNames[pin.ownerUid] ?? 'Member');
                                    return Marker(
                                      point: entry.displayLocation,
                                      width: 56,
                                      height: 68,
                                      child: GestureDetector(
                                        onTap: () {
                                          showPhotoPinViewer(
                                            context,
                                            pin: pin,
                                            partyId: widget.partyId,
                                            isMine: isMine,
                                            ownerLabel: isMine
                                                ? 'You'
                                                : (_memberNames[pin.ownerUid] ?? 'Member'),
                                            maskId: isMine
                                                ? _myMaskId
                                                : _memberMaskIds[pin.ownerUid],
                                            resolveUploaderName: (uid) => uid == user?.uid
                                                ? 'You'
                                                : (_memberNames[uid] ?? 'Member'),
                                            onPhotosChanged: () {}, // pins stream already keeps _pins fresh
                                          );
                                        },
                                        child: Column(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            // Static pins now render as a
                                            // colored pixel badge instead
                                            // of the live-location mask,
                                            // so a saved memory never
                                            // looks like "this person is
                                            // here right now."
                                            MemoryPinBadge(
                                              size: 42,
                                              spiderIconId: isMine
                                                  ? _myPinSpiderId
                                                  : (_memberPinSpiderIds[pin.ownerUid] ?? 'round_body'),
                                              backgroundColor: Color(
                                                isMine
                                                    ? _myPinColorValue
                                                    : (_memberPinColors[pin.ownerUid] ?? 0xFFFF5252),
                                              ),
                                            ),
                                            Container(
                                              margin: const EdgeInsets.only(top: 2),
                                              padding: const EdgeInsets.symmetric(
                                                  horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.black.withOpacity(0.65),
                                                borderRadius: BorderRadius.circular(3),
                                              ),
                                              child: Text(
                                                ownerLabel,
                                                style: GoogleFonts.pressStart2p(
                                                    fontSize: 6, color: Colors.white),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                );
                              },
                            ),
                          ],
                        ),

                      const GridOverlay(),
                      const ScanLinesOverlay(),
                      const RulerOverlay(),

                      Positioned(
                        bottom: 12,
                        right: 12,
                        // Only the radar rebuilds on every pan tick now
                        // (via _boundsNotifier) — it's cheap, just
                        // plotting existing points against a rectangle,
                        // no distance math involved. The rest of the
                        // screen no longer rebuilds at all when the map
                        // moves.
                        child: ValueListenableBuilder<LatLngBounds?>(
                          valueListenable: _boundsNotifier,
                          builder: (context, bounds, _) {
                            return RepaintBoundary(
                              child: RadarSweep(
                                size: 112,
                                visibleBounds: bounds,
                                points: [
                                  if (_currentPosition != null)
                                    RadarPoint(
                                      id: 'self',
                                      location: _currentPosition!,
                                      isSelf: true,
                                    ),
                                  for (final entry in sharingMembers)
                                    if (entry.value.displayLocation != null)
                                      RadarPoint(
                                        id: entry.key,
                                        location: entry.value.displayLocation!,
                                      ),
                                  for (final pin in _pins)
                                    RadarPoint(id: pin.id, location: pin.location),
                                ],
                                onRecenter: _recenter,
                              ),
                            );
                          },
                        ),
                      ),

                      // Recenter moved onto the radar itself (tap it).
                      // This slot is now the ambient sound control —
                      // nudged left of its old spot to leave the corner
                      // clear for the cobweb filter toggle.
                      const Positioned(
                        top: 12,
                        right: 78,
                        child: RepaintBoundary(child: SoundControlButton()),
                      ),

                      // Search icon — sits just left of the sound
                      // control, same visual weight, only ever expands
                      // into a field when tapped (never a permanent
                      // bar sitting on top of the map's own labels).
                      Positioned(
                        top: 12,
                        right: 140,
                        child: SearchLocationButton(
                          onLocationFound: (location, label) {
                            _mapController.move(location, 15);
                            Haptics.confirm();
                            if (mounted) {
                              showThemedSnack(context, label.toUpperCase(), tone: SnackTone.info);
                            }
                          },
                        ),
                      ),

                      if (sharingMembers.isNotEmpty)
                        Positioned(
                          top: 12,
                          left: 12,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 6),
                            decoration: BoxDecoration(
                              color: Colors.black.withOpacity(0.6),
                              border: Border.all(
                                color: Colors.greenAccent,
                                width: 1.5,
                              ),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.sensors,
                                    size: 12, color: Colors.greenAccent),
                                const SizedBox(width: 4),
                                Text(
                                  sharingMembers.length == 1
                                      ? '${(_memberNames[sharingMembers.first.key] ?? "MEMBER").toUpperCase()} LIVE'
                                      : '${sharingMembers.length} MEMBERS LIVE',
                                  style: GoogleFonts.pressStart2p(
                                    fontSize: 6,
                                    color: Colors.greenAccent,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                      Positioned(
                        bottom: 4,
                        left: 4,
                        child: RepaintBoundary(
                          child: MascotActivityBadge(
                            count: _pins.length,
                            onTap: () => _openActivityLog(context, user?.uid),
                          ),
                        ),
                      ),

                      if (_memberUids.isNotEmpty)
                        Positioned(
                          right: 0,
                          top: 0,
                          child: PinFilterRail(
                            memberUids: _memberUids,
                            myUid: user?.uid ?? '',
                            memberNames: _memberNames,
                            memberSpiderIds: _memberPinSpiderIds,
                            memberColors: _memberPinColors,
                            mySpiderId: _myPinSpiderId,
                            myColorValue: _myPinColorValue,
                            hiddenUids: _hiddenOwnerUids,
                            onToggle: (uid) {
                              setState(() {
                                if (_hiddenOwnerUids.contains(uid)) {
                                  _hiddenOwnerUids.remove(uid);
                                } else {
                                  _hiddenOwnerUids.add(uid);
                                }
                              });
                            },
                          ),
                        ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  PixelButton(
                    label: 'PIN',
                    color: _isPinningMode
                        ? Colors.redAccent
                        : const Color(0xFFFFC94A),
                    onTap: () {
                      Haptics.tap();
                      setState(() => _isPinningMode = !_isPinningMode);
                    },
                  ),
                  PixelButton(
                    label: _isSharingLive ? 'LIVE ON' : 'LIVE',
                    color: _isSharingLive
                        ? Colors.greenAccent
                        : const Color(0xFFFFC94A),
                    onTap: _toggleLiveSharing,
                  ),
                  ValueListenableBuilder(
                    valueListenable: Hive.box<String>('chat_history').listenable(),
                    builder: (context, _, __) {
                      final unread = LocalChatStore.hasUnread(widget.partyId, user?.uid ?? '');
                      return Stack(
                        clipBehavior: Clip.none,
                        children: [
                          PixelButton(
                            label: 'CHAT',
                            onTap: () => Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => ChatScreen(partyId: widget.partyId)),
                            ),
                          ),
                          if (unread)
                            Positioned(
                              top: -4,
                              right: -4,
                              child: Container(
                                width: 12,
                                height: 12,
                                decoration: const BoxDecoration(shape: BoxShape.circle, color: Colors.redAccent),
                              ),
                            ),
                        ],
                      );
                    },
                  ),
                  PixelButton(
                    label: 'JOURNAL',
                    onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(builder: (_) => JournalScreen(partyId: widget.partyId)),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'made by aakarshan',
                style: GoogleFonts.pressStart2p(
                  fontSize: 5,
                  color: Colors.white.withOpacity(0.12),
                ),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
        ),
      ),
    );
  }
}