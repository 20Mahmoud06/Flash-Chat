import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../../../core/constants/media_limits.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_text.dart';
import '../../cubit/chat_cubit.dart';
import '../media_preview_sheet/media_preview_caption_bar.dart';
import '../media_preview_sheet/media_preview_chrome.dart';
import '../media_preview_sheet/media_preview_photo_pager.dart';
import '../media_preview_sheet/media_preview_video.dart';

export '../../../../core/constants/media_limits.dart';

const Duration _videoPreviewInitTimeout = Duration(seconds: 15);

class MediaPreviewSheet extends StatefulWidget {
  final List<File> images;
  final List<File> videos;
  final void Function(
    List<File> images,
    List<File> videos,
    String caption,
    List<int?> videoDurations,
  ) onSend;

  final List<int?>? initialVideoDurations;

  MediaPreviewSheet({
    super.key,
    this.images = const [],
    this.videos = const [],
    this.initialVideoDurations,
    required this.onSend,
  }) : assert(images.isNotEmpty || videos.isNotEmpty, 'Provide media');

  @override
  State<MediaPreviewSheet> createState() => _MediaPreviewSheetState();
}

class _MediaPreviewSheetState extends State<MediaPreviewSheet> {
  late final List<File> _images = List.of(widget.images);
  late final List<File> _videos = List.of(widget.videos);
  final _captionController = TextEditingController();
  final _pageController = PageController();

  final List<VideoPlayerController?> _videoControllers = [];
  final List<VoidCallback> _videoListeners = [];
  final List<bool> _videoInitialized = [];
  final List<bool> _videoInitFailed = [];
  final List<bool> _videoPlaying = [];
  final List<bool> _showVideoControls = [];
  final List<double?> _dragSliderValues = [];

  bool _isSending = false;
  int _currentIndex = 0;
  Timer? _releaseTimer;

  bool get _isVideo => _videos.isNotEmpty;
  int get _mediaCount => _isVideo ? _videos.length : _images.length;
  int get _maxCount => _isVideo ? kMaxVideosPerMessage : kMaxPhotosPerMessage;
  bool get _canAddMore => _mediaCount < _maxCount;

  void _noop() {}

  @override
  void initState() {
    super.initState();
    if (!_isVideo) return;
    for (var i = 0; i < _videos.length; i++) {
      _videoControllers.add(null);
      _videoListeners.add(_noop);
      _videoInitialized.add(false);
      _videoInitFailed.add(false);
      _videoPlaying.add(false);
      _showVideoControls.add(true);
      _dragSliderValues.add(null);
    }
    unawaited(_initializeVideoPreview(_currentIndex));
  }

  /// Only the page the user is looking at gets a decoder attached. Decoding
  /// every clip up front spins up one MediaCodec per video, which starves the
  /// UI thread (and the socket writes that the send depends on) on emulators.
  Future<void> _releaseVideoPreview(int index) async {
    if (index < 0 || index >= _videoControllers.length) return;
    final controller = _videoControllers[index];
    if (controller != null) {
      controller.removeListener(_videoListeners[index]);
    }
    _videoControllers[index] = null;
    _videoListeners[index] = _noop;
    _videoInitialized[index] = false;
    _videoInitFailed[index] = false;
    _videoPlaying[index] = false;
    _dragSliderValues[index] = null;
    if (controller != null) {
      await controller.dispose();
    }
  }

  Future<void> _initializeVideoPreview(int index) async {
    if (index < 0 || index >= _videos.length) return;
    final video = _videos[index];
    final controller = VideoPlayerController.file(video);
    void listener() => _onVideoUpdate(index);
    _videoControllers[index] = controller;
    _videoListeners[index] = listener;
    controller.addListener(listener);

    try {
      await controller.initialize().timeout(_videoPreviewInitTimeout);
      if (!mounted || index >= _videoControllers.length) {
        await controller.dispose();
        return;
      }
      if (_videoControllers[index] != controller) {
        await controller.dispose();
        return;
      }
      setState(() {
        _videoInitialized[index] = true;
        _videoInitFailed[index] = false;
      });
    } catch (e) {
      debugPrint('Error initializing video preview: $e');
      if (!mounted || index >= _videoControllers.length) return;
      if (_videoControllers[index] != controller) {
        await controller.dispose();
        return;
      }
      controller.removeListener(listener);
      await controller.dispose();
      if (!mounted) return;
      setState(() {
        _videoControllers[index] = null;
        _videoInitialized[index] = false;
        _videoInitFailed[index] = true;
      });
    }
  }

