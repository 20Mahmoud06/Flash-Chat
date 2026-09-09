import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';

import 'video_playback_url.dart';

class FullVideoViewer extends StatefulWidget {
  final String videoUrl;

  const FullVideoViewer({super.key, required this.videoUrl});

  @override
  State<FullVideoViewer> createState() => _FullVideoViewerState();
}

class _FullVideoViewerState extends State<FullVideoViewer> {
  static const _initTimeout = Duration(seconds: 8);

  VideoPlayerController? _controller;
  bool _showControls = true;
  bool _handledEnded = false;
  bool _initFailed = false;
  bool _isDragging = false;
  double? _dragValue;
  double _playbackSpeed = 1.0;
  Timer? _hideTimer;

  List<String> _attemptUrls = const [];
  int _attemptIndex = 0;
  bool _switchingAttempt = false;

  @override
  void initState() {
    super.initState();
    // Only this viewer may rotate (landscape videos): the rest of the app
    // stays locked to portrait.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _initController();
  }

  void _initController() {
    final raw = widget.videoUrl;
    _attemptUrls = {
      videoCompatUrl(raw),
      videoPlaybackUrl(raw),
      videoRawUrl(raw),
    }.where((url) => url.isNotEmpty).toList();
    _attemptIndex = 0;
    _tryNextAttempt();
  }

  void _tryNextAttempt() {
    _hideTimer?.cancel();
    final old = _controller;
    _controller = null;
    old?.removeListener(_onVideoTick);
    old?.removeListener(_onVideoEnded);
    old?.dispose();

    if (_attemptIndex >= _attemptUrls.length) {
      if (mounted) {
        setState(() {
          _initFailed = true;
          _handledEnded = false;
        });
      }
      return;
    }

    final url = _attemptUrls[_attemptIndex++];
    final controller = VideoPlayerController.networkUrl(Uri.parse(url));
    _controller = controller;
    _switchingAttempt = false;
    if (mounted) {
      setState(() {
        _initFailed = false;
        _handledEnded = false;
        _dragValue = null;
      });
    }

    unawaited(_initializeAttempt(controller, url));
  }

  Future<void> _initializeAttempt(
    VideoPlayerController controller,
    String url,
  ) async {
    try {
      await controller.initialize().timeout(_initTimeout);
      if (!mounted || _controller != controller) return;
      controller.addListener(_onVideoTick);
      controller.addListener(_onVideoEnded);
      controller.setPlaybackSpeed(_playbackSpeed);
      setState(() {
        _showControls = true;
      });
      controller.play();
      _startHideTimer();
    } catch (e) {
      debugPrint('Full video viewer init failed ($url): $e');
      if (!mounted || _controller != controller) return;
      _tryNextAttempt();
    }
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    if (_controller?.value.isPlaying == true && !_isDragging) {
      _hideTimer = Timer(const Duration(seconds: 3, milliseconds: 500), () {
        if (mounted && _controller?.value.isPlaying == true) {
          setState(() => _showControls = false);
        }
      });
    }
  }

  void _retry() {
    setState(() => _initFailed = false);
    _initController();
  }

  void _onVideoTick() {
    final controller = _controller;
    if (!mounted || controller == null) return;
    final value = controller.value;
    if (value.hasError) {
      _handlePlaybackError(controller, value.errorDescription);
      return;
    }
    setState(() {});
  }

