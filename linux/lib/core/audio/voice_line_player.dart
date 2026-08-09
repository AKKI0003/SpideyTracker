import 'dart:collection';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ambient_sound_controller.dart';

/// Short one-shot voice lines (TTS-recorded) tied to specific app
/// events. Always respects the same mute toggle as the ambient sound
/// button — muting one mutes both, since they're both "app audio" from
/// the user's point of view even though they're separate players.
enum VoiceLine {
  appStart('audio/vo_app_start.mp3'),
  newSighting('audio/vo_new_sighting.mp3'),
  liveOn('audio/vo_live_on.mp3'),
  liveOff('audio/vo_live_off.mp3'),
  linkEstablished('audio/vo_link_established.mp3'),
  signalLost('audio/vo_signal_lost.mp3'),
  maskChange('audio/vo_mask_change.mp3'),
  pinDropped('audio/vo_pin_dropped.mp3'),
  usernameUpdated('audio/vo_username_updated.mp3');

  final String assetPath;
  const VoiceLine(this.assetPath);
}

/// A real queue instead of "stop whatever's playing and play this
/// instead." Previously every call to play() did _player.stop() first,
/// so any line fired while another was mid-playback would cut it off —
/// that's why "Got a signal" was getting overpowered by the app-start
/// line arriving a moment later. Now every requested line waits its
/// turn and always finishes.
///
/// appStart gets special treatment: it's always inserted at the FRONT
/// of the queue (ahead of anything already queued, though it still
/// waits for whatever's actively playing right now to finish — nothing
/// interrupts mid-playback, ever). In practice this is called once at
/// launch before most other triggers exist, so it will almost always
/// end up first regardless, but this guarantees it even if something
/// else queues a fraction of a second earlier.
class VoiceLinePlayer {
  final AudioPlayer _player = AudioPlayer();
  final AmbientSoundController _ambient;
  final Queue<VoiceLine> _queue = Queue<VoiceLine>();
  bool _isPlaying = false;

  VoiceLinePlayer(this._ambient) {
    _player.setReleaseMode(ReleaseMode.release);
    _player.onPlayerComplete.listen((_) => _playNext());
  }

  Future<void> play(VoiceLine line) async {
    if (line == VoiceLine.appStart) {
      _queue.addFirst(line);
    } else {
      _queue.add(line);
    }
    if (!_isPlaying) {
      await _playNext();
    }
  }

  Future<void> _playNext() async {
    if (_queue.isEmpty) {
      _isPlaying = false;
      return;
    }

    final line = _queue.removeFirst();

    // Re-check mute at actual playback time, not just at the moment it
    // was queued — a line queued while unmuted but played after the
    // user muted shouldn't sneak through, and vice versa a line queued
    // while briefly muted correctly gets skipped rather than played
    // late and out of context.
    if (_ambient.isMuted) {
      _playNext();
      return;
    }

    _isPlaying = true;
    try {
      await _player.play(AssetSource(line.assetPath));
    } catch (_) {
      // Asset not added yet — fail quietly, same convention as
      // AmbientSoundController, and move on to whatever's next rather
      // than getting stuck.
      _playNext();
    }
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

final voiceLinePlayerProvider = Provider<VoiceLinePlayer>((ref) {
  final ambient = ref.watch(ambientSoundProvider);
  final player = VoiceLinePlayer(ambient);
  ref.onDispose(() => player.dispose());
  return player;
});
