import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';
import '../../calls/services/group_call_tracker.dart';

/// A WhatsApp/Messenger-style "Join call" card rendered inline in a group
/// chat's message list while a group call is still in progress. Shows the
/// call type (voice / video), a pulsing LIVE indicator and who started it, and
/// a "Join call" button that joins the ongoing call.
///
/// Fully themed via [FcAppColors] so it matches light / dark (night) mode,
/// mirroring the rest of the app.
class JoinCallCard extends StatefulWidget {
  final ActiveGroupCall call;

  /// Whether a "Join call" action should be offered. When false (the current
  /// user is the caller), a muted "You are in this call" state is shown.
  final bool canJoin;

  /// The caller's uid — used to phrase the label ("X started a call" vs
  /// "You started a call").
  final String callerId;

  final VoidCallback onJoin;

  const JoinCallCard({
    super.key,
    required this.call,
    required this.canJoin,
    required this.callerId,
    required this.onJoin,
  });

  @override
  State<JoinCallCard> createState() => _JoinCallCardState();
}

class _JoinCallCardState extends State<JoinCallCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse;

  @override
  void initState() {
    super.initState();
    _pulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
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
    final isCaller = widget.call.callerId == widget.callerId;
    final typeLabel = isVideo ? 'Video call' : 'Voice call';

    final LinearGradient avatarGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isVideo
          ? const [Color(0xFF0288D1), Color(0xFF4FC3F7)]
          : const [Color(0xFF00BFA5), Color(0xFF64FFDA)],
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Center(
        child: Container(
          margin: const EdgeInsets.symmetric(horizontal: 20),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: colors.surfaceDim),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  // Call-type avatar
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: avatarGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: Colors.white,
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
                        Text(
                          widget.call.groupName.isEmpty
                              ? 'Group call'
                              : widget.call.groupName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Pulsing "live" indicator
                            FadeTransition(
                              opacity: Tween<double>(begin: 0.35, end: 1)
                                  .animate(_pulse),
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34C759),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'LIVE · $typeLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              const Divider(height: 1),
              const SizedBox(height: 10),
              // Caller line
              Row(
                children: [
                  Icon(
                    Icons.person_rounded,
                    color: colors.textWeak,
                    size: 15,
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      isCaller
                          ? 'You started this call'
                          : '${widget.call.callerName} started this call',
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: colors.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              // Join button (full width)
              SizedBox(
                width: double.infinity,
                height: 42,
                child: widget.canJoin
                    ? ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.bubbleMine,
                          foregroundColor: colors.bubbleMineText,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: widget.onJoin,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.call_rounded,
                              size: 18,
                            ),
                            SizedBox(width: 8),
                            Text('Join call'),
                          ],
                        ),
                      )
                    : Container(
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.surfaceDim),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.headset_rounded,
                              size: 17,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'In this call',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
