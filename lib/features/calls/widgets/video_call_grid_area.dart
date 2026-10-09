import 'dart:math' as math;

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
        // Top clearance clears the header bar / timer, bottom clearance keeps
        // the last row clear of the floating call controls.
        padding: const EdgeInsets.only(
          top: 100,
          left: 8,
          right: 8,
          bottom: 100,
        ),
        child: AnimatedCallGrid(
          uids: uids,
          spacing: 6,
          minTileWidth: 100,
          minTileHeight: 112,
          // Portrait-ish tiles, the way video participants are usually shown.
          tileAspectRatio: 0.72,
          maxColumns: 5,
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

            return VideoCallGridTile(
              content: content,
              participantName: participantName,
              isSpeaking: isSpeaking,
              isMutedAudio: uid != 0 && mutedRemoteAudioUids.contains(uid),
            );
          },
        ),
      ),
    );
  }
}

/// One participant tile of the group video grid: the camera view (or avatar
/// placeholder) with a rounded, speaking-aware border, a mic badge and the
/// name tag.
///
/// Every overlay is sized from the tile box itself so the tile stays readable
/// — and never overflows — no matter how many participants the grid packs on
/// screen.
class VideoCallGridTile extends StatelessWidget {
  const VideoCallGridTile({
    super.key,
    required this.content,
    required this.participantName,
    this.isSpeaking = false,
    this.isMutedAudio = false,
  });

  /// Camera view or avatar placeholder filling the tile.
  final Widget content;

  final String participantName;
  final bool isSpeaking;
  final bool isMutedAudio;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final double width = constraints.maxWidth;
        final double height = constraints.maxHeight;
        final double radius = math.min(16, math.max(6, width * 0.08));
        final double inset = math.min(8, math.max(3, width * 0.05));
        final double badgePadding = math.min(4, math.max(2, width * 0.03));
        final double badgeIcon = math.min(13, math.max(8, width * 0.1));
        final double nameFontSize =
            math.min(11, math.max(8, math.min(width * 0.09, height * 0.06)));
        final double nameVerticalPadding =
            math.min(4, math.max(2, height * 0.02));
        final double nameHorizontalPadding =
            math.min(8, math.max(4, width * 0.05));

        return Stack(
          children: [
            Positioned.fill(
              child: ClipRRect(
                borderRadius: BorderRadius.circular(radius),
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
                top: inset,
                left: inset,
                child: Container(
                  padding: EdgeInsets.all(badgePadding),
                  decoration: BoxDecoration(
                    color: AppColors.speakingGlow,
                    shape: BoxShape.circle,
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.5),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    Icons.mic_rounded,
                    color: Colors.white,
                    size: badgeIcon,
                  ),
                ),
              ),
            // Participant name tag overlay (ellipsized: it may be long and the
            // tile may be only a few dozen pixels wide in a crowded call).
            Positioned(
              left: inset,
              bottom: inset,
              child: Container(
                padding: EdgeInsets.symmetric(
                  horizontal: nameHorizontalPadding,
                  vertical: nameVerticalPadding,
                ),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.65),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Flexible(
                      child: CustomText(
                        text: participantName,
                        textColor: Colors.white,
                        fontSize: nameFontSize,
                        fontWeight: FontWeight.w500,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    if (isMutedAudio) ...[
                      SizedBox(width: math.min(4, width * 0.03)),
                      Icon(
                        Icons.mic_off_rounded,
                        color: Colors.redAccent,
                        size: math.min(12, math.max(8, width * 0.09)),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        );
      },
    );
  }
}