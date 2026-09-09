import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

import '../../../core/utils/full_video_viewer.dart';
import '../../../core/utils/video_playback_url.dart';

/// WhatsApp-style inline video player for chat bubbles.
///
/// Shows a Cloudinary poster frame while the video loads, then renders the
/// video with modern controls: play/pause, buffering indicator, progress
/// slider, elapsed / total time and a fullscreen action. The video keeps its
/// native aspect ratio (landscape and portrait) so it is never cropped or
/// stretched.
class VideoMessagePlayer extends StatefulWidget {
  final String videoUrl;

  const VideoMessagePlayer({super.key, required this.videoUrl});

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer> {
  static const _accent = Color(0xFF4FC3F7);
  static const _initTimeout = Duration(seconds: 15);
  static const _durationLabelStyle = TextStyle(
    color: Colors.white,
    fontSize: 11,
    fontWeight: FontWeight.w600,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  VideoPlayerController? _controller;
  bool _initialized = false;
  bool _initFailed = false;
  bool _playing = false;
  bool _buffering = false;
  bool _ended = false;
  bool _showControls = true;

  List<String> _attemptUrls = const [];
  int _attemptIndex = 0;
  bool _switchingAttempt = false;

  double? _dragValue;
  Duration _lastPosition = Duration.zero;
  bool _wasPlayingBeforeSeek = false;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();
    _initController();
  }

  /// Tries progressively more compatible variants of the same video:
  /// 1. forced re-encoded H.264 ≤1280px (decodes on Huawei / Honor HiSilicon
  ///    hardware decoders that reject high-profile or high-level H.264),
  /// 2. H.264 playback URL (fast, full quality),
  /// 3. the raw uploaded file.
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
    old?.removeListener(_onControllerTick);
    old?.dispose();

    if (_attemptIndex >= _attemptUrls.length) {
      if (mounted) {
        setState(() {
          _initFailed = true;
          _initialized = false;
          _playing = false;
          _buffering = false;
          _ended = false;
        });
      }
      return;
    }

    final url = _attemptUrls[_attemptIndex++];
    final controller = VideoPlayerController.networkUrl(Uri.parse(url))
      ..addListener(_onControllerTick);
    _controller = controller;
    _switchingAttempt = false;

    if (mounted) {
      setState(() {
        _initFailed = false;
        _initialized = false;
        _playing = false;
        _buffering = false;
        _ended = false;
        _showControls = true;
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
      setState(() {
        _initialized = true;
        _showControls = true;
      });
    } catch (e) {
      debugPrint('Video player init failed ($url): $e');
      if (!mounted || _controller != controller) return;
      _tryNextAttempt();
    }
  }

  void _onControllerTick() {
    if (!mounted || _controller == null) return;
    final controller = _controller!;
    final value = controller.value;
    if (value.hasError) {
      _handlePlaybackError(controller, value.errorDescription);
      return;
    }

    final ended = value.isInitialized &&
        value.duration > Duration.zero &&
        !value.isPlaying &&
        value.position >= value.duration;

    if (value.isPlaying != _playing ||
        value.isBuffering != _buffering ||
        value.isInitialized != _initialized ||
        ended != _ended) {
      setState(() {
        _playing = value.isPlaying;
        _buffering = value.isBuffering;
        _initialized = value.isInitialized;
        _ended = ended;
        if (ended) _showControls = true;
      });
      if (ended) {
        _hideTimer?.cancel();
      }
    } else if (_dragValue == null &&
        (value.position - _lastPosition).abs() >=
            const Duration(milliseconds: 400)) {
      setState(() => _lastPosition = value.position);
    }
  }

  void _handlePlaybackError(
    VideoPlayerController controller,
    String? description,
  ) {
    if (_switchingAttempt || _controller != controller) return;
    _switchingAttempt = true;
    final url =
        _attemptIndex > 0 ? _attemptUrls[_attemptIndex - 1] : widget.videoUrl;
    debugPrint('Video player playback failed ($url): $description');
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _controller != controller) return;
      _tryNextAttempt();
    });
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      if (_controller?.value.isPlaying == true) {
        setState(() => _showControls = false);
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller?.removeListener(_onControllerTick);
    _controller?.dispose();
    super.dispose();
  }

