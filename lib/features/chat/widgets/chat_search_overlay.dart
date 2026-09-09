import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';

import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';

/// WhatsApp-style in-chat search: a search field below the app bar with a
/// live results dropdown, a "n of m" counter and up/down arrows. Tapping a
/// result (or using the arrows) jumps the chat to that message.
class ChatSearchOverlay extends StatefulWidget {
  final bool isGroup;
  final String myUid;

  /// uid -> UserModel. For 1:1 chats it must contain both me and the contact
  /// so result tiles can show the sender's name and avatar.
  final Map<String, UserModel> members;
  final VoidCallback onClose;
  final void Function(String messageId) onJumpTo;

  const ChatSearchOverlay({
    super.key,
    required this.isGroup,
    required this.myUid,
    required this.members,
    required this.onClose,
    required this.onJumpTo,
  });

  @override
  State<ChatSearchOverlay> createState() => _ChatSearchOverlayState();
}

class _ChatSearchOverlayState extends State<ChatSearchOverlay> {
  final TextEditingController _controller = TextEditingController();
  String _query = '';
  int _selectedIndex = 0;
  bool _loadingAll = true;

  @override
  void initState() {
    super.initState();
    // Search must see every message, so pull the whole history into memory
    // the first time the search is opened.
    context.read<ChatCubit>().loadAllMessages().whenComplete(() {
      if (!mounted) return;
      setState(() => _loadingAll = false);
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  List<MessageModel> _matches(ChatState state) {
    final q = _query.trim().toLowerCase();
    if (q.isEmpty || state is! ChatLoaded) return const [];
    // Only real user-to-user messages should surface in search. System
    // notices (e.g. "X added Y") and call-history entries are metadata, not
    // searchable content.
    return state.messages.where((m) {
      if (m.isDeleted || m.messageType == MessageType.system) return false;
      if (m.messageType == MessageType.call ||
          m.messageType == MessageType.callActive) {
        return false;
      }
      return m.text.trim().toLowerCase().contains(q);
    }).toList();
  }

  void _onQueryChanged(String value) {
    setState(() {
      _query = value;
      _selectedIndex = 0;
    });
  }

  void _jumpToIndex(int index, List<MessageModel> matches) {
    if (matches.isEmpty) return;
    setState(() =>
        _selectedIndex = (index % matches.length + matches.length) % matches.length);
    widget.onJumpTo(matches[_selectedIndex].id);
  }

  String _timeOf(Timestamp t) => DateFormat('h:mm a').format(t.toDate());

  String _dayOf(Timestamp t) {
    final now = DateTime.now();
    final date = t.toDate();
    final today = DateTime(now.year, now.month, now.day);
    final day = DateTime(date.year, date.month, date.day);
    final diff = today.difference(day).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    if (date.year == now.year) return DateFormat('EEE, MMM d').format(date);
    return DateFormat('MMM d, yyyy').format(date);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        final matches = _matches(state);

        return Material(
          elevation: 3,
          color: colors.surface,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back_rounded),
                      color: colors.textSecondary,
                      onPressed: widget.onClose,
                    ),
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        autofocus: true,
                        style: TextStyle(color: colors.textPrimary),
                        cursorColor: colors.bubbleMine,
                        decoration: InputDecoration(
                          hintText: 'Search messages',
                          hintStyle:
                              TextStyle(color: colors.textWeak, fontSize: 15),
                          border: InputBorder.none,
                          isDense: true,
                        ),
                        onChanged: _onQueryChanged,
                      ),
                    ),
                    if (matches.isNotEmpty) ...[
                      Text(
                        '${_selectedIndex + 1} / ${matches.length}',
                        style: TextStyle(
                          color: colors.textSecondary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_up_rounded),
                        color: colors.textSecondary,
                        visualDensity: VisualDensity.compact,
                        onPressed: matches.isEmpty
                            ? null
                            : () => _jumpToIndex(_selectedIndex - 1, matches),
                      ),
                      IconButton(
                        icon: const Icon(Icons.keyboard_arrow_down_rounded),
                        color: colors.textSecondary,
                        visualDensity: VisualDensity.compact,
                        onPressed: matches.isEmpty
                            ? null
                            : () => _jumpToIndex(_selectedIndex + 1, matches),
                      ),
                    ] else
                      IconButton(
                        icon: const Icon(Icons.close_rounded),
                        color: colors.textSecondary,
                        visualDensity: VisualDensity.compact,
                        onPressed: widget.onClose,
                      ),
                  ],
                ),
              ),
              if (_loadingAll)
                const LinearProgressIndicator(minHeight: 2)
              else if (matches.isNotEmpty)
                _buildResults(colors, matches),
              if (!_loadingAll &&
                  _query.trim().isNotEmpty &&
                  matches.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(14),
                  child: Row(
                    children: [
                      Icon(Icons.search_off_rounded,
                          color: colors.textWeak, size: 18),
                      const SizedBox(width: 8),
                      Text(
                        'No messages found',
                        style: TextStyle(
                            color: colors.textSecondary, fontSize: 14),
                      ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildResults(FcAppColors colors, List<MessageModel> matches) {
    return ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.45,
      ),
      child: ListView.builder(
        shrinkWrap: true,
        itemCount: matches.length,
        itemBuilder: (context, index) {
          final message = matches[index];
          final isMe = message.senderId == widget.myUid;
          final sender = widget.members[message.senderId];
          final senderName = isMe
              ? 'You'
              : (sender != null
                  ? '${sender.firstName} ${sender.lastName}'
                  : 'Unknown');
          final avatar = isMe
              ? (widget.members[widget.myUid]?.avatarEmoji ?? '👤')
              : (sender?.avatarEmoji ?? '👤');

          final isSelected = index == _selectedIndex;
          return ListTile(
            dense: true,
            selected: isSelected,
            selectedTileColor: colors.bubbleMine.withValues(alpha: 0.15),
            leading: CircleAvatar(
              radius: 18,
              backgroundColor: colors.avatarBackground,
              child: Text(avatar, style: const TextStyle(fontSize: 16)),
            ),
            title: Text(
              senderName,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                color: colors.textPrimary,
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
              ),
            ),
            subtitle: Text(
              message.text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: colors.textSecondary, fontSize: 13),
            ),
            trailing: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  _dayOf(message.timestamp),
                  style:
                      TextStyle(color: colors.textWeak, fontSize: 11),
                ),
                const SizedBox(height: 2),
                Text(
                  _timeOf(message.timestamp),
                  style: TextStyle(color: colors.textWeak, fontSize: 12),
                ),
              ],
            ),
            onTap: () {
              setState(() => _selectedIndex = index);
              widget.onClose();
              widget.onJumpTo(message.id);
            },
          );
        },
      ),
    );
  }
}
