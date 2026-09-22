import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import 'call_ended_overlay.dart';
import 'call_status_display.dart';
import 'call_timer_widget.dart';
import 'video_call_controls_fade.dart';

/// Top glassmorphic bar showing the callee's name, call status / timer, and
/// a back button that minimises the call (PiP or background pill).
class VideoCallHeaderBar extends StatelessWidget {
  final String displayName;
  final Animation<double> controlsAnimation;
  final bool showControls;
  final bool isTimerVisible;
  final String? endedReason;
  final bool isJoined;
  final bool isGroup;
  final int remoteUsersCount;
  final bool hadRemoteUser;
  final bool isEngineReady;
  final VoidCallback onBack;

  const VideoCallHeaderBar({
    super.key,
    required this.displayName,
    required this.controlsAnimation,
    required this.showControls,
    required this.isTimerVisible,
    this.endedReason,
    required this.isJoined,
    this.isGroup = false,
    this.remoteUsersCount = 0,
    this.hadRemoteUser = false,
    this.isEngineReady = true,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    return CallControlsFade(
      animation: controlsAnimation,
      show: showControls,
      child: SafeArea(
        child: Container(
          margin: const EdgeInsets.all(12),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          decoration: BoxDecoration(
            color: AppColors.callHeaderBg.withValues(alpha: 0.85),
            borderRadius: BorderRadius.circular(24),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.15),
              width: 1,
            ),
          ),
          child: Row(
            children: [
              IconButton(
                icon: const Icon(
                  Icons.arrow_back_ios_new_rounded,
                  color: Colors.white,
                  size: 20,
                ),
                onPressed: onBack,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    CustomText(
                      text: displayName,
                      textColor: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    isTimerVisible
                        ? const CallTimerWidget()
                        : CustomText(
                            text: endedReason != null
                                ? CallEndedOverlay.statusLabel(endedReason)
                                : callStatusText(
                                    isEngineReady: isEngineReady,
                                    isJoined: isJoined,
                                    isGroup: isGroup,
                                    remoteUsersCount: remoteUsersCount,
                                    hadRemoteUser: hadRemoteUser,
                                  ),
                            textColor: Colors.white70,
                            fontSize: 12,
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
