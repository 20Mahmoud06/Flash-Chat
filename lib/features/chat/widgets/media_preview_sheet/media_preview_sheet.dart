import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import 'package:wechat_assets_picker/wechat_assets_picker.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_text.dart';
import '../media_preview_sheet/media_preview_caption_bar.dart';
import '../media_preview_sheet/media_preview_chrome.dart';
import '../media_preview_sheet/media_preview_photo_pager.dart';
import '../media_preview_sheet/media_preview_video.dart';

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
        const SnackBar(content: CustomText(text: 'Max 4 photos per message')),
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

  Future<void> _toggleVideoPlayback() async {
    final controller = _videoController;
    if (controller == null) return;
    if (controller.value.isPlaying) {
      await controller.pause();
      if (mounted) setState(() => _isVideoPlaying = false);
    } else {
      if (controller.value.position >= controller.value.duration) {
        await controller.seekTo(Duration.zero);
      }
      await controller.play();
      if (mounted) setState(() => _isVideoPlaying = true);
    }
  }

  /// Jumps the preview ±5 seconds, clamped to the video length.
  Future<void> _skipVideo(int seconds) async {
    final controller = _videoController;
    if (controller == null) return;
    final duration = controller.value.duration;
    final current = controller.value.position;
    var target = current + Duration(seconds: seconds);
    if (target < Duration.zero) target = Duration.zero;
    if (duration > Duration.zero && target > duration) target = duration;
    await controller.seekTo(target);
    if (mounted) setState(() {});
  }

  Future<void> _seekVideo(Duration target) async {
    final controller = _videoController;
    if (controller == null) return;
    await controller.seekTo(target);
    if (mounted) setState(() => _dragSliderValue = null);
  }

  Widget _buildPreviewArea() {
    if (_isVideo) {
      return Padding(
        padding: EdgeInsets.symmetric(horizontal: 12.w),
        child: MediaPreviewVideoPlayer(
          controller: _videoController,
          isInitialized: _isVideoInitialized,
          initFailed: _isVideoInitFailed,
          isPlaying: _isVideoPlaying,
          showControls: _showVideoControls,
          dragSliderValue: _dragSliderValue,
          onToggleControls: () =>
              setState(() => _showVideoControls = !_showVideoControls),
          onPlayPause: _toggleVideoPlayback,
          onSkip: _skipVideo,
          onSliderChanged: (value) => setState(() => _dragSliderValue = value),
          onSeek: _seekVideo,
        ),
      );
    }

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
                mediaCount: _mediaCount,
                maxCount: kMaxPhotosPerMessage,
                onTap: _addMorePhotos,
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