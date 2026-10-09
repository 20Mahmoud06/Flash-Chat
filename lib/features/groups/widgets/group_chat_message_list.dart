import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../chat/cubit/chat_cubit.dart';
import '../../chat/models/message_model.dart';
import '../../chat/widgets/pinned_message_banner.dart';
import '../../calls/bloc/call_bloc.dart';
import '../../calls/services/group_call_tracker.dart';
import 'join_call_card.dart';

/// The message list body of a group chat: the reversed lazy [ListView]-builder
/// with infinite scroll (and a pagination spinner), the pinned-message banner
/// above it, and — while a group call is in progress — a WhatsApp-style
/// "Join call" card at the newest position. Pure composition: new message
/// rows are supplied through [itemBuilder], and values that depend on screen
/// state (jump-to-message, joining a live call) are forwarded as callbacks.
class GroupChatMessageList extends StatelessWidget {
  final String chatId;
  final List<MessageModel> messages;
  final bool hasMore;
  final bool loadingMore;
  final bool readOnly;
  final ScrollController scrollController;
  final Widget Function(BuildContext, int) itemBuilder;
  final VoidCallback onLoadMore;
  final ValueChanged<String> onJumpTo;
  final ValueChanged<ActiveGroupCall> onJoinActiveCall;

  const GroupChatMessageList({
    super.key,
    required this.chatId,
    required this.messages,
    required this.hasMore,
    required this.loadingMore,
    required this.readOnly,
    required this.scrollController,
    required this.itemBuilder,
    required this.onLoadMore,
    required this.onJumpTo,
    required this.onJoinActiveCall,
  });

  @override
  Widget build(BuildContext context) {
    // A group call currently in progress surfaces a WhatsApp-style "Join
    // call" card pinned between the app-bar/pinned-message banner and the
    // message list — it never floats over (and hides) the newest messages or
    // the composer.
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
                  ? () => onJumpTo(pin['messageId']!.toString())
                  : null,
              onUnpin: () => context.read<ChatCubit>().unpinMessage(),
            );
          },
        ),
        ListenableBuilder(
          listenable: GroupCallTracker.instance,
          builder: (context, _) {
            final track = GroupCallTracker.instance.callForGroup(chatId);
            if (track == null) return const SizedBox.shrink();

            final showJoin =
                FirebaseAuth.instance.currentUser?.uid != track.callerId &&
                    !CallBloc.instance.isCallActive &&
                    !readOnly;
            if (!showJoin) return const SizedBox.shrink();

            // Top: a thin divider keeps the banner visually attached to the
            // list top; Alignment.topCenter makes it shrink to its content
            // instead of the full available height.
            return Column(
              children: [
                const SizedBox(height: 8),
                JoinCallCard(
                  call: track,
                  callerId: FirebaseAuth.instance.currentUser?.uid ?? '',
                  canJoin: true,
                  onJoin: () => onJoinActiveCall(track),
                ),
                const SizedBox(height: 2),
              ],
            );
          },
        ),
        Expanded(
          child: NotificationListener<ScrollNotification>(
            onNotification: (scroll) {
              if (hasMore &&
                  scroll.metrics.pixels >=
                      scroll.metrics.maxScrollExtent - 40) {
                onLoadMore();
              }
              return false;
            },
            child: ListView.builder(
              controller: scrollController,
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
                return itemBuilder(context, index);
              },
            ),
          ),
        ),
      ],
    );
  }
}