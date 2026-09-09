import 'dart:math' as math;

import 'package:audioplayers/audioplayers.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Premium voice message player shown inside chat bubbles.
/// Features an animated progress waveform, a tap-to-seek bar,
/// and 1x / 1.5x / 2x playback speed selector.
class VoiceMessagePlayer extends StatefulWidget {
  final String audioUrl;
  final Duration? initialDuration;
  final Color playedColor;
  final Color idleColor;
  final Color textColor;

  const VoiceMessagePlayer({
    super.key,
    required this.audioUrl,
    this.initialDuration,
    required this.playedColor,
    required this.idleColor,
    required this.textColor,
  });

  @override
  State<VoiceMessagePlayer> createState() => _VoiceMessagePlayerState();
}

class _VoiceMessagePlayerState extends State<VoiceMessagePlayer>
    with SingleTickerProviderStateMixin {
  late AudioPlayer _player;
  late AnimationController _pulseController;

  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;
  double _progress = 0.0;

  static const List<double> _speeds = [1.0, 1.5, 2.0];
  int _speedIndex = 0;
  double get _currentSpeed => _speeds[_speedIndex];

  @override
  void initState() {
    super.initState();
    _duration = widget.initialDuration ?? Duration.zero;
    _player = AudioPlayer()..setPlayerMode(PlayerMode.mediaPlayer);
    _player.onPlayerStateChanged.listen((state) {
      if (!mounted) return;
      setState(() => _isPlaying = state == PlayerState.playing);
    });
    _player.onPositionChanged.listen((pos) {
      if (!mounted) return;
      setState(() {
        _position = pos;
        _progress = _duration.inMilliseconds > 0
            ? (pos.inMilliseconds / _duration.inMilliseconds).clamp(0.0, 1.0)
            : 0.0;
      });
    });
    _player.onDurationChanged.listen((dur) {
      if (!mounted || dur.inMilliseconds <= 0) return;
      setState(() => _duration = dur);
    });
    _player.onPlayerComplete.listen((_) {
      if (!mounted) return;
      setState(() {
        _isPlaying = false;
        _position = Duration.zero;
        _progress = 0.0;
      });
    });

    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1400),
    );
  }

  Future<void> _togglePlay() async {
    if (_isPlaying) {
      await _player.pause();
      _pulseController.stop();
    } else {
      await _player.play(UrlSource(widget.audioUrl));
      await _player.setPlaybackRate(_currentSpeed);
      _pulseController.repeat(reverse: true);
    }
  }

  Future<void> _cycleSpeed() async {
    _speedIndex = (_speedIndex + 1) % _speeds.length;
    setState(() {});
    await _player.setPlaybackRate(_currentSpeed);
  }

  Future<void> _seekToFraction(double fraction) async {
    final target = Duration(milliseconds: (_duration.inMilliseconds * fraction).toInt());
    await _player.seek(target);
    setState(() {
      _position = target;
      _progress = fraction.clamp(0.0, 1.0);
    });
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _player.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes.toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        // Play / Pause
        GestureDetector(
          onTap: _togglePlay,
          child: Container(
            width: 40.w,
            height: 40.w,
            decoration: BoxDecoration(
              color: widget.playedColor.withValues(alpha: 0.12),
              shape: BoxShape.circle,
              border: Border.all(
                color: widget.playedColor.withValues(alpha: 0.5),
                width: 1.2,
              ),
            ),
            child: Icon(
              _isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded,
              color: widget.playedColor,
              size: 24.sp,
            ),
          ),
        ),
        SizedBox(width: 8.w),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              // Animated waveform (tap to seek)
              Builder(
                builder: (waveContext) => GestureDetector(
                  onTapDown: (details) {
                    final size = (waveContext.findRenderObject() as RenderBox?)?.size;
                    if (size == null || size.width <= 0) return;
                    _seekToFraction(details.localPosition.dx / size.width);
                  },
                  child: LayoutBuilder(
                    builder: (context, constraints) => AnimatedBuilder(
                      animation: _pulseController,
                      builder: (context, _) => CustomPaint(
                        size: Size(constraints.maxWidth, 34.h),
                        painter: _WaveformPainter(
                          progress: _progress,
                          playing: _isPlaying,
                          pulse: _pulseController.value,
                          playedColor: widget.playedColor,
                          idleColor: widget.idleColor,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SizedBox(height: 3.h),
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  Text(
                    // Total length before playback starts, elapsed while
                    // playing / paused (WhatsApp style).
                    _format(_isPlaying || _position > Duration.zero
                        ? _position
                        : _duration),
                    style: TextStyle(
                      color: widget.textColor.withValues(alpha: 0.75),
                      fontSize: 11.sp,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  // Speed selector
                  GestureDetector(
                    onTap: _cycleSpeed,
                    child: Container(
                      padding: EdgeInsets.symmetric(
                        horizontal: 8.w,
                        vertical: 2.h,
                      ),
                      decoration: BoxDecoration(
                        color: widget.playedColor.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(8.r),
                        border: Border.all(
                          color: widget.playedColor.withValues(alpha: 0.4),
                        ),
                      ),
                      child: Text(
                        _speeds[_speedIndex] == 1.0
                            ? '1x'
                            : _speeds[_speedIndex] == 2.0
                                ? '2x'
                                : '${_speeds[_speedIndex]}x',
                        style: TextStyle(
                          color: widget.playedColor,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ],
    );
  }
}

/// Draws a static fingerprint of bars, highlights the heard portion in the
/// played color and gently pulses the whole waveform while playing.
class _WaveformPainter extends CustomPainter {
  final double progress;
  final bool playing;
  final double pulse;
  final Color playedColor;
  final Color idleColor;

  _WaveformPainter({
    required this.progress,
    required this.playing,
    required this.pulse,
    required this.playedColor,
    required this.idleColor,
  });

  static const int _barCount = 30;

  @override
  void paint(Canvas canvas, Size size) {
    final barWidth = size.width / _barCount;
    final loose = barWidth * 0.32;
    final barW = barWidth - loose;

    for (var i = 0; i < _barCount; i++) {
      // Deterministic pseudo-random heights (based on index)
      final seed = math.sin(i * 7.31) * 10000;
      final rnd = seed - seed.floorToDouble();
      final base = 0.35 + 0.65 * rnd;
      final pulseFactor = playing ? (0.72 + 0.28 * pulse) : 0.6;
      final height = size.height * base * pulseFactor;
      final x = i * barWidth + loose / 2;

      final centerY = size.height / 2;
      final rect = Rect.fromLTWH(
        x,
        centerY - height / 2,
        barW,
        height,
      );
      final fraction = (i + 1) / _barCount;
      final color = fraction <= progress ? playedColor : idleColor;

      final rrect = RRect.fromRectAndRadius(
        rect,
        Radius.circular(barW / 2),
      );
      canvas.drawRRect(rrect, Paint()..color = color);
    }
  }

  @override
  bool shouldRepaint(_WaveformPainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.playing != playing ||
        oldDelegate.pulse != pulse ||
        oldDelegate.playedColor != playedColor ||
        oldDelegate.idleColor != idleColor;
  }
}