  // ================================
  // 🎮 CONTROLS
  // ================================
  void _togglePlay() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return;

    setState(() {
      if (controller.value.isPlaying) {
        controller.pause();
        _showControls = true;
        _hideTimer?.cancel();
      } else {
        if (_ended) {
          controller.seekTo(Duration.zero);
          _ended = false;
        }
        controller.play();
        _startHideTimer();
      }
    });
  }

  void _onTap() {
    if (!_initialized) return;
    setState(() => _showControls = !_showControls);
    if (_showControls) {
      _startHideTimer();
    } else {
      _hideTimer?.cancel();
    }
  }

  void _openFullscreen() {
    _hideTimer?.cancel();
    _controller?.pause();
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullVideoViewer(videoUrl: widget.videoUrl),
      ),
    );
  }

  void _retry() {
    setState(() {
      _initFailed = false;
      _initialized = false;
    });
    _initController();
  }

  double get _positionMs {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) return 0;
    final durationMs = controller.value.duration.inMilliseconds;
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

  // ================================
  // 🧱 UI
  // ================================
  @override
  Widget build(BuildContext context) {
    final controller = _controller;

    return ClipRRect(
      borderRadius: BorderRadius.circular(12.r),
      child: AspectRatio(
        aspectRatio: controller != null && controller.value.isInitialized
            ? controller.value.aspectRatio
            : 16 / 9,
        child: Container(
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            children: [
              _buildStage(),
              if (_initialized) _buildBottomGradient(),
              if (_initFailed)
                _buildErrorState()
              else if (!_initialized)
                _buildLoadingOverlay(),
              if (_initialized && _buffering)
                const Center(
                  child: SizedBox(
                    width: 36,
                    height: 36,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: _accent,
                    ),
                  ),
                ),
              if (_initialized && _showControls) ...[
                Center(child: _buildPlayPauseButton()),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: _buildBottomBar(),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildStage() {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!_initialized)
            Image.network(
              videoThumbnailUrl(widget.videoUrl),
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                color: Colors.black87,
                child: const Center(
                  child: Icon(
                    Icons.movie_outlined,
                    color: Colors.white38,
                    size: 40,
                  ),
                ),
              ),
            )
          else
            VideoPlayer(_controller!),
        ],
      ),
    );
  }

  Widget _buildLoadingOverlay() {
    return Container(
      color: Colors.black38,
      child: const Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: _accent,
          ),
        ),
      ),
    );
  }

  Widget _buildErrorState() {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 34),
            SizedBox(height: 8.h),
            TextButton.icon(
              onPressed: _retry,
              icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
              label: const Text(
                'Video failed to load. Tap to retry',
                style: TextStyle(color: Colors.white, fontSize: 12),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomGradient() {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
            ],
            stops: const [0.0, 0.55],
          ),
        ),
      ),
    );
  }

  Widget _buildPlayPauseButton() {
    return GestureDetector(
      onTap: _togglePlay,
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
          _ended
              ? Icons.replay_rounded
              : (_playing ? Icons.pause_rounded : Icons.play_arrow_rounded),
          color: Colors.white,
          size: 34,
        ),
      ),
    );
  }

  Widget _buildBottomBar() {
    final controller = _controller;
    if (controller == null || !controller.value.isInitialized) {
      return const SizedBox.shrink();
    }

    final durationMs = controller.value.duration.inMilliseconds;
    final positionMs = _positionMs.clamp(0, durationMs.toDouble()).toDouble();
    final position = Duration(milliseconds: positionMs.round());
    final duration = controller.value.duration;

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
                activeTrackColor: _accent,
                inactiveTrackColor: Colors.white24,
                thumbColor: Colors.white,
                overlayColor: _accent.withValues(alpha: 0.25),
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
            onTap: _openFullscreen,
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
