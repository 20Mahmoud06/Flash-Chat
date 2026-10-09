import 'package:cached_network_image/cached_network_image.dart';
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
    final videos = <_GalleryVideo>[];
    for (final message in messages) {
      if (message.messageType != MessageType.video) continue;
      final urls = message.mediaUrls ?? [];
      for (var i = 0; i < urls.length; i++) {
        videos.add(_GalleryVideo(
          url: urls[i],
          durationSeconds: message.videoDurationAt(i),
        ));
      }
    }
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
        return GestureDetector(
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                fullscreenDialog: true,
                builder: (_) => FullVideoViewer(
                  videoUrl: video.url,
                  initialDuration: video.durationSeconds != null
                      ? Duration(seconds: video.durationSeconds!)
                      : null,
                ),
              ),
            );
          },
          child: Stack(
            fit: StackFit.expand,
            children: [
              CachedNetworkImage(
                imageUrl: videoThumbnailUrl(video.url),
                fit: BoxFit.cover,
                placeholder: (context, _) => Container(
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
                errorWidget: (context, error, stackTrace) => Container(
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
              if (video.durationSeconds != null)
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
                      text: formatGalleryDuration(video.durationSeconds!),
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

class _GalleryVideo {
  final String url;
  final int? durationSeconds;

  const _GalleryVideo({required this.url, this.durationSeconds});
}
