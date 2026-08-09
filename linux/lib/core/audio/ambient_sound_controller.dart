import 'package:audioplayers/audioplayers.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// Feature 10 - Sound System.
///
/// Plays a looping ambient soundtrack while the user is on the map, and
/// is meant to be paused whenever the chat screen is open (call
/// [pauseForChat] / [resumeAfterChat] from the chat screen's
/// init/dispose once it's built). Designed so more tracks can be added
/// later as "sound packs" without changing this controller's API —
/// callers just pass a different asset path to [setTrack].
class AmbientSoundController {
  final AudioPlayer _player = AudioPlayer();

  bool _muted = false;
  double _volume = 0.5;
  String _currentTrackAsset = 'audio/ambient_theme.mp3';
  bool _pausedForChat = false;
  bool _pausedForBackground = false;

  bool get isMuted => _muted;
  double get volume => _volume;
  String get currentTrackAsset => _currentTrackAsset;

  Future<void> init() async {
    await _player.setReleaseMode(ReleaseMode.release);
    await _player.setVolume(_muted ? 0 : _volume);
    try {
      await _player.play(AssetSource(_currentTrackAsset));
    } catch (_) {
      // Asset not added yet — fail quietly so the app still runs before
      // the audio file is dropped in. See ambient_sound_controller docs.
    }
  }

  Future<void> toggleMute() async {
    _muted = !_muted;
    await _player.setVolume(_muted ? 0 : _volume);
  }

  Future<void> setVolume(double value) async {
    _volume = value.clamp(0.0, 1.0);
    if (!_muted) {
      await _player.setVolume(_volume);
    }
  }

  /// Swap to a different ambient track (future sound-pack support).
  /// [assetPath] is relative to the `assets/audio/` folder registered
  /// in pubspec.yaml, e.g. 'audio/rooftop_night.mp3'.
  Future<void> setTrack(String assetPath) async {
    _currentTrackAsset = assetPath;
    await _player.stop();
    try {
      await _player.play(AssetSource(_currentTrackAsset));
      await _player.setVolume(_muted ? 0 : _volume);
    } catch (_) {}
  }

  Future<void> pauseForChat() async {
    if (_pausedForChat) return;
    _pausedForChat = true;
    await _player.pause();
  }

  Future<void> resumeAfterChat() async {
    if (!_pausedForChat) return;
    _pausedForChat = false;
    // Don't resume if the chat pause is lifted while the app is
    // backgrounded or the user has it muted — those states take
    // priority over "chat closed".
    if (_pausedForBackground || _muted) return;
    await _player.resume();
  }

  /// Called whenever the app stops being on screen — minimized,
  /// switched away from, or backgrounded — so the ambient track never
  /// keeps playing behind other apps. Independent of [pauseForChat]:
  /// either one pausing keeps it paused, and both have to clear before
  /// sound resumes.
  Future<void> pauseForBackground() async {
    if (_pausedForBackground) return;
    _pausedForBackground = true;
    await _player.pause();
  }

  /// Called when the app comes back to the foreground. Only actually
  /// resumes playback if nothing else — chat being open, or the user
  /// having muted it — is also holding it paused.
  Future<void> resumeFromBackground() async {
    if (!_pausedForBackground) return;
    _pausedForBackground = false;
    if (_pausedForChat || _muted) return;
    await _player.resume();
  }

  Future<void> dispose() async {
    await _player.dispose();
  }
}

final ambientSoundProvider = Provider<AmbientSoundController>((ref) {
  final controller = AmbientSoundController();
  controller.init();
  ref.onDispose(() => controller.dispose());
  return controller;
});
