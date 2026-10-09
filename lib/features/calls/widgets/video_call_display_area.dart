import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import '../services/call_avatar_loader.dart';
import 'call_status_display.dart';
import 'video_call_avatar_placeholder.dart';
import 'video_call_connecting_view.dart';
import 'video_call_grid_area.dart';
import 'video_call_video_views.dart';

/// Main video/placeholder display area of a video call: connecting view,
/// ringing/camera-off avatar placeholder for 1-on-1, or the animated group
/// grid once remote video is available.
class VideoCallDisplayArea extends StatelessWidget {
  final RtcEngine? engine;
  final bool isEngineReady;
  final bool isGroup;
  final String displayName;
  final String? avatarEmoji;
  final String? ownAvatar;
  final bool isCameraOff;
  final bool isJoined;
  final bool hadRemoteUser;
  final List<int> remoteUids;
  final Set<int> mutedRemoteUids;
  final Set<int> mutedRemoteAudioUids;
  final Set<int> speakingUids;
  final String channelName;
  final Map<int, CallParticipantInfo> participants;

  const VideoCallDisplayArea({
    super.key,
    required this.engine,
    required this.isEngineReady,
    required this.isGroup,
    required this.displayName,
    required this.avatarEmoji,
    required this.ownAvatar,
    required this.isCameraOff,
    required this.isJoined,
    required this.remoteUids,
    required this.mutedRemoteUids,
    required this.mutedRemoteAudioUids,
    required this.speakingUids,
    required this.channelName,
    required this.participants,
    this.hadRemoteUser = false,
  });

  @override
  Widget build(BuildContext context) {
    final videoEngine = engine;
    if (!isEngineReady || videoEngine == null) {
      return VideoCallConnectingView(displayName: displayName);
    }
    if (remoteUids.isEmpty) {
      // Calling / Ringing state placeholder. When the last remote user left
      // (or a 1:1 peer hung up) show "left the call" instead of a fake ring.
      return VideoCallAvatarPlaceholder(
        displayName: displayName,
        avatarEmoji: avatarEmoji,
        statusText: callStatusText(
          isEngineReady: true,
          isJoined: isJoined,
          isGroup: isGroup,
          remoteUsersCount: 0,
          hadRemoteUser: hadRemoteUser,
        ),
        statusIcon: hadRemoteUser
            ? Icons.phonelink_erase_rounded
            : Icons.phone_forwarded_rounded,
      );
    }
    if (!isGroup && remoteUids.length == 1) {
      // 1-on-1: Full screen view
      return mutedRemoteUids.contains(remoteUids[0])
          ? VideoCallAvatarPlaceholder(
              displayName: displayName,
              avatarEmoji: avatarEmoji,
              statusText: '$displayName turned off camera',
              statusIcon: Icons.videocam_off_rounded,
            )
          : buildRemoteVideoView(videoEngine, remoteUids[0], channelName);
    }
    // Group Grid View. Tiles are computed by AnimatedCallGrid from the screen
    // bounds so they fill ALL the available surface (no giant black
    // letterbox) and animate smoothly when someone joins/leaves.
    return VideoCallGridArea(
      engine: videoEngine,
      channelName: channelName,
      uids: [0, ...remoteUids],
      participants: participants,
      speakingUids: speakingUids,
      mutedRemoteUids: mutedRemoteUids,
      mutedRemoteAudioUids: mutedRemoteAudioUids,
      isCameraOff: isCameraOff,
      ownAvatar: ownAvatar,
    );
  }
}