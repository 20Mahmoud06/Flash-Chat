import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter/services.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_text.dart';
import '../../../profile/models/user_model.dart';
import '../../cubit/chat_cubit.dart';
import '../../models/message_model.dart';
import 'message_bubble_dialogs.dart';

/// Long-press menu for a message: quick reactions, reply, favorite, pin,
/// copy, info/edit/delete (mine) or delete-for-me (theirs).
void showMessageBubbleOptionsSheet(
  BuildContext context, {
  required MessageModel message,
  required bool isMe,
  required bool isGroup,
  required UserModel? sender,
  required String? contactName,
  required Map<String, UserModel> members,
  int? replyMediaIndex,
  int? mediaIndex,
}) {
  final chatCubit = context.read<ChatCubit>();
  final currentUser = FirebaseAuth.instance.currentUser!;

  // True when the options were opened by long-pressing a specific photo,
  // so reactions apply to that photo (imageReactions) instead of the
  // whole message (reactions).
  final bool targetingImage =
      mediaIndex != null && message.messageType == MessageType.image;
  final currentReaction = targetingImage
      ? (message.imageReactions['$mediaIndex'] ?? const {})[currentUser.uid]
      : message.reactions[currentUser.uid];

  // Specific photo being replied to (null = reply to the whole group).
  // For whole-group replies the first photo is used as the thumbnail and
  // the count is attached so the preview shows a "📷 Photos" badge.
  final String? replyMediaUrl;
  final int? replyMediaCount;
  final mediaUrls = message.mediaUrls;
  if (replyMediaIndex != null &&
      mediaUrls != null &&
      replyMediaIndex < mediaUrls.length) {
    replyMediaUrl = mediaUrls[replyMediaIndex];
    replyMediaCount = null;
  } else if (mediaUrls != null && mediaUrls.isNotEmpty) {
    replyMediaUrl = mediaUrls.first;
    replyMediaCount =
        message.messageType == MessageType.image && mediaUrls.length > 1
            ? mediaUrls.length
            : null;
  } else {
    replyMediaUrl = null;
    replyMediaCount = null;
  }

  final String senderName = isGroup
      ? (sender != null
          ? '${sender.firstName} ${sender.lastName}'
          : 'Unknown')
      : (isMe ? 'You' : contactName ?? 'Unknown');

  void toggleReaction(String emoji) {
    final chatCubit = context.read<ChatCubit>();
    if (targetingImage) {
      if (currentReaction == emoji) {
        chatCubit.removeImageReaction(message.id, mediaIndex);
      } else {
        chatCubit.updateImageReaction(message.id, mediaIndex, emoji);
      }
    } else {
      if (currentReaction == emoji) {
        chatCubit.removeReaction(message.id);
      } else {
        chatCubit.updateReaction(message.id, emoji);
      }
    }
  }

  showModalBottomSheet(
    context: context,
    backgroundColor: Colors.transparent,
    builder: (ctx) {
      final colors = FcAppColors.of(ctx);
      final List<String> quickReactions = ['❤️', '😂', '😮', '😢', '👍'];
      return Container(
        margin: EdgeInsets.all(8.w),
        decoration: BoxDecoration(
            color: colors.surface, borderRadius: BorderRadius.circular(15.r)),
        child: SingleChildScrollView(
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.symmetric(vertical: 10.h),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: [
                      ...quickReactions.map((emoji) {
                        return GestureDetector(
                          onTap: () {
                            toggleReaction(emoji);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: currentReaction == emoji
                                  ? Colors.lightBlue.shade100
                                  : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: CustomText(text: emoji, fontSize: 24.sp),
                          ),
                        );
                      }),
                      if (currentReaction != null &&
                          !quickReactions.contains(currentReaction))
                        GestureDetector(
                          onTap: () {
                            toggleReaction(currentReaction);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: Colors.lightBlue.shade100,
                              shape: BoxShape.circle,
                            ),
                            child:
                                CustomText(text: currentReaction, fontSize: 24.sp),
                          ),
                        ),
                      IconButton(
                        icon: Icon(Icons.add_reaction_outlined,
                            color: colors.textWeak),
                        onPressed: () {
                          Navigator.pop(ctx);
                          showMessageEmojiPicker(context, (selectedEmoji) {
                            toggleReaction(selectedEmoji);
                          });
                        },
                      )
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.reply, color: colors.textSecondary),
                  title: const CustomText(text: 'Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    chatCubit.setReplyingTo(message, senderName,
                        mediaUrl: replyMediaUrl, mediaCount: replyMediaCount);
                  },
                ),
                ListTile(
                  leading: Icon(
                    message.starredBy.contains(currentUser.uid)
                        ? Icons.star
                        : Icons.star_border,
                    color: message.starredBy.contains(currentUser.uid)
                        ? AppColors.amber
                        : colors.textWeak,
                  ),
                  title: CustomText(
                    text: message.starredBy.contains(currentUser.uid)
                        ? 'Remove from favorites'
                        : 'Favorite',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (message.starredBy.contains(currentUser.uid)) {
                      chatCubit.unstarMessage(message.id);
                    } else {
                      chatCubit.starMessage(message.id);
                    }
                  },
                ),
                if (chatCubit.canPin)
                  ListTile(
                    leading: SizedBox(
                      width: 24.w,
                      child:
                          chatCubit.pinnedMessageNotifier.value?['messageId'] ==
                                  message.id
                              ? Transform.rotate(
                                  angle: 0.785,
                                  child: Icon(Icons.push_pin,
                                      color: colors.textWeak, size: 24),
                                )
                              : Icon(Icons.push_pin_outlined,
                                  color: colors.textWeak, size: 24),
                    ),
                    title: CustomText(
                      text: chatCubit.pinnedMessageNotifier.value?['messageId'] ==
                              message.id
                          ? 'Unpin'
                          : 'Pin',
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (chatCubit.pinnedMessageNotifier.value?['messageId'] ==
                          message.id) {
                        chatCubit.unpinMessage();
                      } else {
                        showMessagePinDurationPicker(context, message);
                      }
                    },
                  ),
                if (message.messageType == MessageType.text ||
                    message.text.trim().isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.copy, color: colors.textWeak),
                    title: const CustomText(text: 'Copy'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                          ClipboardData(text: message.text));
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      messenger.showSnackBar(
                        SnackBar(
                          content: Row(
                            children: [
                              Icon(Icons.check_circle,
                                  color: Colors.white, size: 20.sp),
                              SizedBox(width: 12.w),
                              const CustomText(
                                  text: 'Message copied to clipboard'),
                            ],
                          ),
                          backgroundColor: Colors.lightBlueAccent,
                          behavior: SnackBarBehavior.floating,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(10.r)),
                          margin: EdgeInsets.all(16.w),
                          duration: const Duration(seconds: 2),
                        ),
                      );
                    },
                  ),
                if (isMe) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: const Icon(Icons.info_outline, color: Colors.blue),
                    title: const CustomText(text: 'Info'),
                    onTap: () {
                      Navigator.pop(ctx);
                      showMessageInfoDialog(context, message,
                          isGroup: isGroup, members: members);
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.edit_outlined, color: Colors.green),
                    title: const CustomText(text: 'Edit'),
                    onTap: () {
                      Navigator.pop(ctx);
                      showMessageEditDialog(context, message);
                    },
                  ),
                  ListTile(
                    leading:
                        const Icon(Icons.delete_outline, color: Colors.red),
                    title: const CustomText(text: 'Delete'),
                    onTap: () {
                      Navigator.pop(ctx);
                      showMessageDeleteDialog(context, message);
                    },
                  ),
                ],
                if (!isMe) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.delete_sweep_outlined,
                        color: colors.textWeak),
                    title: const CustomText(text: 'Delete for me'),
                    onTap: () {
                      Navigator.pop(ctx);
                      showMessageDeleteForMeDialog(context, message);
                    },
                  ),
                ]
              ],
            ),
          ),
        ),
      );
    },
  );
}