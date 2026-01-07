import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';
import '../widgets/custom_text.dart';

class MediaPreviewSheet extends StatefulWidget {
  final List<File> images;
  final File? video;
  final Function(String) onSend;

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
  final _captionController = TextEditingController();
  VideoPlayerController? _videoController;
  bool _isVideoInitialized = false;

  @override
  void initState() {
    super.initState();
    if (widget.video != null) {
      _videoController = VideoPlayerController.file(widget.video!)
        ..initialize().then((_) {
          if (mounted) {
            setState(() {
              _isVideoInitialized = true;
            });
          }
        }).catchError((e) {
          debugPrint("Error initializing video: $e");
        });
    }
  }

  @override
  void dispose() {
    _captionController.dispose();
    _videoController?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: MediaQuery.of(context).viewInsets,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Header
          Padding(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: Icon(Icons.close, color: Colors.grey.shade600),
                  onPressed: () => Navigator.pop(context),
                ),
                CustomText(
                  text: 'Preview',
                  fontWeight: FontWeight.bold,
                  fontSize: 18.sp,
                ),
                TextButton(
                  onPressed: () => widget.onSend(_captionController.text.trim()),
                  child: CustomText(
                    text: 'Send',
                    textColor: Colors.lightBlueAccent,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1.h),
          // Preview area
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                children: [
                  SizedBox(
                    height: 300.h,
                    child: widget.video != null
                        ? _buildVideoPreview()
                        : _buildImagesPreview(),
                  ),
                  // Caption input
                  Padding(
                    padding: EdgeInsets.all(12.w),
                    child: TextField(
                      controller: _captionController,
                      minLines: 1,
                      maxLines: 4,
                      decoration: InputDecoration(
                        hintText: 'Add a caption...',
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20.r),
                          borderSide: BorderSide.none,
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20.r),
                          borderSide: BorderSide(color: Colors.lightBlue.shade100, width: 1.5.w),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(20.r),
                          borderSide: BorderSide(color: Colors.lightBlue.shade300, width: 1.5.w),
                        ),
                        filled: true,
                        fillColor: Colors.grey.shade200,
                      ),
                      autofocus: false,
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildVideoPreview() {
    if (_videoController == null || !_isVideoInitialized) {
      return const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent));
    }
    return Stack(
      alignment: Alignment.center,
      children: [
        AspectRatio(
          aspectRatio: _videoController!.value.aspectRatio,
          child: VideoPlayer(_videoController!),
        ),
        IconButton(
          icon: Icon(
            _videoController!.value.isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
            size: 60.sp,
            color: Colors.white.withOpacity(0.8),
          ),
          onPressed: () {
            setState(() {
              if (_videoController!.value.isPlaying) {
                _videoController!.pause();
              } else {
                _videoController!.play();
              }
            });
          },
        ),
      ],
    );
  }

  Widget _buildImagesPreview() {
    if (widget.images.isEmpty) {
      return const Center(child: CustomText(text: 'No images selected'));
    }
    if (widget.images.length == 1) {
      return Image.file(
        widget.images.first,
        fit: BoxFit.contain,
        errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, color: Colors.red),
      );
    } else {
      return GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1,
          crossAxisSpacing: 4.w,
          mainAxisSpacing: 4.h,
        ),
        itemCount: widget.images.length,
        itemBuilder: (_, i) => Image.file(
          widget.images[i],
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => const Icon(Icons.error, color: Colors.red),
        ),
      );
    }
  }
}