  void _onVideoUpdate(int index) {
    if (!mounted || index >= _videoControllers.length) return;
    final controller = _videoControllers[index];
    if (controller == null || !controller.value.isInitialized) return;
    final value = controller.value;
    final isPlaying = value.isPlaying;
    final completed = value.duration > Duration.zero &&
        value.position >= value.duration &&
        !isPlaying;
    if (completed && _videoPlaying[index]) {
      setState(() {
        _videoPlaying[index] = false;
        _showVideoControls[index] = true;
      });
      return;
    }
    if (isPlaying != _videoPlaying[index]) {
      setState(() {
        _videoPlaying[index] = isPlaying;
      });
    }
  }

  @override
  void dispose() {
    _releaseTimer?.cancel();
    _captionController.dispose();
    _pageController.dispose();
    for (var i = 0; i < _videoControllers.length; i++) {
      final controller = _videoControllers[i];
      if (controller == null) continue;
      controller.removeListener(_videoListeners[i]);
      controller.dispose();
    }
    super.dispose();
  }

  void _send() {
    if (_isSending) return;
    final videoDurations = <int?>[];
    for (var i = 0; i < _videos.length; i++) {
      final controller =
          i < _videoControllers.length ? _videoControllers[i] : null;
      final duration = controller?.value;
      final controllerDuration = (duration != null &&
              duration.isInitialized &&
              duration.duration > Duration.zero)
          ? duration.duration.inSeconds
          : null;
      final initialDuration = (widget.initialVideoDurations != null &&
              i < widget.initialVideoDurations!.length)
          ? widget.initialVideoDurations![i]
          : null;
      videoDurations.add(controllerDuration ?? initialDuration);
    }
    setState(() => _isSending = true);
    widget.onSend(
      _images,
      _videos,
      _captionController.text.trim(),
      videoDurations,
    );
  }

  Future<void> _addMorePhotos() async {
    final remaining = _maxCount - _images.length;
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
    if (assets == null || assets.isEmpty || !mounted) return;

    final added = <File>[];
    for (final asset in assets) {
      final file = (await asset.originFile) ?? (await asset.file);
      if (file != null) added.add(file);
    }
    if (!mounted || added.isEmpty) return;

    setState(() => _images.addAll(added));
  }

  Future<void> _addMoreVideos() async {
    final remaining = _maxCount - _videos.length;
    if (remaining <= 0) {
      _showLimitReached();
      return;
    }

    final colors = FcAppColors.of(context);
    final assets = await AssetPicker.pickAssets(
      context,
      pickerConfig: AssetPickerConfig(
        maxAssets: remaining,
        requestType: RequestType.video,
        themeColor: colors.bubbleMine,
      ),
    );
    if (assets == null || assets.isEmpty || !mounted) return;

    final added = <File>[];
    for (final asset in assets) {
      final file = (await asset.originFile) ?? (await asset.file);
      if (file == null) continue;
      try {
        if (await file.exists() &&
            await file.length() <= ChatCubit.maxFileSizeBytes) {
          added.add(file);
        }
      } catch (e) {
        debugPrint('Could not read selected video: $e');
      }
    }
    if (!mounted || added.isEmpty) return;

    setState(() {
      _videos.addAll(added);
      for (var i = 0; i < added.length; i++) {
        _videoControllers.add(null);
        _videoListeners.add(_noop);
        _videoInitialized.add(false);
        _videoInitFailed.add(false);
        _videoPlaying.add(false);
        _showVideoControls.add(true);
        _dragSliderValues.add(null);
      }
    });
    // Appended clips stay undecoded until the pager lands on them.
  }

