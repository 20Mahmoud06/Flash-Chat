import 'package:flash_chat_app/core/utils/full_video_viewer.dart';
import 'package:flash_chat_app/core/utils/video_playback_url.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'media_gallery_helpers.dart';

/// 3-column video grid; each tile shows a poster thumbnail with a play icon
/// badge and optional duration chip, opening [FullVideoViewer] on tap.
class MediaGalleryVideosTab extends StatelessWidget {
  final List<MessageModel> messages;

  const MediaGalleryVideosTab({super.key, required this.messages});

  @override
  Widget build(BuildContext context) {
    final videos = messages
        .where((m) => m.messageType == MessageType.video && m.mediaUrls != null)
        .toList();
    if (videos.isEmpty) {
      return const MediaGalleryEmptyState(
        label: 'No videos',
        icon: Icons.videocam_outlined,
      );
    }
    return GridView.builder(
      padding: EdgeInsets.all(2.w),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: videos.length,
      itemBuilder: (context, i) {
        final video = videos[i];
        final url = video.mediaUrls!.first;
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => FullVideoViewer(
                  videoUrl: url,
                  initialDuration: video.videoDuration != null
                      ? Duration(seconds: video.videoDuration!)
                      : null,
                ),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                videoThumbnailUrl(url),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Container(
                        color: Colors.black26,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.lightBlueAccent,
                            ),
                          ),
                        ),
                      ),
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.black38,
                  child: const Center(
                    child: Icon(Icons.videocam_outlined,
                        color: Colors.white70, size: 30),
                  ),
                ),
              ),
              const Center(
                child:
                    Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
              ),
              if (video.videoDuration != null)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: CustomText(
                      text: formatGalleryDuration(video.videoDuration!),
                      textColor: Colors.white,
                      fontSize: 11,
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}