import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_text.dart';
import '../../../profile/models/user_model.dart';
import '../../models/message_model.dart';

String formatCallDuration(int seconds) {
  final h = seconds ~/ 3600;
  final m = (seconds % 3600) ~/ 60;
  final s = seconds % 60;
  String two(int v) => v.toString().padLeft(2, '0');
  if (h > 0) return '$h:${two(m)}:${two(s)}';
  return '${two(m)}:${two(s)}';
}

String callOutcomeLabel(String? outcome) {
  switch (outcome) {
    case 'missed':
      return 'Missed';
    case 'declined':
      return 'Declined';
    case 'cancelled':
      return 'Cancelled';
    case 'busy':
      return 'Busy';
    default:
      return 'Call ended';
  }
}

/// Centered call-history notice inline in the chat history: who called, the
/// type, the outcome and the duration. Not a chat bubble, so it has no
/// reactions, reply, pin or edit.
class MessageBubbleCallNotice extends StatelessWidget {
  final MessageModel message;
  final bool isGroup;
  final UserModel? sender;
  final String? contactName;

  const MessageBubbleCallNotice({
    super.key,
    required this.message,
    required this.isGroup,
    this.sender,
    this.contactName,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isVideo = message.callType == 'video';
    final isCompleted = message.callOutcome == 'completed';

    // Viewer-aware caller name: "You" for the participant who placed the call,
    // otherwise the caller's display name.
    String caller;
    if (message.callerId != null && message.callerId == myUid) {
      caller = 'You';
    } else if (!isGroup) {
      caller = contactName ?? message.senderName ?? 'Caller';
    } else {
      caller = sender != null
          ? '${sender!.firstName} ${sender!.lastName}'
          : (message.senderName ?? 'Caller');
    }

    final typeLabel = isVideo ? 'Video call' : 'Voice call';
    final String detail;
    if (isCompleted) {
      detail = formatCallDuration(message.callDuration ?? 0);
    } else {
      detail = callOutcomeLabel(message.callOutcome);
    }

    // For group call history, mention how many members were offline at call
    // time (they never saw the ring).
    final String summaryDetail = (isGroup && (message.offlineCount ?? 0) > 0)
        ? '$detail · ${message.offlineCount} offline'
        : detail;

    final accent = isCompleted ? AppColors.iosGreen : Colors.redAccent;
    final icon = isVideo ? Icons.videocam_rounded : Icons.call_rounded;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 24.w),
      child: Center(
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(
              color: accent.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15.sp, color: accent),
              SizedBox(width: 6.w),
              Flexible(
                child: CustomText(
                  text: '$caller · $typeLabel · $summaryDetail',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  textColor: colors.textPrimary,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// WhatsApp / Messenger-style active group call card rendered as a real
/// message in the chat list. Shows the caller name, a pulsing LIVE dot,
/// and a full-width "Join call" button that taps into the ongoing call.
class MessageBubbleActiveCallCard extends StatefulWidget {
  final MessageModel message;
  final UserModel? sender;
  final VoidCallback? onJoinCall;

  const MessageBubbleActiveCallCard({
    super.key,
    required this.message,
    this.sender,
    this.onJoinCall,
  });

  @override
  State<MessageBubbleActiveCallCard> createState() =>
      _MessageBubbleActiveCallCardState();
}

class _MessageBubbleActiveCallCardState extends State<MessageBubbleActiveCallCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _livePulse;

  @override
  void initState() {
    super.initState();
    _livePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _livePulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final message = widget.message;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isVideo = message.callType == 'video';
    final callerId = message.callerId;
    final isCaller = callerId == myUid;
    final typeLabel = isVideo ? 'Video call' : 'Voice call';

    String caller;
    if (isCaller) {
      caller = 'You';
    } else if (widget.sender != null) {
      caller = '${widget.sender!.firstName} ${widget.sender!.lastName}';
    } else {
      caller = message.senderName ?? 'Someone';
    }

    final LinearGradient avatarGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isVideo
          ? const [AppColors.primaryDark, AppColors.sky]
          : const [AppColors.teal, AppColors.tealLight],
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 20.w),
      child: Center(
        child: Container(
          padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 12.h),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18.r),
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
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: avatarGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo ? Icons.videocam_rounded : Icons.call_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CustomText(
                          text: '$caller started a $typeLabel',
                          textColor: colors.textPrimary,
                          fontSize: 14.5,
                          fontWeight: FontWeight.w600,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FadeTransition(
                              opacity: Tween<double>(begin: 0.35, end: 1)
                                  .animate(_livePulse),
                              child: Container(
                                width: 8,
                                height: 8,
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
                ],
              ),
              SizedBox(height: 10.h),
              const Divider(height: 1),
              SizedBox(height: 10.h),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: isCaller
                    ? Container(
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
                            CustomText(
                              text: 'In this call',
                              textColor: colors.textSecondary,
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                            ),
                          ],
                        ),
                      )
                    : ElevatedButton(
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
                        onPressed: widget.onJoinCall,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.call_rounded, size: 18),
                            SizedBox(width: 8),
                            CustomText(text: 'Join call'),
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