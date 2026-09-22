import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:swipe_to/swipe_to.dart';
import '../../chat/cubit/chat_cubit.dart';
import '../../chat/models/message_model.dart';
import '../../chat/widgets/day_separator.dart';
import '../../chat/widgets/message_bubble/message_bubble.dart';
import '../../profile/models/user_model.dart';

/// A single message row in a group chat: the [MessageBubble] (with the app
/// bar's chat name and the live member maps for sender lookup), wrapped in a
/// swipe-to-reply [SwipeTo] when permitted, with an optional [DaySeparator]
/// above it.
class GroupChatMessageTile extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final String chatName;
  final Map<String, UserModel> members;
  final bool showDaySeparator;
  final bool highlighted;
  final bool readOnly;
  final Key bubbleKey;
  final ValueChanged<String> onTapReplied;
  final ValueChanged<MessageModel> onJoinCall;

  const GroupChatMessageTile({
    super.key,
    required this.message,
    required this.isMe,
    required this.chatName,
    required this.members,
    required this.showDaySeparator,
    required this.highlighted,
    required this.readOnly,
    required this.bubbleKey,
    required this.onTapReplied,
    required this.onJoinCall,
  });

  @override
  Widget build(BuildContext context) {
    final sender = members[message.senderId];
    final senderAvatar = sender?.avatarEmoji ?? '👤';
    final senderName =
        sender != null ? '${sender.firstName} ${sender.lastName}' : 'Unknown';

    final messageWidget = MessageBubble(
      key: bubbleKey,
      message: message,
      isMe: isMe,
      isGroup: true,
      sender: sender,
      senderAvatar: senderAvatar,
      contactName: chatName,
      members: members,
      highlighted: highlighted,
      readOnly: readOnly,
      onJoinCall: () => onJoinCall(message),
      onTapReplied: () {
        final repliedId = (message.repliedTo?['id'] ??
                message.repliedTo?['messageId'] ??
                message.repliedTo?['_id'])
            ?.toString();
        if (repliedId != null && repliedId.isNotEmpty) {
          onTapReplied(repliedId);
        }
      },
    );

    Widget result = messageWidget;
    if (!message.isDeleted && !readOnly) {
      result = SwipeTo(
        onLeftSwipe: isMe
            ? (details) {
                context.read<ChatCubit>().setReplyingTo(message, senderName);
              }
            : null,
        onRightSwipe: !isMe
            ? (details) {
                context.read<ChatCubit>().setReplyingTo(message, senderName);
              }
            : null,
        child: messageWidget,
      );
    }

    if (showDaySeparator) {
      result = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DaySeparator(date: message.timestamp.toDate()),
          result,
        ],
      );
    }

    return result;
  }
}