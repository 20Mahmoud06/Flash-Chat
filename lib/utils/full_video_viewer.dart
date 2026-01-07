import 'dart:async';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

class FullVideoViewer extends StatefulWidget {
  final String videoUrl;

  const FullVideoViewer({super.key, required this.videoUrl});

  @override
  State<FullVideoViewer> createState() => _FullVideoViewerState();
}

class _FullVideoViewerState extends State<FullVideoViewer> {
  late VideoPlayerController _controller;
  bool _showControls = true;
  Timer? _hideTimer;

  @override
  void initState() {
    super.initState();

    _controller = VideoPlayerController.network(widget.videoUrl)
      ..initialize().then((_) {
        if (!mounted) return;
        setState(() {});
        _controller.addListener(_onVideoTick);
      });
  }

  void _onVideoTick() {
    if (!mounted) return;
    setState(() {});
  }

  void _startHideTimer() {
    _hideTimer?.cancel();
    _hideTimer = Timer(const Duration(seconds: 2), () {
      if (mounted) setState(() => _showControls = false);
    });
  }

  void _toggleControls() {
    setState(() => _showControls = !_showControls);
    if (_showControls) _startHideTimer();
  }

  void _playPause() {
    setState(() {
      if (_controller.value.isPlaying) {
        _controller.pause();
        _showControls = true;
      } else {
        _controller.play();
        _showControls = true;
        _startHideTimer();
      }
    });
  }

  @override
  void dispose() {
    _hideTimer?.cancel();
    _controller.removeListener(_onVideoTick);
    _controller.dispose();
    super.dispose();
  }

  String _format(Duration d) {
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final isReady = _controller.value.isInitialized &&
        _controller.value.duration.inMilliseconds > 0;

    final backgroundColor = Colors.white;
    final iconColor = Colors.white;
    final textColor = Colors.grey.shade900;
    final accentColor = Colors.lightBlueAccent;
    final inactiveColor = Colors.grey.shade300;

    return Scaffold(
      backgroundColor: backgroundColor,
      body: SafeArea(
        child: GestureDetector(
          onTap: _toggleControls,
          child: Stack(
            alignment: Alignment.center,
            children: [
              /// VIDEO
              if (isReady)
                Center(
                  child: AspectRatio(
                    aspectRatio: _controller.value.aspectRatio,
                    child: VideoPlayer(_controller),
                  ),
                )
              else
                CircularProgressIndicator(color: accentColor),

              /// CENTER PLAY BUTTON
              if (_showControls && isReady)
                IconButton(
                  iconSize: 64,
                  icon: Icon(
                    _controller.value.isPlaying
                        ? Icons.pause_circle_filled
                        : Icons.play_circle_fill,
                    color: iconColor,
                  ),
                  onPressed: _playPause,
                ),

              /// TOP BAR
              if (_showControls)
                Positioned(
                  top: 12,
                  left: 12,
                  child: IconButton(
                    icon: Icon(Icons.close, color: iconColor),
                    onPressed: () => Navigator.pop(context),
                  ),
                ),

              /// BOTTOM CONTROLS
              if (_showControls && isReady)
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 16,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Slider(
                        min: 0,
                        max: _controller.value.duration.inMilliseconds.toDouble(),
                        value: _controller.value.position.inMilliseconds
                            .clamp(0, _controller.value.duration.inMilliseconds)
                            .toDouble(),
                        onChanged: (value) {
                          _controller.seekTo(
                            Duration(milliseconds: value.toInt()),
                          );
                        },
                        activeColor: accentColor,
                        inactiveColor: inactiveColor,
                      ),
                      Text(
                        '${_format(_controller.value.position)} / ${_format(_controller.value.duration)}',
                        style: TextStyle(color: textColor),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}