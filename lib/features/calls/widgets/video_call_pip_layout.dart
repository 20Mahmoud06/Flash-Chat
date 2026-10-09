import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'video_call_video_views.dart';

/// Compact Picture-in-Picture layout: the full call UI (header bar,
/// big controls, local preview) overflows in the small PiP window, so
/// this shows only the video plus small end / mute / switch-camera buttons.
class VideoCallPipLayout extends StatelessWidget {
  final String displayName;
  final String? avatarEmoji;
  final String? ownAvatar;
  final bool isGroup;
  final RtcEngine? engine;
  final bool isEngineReady;
  final String channelName;
  final List<int> remoteUids;
  final Set<int> mutedRemoteUids;
  final bool isCameraOff;
  final bool isMuted;
  final VoidCallback? onToggleMute;
  final VoidCallback? onSwitchCamera;
  final VoidCallback onEndCall;

  const VideoCallPipLayout({
    super.key,
    required this.displayName,
    this.avatarEmoji,
    this.ownAvatar,
    required this.isGroup,
    this.engine,
    required this.isEngineReady,
    required this.channelName,
    required this.remoteUids,
    required this.mutedRemoteUids,
    required this.isCameraOff,
    required this.isMuted,
    this.onToggleMute,
    this.onSwitchCamera,
    required this.onEndCall,
  });

  @override
  Widget build(BuildContext context) {
    Widget placeholder(String emoji) => ColoredBox(
          color: AppColors.callPageBackground,
          child: Center(
            child: CustomText(text: emoji, fontSize: 34),
          ),
        );

    Widget video;
    if (!isEngineReady || engine == null || remoteUids.isEmpty) {
      video = placeholder(avatarEmoji ?? '👤');
    } else if (!isGroup && remoteUids.length == 1) {
      video = mutedRemoteUids.contains(remoteUids[0])
          ? placeholder(avatarEmoji ?? '👤')
          : buildRemoteVideoView(engine!, remoteUids[0], channelName);
    } else {
      video = isCameraOff
          ? placeholder(ownAvatar ?? '👤')
          : buildLocalVideoView(engine!);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          video,
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: CustomText(
                    text: displayName,
                    textColor: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.w500,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ),
            ),
          ),
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      VideoCallPipButton(
                        icon:
                            isMuted ? Icons.mic_off_rounded : Icons.mic_rounded,
                        iconColor: isMuted ? Colors.amber : Colors.white,
                        backgroundColor: Colors.transparent,
                        onTap: isEngineReady ? onToggleMute : null,
                      ),
                      const SizedBox(width: 4),
                      VideoCallPipButton(
                        icon: Icons.call_end_rounded,
                        backgroundColor: Colors.red.shade600,
                        size: 40,
                        onTap: onEndCall,
                      ),
                      const SizedBox(width: 4),
                      VideoCallPipButton(
                        icon: Icons.cameraswitch_rounded,
                        backgroundColor: Colors.transparent,
                        onTap: (isEngineReady && !isCameraOff)
                            ? onSwitchCamera
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Small round button used in the PiP window (end call / mute / switch
/// camera). Disabled ([onTap] null) renders dimmed.
class VideoCallPipButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final double size;
  final VoidCallback? onTap;

  const VideoCallPipButton({
    super.key,
    required this.icon,
    this.iconColor = Colors.white,
    required this.backgroundColor,
    this.size = 34,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? backgroundColor
              : backgroundColor.withValues(alpha: 0.35),
        ),
        child: Icon(
          icon,
          color: enabled ? iconColor : Colors.white54,
          size: size * 0.52,
        ),
      ),
    );
  }
}
