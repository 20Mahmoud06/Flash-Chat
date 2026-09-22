import 'dart:async';
import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import '../../../core/utils/message_preview.dart';
import '../../chat/widgets/day_separator.dart';
import 'home_chat_tile_view.dart';

/// A single chat / group row on the home screen.
/// Each row owns its own live stream for the last message, so a new message
/// only updates that row — the rest of the list never flickers or reloads.
/// Unread conversations get the app's main color border + a count badge.
class HomeChatListTile extends StatefulWidget {
  final String chatDocId;
  final String collectionName; // 'chats' | 'groups'
  final String avatar;
  final String title;
  final String prefixName;
  final bool isGroup;
  final bool isSelfChat;
  final String currentUid;
  final int unreadCount;

  /// Group read watermark (`groups/{id}.lastSeen.{uid}`). Only used when
  /// [isGroup] is true; null means the member has never opened the group.
  final Timestamp? groupLastSeenAt;
  final bool isBlocked;
  final bool isDeleted;
  final bool isNewChat;
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const HomeChatListTile({
    super.key,
    required this.chatDocId,
    required this.collectionName,
    required this.avatar,
    required this.title,
    required this.prefixName,
    required this.isGroup,
    required this.isSelfChat,
    required this.currentUid,
    required this.unreadCount,
    this.groupLastSeenAt,
    this.isBlocked = false,
    this.isDeleted = false,
    this.isNewChat = false,
    this.isPinned = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<HomeChatListTile> createState() => _HomeChatListTileState();
}

class _HomeChatListTileState extends State<HomeChatListTile> {
  /// True while the brand-new-chat entrance glow and NEW pill are showing.
  /// Flips off a few seconds after the tile appears; the highlight fades via
  /// [AnimatedContainer] so the switch is smooth.
  bool _newHighlight = false;

  @override
  void initState() {
    super.initState();
    if (widget.isNewChat) {
      _newHighlight = true;
      Timer(const Duration(milliseconds: 2800), () {
        if (mounted) setState(() => _newHighlight = false);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.chatDocId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = (snapshot.hasData ? snapshot.data!.docs : <dynamic>[])
            .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
        final msgData =
            docs.isNotEmpty ? docs.first.data() : <String, dynamic>{};

        // Count the unseen messages. 1-1 chats use each message's `status`
        // (messages are marked 'seen' when the chat is opened). Group messages
        // are never individually marked, so they compare against my per-member
        // `lastSeen` watermark on the group doc — same badge/border behavior.
        int unseenCount = 0;
        if (widget.isGroup) {
          // No watermark yet (group never opened since this feature landed):
          // show nothing rather than flagging the entire existing history as
          // unread. The first open writes `lastSeen` and enables the badge.
          final lastSeenMs =
              widget.groupLastSeenAt?.millisecondsSinceEpoch;
          if (lastSeenMs != null) {
            for (final doc in docs) {
              final m = doc.data();
              if (m['senderId'] == widget.currentUid) continue;
              if (m['isDeleted'] == true) continue;
              final ts = m['timestamp'];
              if (ts is Timestamp && ts.millisecondsSinceEpoch <= lastSeenMs) {
                continue;
              }
              unseenCount++;
            }
          }
        } else {
          for (final doc in docs) {
            final m = doc.data();
            if (m['senderId'] == widget.currentUid) continue;
            if (m['status'] == 'seen') continue;
            unseenCount++;
          }
        }

        var lastMessage = messagePreviewText(msgData);
        String time = '';
        String prefix = '';

        if (msgData.isNotEmpty) {
          if (msgData['timestamp'] != null) {
            time = lastMessageTimeLabel(
                (msgData['timestamp'] as Timestamp).toDate());
          }
          final senderId = msgData['senderId'] ?? '';
          if (senderId == widget.currentUid) {
            prefix = 'You: ';
          } else if (widget.isGroup) {
            prefix = '${msgData['senderName'] ?? 'Someone'}: ';
          } else {
            prefix = '${widget.prefixName}: ';
          }
        }

        // Unread detection reads the live message stream for BOTH 1-1 chats
        // and groups, so the badge appears/clears as soon as a message arrives
        // or the chat is opened. Never shown before the stream has data, so
        // tiles can't flash the wrong state.
        final bool isUnread = snapshot.hasData && unseenCount > 0;
        final int badgeCount = unseenCount;

        final Widget tile = HomeChatTileView(
          avatar: widget.avatar,
          title: widget.title,
          isPinned: widget.isPinned,
          isDeleted: widget.isDeleted,
          isBlocked: widget.isBlocked,
          isNewHighlight: _newHighlight,
          isUnread: isUnread,
          badgeCount: badgeCount,
          prefix: prefix,
          lastMessage: lastMessage,
          time: time,
          onTap: widget.onTap,
          onLongPress: widget.onLongPress,
        );

        // Brand-new chats get a more noticeable entrance (slide from above),
        // every other tile keeps the usual quiet fade-in.
        return widget.isNewChat
            ? FadeInDown(
                duration: const Duration(milliseconds: 650),
                child: tile,
              )
            : FadeInUp(
                duration: const Duration(milliseconds: 300),
                child: tile,
              );
      },
    );
  }
}
