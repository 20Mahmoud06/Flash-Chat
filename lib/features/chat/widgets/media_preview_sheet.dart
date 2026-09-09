import 'dart:async';
import 'dart:io';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

/// Maximum number of photos allowed in a single message.
const int kMaxPhotosPerMessage = 4;
const Duration _videoPreviewInitTimeout = Duration(seconds: 15);

class MediaPreviewSheet extends StatefulWidget {
  final List<File> images;
  final File? video;
  final void Function(
      List<File> images, String caption, Duration? videoDuration) onSend;

  MediaPreviewSheet({
    super.key,
    this.images = const [],
    this.video,
    required this.onSend,
  }) : assert(images.isNotEmpty || video != null, 'Provide images or video');

  @override
  State<MediaPreviewSheet> createState() => _MediaPreviewSheetState();
}

class _MediaPreviewSheetState extends State<MediaPreviewSheet> {
  late final List<File> _images = List.of(widget.images);
  final _captionController = TextEditingController();
  final _pageController = PageController();

  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;
  bool _isVideoInitFailed = false;
  bool _isSending = false;

  int _currentIndex = 0;
  bool _isVideoPlaying = false;
  bool _showVideoControls = true;

  double? _dragSliderValue;
  bool _wasPlayingBeforeSeek = false;

  bool get _isVideo => widget.video != null;
  int get _mediaCount => _isVideo ? 1 : _images.length;
  bool get _canAddMore => !_isVideo && _mediaCount < kMaxPhotosPerMessage;

  @override
  void initState() {
    super.initState();
    if (widget.video != null) {
      unawaited(_initializeVideoPreview());
    }
  }

  Future<void> _initializeVideoPreview() async {
    final video = widget.video;
    if (video == null) return;

    final controller = VideoPlayerController.file(video)
      ..addListener(_onVideoUpdate);
    _videoController = controller;

    try {
      await controller.initialize().timeout(_videoPreviewInitTimeout);
      if (!mounted || _videoController != controller) return;
      setState(() => _isVideoInitialized = true);
    } catch (e) {
      debugPrint('Error initializing video preview: $e');
      if (!mounted || _videoController != controller) return;
      controller.removeListener(_onVideoUpdate);
      await controller.dispose();
      if (!mounted || _videoController != controller) return;
      setState(() {
        _videoController = null;
        _isVideoInitialized = false;
        _isVideoInitFailed = true;
      });
    }
  }