  void _showLimitReached() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: CustomText(
            text: _isVideo
                ? 'Max $kMaxVideosPerMessage videos per message'
                : 'Max $kMaxPhotosPerMessage photos per message',
          ),
        ),
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

  void _removeVideo(int index) {
    if (index < 0 || index >= _videos.length) return;
    final controller = _videoControllers[index];
    controller?.removeListener(_videoListeners[index]);
    controller?.dispose();
    _videoControllers.removeAt(index);
    _videoListeners.removeAt(index);
    _videoInitialized.removeAt(index);
    _videoInitFailed.removeAt(index);
    _videoPlaying.removeAt(index);
    _showVideoControls.removeAt(index);
    _dragSliderValues.removeAt(index);
    _videos.removeAt(index);

    if (_videos.isEmpty) {
      Navigator.pop(context);
      return;
    }

    final nextIndex = index < _videos.length ? index : _videos.length - 1;
    _releaseTimer?.cancel();
    setState(() {
      _currentIndex = nextIndex;
    });
    if (_videoControllers[nextIndex] == null) {
      unawaited(_initializeVideoPreview(nextIndex));
    }
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pageController.hasClients) return;
      _pageController.jumpToPage(_currentIndex);
    });
  }

  Future<void> _toggleVideoPlayback(int index) async {
    final controller = _videoControllers[index];
    if (controller == null) return;
    for (var i = 0; i < _videoControllers.length; i++) {
      if (i == index) continue;
      final other = _videoControllers[i];
      if (other?.value.isPlaying == true) {
        await other?.pause();
        if (mounted) setState(() => _videoPlaying[i] = false);
      }
    }
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) setState(() => _videoPlaying[index] = false);
    } else {
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      if (mounted) setState(() => _videoPlaying[index] = true);
    }
  }

  Future<void> _skipVideo(int index, int seconds) async {
    final controller = _videoControllers[index];
    if (controller == null) return;
    final duration = controller.value.duration;
    final current = controller.value.position;
    var target = current + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await controller.seekTo(target);
    if (mounted) setState(() {});
  }

  Future<void> _seekVideo(int index, Duration target) async {
    final controller = _videoControllers[index];
    if (controller == null) return;
    await controller.seekTo(target);
    if (mounted) setState(() => _dragSliderValues[index] = null);
  }

  void _onVideoPageChanged(int index) {
    final previous = _currentIndex;
    _releaseTimer?.cancel();
    if (previous != index) {
      final controller = _videoControllers[previous];
      if (controller?.value.isPlaying == true) {
        controller?.pause();
      }
    }
    setState(() {
      _currentIndex = index;
      _showVideoControls[index] = true;
      _dragSliderValues[index] = null;
    });
    if (_videoControllers[index] == null) {
      unawaited(_initializeVideoPreview(index));
    }
    if (previous != index) {
      // Let the swipe finish before dropping the outgoing decoder, otherwise
      // the page being dragged away flashes its loading placeholder.
      _releaseTimer = Timer(const Duration(milliseconds: 300), () {
        if (!mounted || previous == _currentIndex) return;
        unawaited(_releaseVideoPreview(previous));
      });
    }
  }

  Widget _buildVideoPager() {
    final colors = FcAppColors.of(context);
    return Stack(
      children: [
        PageView.builder(
          controller: _pageController,
          itemCount: _videos.length,
          onPageChanged: _onVideoPageChanged,
          itemBuilder: (context, index) => MediaPreviewVideoPlayer(
            controller: _videoControllers[index],
            isInitialized: _videoInitialized[index],
            initFailed: _videoInitFailed[index],
            isPlaying: _videoPlaying[index],
            showControls: _showVideoControls[index],
            dragSliderValue: _dragSliderValues[index],
            onRemove: () => _removeVideo(index),
            onToggleControls: () => setState(() {
              _showVideoControls[index] = !_showVideoControls[index];
            }),
            onPlayPause: () => _toggleVideoPlayback(index),
            onSkip: (seconds) => _skipVideo(index, seconds),
            onSliderChanged: (value) => setState(() {
              _dragSliderValues[index] = value;
            }),
            onSeek: (target) => _seekVideo(index, target),
          ),
        ),
        if (_videos.length > 1) ...[
          Positioned(
            top: 10,
            left: 0,
            right: 0,
            child: Center(
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 5.h),
                decoration: BoxDecoration(
                  color: colors.surface.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: colors.divider),
                ),
                child: CustomText(
                  text: '${_currentIndex + 1}/${_videos.length}',
                  textColor: colors.textPrimary,
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ),
          ),
          Positioned(
            bottom: 10,
            left: 0,
            right: 0,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_videos.length, (i) {
                final active = i == _currentIndex;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: EdgeInsets.symmetric(horizontal: 3.w),
                  width: active ? 18.w : 6.w,
                  height: 6,
                  decoration: BoxDecoration(
                    color: active ? colors.bubbleMine : colors.surfaceDim,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildPreviewArea() {
    if (_isVideo) return _buildVideoPager();

    return Padding(
      padding: _mediaCount == 1
          ? EdgeInsets.symmetric(horizontal: 12.w)
          : EdgeInsets.zero,
      child: MediaPreviewPhotoPager(
        images: _images,
        currentIndex: _currentIndex,
        pageController: _pageController,
        onPageChanged: (index) => setState(() => _currentIndex = index),
        onRemove: _removePhoto,
      ),
    );
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
            const MediaPreviewDragHandle(),
            MediaPreviewHeader(
              isVideo: _isVideo,
              mediaCount: _mediaCount,
              currentIndex: _currentIndex,
              onBack: () => Navigator.pop(context),
            ),
            if (_canAddMore)
              MediaPreviewAddMoreButton(
                isVideo: _isVideo,
                mediaCount: _mediaCount,
                maxCount: _maxCount,
                onTap: _isVideo ? _addMoreVideos : _addMorePhotos,
              ),
            const SizedBox(height: 8),
            Expanded(child: _buildPreviewArea()),
            MediaPreviewCaptionBar(
              captionController: _captionController,
              isSending: _isSending,
              onSend: _send,
            ),
          ],
        ),
      ),
    );
  }
}
