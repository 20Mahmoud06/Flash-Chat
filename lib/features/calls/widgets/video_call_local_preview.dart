import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'video_call_video_views.dart';

/// Small rounded local-camera preview shown in the corner of a 1-on-1 video
/// call. Shows my avatar ("You (Off)") when the camera is switched off.
class VideoCallLocalPreview extends StatelessWidget {
  final RtcEngine engine;
  final bool isCameraOff;
  final String? ownAvatar;
  final double topOffset;

  const VideoCallLocalPreview({
    super.key,
    required this.engine,
    required this.isCameraOff,
    this.ownAvatar,
    required this.topOffset,
  });

  @override
  Widget build(BuildContext context) {
    return Positioned(
      right: 16,
      top: topOffset,
      width: 110,
      height: 150,
      child: Container(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.25),
            width: 1.5,
          ),
          boxShadow: const [
            BoxShadow(
              color: Colors.black45,
              blurRadius: 16,
              spreadRadius: 2,
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(15),
          child: Container(
            color: AppColors.callOverlay,
            child: isCameraOff
                ? Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        CustomText(
                          text: ownAvatar ?? '👤',
                          fontSize: 34,
                        ),
                        const SizedBox(height: 6),
                        const CustomText(
                          text: 'You (Off)',
                          textColor: Colors.white60,
                          fontSize: 11,
                        ),
                      ],
                    ),
                  )
                : buildLocalVideoView(engine),
          ),
        ),
      ),
    );
  }
}
