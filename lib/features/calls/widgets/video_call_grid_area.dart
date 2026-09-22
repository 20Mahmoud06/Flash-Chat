import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import '../services/call_avatar_loader.dart';
import 'animated_call_grid.dart';
import 'video_call_avatar_placeholder.dart';
import 'video_call_video_views.dart';

/// Full-screen group-call participant grid: tiles are computed from the
/// screen bounds so they fill all the available surface (no giant black
/// letterbox) and animate smoothly when someone joins / leaves.
class VideoCallGridArea extends StatelessWidget {
  final RtcEngine engine;
  final String channelName;
  final List<int> uids;
  final Map<int, CallParticipantInfo> participants;
  final Set<int> speakingUids;
  final Set<int> mutedRemoteUids;
  final Set<int> mutedRemoteAudioUids;
  final bool isCameraOff;
  final String? ownAvatar;

  const VideoCallGridArea({
    super.key,
    required this.engine,
    required this.channelName,
    required this.uids,
    required this.participants,
    required this.speakingUids,
    required this.mutedRemoteUids,
    required this.mutedRemoteAudioUids,
    required this.isCameraOff,
    this.ownAvatar,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(
          top: 60,
          left: 8,
          right: 8,
          bottom: 8,
        ),
        child: AnimatedCallGrid(
          uids: uids,
          spacing: 6,
          itemBuilder: (context, uid) {
            Widget content;
            String participantName;
            final bool isSpeaking = speakingUids.contains(uid);
            // Crop fills each tile edge-to-edge (WhatsApp look); Fit would
            // letterbox the video inside it.
            const tileRenderMode = RenderModeType.renderModeHidden;

            if (uid == 0) {
              participantName = "You";
              if (isCameraOff) {
                content = VideoCallAvatarPlaceholder(
                  displayName: participantName,
                  avatarEmoji: ownAvatar,
                  statusText: "Camera off",
                  isCompact: true,
                );
              } else {
                content = buildLocalVideoView(
                  engine,
                  renderMode: tileRenderMode,
                );
              }
            } else {
              final info = participants[uid];
              participantName = info?.name ?? "Participant $uid";
              if (mutedRemoteUids.contains(uid)) {
                content = VideoCallAvatarPlaceholder(
                  displayName: participantName,
                  avatarEmoji: info?.avatarEmoji,
                  statusText: "Camera off",
                  isCompact: true,
                );
              } else {
                content = buildRemoteVideoView(
                  engine,
                  uid,
                  channelName,
                  renderMode: tileRenderMode,
                );
              }
            }

            return Stack(
              children: [
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Container(
                      decoration: BoxDecoration(
                        border: Border.all(
                          color: isSpeaking
                              ? AppColors.speakingBorder
                              : Colors.transparent,
                          width: 3,
                        ),
                      ),
                      child: Container(
                        color: AppColors.callOverlay,
                        child: content,
                      ),
                    ),
                  ),
                ),
                // Speaking indicator badge (green mic)
                if (isSpeaking)
                  Positioned(
                    top: 8,
                    left: 8,
                    child: Container(
                      padding: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                        color: AppColors.speakingGlow,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.5),
                          width: 1,
                        ),
                      ),
                      child: const Icon(
                        Icons.graphic_eq_rounded,
                        color: Colors.white,
                        size: 13,
                      ),
                    ),
                  ),
                // Participant name tag overlay
                Positioned(
                  left: 8,
                  bottom: 8,
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 8,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.65),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomText(
                          text: participantName,
                          textColor: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.w500,
                        ),
                        if (uid != 0 && mutedRemoteAudioUids.contains(uid)) ...[
                          const SizedBox(width: 4),
                          const Icon(
                            Icons.mic_off_rounded,
                            color: Colors.redAccent,
                            size: 12,
                          ),
                        ],
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
