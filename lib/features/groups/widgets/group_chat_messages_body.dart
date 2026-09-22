import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/features/chat/cubit/chat_cubit.dart';
import 'package:flash_chat_app/features/chat/cubit/chat_state.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../calls/services/group_call_tracker.dart';
import '../../chat/widgets/day_separator.dart';
import 'group_chat_empty_state.dart';
import 'group_chat_message_list.dart';
import 'group_chat_message_tile.dart';

/// Renders the scrolling conversation area of a group: the realtime state
/// stream (loading / empty / error states) plus the reversed message list
/// with the pinned-message banner and lazy pagination. The last loaded
/// messages are kept so the chat stays visible while a media upload is in
/// progress (ChatUploading / ChatError replace ChatLoaded).
class GroupChatMessagesBody extends StatefulWidget {
  final ScrollController scrollController;
  final Map<String, GlobalKey> messageKeys;
  final Map<String, UserModel> groupMembers;
  final String chatName;
  final Map<String, Timestamp> joinTimestamps;
  final bool iCreatedGroup;
  final String? highlightedMessageId;

  /// When true (removed from / group deleted) the list becomes read-only.
  final bool readOnly;
  final ValueChanged<String> onJumpToMessage;
  final ValueChanged<ActiveGroupCall> onJoinActiveCall;
  final ValueChanged<MessageModel> onJoinCallFromMessage;

  const GroupChatMessagesBody({
    super.key,
    required this.scrollController,
    required this.messageKeys,
    required this.groupMembers,
    required this.chatName,
    required this.joinTimestamps,
    required this.iCreatedGroup,
    required this.highlightedMessageId,
    required this.readOnly,
    required this.onJumpToMessage,
    required this.onJoinActiveCall,
    required this.onJoinCallFromMessage,
  });

  @override
  State<GroupChatMessagesBody> createState() => _GroupChatMessagesBodyState();
}

class _GroupChatMessagesBodyState extends State<GroupChatMessagesBody> {
  /// Kept so the list stays visible while a media upload is in progress
  /// (ChatUploading / ChatError replace ChatLoaded).
  List<MessageModel>? _lastMessages;

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<ChatCubit, ChatState>(
      listener: (context, state) {
        if (state is ChatError) {
          final isOffline =
              !ConnectivityService.instance.isConnected.value;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: CustomText(
                text: isOffline
                    ? 'You are offline — showing your saved messages.'
                    : state.message,
              ),
              backgroundColor: isOffline ? Colors.orange : Colors.red,
            ));
        }
      },
      builder: (context, state) {
        if (state is ChatLoading || state is ChatInitial) {
          return const Center(
              child: CircularProgressIndicator(
                  color: Colors.lightBlueAccent));
        }

        if (state is ChatLoaded) {
          _lastMessages = state.messages;

          if (state.messages.isEmpty) {
            // Only show the "joined" notice when there really is nothing to
            // read (the user was recently added to the group).
            final currentUser = FirebaseAuth.instance.currentUser;
            final joinTimestamp = currentUser != null
                ? widget.joinTimestamps[currentUser.uid]
                : null;
            return GroupChatEmptyState(
              joinTimestamp: joinTimestamp?.toDate(),
              iCreatedGroup: widget.iCreatedGroup,
            );
          }

          return _buildMessagesList(context, state.messages,
              hasMore: state.hasMore, loadingMore: state.loadingMore);
        }

        // Keep the conversation visible while media uploads are running or
        // right after a transient error instead of flashing "Something went
        // wrong." (the old behavior when sending multiple photos).
        if ((state is ChatUploading || state is ChatError) &&
            _lastMessages != null &&
            _lastMessages!.isNotEmpty) {
          return _buildMessagesList(context, _lastMessages!);
        }

        if (state is ChatError) {
          final isOffline =
              !ConnectivityService.instance.isConnected.value;
          return Center(
            child: CustomText(
              text: isOffline
                  ? 'You are offline. Open this chat once with an internet '
                      'connection to save it for offline reading.'
                  : 'Something went wrong.',
              textAlign: TextAlign.center,
            ),
          );
        }

        return const Center(
            child: CustomText(text: "Something went wrong."));
      },
    );
  }

  Widget _buildMessagesList(
    BuildContext context,
    List<MessageModel> messages, {
    bool hasMore = true,
    bool loadingMore = false,
  }) {
    return GroupChatMessageList(
      chatId: context.read<ChatCubit>().chatId,
      messages: messages,
      hasMore: hasMore,
      loadingMore: loadingMore,
      readOnly: widget.readOnly,
      scrollController: widget.scrollController,
      itemBuilder: (context, index) => _MessageTile(
        message: messages[index],
        messages: messages,
        index: index,
        messageKeys: widget.messageKeys,
        groupMembers: widget.groupMembers,
        chatName: widget.chatName,
        highlighted:
            widget.highlightedMessageId == messages[index].id,
        readOnly: widget.readOnly,
        onJoinCall: widget.onJoinCallFromMessage,
        onTapReplied: widget.onJumpToMessage,
      ),
      onLoadMore: () => context.read<ChatCubit>().loadMoreMessages(),
      onJumpTo: widget.onJumpToMessage,
      onJoinActiveCall: widget.onJoinActiveCall,
    );
  }
}

/// A single group-chat row: the [GroupChatMessageTile] plus an optional day
/// separator above it.
class _MessageTile extends StatelessWidget {
  final MessageModel message;
  final List<MessageModel> messages;
  final int index;
  final Map<String, GlobalKey> messageKeys;
  final Map<String, UserModel> groupMembers;
  final String chatName;
  final bool highlighted;
  final bool readOnly;
  final ValueChanged<MessageModel> onJoinCall;
  final ValueChanged<String> onTapReplied;

  const _MessageTile({
    required this.message,
    required this.messages,
    required this.index,
    required this.messageKeys,
    required this.groupMembers,
    required this.chatName,
    required this.highlighted,
    required this.readOnly,
    required this.onJoinCall,
    required this.onTapReplied,
  });

  @override
  Widget build(BuildContext context) {
    if (message.messageType == MessageType.callActive) {
      return const SizedBox.shrink();
    }

    final showDaySeparator = index > 0 &&
        !DaySeparator.isSameDay(
          message.timestamp.toDate(),
          messages[index - 1].timestamp.toDate(),
        );

    return GroupChatMessageTile(
      bubbleKey: messageKeys[message.id] ??= GlobalKey(),
      message: message,
      isMe: message.senderId == FirebaseAuth.instance.currentUser!.uid,
      chatName: chatName,
      members: groupMembers,
      showDaySeparator: showDaySeparator,
      highlighted: highlighted,
      readOnly: readOnly,
      onJoinCall: onJoinCall,
      onTapReplied: onTapReplied,
    );
  }
}