  void _handlePlaybackError(
    VideoPlayerController controller,
    String? description,
  ) {
    if (_switchingAttempt || _controller != controller) return;
    _switchingAttempt = true;
    final url =
        _attemptIndex > 0 ? _attemptUrls[_attemptIndex - 1] : widget.videoUrl;
    debugPrint('Full video viewer playback failed ($url): $description');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller != controller) return;
      _tryNextAttempt();
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _playPause() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _showControls = true;
        _hideTimer?.cancel();
      } else {
        if (_handledEnded ||
            controller.value.position >= controller.value.duration) {
          controller.seekTo(Duration.zero);
          _handledEnded = false;
        }
        controller.play();
        _startHideTimer();
      }
    });
  }

  void _seekRelative(Duration offset) {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;
    final current = controller.value.position;
    final maxMs = controller.value.duration.inMilliseconds;
    final targetMs = (current + offset).inMilliseconds.clamp(0, maxMs);
    controller.seekTo(Duration(milliseconds: targetMs));
    setState(() {});
    _startHideTimer();
  }

  void _changeSpeed() {
    final speeds = [1.0, 1.25, 1.5, 2.0];
    final nextIndex = (speeds.indexOf(_playbackSpeed) + 1) % speeds.length;
    setState(() {
      _playbackSpeed = speeds[nextIndex];
      _controller?.setPlaybackSpeed(_playbackSpeed);
    });
  }

  void _onVideoEnded() {
    final controller = _controller;
    if (controller == null) return;
    final value = controller.value;
    if (value.isInitialized &&
        !value.isPlaying &&
        value.duration > Duration.zero &&
        value.position >= value.duration &&
        !_handledEnded) {
      _handledEnded = true;
      _hideTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        setState(() {
          _showControls = true;
        });
      });
    } else if (value.position < value.duration) {
      _handledEnded = false;
    }
  }

  @override
  void dispose() {
    // Restore the portrait-only lock for the rest of the app.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    _hideTimer?.cancel();
    _controller?.removeListener(_onVideoTick);
    _controller?.removeListener(_onVideoEnded);
    _controller?.dispose();
    super.dispose();
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady = controller?.value.isInitialized ?? false;
    final isPlaying = controller?.value.isPlaying ?? false;
    final durationMs =
        (controller?.value.duration.inMilliseconds ?? 0).toDouble();
    final currentMs =
        (controller?.value.position.inMilliseconds ?? 0).toDouble();
    final sliderVal =
        (_dragValue ?? currentMs).clamp(0.0, durationMs > 0 ? durationMs : 1.0);

    const accent = Color(0xFF4FC3F7);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            // VIDEO PLAYER STAGE
            Positioned.fill(
              child: Container(
                color: Colors.black,
                child: _initFailed
                    ? Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.error_outline,
                              color: Colors.white54,
                              size: 44,
                            ),
                            const SizedBox(height: 12),
                            TextButton.icon(
                              onPressed: _retry,
                              icon: const Icon(Icons.refresh,
                                  color: accent, size: 20),
                              label: const Text(
                                'Video failed to load. Tap to retry',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 14,
                                ),
                              ),
                            ),
                          ],
                        ),
                      )
                    : isReady
                        ? Center(
                            child: AspectRatio(
                              aspectRatio: controller!.value.aspectRatio,
                              child: VideoPlayer(controller),
                            ),
                          )
                        : const Center(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                SizedBox(
                                  width: 44,
                                  height: 44,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 3,
                                    color: accent,
                                  ),
                                ),
                                SizedBox(height: 14),
                                Text(
                                  'Loading video...',
                                  style: TextStyle(
                                    color: Colors.white60,
                                    fontSize: 13,
                                    letterSpacing: 0.5,
                                  ),
                                ),
                              ],
                            ),
                          ),
              ),
            ),

            // BUFFERING SPINNER
            // Hidden once the video has ended: at the end the player can
            // briefly report "buffering" while showing the rewatch control,
            // which would otherwise flash a spinner behind it.
            if (!_initFailed &&
                isReady &&
                !_handledEnded &&
                controller!.value.isBuffering)
              Center(
                child: Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: Colors.black.withValues(alpha: 0.6),
                  ),
                  child: const Padding(
                    padding: EdgeInsets.all(12),
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: accent,
                    ),
                  ),
                ),
              ),

            // VIGNETTE OVERLAY
            Positioned.fill(
              child: IgnorePointer(
                child: AnimatedOpacity(
                  opacity: isReady && _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.65),
                          Colors.transparent,
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.75),
                        ],
                        stops: const [0.0, 0.25, 0.7, 1.0],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // CENTER CONTROL BUTTONS (Rewind, Play/Pause, Forward)
            Positioned.fill(
              child: Align(
                alignment: Alignment.center,
                child: IgnorePointer(
                  ignoring: !(_showControls && isReady),
                  child: AnimatedOpacity(
                    opacity: _showControls && isReady ? 1.0 : 0.0,
                    duration: const Duration(milliseconds: 250),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        // -5 Seconds
                        IconButton(
                          iconSize: 38,
                          icon: const Icon(
                            Icons.replay_5_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () =>
                              _seekRelative(const Duration(seconds: -5)),
                        ),
                        const SizedBox(width: 28),

                        // Play / Pause / Replay
                        GestureDetector(
                          onTap: _playPause,
                          child: Container(
                            width: 68,
                            height: 68,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: Colors.black.withValues(alpha: 0.55),
                              border: Border.all(
                                color: Colors.white.withValues(alpha: 0.35),
                                width: 1.5,
                              ),
                              boxShadow: [
                                BoxShadow(
                                  color: accent.withValues(alpha: 0.35),
                                  blurRadius: 20,
                                  spreadRadius: 2,
                                ),
                              ],
                            ),
                            child: Icon(
                              _handledEnded
                                  ? Icons.replay_rounded
                                  : (isPlaying
                                      ? Icons.pause_rounded
                                      : Icons.play_arrow_rounded),
                              color: Colors.white,
                              size: 42,
                            ),
                          ),
                        ),
                        const SizedBox(width: 28),

                        // +5 Seconds
                        IconButton(
                          iconSize: 38,
                          icon: const Icon(
                            Icons.forward_5_rounded,
                            color: Colors.white,
                          ),
                          onPressed: () =>
                              _seekRelative(const Duration(seconds: 5)),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),

            // TOP NAVIGATION BAR
            Positioned(
              top: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !_showControls,
                child: AnimatedOpacity(
                  opacity: _showControls ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 8),
                      child: Row(
                        children: [
                          _GlassButton(
                            icon: Icons.arrow_back_rounded,
                            size: 20,
                            iconColor: Colors.white,
                            backgroundColor:
                                Colors.black.withValues(alpha: 0.45),
                            borderColor: Colors.white.withValues(alpha: 0.2),
                            onTap: () => Navigator.pop(context),
                          ),
                          const SizedBox(width: 12),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 5),
                            decoration: BoxDecoration(
                              color: Colors.black.withValues(alpha: 0.45),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.15)),
                            ),
                            child: const Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.videocam_rounded,
                                  color: accent,
                                  size: 15,
                                ),
                                SizedBox(width: 6),
                                Text(
                                  'VIDEO PLAYER',
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 11,
                                    fontWeight: FontWeight.bold,
                                    letterSpacing: 1.2,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const Spacer(),
                          // Speed Toggle Button
                          if (isReady)
                            GestureDetector(
                              onTap: _changeSpeed,
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(
                                  color: Colors.black.withValues(alpha: 0.45),
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                      color:
                                          Colors.white.withValues(alpha: 0.2)),
                                ),
                                child: Text(
                                  '${_playbackSpeed}x',
                                  style: const TextStyle(
                                    color: Colors.white,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // BOTTOM CONTROL BAR (SLIDER & TIMERS)
            Positioned(
              bottom: 0,
              left: 0,
              right: 0,
              child: IgnorePointer(
                ignoring: !(_showControls && isReady),
                child: AnimatedOpacity(
                  opacity: _showControls && isReady ? 1.0 : 0.0,
                  duration: const Duration(milliseconds: 250),
                  child: SafeArea(
                    child: Container(
                      margin: const EdgeInsets.all(16),
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15)),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.4),
                            blurRadius: 16,
                            offset: const Offset(0, 4),
                          ),
                        ],
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // INTERACTIVE SLIDER
                          SliderTheme(
                            data: SliderTheme.of(context).copyWith(
                              trackHeight: 4,
                              thumbShape: const RoundSliderThumbShape(
                                  enabledThumbRadius: 7),
                              overlayShape: const RoundSliderOverlayShape(
                                  overlayRadius: 14),
                              activeTrackColor: accent,
                              inactiveTrackColor: Colors.white24,
                              thumbColor: Colors.white,
                              overlayColor: accent.withValues(alpha: 0.3),
                            ),
                            child: Slider(
                              value: sliderVal,
                              max: durationMs > 0 ? durationMs : 1.0,
                              onChangeStart: (_) {
                                _isDragging = true;
                                _hideTimer?.cancel();
                              },
                              onChanged: (val) {
                                setState(() => _dragValue = val);
                              },
                              onChangeEnd: (val) {
                                _isDragging = false;
                                controller?.seekTo(
                                    Duration(milliseconds: val.round()));
                                setState(() => _dragValue = null);
                                _startHideTimer();
                              },
                            ),
                          ),
                          const SizedBox(height: 2),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Text(
                                _formatDuration(
                                  Duration(milliseconds: sliderVal.round()),
                                ),
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              Text(
                                _formatDuration(
                                  controller?.value.duration ?? Duration.zero,
                                ),
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GlassButton extends StatelessWidget {
  final IconData icon;
  final double size;
  final Color iconColor;
  final Color backgroundColor;
  final Color borderColor;
  final VoidCallback onTap;

  const _GlassButton({
    required this.icon,
    required this.size,
    required this.iconColor,
    required this.backgroundColor,
    required this.borderColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 38,
        height: 38,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor),
        ),
        child: Icon(icon, color: iconColor, size: size),
      ),
    );
  }
}
