import 'dart:async';
import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'ambient_sound_controller.dart';

/// Short one-shot voice lines (TTS-recorded) tied to specific app
/// events. Always respects the same mute toggle as the ambient sound
/// button, and never plays while the app is backgrounded — both flags
/// are checked at actual playback time (inside _playNext), not just at
/// the moment a line was requested, so a line queued right as the app
/// got minimized still gets silenced correctly.
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
/// instead." Calling _player.stop() before every play() — which is
/// what this regressed back to — means any line fired while another is
/// mid-playback cuts it off immediately. Every requested line now waits
/// its turn and always finishes start-to-end; nothing interrupts
/// anything, ever.
///
/// appStart is inserted at the FRONT of the queue (ahead of anything
/// already queued) so it's very likely to end up first even under
/// unlucky timing — but it still waits for whatever's actively playing
/// right now to finish, since nothing preempts mid-playback.
///
/// Within that, lines are also grouped into priority tiers so a direct
/// user action (tapping LIVE, dropping a pin, changing your mask) can't
/// get stuck behind a backlog of passive/ambient notifications (e.g.
/// several "X is now live" lines queued back to back right when the
/// screen opens because multiple party members are already sharing).
/// A higher-priority line inserted while lower-priority ones are still
/// waiting jumps ahead of them — but NOT ahead of anything with equal
/// or higher priority already queued, so ordering among peers (and the
/// "everything eventually plays, nothing is dropped" guarantee) is
/// unchanged. This only affects where a new line lands among items
/// that haven't started playing yet; whatever's currently playing is
/// never touched.
int _priorityOf(VoiceLine line) {
  switch (line) {
    case VoiceLine.appStart:
      return 0; // always first, see play() below
    case VoiceLine.liveOn:
    case VoiceLine.liveOff:
    case VoiceLine.pinDropped:
    case VoiceLine.maskChange:
    case VoiceLine.usernameUpdated:
      return 1; // direct user actions — should feel responsive
    case VoiceLine.linkEstablished:
    case VoiceLine.signalLost:
    case VoiceLine.newSighting:
      return 2; // passive/ambient notifications
  }
}

class VoiceLinePlayer {
  final AudioPlayer _player = AudioPlayer();
  final AmbientSoundController _ambient;
  final List<VoiceLine> _queue = [];
  bool _isPlaying = false;
  bool _foreground = true;
  Timer? _safetyTimer;
  int _playToken = 0;

  VoiceLinePlayer(this._ambient) {
    _player.setReleaseMode(ReleaseMode.release);
    _player.onPlayerComplete.listen((_) => _advance());
  }

  /// Called from the app's lifecycle observer whenever it backgrounds.
  /// Stops whatever's currently playing and blocks new lines from
  /// starting until [resumeFromBackground] — but does NOT clear the
  /// queue, so anything queued while backgrounded still plays, in
  /// order, once the app comes back to the foreground.
  void pauseForBackground() {
    _foreground = false;
    _safetyTimer?.cancel();
    _player.stop();
    _isPlaying = false;
  }

  void resumeFromBackground() {
    _foreground = true;
    if (!_isPlaying && _queue.isNotEmpty) {
      _playNext();
    }
  }

  Future<void> play(VoiceLine line) async {
    debugPrint('[VoiceLinePlayer] play($line) called, queue before=$_queue, isPlaying=$_isPlaying');

    if (line == VoiceLine.appStart) {
      _queue.insert(0, line);
    } else {
      final priority = _priorityOf(line);
      int insertIndex = _queue.length;
      for (int i = 0; i < _queue.length; i++) {
        if (_priorityOf(_queue[i]) > priority) {
          insertIndex = i;
          break;
        }
      }
      _queue.insert(insertIndex, line);
    }

    if (!_isPlaying && _foreground) {
      await _playNext();
    }
  }

  /// Called by onPlayerComplete AND by the safety timer below — guarded
  /// by [_playToken] so if both somehow fire for the same line, it only
  /// advances the queue once, not twice.
  void _advance() {
    _safetyTimer?.cancel();
    _playNext();
  }

  Future<void> _playNext() async {
    _safetyTimer?.cancel();

    if (!_foreground) {
      // Leave whatever's left in the queue for resumeFromBackground to
      // pick up — don't drop it, and don't mark _isPlaying true for a
      // line that isn't actually going to play right now.
      _isPlaying = false;
      return;
    }

    if (_queue.isEmpty) {
      _isPlaying = false;
      return;
    }

    final line = _queue.removeAt(0);

    if (_ambient.isMuted) {
      debugPrint('[VoiceLinePlayer] $line skipped — ambient is muted');
      _playNext();
      return;
    }

    _isPlaying = true;
    final myToken = ++_playToken;

    try {
      debugPrint('[VoiceLinePlayer] actually playing ${line.assetPath}');
      await _player.play(AssetSource(line.assetPath));

      // Safety net only — 30s is deliberately generous so it never
      // fires for a real (short) voice line and cuts it off itself;
      // it exists purely so a missed onPlayerComplete event can't
      // permanently jam the queue forever.
      _safetyTimer = Timer(const Duration(seconds: 30), () {
        if (myToken == _playToken && _isPlaying) {
          debugPrint('[VoiceLinePlayer] onPlayerComplete never fired for $line — forcing queue forward');
          _advance();
        }
      });
    } catch (e) {
      debugPrint('[VoiceLinePlayer] FAILED to play ${line.assetPath}: $e');
      _playNext();
    }
  }

  Future<void> dispose() async {
    _safetyTimer?.cancel();
    await _player.dispose();
  }
}

final voiceLinePlayerProvider = Provider<VoiceLinePlayer>((ref) {
  final ambient = ref.watch(ambientSoundProvider);
  final player = VoiceLinePlayer(ambient);
  ref.onDispose(() => player.dispose());
  return player;
});