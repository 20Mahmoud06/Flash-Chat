import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';
import '../../../../core/utils/video_playback_url.dart';

/// The video surface itself: shows the Cloudinary poster frame while loading
/// and the live [VideoPlayer] once initialized. Covers the whole player area
/// and forwards taps (centered overlay / show controls) to [onTap].
class VideoPlayerStage extends StatelessWidget {
  final bool initialized;
  final String videoUrl;
  final VideoPlayerController? controller;
  final VoidCallback onTap;

  const VideoPlayerStage({
    super.key,
    required this.initialized,
    required this.videoUrl,
    required this.controller,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Stack(
        fit: StackFit.expand,
        children: [
          if (!initialized)
            CachedNetworkImage(
              imageUrl: videoThumbnailUrl(videoUrl),
              fit: BoxFit.cover,
              placeholder: (context, _) => Container(
                color: Colors.black87,
                child: const Center(
                  child: SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.lightBlueAccent,
                    ),
                  ),
                ),
              ),
              errorWidget: (context, error, stackTrace) => Container(
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
            VideoPlayer(controller!),
        ],
      ),
    );
  }
}