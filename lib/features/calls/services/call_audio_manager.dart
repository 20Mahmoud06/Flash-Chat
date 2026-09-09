import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/foundation.dart';

/// Plays the call UX sounds as a SIDE-EFFECT of the call state machine.
///
/// The call state (in [CallCubit]) is always the source of truth; this
/// manager only reacts to it. A failure here never breaks the call itself.
///
/// Scope of what this manager plays:
///   * OUTGOING "waiting for answer" tone — the caller hears
///     `assets/waiting ringtone.wav` looping while the channel is still
///     ringing (nobody joined yet). Started by the outgoing call state and
///     stopped the moment the call transitions to connected / ended.
///
/// The INCOMING ring is intentionally NOT played here: incoming calls are
/// presented by the native CallKit plugin (`CallkitSoundPlayerManager`),
/// which already loops the app's bundled `ringtone.wav` on the RING stream
/// and works when the app is backgrounded or terminated. Reproducing it in
/// Flutter would create a competing/second ring, so it is left entirely to
/// the native layer (see `android/app/src/main/res/raw/ringtone.wav`).
///
/// Design rules:
///   * At most one call sound plays at a time (single shared player).
///   * Starting a ringtone while another is playing restarts the shared
///     player instead of stacking a second one.
///   * `stop()` / `dispose()` are idempotent and safe to call repeatedly.
///   * Playback failures are logged and swallowed — never a crash.
class CallAudioManager {
  CallAudioManager._();

  /// App-wide singleton so a duplicate call-state event can never create a
  /// second overlapping player.
  static final CallAudioManager instance = CallAudioManager._();

  /// Path relative to the `assets/` folder declared in pubspec.yaml. The
  /// actual file is `assets/waiting ringtone.wav` (keep the space — that is
  /// the bundled asset key).
  static const String _waitingRingtonAsset = 'waiting ringtone.wav';

  AudioPlayer? _player;
  bool _waitingPlaying = false;

  AudioPlayer _ensurePlayer() {
    return _player ??= (AudioPlayer()..setPlayerMode(PlayerMode.mediaPlayer));
  }

  /// Starts looping the outgoing "waiting for answer" tone.
  ///
  /// Idempotent: if it is already playing, this is a no-op so a duplicated
  /// state event (e.g. a re-emitted `CallEngineReady`) can never start a second
  /// overlapping player.
  Future<void> playWaitingRingtone() async {
    if (_waitingPlaying) return;
    _waitingPlaying = true;
    final player = _ensurePlayer();
    try {
      // The player itself loops the ~11s file with no audible gap —
      // not a Timer restarting the asset every 11 seconds.
      await player.setReleaseMode(ReleaseMode.loop);
      await player.stop();
      await player.play(AssetSource(_waitingRingtonAsset));
    } catch (e) {
      _waitingPlaying = false;
      debugPrint('CallAudioManager: waiting ringtone failed: $e');
    }
  }

  /// Stops any call audio and releases the shared player. Safe to call many
  /// times in a row, and after a terminal state nothing will restart it.
  Future<void> stop() async {
    _waitingPlaying = false;
    final player = _player;
    if (player == null) return;
    try {
      await player.stop();
    } catch (e) {
      debugPrint('CallAudioManager: stop failed: $e');
    }
  }

  /// Fully releases the underlying native player. The manager can be reused
  /// afterwards (a new player is lazily recreated). Safe to repeat.
  Future<void> dispose() async {
    _waitingPlaying = false;
    final player = _player;
    _player = null;
    if (player == null) return;
    try {
      await player.dispose();
    } catch (e) {
      debugPrint('CallAudioManager: dispose failed: $e');
    }
  }
}
