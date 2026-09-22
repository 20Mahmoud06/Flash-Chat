import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/utils/video_duration.dart';

/// Center play / pause button. Shows a replay icon when the video has ended.
class VideoPlayerPlayPauseButton extends StatelessWidget {
  final bool playing;
  final bool ended;
  final VoidCallback onTap;

  const VideoPlayerPlayPauseButton({
    super.key,
    required this.playing,
    required this.ended,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 56,
        height: 56,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.45),
          border: Border.all(color: Colors.white.withValues(alpha: 0.35)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.3),
              blurRadius: 14,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: Icon(
          ended
              ? Icons.replay_rounded
              : (playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }
}

/// Bottom seek bar: elapsed time, drag-to-seek slider, total time and the
/// fullscreen action. Owns its own drag state so scrubbing keeps smoothing
/// even while the player state ticks.
class VideoPlayerBottomBar extends StatefulWidget {
  final VideoPlayerController controller;
  final Color accent;
  final VoidCallback onFullscreen;

  /// Known length of the video (from the message's stored `videoDuration`).
  /// Used while the network controller still reports an unknown (zero)
  /// duration — typically right after a send, before Cloudinary finishes
  /// deriving the on-the-fly H.264 transform — so the slider and the total
  /// time are correct immediately instead of showing a dead `00:00`.
  final Duration? initialDuration;

  const VideoPlayerBottomBar({
    super.key,
    required this.controller,
    required this.accent,
    required this.onFullscreen,
    this.initialDuration,
  });

  @override
  State<VideoPlayerBottomBar> createState() => _VideoPlayerBottomBarState();
}

class _VideoPlayerBottomBarState extends State<VideoPlayerBottomBar> {
  static const _durationLabelStyle = TextStyle(
    color: Colors.white,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  double? _dragValue;
  bool _wasPlayingBeforeSeek = false;

  /// The controller's real duration when known, falling back to the message's
  /// stored length while the stream reports an unknown (zero) duration.
  Duration get _knownDuration =>
      effectiveVideoDuration(widget.controller.value.duration,
          widget.initialDuration);

  double get _positionMs {
    final controller = widget.controller;
    if (!controller.value.isInitialized) return 0;
    final durationMs = _knownDuration.inMilliseconds;
    if (durationMs <= 0) return 0;
    final positionMs =
        controller.value.position.inMilliseconds.clamp(0, durationMs);
    return _dragValue ?? positionMs.toDouble();
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final durationMs = _knownDuration.inMilliseconds;
    final positionMs = _positionMs.clamp(0, durationMs.toDouble()).toDouble();
    final position = Duration(milliseconds: positionMs.round());
    final duration = _knownDuration;

    return GestureDetector(
      onTap: () {},
      child: Row(
        children: [
          Text(
            _formatDuration(position),
            style: _durationLabelStyle,
          ),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(context).copyWith(
                trackHeight: 3,
                thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
                overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
                activeTrackColor: widget.accent,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: widget.accent.withValues(alpha: 0.25),
              ),
              child: Slider(
                value: positionMs,
                max: durationMs.toDouble(),
                onChangeStart: (_) {
                  _wasPlayingBeforeSeek = controller.value.isPlaying;
                  controller.pause();
                },
                onChanged: (value) {
                  setState(() => _dragValue = value);
                },
                onChangeEnd: (value) {
                  controller.seekTo(Duration(milliseconds: value.round()));
                  setState(() => _dragValue = null);
                  if (_wasPlayingBeforeSeek) {
                    controller.play();
                  }
                },
              ),
            ),
          ),
          Text(
            _formatDuration(duration),
            style: _durationLabelStyle,
          ),
          SizedBox(width: 4.w),
          GestureDetector(
            onTap: widget.onFullscreen,
            child: Padding(
              padding: EdgeInsets.all(2.w),
              child: const Icon(
                Icons.fullscreen,
                color: Colors.white,
                size: 18,
              ),
            ),
          ),
        ],
      ),
    );
  }
}