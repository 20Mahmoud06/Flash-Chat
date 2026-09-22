import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/features/chat/cubit/chat_cubit.dart';
import 'package:flash_chat_app/features/chat/cubit/chat_state.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:swipe_to/swipe_to.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../shared/widgets/custom_text.dart';
import 'chat_empty_state.dart';
import 'day_separator.dart';
import 'message_bubble/message_bubble.dart';
import 'pinned_message_banner.dart';

/// Renders the scrolling conversation area: a realtime state stream that
/// shows the loading / empty / error states, plus the reversed message list
/// with the pinned-message banner and the lazy pagination. The last loaded
/// messages are kept so the chat stays visible while a media upload is in
/// progress (ChatUploading / ChatError replace ChatLoaded).
class ChatMessagesBody extends StatefulWidget {
  final ScrollController scrollController;
  final Map<String, GlobalKey> messageKeys;
  final Map<String, UserModel> members;

  /// Shown as the contact's name inside bubbles / replies.
  final String chatName;

  /// My current avatar (falls back to '👤' when my user doc is not loaded).
  final String myAvatar;

  /// Contact's avatar ('❌' when the account is deleted).
  final String contactAvatar;
  final String? highlightedMessageId;
  final bool accountDeleted;
  final bool myAccountDeleted;
  final bool blockedChat;
  final bool iBlockedContact;
  final ValueChanged<String> onJumpToMessage;

  const ChatMessagesBody({
    super.key,
    required this.scrollController,
    required this.messageKeys,
    required this.members,
    required this.chatName,
    required this.myAvatar,
    required this.contactAvatar,
    required this.highlightedMessageId,
    required this.accountDeleted,
    required this.myAccountDeleted,
    required this.blockedChat,
    required this.iBlockedContact,
    required this.onJumpToMessage,
  });

  @override
  State<ChatMessagesBody> createState() => _ChatMessagesBodyState();
}

class _ChatMessagesBodyState extends State<ChatMessagesBody> {
  /// Kept so the list stays visible while a media upload is in progress
  /// (ChatUploading / ChatError replace ChatLoaded).
  List<MessageModel>? _lastMessages;

  bool get _isDeletedOrBlocked =>
      widget.accountDeleted || widget.blockedChat;

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
            if (_isDeletedOrBlocked || widget.myAccountDeleted) {
              return ChatEmptyState(
                myAccountDeleted: widget.myAccountDeleted,
                accountDeleted: widget.accountDeleted,
                isBlockedChat: widget.blockedChat,
                iBlockedContact: widget.iBlockedContact,
                chatName: widget.chatName,
              );
            }

            return const Center(child: CustomText(text: "Say hello! 👋"));
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
    final Widget list = NotificationListener<ScrollNotification>(
      onNotification: (scroll) {
        if (hasMore &&
            scroll.metrics.pixels >= scroll.metrics.maxScrollExtent - 40) {
          context.read<ChatCubit>().loadMoreMessages();
        }
        return false;
      },
      child: ListView.builder(
        controller: widget.scrollController,
        reverse: true,
        itemCount: messages.length + (loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (loadingMore && index == messages.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.lightBlueAccent,
                  ),
                ),
              ),
            );
          }
          return _MessageTile(
            message: messages[index],
            messages: messages,
            index: index,
            messageKeys: widget.messageKeys,
            members: widget.members,
            myAvatar: widget.myAvatar,
            contactAvatar: widget.contactAvatar,
            chatName: widget.chatName,
            highlighted: widget.highlightedMessageId == messages[index].id,
            onJumpToMessage: widget.onJumpToMessage,
          );
        },
      ),
    );

    return Column(
      children: [
        StreamBuilder<Map<String, dynamic>?>(
          stream: context.read<ChatCubit>().pinnedMessageStream,
          initialData: context.read<ChatCubit>().pinnedMessageNotifier.value,
          builder: (context, snapshot) {
            final pin = snapshot.data;
            if (pin == null) return const SizedBox.shrink();
            return PinnedMessageBanner(
              pin: pin,
              canUnpin: context.read<ChatCubit>().canPin,
              onTap: pin['messageId'] != null
                  ? () =>
                      widget.onJumpToMessage(pin['messageId']!.toString())
                  : null,
              onUnpin: () => context.read<ChatCubit>().unpinMessage(),
            );
          },
        ),
        Expanded(child: list),
      ],
    );
  }
}

/// A single list row: the [MessageBubble] wrapped in the swipe-to-reply
/// gesture, with an optional day separator above it.
class _MessageTile extends StatelessWidget {
  final MessageModel message;
  final List<MessageModel> messages;
  final int index;
  final Map<String, GlobalKey> messageKeys;
  final Map<String, UserModel> members;
  final String myAvatar;
  final String contactAvatar;
  final String chatName;
  final bool highlighted;
  final ValueChanged<String> onJumpToMessage;

  const _MessageTile({
    required this.message,
    required this.messages,
    required this.index,
    required this.messageKeys,
    required this.members,
    required this.myAvatar,
    required this.contactAvatar,
    required this.chatName,
    required this.highlighted,
    required this.onJumpToMessage,
  });

  @override
  Widget build(BuildContext context) {
    final isMe =
        message.senderId == FirebaseAuth.instance.currentUser!.uid;

    final showDaySeparator = index > 0 &&
        !DaySeparator.isSameDay(
          message.timestamp.toDate(),
          messages[index - 1].timestamp.toDate(),
        );

    final senderAvatar = isMe ? myAvatar : contactAvatar;
    final senderName = isMe ? 'You' : chatName;

    final key = messageKeys[message.id] ??= GlobalKey();

    final messageWidget = MessageBubble(
      key: key,
      message: message,
      isMe: isMe,
      isGroup: false,
      sender: null,
      senderAvatar: senderAvatar,
      contactName: chatName,
      members: members,
      highlighted: highlighted,
      onTapReplied: () {
        final repliedId = (message.repliedTo?['id'] ??
                message.repliedTo?['messageId'] ??
                message.repliedTo?['_id'])
            ?.toString();
        if (repliedId != null && repliedId.isNotEmpty) {
          onJumpToMessage(repliedId);
        }
      },
    );

    Widget result = messageWidget;
    if (!message.isDeleted) {
      result = SwipeTo(
        onLeftSwipe: isMe
            ? (details) {
                context
                    .read<ChatCubit>()
                    .setReplyingTo(message, senderName);
              }
            : null,
        onRightSwipe: !isMe
            ? (details) {
                context
                    .read<ChatCubit>()
                    .setReplyingTo(message, senderName);
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