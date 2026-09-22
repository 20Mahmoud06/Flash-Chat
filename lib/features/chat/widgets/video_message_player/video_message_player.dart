import 'dart:async';
import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/utils/full_video_viewer.dart';
import '../../../../core/utils/video_playback_url.dart';
import 'video_player_controls.dart';
import 'video_player_overlays.dart';
import 'video_player_stage.dart';

/// WhatsApp-style inline video player for chat bubbles.
///
/// Shows a Cloudinary poster frame while the video loads, then renders the
/// video with modern controls: play/pause, buffering indicator, progress
/// slider, elapsed / total time and a fullscreen action. The video keeps its
/// native aspect ratio (landscape and portrait) so it is never cropped or
/// stretched.
class VideoMessagePlayer extends StatefulWidget {
  final String videoUrl;

  /// Known length of the video coming from the message's stored
  /// `videoDuration`. While the network controller still reports an unknown
  /// (zero) duration — typically right after a send, before Cloudinary
  /// finishes deriving the on-the-fly H.264 transform — this keeps the
  /// elapsed / total time and the seek slider correct immediately.
  final Duration? initialDuration;

  const VideoMessagePlayer({
    super.key,
    required this.videoUrl,
    this.initialDuration,
  });

  @override
  State<VideoMessagePlayer> createState() => _VideoMessagePlayerState();
}

class _VideoMessagePlayerState extends State<VideoMessagePlayer> {
  static const _accent = AppColors.sky;
  static const _initTimeout = Duration(seconds: 15);

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

  Duration _lastPosition = Duration.zero;
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
      // A "successful" init can still leave the duration unknown (zero) — what
      // happens right after a send, while Cloudinary is still deriving the
      // on-the-fly H.264 transform. When we have no stored length to fall back
      // on for the seek bar, move to the next source (the raw upload carries
      // full metadata and is always immediately available).
      final zeroDuration = controller.value.isInitialized &&
          controller.value.duration <= Duration.zero;
      if (zeroDuration &&
          widget.initialDuration == null &&
          _attemptIndex < _attemptUrls.length) {
        debugPrint('Video player initialized with no duration ($url), '
            'falling back to the next source');
        _tryNextAttempt();
        return;
      }
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
    } else if ((value.position - _lastPosition).abs() >=
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
        builder: (_) => FullVideoViewer(
          videoUrl: widget.videoUrl,
          initialDuration: widget.initialDuration,
        ),
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
              VideoPlayerStage(
                initialized: _initialized,
                videoUrl: widget.videoUrl,
                controller: _controller,
                onTap: _onTap,
              ),
              if (_initialized) const VideoPlayerBottomGradient(),
              if (_initFailed)
                VideoPlayerErrorOverlay(onRetry: _retry)
              else if (!_initialized)
                const VideoPlayerLoadingOverlay(accent: _accent),
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
                Center(
                  child: VideoPlayerPlayPauseButton(
                    playing: _playing,
                    ended: _ended,
                    onTap: _togglePlay,
                  ),
                ),
                Positioned(
                  left: 8,
                  right: 8,
                  bottom: 8,
                  child: VideoPlayerBottomBar(
                    controller: _controller!,
                    accent: _accent,
                    initialDuration: widget.initialDuration,
                    onFullscreen: _openFullscreen,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}