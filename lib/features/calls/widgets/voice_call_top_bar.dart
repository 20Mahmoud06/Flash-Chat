import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';
import '../../../shared/widgets/custom_text.dart';
import 'call_ended_overlay.dart';
import 'call_status_display.dart';
import 'call_timer_widget.dart';

/// Glassmorphic bar at the top of a voice call: back/minimize button, the
/// caller name with timer/status underneath, and the caller's own avatar chip.
class VoiceCallTopBar extends StatelessWidget {
  final String displayName;
  final String? ownAvatar;
  final bool showTimer;
  final String? endedReason;
  final bool isJoined;
  final bool isGroup;
  final int remoteUsersCount;
  final bool hadRemoteUser;
  final bool isEngineReady;
  final VoidCallback onMinimize;

  const VoiceCallTopBar({
    super.key,
    required this.displayName,
    required this.ownAvatar,
    required this.showTimer,
    required this.endedReason,
    required this.isJoined,
    this.isGroup = false,
    this.remoteUsersCount = 0,
    this.hadRemoteUser = false,
    this.isEngineReady = true,
    required this.onMinimize,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
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
              onPressed: onMinimize,
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
                  if (showTimer)
                    const CallTimerWidget()
                  else
                    CustomText(
                      text: endedReason != null
                          ? CallEndedOverlay.statusLabel(endedReason!)
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
            // Own avatar chip
            Container(
              width: 38,
              height: 38,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                gradient: const LinearGradient(
                  colors: [
                    Colors.lightBlueAccent,
                    AppColors.primaryDark,
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                border: Border.all(
                  color: Colors.white.withValues(alpha: 0.4),
                  width: 1.5,
                ),
              ),
              child: Center(
                child: CustomText(
                  text: ownAvatar ?? '👤',
                  fontSize: 17,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}