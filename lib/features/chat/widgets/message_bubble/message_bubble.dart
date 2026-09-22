import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_text.dart';
import '../../../profile/models/user_model.dart';
import '../../../calls/bloc/call_bloc.dart';
import '../../../calls/services/group_call_tracker.dart';
import '../../cubit/chat_cubit.dart';
import '../../models/message_model.dart';
import 'group_message_seen.dart';
import 'message_bubble_actions.dart';
import 'message_bubble_call.dart';
import 'message_bubble_chrome.dart';
import 'message_bubble_reactions.dart';

/// A single item in a chat list: system notices, call-history notices, active
/// call cards, and the regular message bubbles with their text/media payload,
/// reactions, reply previews, and per-message actions.
///
/// Kept deliberately dumb: rendering concerns are split across the sub-widgets
/// in this folder ([message_bubble_content.dart], [message_bubble_call.dart],
/// [message_bubble_actions.dart], [message_bubble_reactions.dart]) while the
/// bubble chrome (avatars, alignment, pin/favorite highlight, ticks) stays
/// here.
class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isGroup;
  final UserModel? sender;
  final String senderAvatar;
  final String? contactName;
  final Map<String, UserModel> members;
  final VoidCallback? onTapReplied;

  /// Fired when the user taps "Join call" on an active-group-call card.
  /// Optional — 1:1 chats never build these cards, so the callback can be
  /// null there. Implementations should join the ongoing call and open its
  /// call page.
  final VoidCallback? onJoinCall;

  /// True right after the user jumped to this message from the in-chat
  /// search, so it gets a temporary accent outline.
  final bool highlighted;

  /// When true the bubble is view-only: long-press (react/reply/pin) and the
  /// per-media long-press options are disabled. Used for removed/left group
  /// members who can read past messages but not interact.
  final bool readOnly;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isGroup,
    this.sender,
    required this.senderAvatar,
    this.contactName,
    required this.members,
    this.onTapReplied,
    this.onJoinCall,
    this.highlighted = false,
    this.readOnly = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);

    if (message.messageType == MessageType.system) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 24.w),
        child: Center(
          child: CustomText(
            text: message.text,
            fontSize: 12.sp,
            fontWeight: FontWeight.w500,
            textColor: colors.textWeak,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }

    // Centered WhatsApp-style call-history notice (who called, type, outcome
    // and duration). Not a chat bubble: no reactions, reply, pin or edit.
    if (message.messageType == MessageType.call) {
      return MessageBubbleCallNotice(
        message: message,
        isGroup: isGroup,
        sender: sender,
        contactName: contactName,
      );
    }

    // Active group call message with a "Join call" button — WhatsApp /
    // Messenger style inline card so latecomers can join in one tap. Only
    // shown to members who are NOT in the call (they are the only ones who
    // need the Join button); the caller and anyone already connected don't
    // need a card that simply says they're in the call.
    if (message.messageType == MessageType.callActive) {
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      final inThisCall =
          message.callerId == myUid || CallBloc.instance.isCallActive;
      if (inThisCall) return const SizedBox.shrink();
      // Hide the card when the tracked call is gone (ended or orphaned): a
      // stale "ongoing call" card after the call finished was misleading.
      if (!GroupCallTracker.instance.isCallActive(message.text)) {
        return const SizedBox.shrink();
      }
      return MessageBubbleActiveCallCard(
        message: message,
        sender: sender,
        onJoinCall: onJoinCall,
      );
    }

    final color = isMe ? colors.bubbleMine : colors.bubbleOther;
    final textColor = isMe ? colors.bubbleMineText : colors.bubbleOtherText;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isStarred = myUid != null && message.starredBy.contains(myUid);

    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: context.read<ChatCubit>().pinnedMessageNotifier,
      builder: (context, pin, _) {
        final isPinned = pin?['messageId'] == message.id;
        return ValueListenableBuilder<Map<String, Timestamp>>(
          valueListenable: context.read<ChatCubit>().memberLastSeenNotifier,
          builder: (context, memberLastSeen, _) {
            final chatCubit = context.read<ChatCubit>();
            // Group read receipts: an own message gains the blue double-tick
            // only once every member who was in the group at send time has
            // read it (their per-member `lastSeen` watermark passed it).
            final groupAllSeen = isGroup && isMe && myUid != null
                ? _isGroupMessageSeenByAll(
                    memberLastSeen: memberLastSeen,
                    chatCubit: chatCubit,
                    myUid: myUid,
                  )
                : false;
            return MessageBubbleChrome(
              message: message,
              isMe: isMe,
              isGroup: isGroup,
              sender: sender,
              senderAvatar: senderAvatar,
              textColor: textColor,
              color: color,
              highlighted: highlighted,
              isStarred: isStarred,
              isPinned: isPinned,
              groupAllSeen: groupAllSeen,
              onLongPress: () {
                if (message.isDeleted || readOnly) return;
                _showOptions(context);
              },
              onTapReplied: onTapReplied,
              onShowOptions: (replyMediaIndex, mediaIndex) => _showOptions(
                context,
                replyMediaIndex: replyMediaIndex,
                mediaIndex: mediaIndex,
              ),
              onShowImageReactions: (mediaIndex) =>
                  _showImageReactions(context, mediaIndex),
              onShowReactions: () => _showReactions(context),
            );
          },
        );
      },
    );
  }

  /// True when every member who was in the group when [message] was sent
  /// (excluding me) has already read it.
  bool _isGroupMessageSeenByAll({
    required Map<String, Timestamp> memberLastSeen,
    required ChatCubit chatCubit,
    required String myUid,
  }) {
    final seenBy = groupMessageSeenBy(
      message: message,
      members: members,
      memberLastSeen: memberLastSeen,
      memberJoinTimestamps: chatCubit.memberJoinTimestamps,
      myUid: myUid,
    );
    final total = groupMessageSeenTotal(
      message: message,
      members: members,
      memberJoinTimestamps: chatCubit.memberJoinTimestamps,
      myUid: myUid,
    );
    return total > 0 && seenBy.length >= total;
  }

  /// Long-press entry point: opens the message options sheet. Suppressed for
  /// read-only bubbles (removed/left group members) and deleted messages.
  void _showOptions(
    BuildContext context, {
    int? replyMediaIndex,
    int? mediaIndex,
  }) {
    if (readOnly || message.isDeleted) return;
    showMessageBubbleOptionsSheet(
      context,
      message: message,
      isMe: isMe,
      isGroup: isGroup,
      sender: sender,
      contactName: contactName,
      members: members,
      replyMediaIndex: replyMediaIndex,
      mediaIndex: mediaIndex,
    );
  }

  void _showReactions(BuildContext context) {
    showMessageReactionsDialog(
      context,
      reactions: message.reactions,
      members: members,
      onRemoveMyReaction: () =>
          context.read<ChatCubit>().removeReaction(message.id),
    );
  }

  /// Shows who reacted to a specific photo inside a (multi-)image message.
  void _showImageReactions(BuildContext context, int mediaIndex) {
    showMessageReactionsDialog(
      context,
      reactions: message.imageReactions['$mediaIndex'] ?? const {},
      members: members,
      onRemoveMyReaction: () => context
          .read<ChatCubit>()
          .removeImageReaction(message.id, mediaIndex),
    );
  }
}