import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flutter/material.dart';
import '../services/call_avatar_loader.dart';
import 'call_controls.dart';
import 'call_ended_overlay.dart';
import 'video_call_controls_fade.dart';
import 'video_call_display_area.dart';
import 'video_call_header_bar.dart';
import 'video_call_local_preview.dart';

/// The full-screen video call UI: the video (or placeholder) display area,
/// the small local preview PiP, the top glassmorphic bar, the floating bottom
/// controls and the call-ended overlay, wrapped in the tap-to-toggle controls
/// gesture and the back (minimize/PiP) handler.
///
/// Kept deliberately dumb: it only renders the tree; all state mutation
/// (controls visibility, minimizing, ending the call) is delegated through
/// callbacks so [VideoCallPage] stays the single place that talks to the bloc.
class VideoCallScaffold extends StatelessWidget {
  final String displayName;
  final String? avatarEmoji;
  final String? ownAvatar;
  final bool isGroup;
  final String channelName;
  final RtcEngine? engine;
  final bool isEngineReady;
  final List<int> remoteUids;
  final Set<int> mutedRemoteUids;
  final Set<int> mutedRemoteAudioUids;
  final Set<int> speakingUids;
  final bool isCameraOff;
  final bool isMuted;
  final bool isJoined;
  final bool hadRemoteUser;
  final Map<int, CallParticipantInfo> participants;
  final AnimationController controlsAnimation;
  final bool showControls;
  final String? endedReason;
  final Duration? callDuration;
  final bool canPop;
  final void Function(bool didPop, Object? result)? onPopInvoked;
  final VoidCallback onToggleControls;
  final VoidCallback onBack;
  final VoidCallback onToggleMute;
  final VoidCallback onSwitchCamera;
  final VoidCallback onCameraToggle;
  final VoidCallback onEndCall;
  final VoidCallback onDismissEnded;

  const VideoCallScaffold({
    super.key,
    required this.displayName,
    required this.avatarEmoji,
    required this.ownAvatar,
    required this.isGroup,
    required this.channelName,
    required this.engine,
    required this.isEngineReady,
    required this.remoteUids,
    required this.mutedRemoteUids,
    required this.mutedRemoteAudioUids,
    required this.speakingUids,
    required this.isCameraOff,
    required this.isMuted,
    required this.isJoined,
    required this.participants,
    required this.controlsAnimation,
    required this.showControls,
    required this.endedReason,
    required this.callDuration,
    required this.canPop,
    required this.onPopInvoked,
    required this.onToggleControls,
    required this.onBack,
    required this.onToggleMute,
    required this.onSwitchCamera,
    required this.onCameraToggle,
    required this.onEndCall,
    required this.onDismissEnded,
    this.hadRemoteUser = false,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onToggleControls,
      child: PopScope(
        canPop: canPop,
        onPopInvokedWithResult: onPopInvoked,
        child: Scaffold(
          backgroundColor: AppColors.callPageBackground,
          body: Stack(
            children: [
              // 1. VIDEO OR PLACEHOLDER DISPLAY AREA
              VideoCallDisplayArea(
                engine: engine,
                isEngineReady: isEngineReady,
                isGroup: isGroup,
                displayName: displayName,
                avatarEmoji: avatarEmoji,
                ownAvatar: ownAvatar,
                isCameraOff: isCameraOff,
                isJoined: isJoined,
                hadRemoteUser: hadRemoteUser,
                remoteUids: remoteUids,
                mutedRemoteUids: mutedRemoteUids,
                mutedRemoteAudioUids: mutedRemoteAudioUids,
                speakingUids: speakingUids,
                channelName: channelName,
                participants: participants,
              ),

              // 2. SMALL LOCAL PREVIEW PIP (1-on-1 only)
              if (isEngineReady && !isGroup && engine != null)
                VideoCallLocalPreview(
                  engine: engine!,
                  isCameraOff: isCameraOff,
                  ownAvatar: ownAvatar,
                  topOffset: MediaQuery.of(context).padding.top + 64,
                  isSpeaking: speakingUids.contains(0),
                ),

              // 3. TOP GLASSMORPHIC BAR
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: VideoCallHeaderBar(
                  displayName: displayName,
                  controlsAnimation: controlsAnimation,
                  showControls: showControls,
                  isTimerVisible: remoteUids.isNotEmpty,
                  endedReason: endedReason,
                  isJoined: isJoined,
                  isGroup: isGroup,
                  remoteUsersCount: remoteUids.length,
                  hadRemoteUser: hadRemoteUser,
                  isEngineReady: isEngineReady,
                  onBack: onBack,
                ),
              ),

              // 4. FLOATING BOTTOM CONTROLS
              if (isEngineReady)
                Positioned(
                  bottom: 30,
                  left: 0,
                  right: 0,
                  child: CallControlsFade(
                    animation: controlsAnimation,
                    show: showControls,
                    child: CallControls(
                      isMuted: isMuted,
                      isCameraOff: isCameraOff,
                      isVideo: true,
                      onMuteToggle: onToggleMute,
                      onCameraToggle: onCameraToggle,
                      onSwitchCamera: onSwitchCamera,
                      onEndCall: onEndCall,
                    ),
                  ),
                ),

              // 5. CALL ENDED / TERMINATION OVERLAY
              if (endedReason != null)
                Positioned.fill(
                  child: CallEndedOverlay(
                    reason: endedReason,
                    duration: callDuration,
                    onDismiss: onDismissEnded,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}