import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:video_player/video_player.dart';
import 'video_duration.dart';
import 'video_playback_url.dart';
import 'video_viewer/video_bottom_bar_view.dart';
import 'video_viewer/video_stage_view.dart';
import 'video_viewer/video_top_bar_view.dart';
import 'video_viewer/video_transport_overlay.dart';
import 'video_viewer/video_vignette.dart';

/// Full-screen video player with auto-hiding controls, seek-by-5s, playback
/// speed, and a multi-URL retry chain (see [video_playback_url]).
///
/// Owns the [VideoPlayerController] and all playback logic; the on-screen
/// chrome is delegated to the small widgets under `video_viewer/`.
class FullVideoViewer extends StatefulWidget {
  final String videoUrl;

  /// Known length of the video (from the message's stored `videoDuration`).
  /// Used while the network controller still reports an unknown (zero)
  /// duration — typically right after a send, before Cloudinary finishes
  /// deriving the on-the-fly H.264 transform — so the seek bar and the total
  /// time are correct immediately.
  final Duration? initialDuration;

  const FullVideoViewer({
    super.key,
    required this.videoUrl,
    this.initialDuration,
  });

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
      // See VideoMessagePlayer._initializeAttempt: a successful init can still
      // report an unknown (zero) duration while Cloudinary derives the
      // transform. Without a stored length to fall back on, switch to the next
      // source (the raw upload carries full metadata).
      final zeroDuration = controller.value.isInitialized &&
          controller.value.duration <= Duration.zero;
      if (zeroDuration &&
          widget.initialDuration == null &&
          _attemptIndex < _attemptUrls.length) {
        debugPrint('Full video viewer initialized with no duration ($url), '
            'falling back to the next source');
        _tryNextAttempt();
        return;
      }
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
    final maxMs = _knownDuration.inMilliseconds;
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

  /// The controller's real duration when known, falling back to the stored
  /// [initialDuration] while the stream reports an unknown (zero) duration.
  Duration get _knownDuration => effectiveVideoDuration(
      _controller?.value.duration ?? Duration.zero, widget.initialDuration);

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

  @override
  Widget build(BuildContext context) {
    final controller = _controller;
    final isReady = controller?.value.isInitialized ?? false;
    final isPlaying = controller?.value.isPlaying ?? false;
    final durationMs = _knownDuration.inMilliseconds.toDouble();
    final currentMs =
        (controller?.value.position.inMilliseconds ?? 0).toDouble();
    final sliderVal =
        (_dragValue ?? currentMs).clamp(0.0, durationMs > 0 ? durationMs : 1.0);

    return Scaffold(
      backgroundColor: Colors.black,
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _toggleControls,
        child: Stack(
          fit: StackFit.expand,
          children: [
            VideoStageView(
              controller: controller,
              isReady: isReady,
              isBuffering: controller?.value.isBuffering ?? false,
              initFailed: _initFailed,
              handledEnded: _handledEnded,
              onRetry: _retry,
            ),
            VideoVignette(visible: isReady && _showControls),
            VideoTransportOverlay(
              visible: _showControls && isReady,
              isPlaying: isPlaying,
              handledEnded: _handledEnded,
              onPlayPause: _playPause,
              onSeek: _seekRelative,
            ),
            VideoTopBarView(
              visible: _showControls,
              isReady: isReady,
              playbackSpeed: _playbackSpeed,
              onChangeSpeed: _changeSpeed,
              onClose: () => Navigator.pop(context),
            ),
            VideoBottomBarView(
              visible: _showControls && isReady,
              value: sliderVal,
              duration: _knownDuration,
              onDragStart: () {
                _isDragging = true;
                _hideTimer?.cancel();
              },
              onDragChanged: (val) => setState(() => _dragValue = val),
              onDragEnd: (val) {
                _isDragging = false;
                controller?.seekTo(Duration(milliseconds: val.round()));
                setState(() => _dragValue = null);
                _startHideTimer();
              },
            ),
          ],
        ),
      ),
    );
  }
}
