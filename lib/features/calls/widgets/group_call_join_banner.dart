import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';
import '../services/group_call_tracker.dart';

/// A premium "call in progress — tap to join" banner shown at the top of a
/// group chat when a group call is already running and the viewer is not the
/// caller. Fully themed via [FcAppColors] so it matches light / dark (night)
/// mode, mirroring the app's look.
class GroupCallJoinBanner extends StatefulWidget {
  final ActiveGroupCall call;
  final VoidCallback onJoin;
  final bool canJoin;

  const GroupCallJoinBanner({
    super.key,
    required this.call,
    required this.onJoin,
    this.canJoin = true,
  });

  @override
  State<GroupCallJoinBanner> createState() => _GroupCallJoinBannerState();
}

class _GroupCallJoinBannerState extends State<GroupCallJoinBanner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final isVideo = widget.call.isVideo;
    final icon = isVideo ? Icons.videocam_rounded : Icons.call_rounded;
    final typeLabel = isVideo ? 'Video call' : 'Voice call';

    return Container(
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: colors.surfaceDim),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: widget.canJoin ? widget.onJoin : null,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            child: Row(
              children: [
                // Call-type avatar
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: colors.avatarBackground,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    icon,
                    color: colors.bubbleMine,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                // Text
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      CustomText(
                        text: widget.call.groupName.isEmpty
                            ? 'Group call'
                            : widget.call.groupName,
                        textColor: colors.textPrimary,
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 2),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Pulsing "live" indicator
                          FadeTransition(
                            opacity: Tween<double>(begin: 0.35, end: 1)
                                .animate(_pulse),
                            child: Container(
                              width: 7,
                              height: 7,
                              decoration: const BoxDecoration(
                                color: AppColors.iosGreen,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                          const SizedBox(width: 5),
                          Flexible(
                            child: CustomText(
                              text: 'LIVE · $typeLabel',
                              textColor: colors.textSecondary,
                              fontSize: 11.5,
                              fontWeight: FontWeight.w500,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                // Join button
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: colors.bubbleMine,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        widget.canJoin
                            ? Icons.call_rounded
                            : Icons.lock_clock_rounded,
                        color: colors.bubbleMineText,
                        size: 15,
                      ),
                      const SizedBox(width: 5),
                      CustomText(
                        text: widget.canJoin ? 'Join' : 'You called',
                        textColor: colors.bubbleMineText,
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}