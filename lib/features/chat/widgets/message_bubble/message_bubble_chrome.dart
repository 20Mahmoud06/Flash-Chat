import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_text.dart';
import '../../../profile/models/user_model.dart';
import '../../models/message_model.dart';
import '../reply_preview_card.dart';
import 'message_bubble_content.dart';

/// The bubble chrome for a regular chat message: the pinned label, the group
/// sender name, the avatar row, the rounded bubble with its
/// highlight/favorite/pending styling, the reactions badge, the reply preview
/// (+ payload) and the bottom metadata row (star, "Edited ·", time, ticks).
///
/// Kept deliberately dumb: it only renders the tree handed down by
/// [MessageBubble], which decides on long-press / tap behavior and supplies
/// the callbacks for options, image reactions and the reactions dialog.
class MessageBubbleChrome extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isGroup;
  final UserModel? sender;
  final String senderAvatar;
  final Color textColor;
  final Color color;
  final bool highlighted;
  final bool isStarred;
  final bool isPinned;
  final bool groupAllSeen;
  final VoidCallback? onLongPress;
  final VoidCallback? onTapReplied;
  final void Function(int? replyMediaIndex, int? mediaIndex) onShowOptions;
  final void Function(int mediaIndex) onShowImageReactions;
  final VoidCallback onShowReactions;

  const MessageBubbleChrome({
    super.key,
    required this.message,
    required this.isMe,
    required this.isGroup,
    required this.sender,
    required this.senderAvatar,
    required this.textColor,
    required this.color,
    required this.highlighted,
    required this.isStarred,
    required this.isPinned,
    this.groupAllSeen = false,
    required this.onLongPress,
    required this.onTapReplied,
    required this.onShowOptions,
    required this.onShowImageReactions,
    required this.onShowReactions,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    // Gold is used for the favorite highlight on every bubble. On the other
    // person's light bubbles it pops nicely, and on my own bubbles (light blue
    // in light mode, medium blue in dark mode) a gold star icon + border keeps
    // the highlight clearly visible — white was invisible in light mode.
    const starColor = AppColors.amber;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: 4.h,
        horizontal: 8.w,
      ).copyWith(bottom: message.reactions.isNotEmpty ? 15.h : 4.h),
      child: GestureDetector(
        onLongPress: onLongPress,
        child: Column(
          crossAxisAlignment: alignment,
          children: [
            if (isPinned)
              Padding(
                padding: EdgeInsets.only(bottom: 2.h),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.push_pin,
                      size: 11.sp,
                      color: textColor.withValues(alpha: 0.7),
                    ),
                    SizedBox(width: 3.w),
                    CustomText(
                      text: 'Pinned',
                      fontSize: 10.sp,
                      fontWeight: FontWeight.w600,
                      textColor: textColor.withValues(alpha: 0.7),
                    ),
                  ],
                ),
              ),
            if (isGroup && !isMe && sender != null)
              Padding(
                padding: EdgeInsets.only(left: 48.w, bottom: 4.h),
                child: CustomText(
                    text: '${sender!.firstName} ${sender!.lastName}',
                    fontSize: 12.sp,
                    textColor: colors.textWeak),
              ),
            Row(
              mainAxisAlignment: isMe
                  ? MainAxisAlignment.end
                  : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe)
                  Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: CircleAvatar(
                      radius: 18.r,
                      backgroundColor: Colors.transparent,
                      child: CustomText(
                          text: senderAvatar, fontSize: 18.sp),
                    ),
                  ),
                Flexible(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        constraints: BoxConstraints(maxWidth: 0.7.sw),
                        padding: EdgeInsets.symmetric(
                            vertical: 10.h, horizontal: 14.w),
                        decoration: BoxDecoration(
                          color: highlighted &&
                                  message.status != 'pending'
                              ? Color.alphaBlend(
                                  AppColors.sky.withValues(alpha: 0.35),
                                  color,
                                )
                              : isStarred && message.status != 'pending'
                                  ? Color.alphaBlend(
                                      starColor.withValues(alpha: 0.22),
                                      color,
                                    )
                                  : message.status == 'pending'
                                      ? color.withValues(alpha: 0.55)
                                      : color,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(18.r),
                            topRight: Radius.circular(18.r),
                            bottomLeft: isMe
                                ? Radius.circular(18.r)
                                : Radius.circular(4.r),
                            bottomRight: isMe
                                ? Radius.circular(4.r)
                                : Radius.circular(18.r),
                          ),
                          border: highlighted
                              ? Border.all(
                                  color: AppColors.primaryDark,
                                  width: 2,
                                )
                              : isStarred
                                  ? Border.all(color: starColor, width: 2)
                                  : Border.all(
                                      color: Colors.transparent,
                                      width: 0,
                                    ),
                          boxShadow: [
                            BoxShadow(
                              color: highlighted
                                  ? AppColors.sky.withValues(alpha: 0.65)
                                  : isStarred
                                      ? starColor.withValues(alpha: 0.5)
                                      : Colors.black.withValues(alpha: 0.1),
                              blurRadius: (highlighted || isStarred) ? 16 : 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (message.repliedTo != null)
                              Padding(
                                padding: EdgeInsets.only(bottom: 8.h),
                                child: ReplyPreviewCard.fromReplyMeta(
                                  repliedTo: message.repliedTo!,
                                  isOwnMessage: isMe,
                                  resolvedSenderName:
                                      message.repliedTo!['senderName']
                                              as String? ??
                                          'Unknown',
                                  onTap: onTapReplied,
                                ),
                              ),
                            message.isDeleted
                                ? CustomText(
                                    text: "This message was deleted",
                                    fontStyle: FontStyle.italic,
                                    textColor:
                                        textColor.withValues(alpha: 0.7),
                                  )
                                : MessageBubbleContent(
                                    message: message,
                                    isMe: isMe,
                                    textColor: textColor,
                                    bubbleColor: color,
                                    onShowOptions: (replyMediaIndex,
                                            mediaIndex) =>
                                        onShowOptions(replyMediaIndex,
                                            mediaIndex),
                                    onShowImageReactions: (mediaIndex) =>
                                        onShowImageReactions(mediaIndex),
                                  ),
                            SizedBox(height: 4.h),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (isStarred) ...[
                                  Icon(Icons.star,
                                      size: 12.sp, color: starColor),
                                  SizedBox(width: 3.w),
                                ],
                                if (message.isEdited)
                                  CustomText(
                                      text: "Edited · ",
                                      textColor:
                                          textColor.withValues(alpha: 0.7),
                                      fontSize: 11.sp),
                                CustomText(
                                  text: intl.DateFormat('h:mm a').format(
                                      message.timestamp.toDate()),
                                  textColor:
                                      textColor.withValues(alpha: 0.7),
                                  fontSize: 11.sp,
                                ),
                                if (isMe && !message.isDeleted) ...[
                                  SizedBox(width: 4.w),
                                  if (message.status == 'pending')
                                    Icon(
                                      Icons.schedule,
                                      size: 14.sp,
                                      color: Colors.orange.shade600,
                                    )
                                  else
                                    // Groups: single tick until every member
                                    // present at send time has read the
                                    // message, then the blue double-tick (same
                                    // as 1:1 "seen"). 1:1: one tick for sent,
                                    // double-tick for delivered / seen.
                                    Icon(
                                      isGroup
                                          ? (groupAllSeen
                                              ? Icons.done_all
                                              : Icons.done)
                                          : (message.status == 'seen'
                                              ? Icons.done_all
                                              : (message.status == 'delivered'
                                                  ? Icons.done_all
                                                  : Icons.done)),
                                      size: 14.sp,
                                      color: isGroup
                                          ? (groupAllSeen
                                              ? Colors.blue
                                              : textColor
                                                  .withValues(alpha: 0.7))
                                          : message.status == 'seen'
                                              ? Colors.blue
                                              : textColor
                                                  .withValues(alpha: 0.7),
                                    ),
                                ]
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (message.reactions.isNotEmpty)
                        Positioned(
                          bottom: -12.h,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: onShowReactions,
                              child: Container(
                                padding: EdgeInsets.symmetric(
                                    horizontal: 8.w, vertical: 2.5.h),
                                decoration: BoxDecoration(
                                  color: colors.surface,
                                  borderRadius:
                                      BorderRadius.circular(12.r),
                                  border: Border.all(
                                    color: colors.surfaceDim,
                                    width: 1,
                                  ),
                                  boxShadow: [
                                    BoxShadow(
                                      color: Colors.black
                                          .withValues(alpha: 0.12),
                                      blurRadius: 6,
                                      spreadRadius: 1,
                                    ),
                                  ],
                                ),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    CustomText(
                                      text: message.reactions.values
                                          .toSet()
                                          .join(''),
                                      fontSize: 13.sp,
                                    ),
                                    SizedBox(width: 4.w),
                                    CustomText(
                                      text: '${message.reactions.length}',
                                      textColor: colors.textSecondary,
                                      fontSize: 11.5.sp,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (isMe)
                  Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: CircleAvatar(
                      radius: 18.r,
                      backgroundColor: Colors.transparent,
                      child: CustomText(
                          text: senderAvatar, fontSize: 18.sp),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}