  void _onVideoUpdate() {
    if (!mounted || _videoController == null) return;
    final value = _videoController!.value;
    if (!value.isInitialized) return;

    final isPlaying = value.isPlaying;
    final duration = value.duration;
    final position = value.position;
    final isCompleted =
        duration > Duration.zero && position >= duration && !isPlaying;

    if (isCompleted) {
      if (_isVideoPlaying) {
        setState(() {
          _isVideoPlaying = false;
          _showVideoControls = true;
        });
      }
      return;
    }

    if (isPlaying != _isVideoPlaying || isPlaying) {
      setState(() {
        _isVideoPlaying = isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _pageController.dispose();
    _videoController?.removeListener(_onVideoUpdate);
    _videoController?.dispose();
    super.dispose();
  }

  void _send() {
    if (_isSending) return;
    Duration? videoDuration;
    final controller = _videoController;
    if (controller != null &&
        controller.value.isInitialized &&
        controller.value.duration > Duration.zero) {
      videoDuration = controller.value.duration;
    }
    setState(() => _isSending = true);
    widget.onSend(_images, _captionController.text.trim(), videoDuration);
  }

  /// Adds more photos from the gallery to the current selection.
  /// The total is capped at [kMaxPhotosPerMessage] (4 photos per message).
  Future<void> _addMorePhotos() async {
    final remaining = kMaxPhotosPerMessage - _images.length;
    if (remaining <= 0) {
      _showLimitReached();
      return;
    }

    final colors = FcAppColors.of(context);
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: remaining,
        requestType: RequestType.image,
        themeColor: colors.bubbleMine,
      ),
    );
    if (assets == null || assets.isEmpty) return;

    final added = <File>[];
    for (final asset in assets) {
      final file = (await asset.originFile) ?? (await asset.file);
      if (file != null) added.add(file);
    }
    if (!mounted || added.isEmpty) return;

    setState(() {
      _images.addAll(added);
    });
  }

  void _showLimitReached() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        const SnackBar(content: Text('Max 4 photos per message')),
      );
  }

  String _formatDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      height: MediaQuery.of(context).size.height * 0.92,
      padding: MediaQuery.of(context).viewInsets,
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          children: [
            _buildDragHandle(),
            _buildHeader(),
            if (_canAddMore) _buildAddMoreButton(),
            const SizedBox(height: 8),
            Expanded(child: _buildPreviewArea()),
            _buildCaptionBar(),
          ],
        ),
      ),
    );
  }

  // ================================
  // ➕ ADD MORE PHOTOS
  // ================================
  Widget _buildAddMoreButton() {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
      child: GestureDetector(
        onTap: _addMorePhotos,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.add_photo_alternate_outlined,
                color: Color(0xFF0288D1),
                size: 18,
              ),
              SizedBox(width: 6.w),
              Text(
                'Add More Photos',
                style: TextStyle(
                  color: const Color(0xFF0288D1),
                  fontSize: 13.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
              SizedBox(width: 6.w),
              Text(
                '$_mediaCount/$kMaxPhotosPerMessage',
                style: TextStyle(
                  color: colors.textWeak,
                  fontSize: 12.sp,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ================================
  // 🔘 DRAG HANDLE
  // ================================
  Widget _buildDragHandle() {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 10.h, bottom: 6.h),
      child: Container(
        width: 40.w,
        height: 4,
        decoration: BoxDecoration(
          color: colors.surfaceDim,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  // ================================
  // 🧭 HEADER
  // ================================
  Widget _buildHeader() {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        children: [
          _CircleButton(
            size: 34,
            icon: Icons.arrow_back_rounded,
            iconColor: colors.textPrimary,
            backgroundColor: colors.inputFill,
            onTap: () => Navigator.pop(context),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _isVideo ? 'Video Preview' : 'Photo Preview',
                  style: TextStyle(
                    color: colors.textPrimary,
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 2.h),
                Text(
                  _isVideo
                      ? 'Ready to send'
                      : _mediaCount > 1
                          ? '${_currentIndex + 1} of $_mediaCount selected'
                          : '1 photo, ready to send',
                  style: TextStyle(
                    color: colors.textSecondary,
                    fontSize: 12.sp,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSendButton() {
    return GestureDetector(
      onTap: _send,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [Color(0xFF4FC3F7), Color(0xFF0288D1)],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: const Color(0xFF0288D1).withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: _isSending
            ? const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 24,
              ),
      ),
    );
  }

  // ================================
  // 🖼️ PREVIEW AREA
  // ================================
  Widget _buildPreviewArea() {
    final colors = FcAppColors.of(context);
    if (_isVideo) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        child: _buildVideoPreview(),
      );
    }

    if (_mediaCount == 1) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        child: _buildImageTile(0),
      );
    }

    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: _mediaCount,
          onPageChanged: (index) => setState(() => _currentIndex = index),
          itemBuilder: (context, index) => _buildImageTile(index),
        ),
        // Count badge
        Positioned(
          top: 10,
          right: 16,
          child: Container(
            padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
            decoration: BoxDecoration(
              color: colors.surface.withValues(alpha: 0.92),
              borderRadius: BorderRadius.circular(20),
              border: Border.all(color: colors.divider),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.08),
                  blurRadius: 8,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Text(
              '${_currentIndex + 1}/$_mediaCount',
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 12.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ),
        // Dots
        Positioned(
          bottom: 10,
          left: 0,
          right: 0,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: List.generate(_mediaCount, (i) {
              final active = i == _currentIndex;
              return AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                margin: EdgeInsets.symmetric(horizontal: 3.w),
                width: active ? 18.w : 6.w,
                height: 6,
                decoration: BoxDecoration(
                  color: active ? const Color(0xFF0288D1) : colors.surfaceDim,
                  borderRadius: BorderRadius.circular(3),
                ),
              );
            }),
          ),
        ),
      ],
    );
  }

  void _removePhoto(int index) {
    if (index < 0 || index >= _images.length) return;
    setState(() {
      _images.removeAt(index);
      if (_images.isEmpty) {
        Navigator.pop(context);
        return;
      }
      if (_currentIndex >= _images.length) {
        _currentIndex = _images.length - 1;
      }
    });
  }

  Widget _buildImageTile(int index) {
    return Container(
      width: double.infinity,
      height: double.infinity,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          InteractiveViewer(
            minScale: 1.0,
            maxScale: 4.0,
            child: SizedBox.expand(
              child: Image.file(
                _images[index],
                fit: BoxFit.contain,
                errorBuilder: (context, error, stackTrace) => Icon(
                  Icons.broken_image_outlined,
                  color: FcAppColors.of(context).textWeak,
                  size: 56,
                ),
              ),
            ),
          ),
          Positioned(
            top: 12.h,
            left: 12.w,
            child: GestureDetector(
              onTap: () => _removePhoto(index),
              child: Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1,
                  ),
                  boxShadow: const [
                    BoxShadow(
                      color: Colors.black38,
                      blurRadius: 6,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                child: const Icon(
                  Icons.close_rounded,
                  color: Colors.white,
                  size: 20,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ================================
  // 🎬 VIDEO PREVIEW
  // ================================
  Widget _buildVideoPreview() {
    if (_isVideoInitFailed) {
      return _buildVideoPreviewFallback();
    }

    if (_videoController == null || !_isVideoInitialized) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: FcAppColors.of(context).surfaceMuted,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: Color(0xFF0288D1)),
        ),
      );
    }

    final controller = _videoController!;
    final duration = controller.value.duration;
    final position = controller.value.position;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20.r),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _showVideoControls = !_showVideoControls),
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // Video keeps its native aspect ratio (landscape or portrait):
              // centered, never cropped or stretched, with a rounded frame.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              ),
              // Buffering indicator while loading during playback, never at EOF.
              if (controller.value.isBuffering &&
                  !(duration > Duration.zero && position >= duration))
                const Center(
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: Color(0xFF4FC3F7),
                    ),
                  ),
                ),
              // Decorative gradient overlay for visibility
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.4),
                      ],
                    ),
                  ),
                ),
              ),
              // Play / Pause
              if (_showVideoControls) ...[
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _CircleButton(
                        size: 48,
                        icon: Icons.replay_5_rounded,
                        iconSize: 26,
                        iconColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        onTap: () => _skipVideo(controller, seconds: -5),
                      ),
                      SizedBox(width: 18.w),
                      _CircleButton(
                        size: 62,
                        icon: _isVideoPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        iconSize: 34,
                        iconColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        onTap: () async {
                          if (controller.value.isPlaying) {
                            await controller.pause();
                            if (mounted) {
                              setState(() => _isVideoPlaying = false);
                            }
                          } else {
                            if (controller.value.position >=
                                controller.value.duration) {
                              await controller.seekTo(Duration.zero);
                            }
                            await controller.play();
                            if (mounted) setState(() => _isVideoPlaying = true);
                          }
                        },
                      ),
                      SizedBox(width: 18.w),
                      _CircleButton(
                        size: 48,
                        icon: Icons.forward_5_rounded,
                        iconSize: 26,
                        iconColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        onTap: () => _skipVideo(controller, seconds: 5),
                      ),
                    ],
                  ),
                ),
                // Top: video chip
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        Text(
                          'VIDEO',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 1.2,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                // Bottom row: time + progress
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            _formatDuration(
                              _dragSliderValue != null
                                  ? Duration(
                                      milliseconds: _dragSliderValue!.round())
                                  : position,
                            ),
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            _formatDuration(duration),
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 11.sp,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _buildVideoSlider(controller),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildVideoPreviewFallback() {
    final colors = FcAppColors.of(context);
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_outlined,
              color: Colors.white70,
              size: 52,
            ),
            SizedBox(height: 12.h),
            Text(
              'Preview unavailable on this phone',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: Colors.white,
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
              ),
            ),
            SizedBox(height: 6.h),
            Text(
              'You can still send it. The chat video will be converted for playback.',
              textAlign: TextAlign.center,
              style: TextStyle(
                color: colors.textWeak,
                fontSize: 12.sp,
                height: 1.3,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Jumps the preview ±5 seconds, clamped to the video length.
  Future<void> _skipVideo(VideoPlayerController controller,
      {required int seconds}) async {
    final duration = controller.value.duration;
    final current = controller.value.position;
    var target = current + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await controller.seekTo(target);
    if (mounted) setState(() {});
  }

  Widget _buildVideoSlider(VideoPlayerController controller) {
    final durationMs = controller.value.duration.inMilliseconds;
    if (durationMs <= 0) {
      return const SizedBox(height: 24);
    }

    final positionMs =
        controller.value.position.inMilliseconds.clamp(0, durationMs);
    final valueMs = _dragSliderValue ?? positionMs.toDouble();

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: const Color(0xFF4FC3F7),
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayColor: const Color(0xFF4FC3F7).withValues(alpha: 0.25),
        tickMarkShape: const RoundSliderTickMarkShape(),
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
      ),
      child: Slider(
        value: valueMs.clamp(0, durationMs.toDouble()),
        max: durationMs.toDouble(),
        onChangeStart: (_) {
          _wasPlayingBeforeSeek = controller.value.isPlaying;
          controller.pause();
        },
        onChanged: (value) {
          setState(() => _dragSliderValue = value);
        },
        onChangeEnd: (value) async {
          final target = Duration(milliseconds: value.round());
          await controller.seekTo(target);
          if (mounted) {
            setState(() => _dragSliderValue = null);
            if (_wasPlayingBeforeSeek && target < controller.value.duration) {
              controller.play();
            }
          }
        },
      ),
    );
  }

  // ================================
  // 📝 CAPTION BAR
  // ================================
  Widget _buildCaptionBar() {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(26.r),
          border: Border.all(color: colors.divider),
        ),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _captionController,
                minLines: 1,
                maxLines: 3,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                ),
                cursorColor: const Color(0xFF0288D1),
                decoration: InputDecoration(
                  hintText: 'Add a caption...',
                  hintStyle: TextStyle(color: colors.textWeak),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            const SizedBox(width: 8),
            _buildSendButton(),
          ],
        ),
      ),
    );
  }
}

// ================================
// 🔘 REUSABLE CIRCLE BUTTON
// ================================
class _CircleButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final Color backgroundColor;
  final VoidCallback onTap;

  const _CircleButton({
    required this.size,
    required this.icon,
    this.iconSize = 18,
    required this.iconColor,
    required this.backgroundColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }
}
