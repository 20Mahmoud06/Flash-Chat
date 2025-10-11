import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/screens/profile/sender_profile_screen.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:swipe_to/swipe_to.dart';
import '../../cubits/chat_cubit/chat_cubit.dart';
import '../../cubits/chat_cubit/chat_state.dart';
import '../../widgets/page_transition.dart';
import '../profile/group_info_screen.dart';

class ChatScreen extends StatefulWidget {
  final UserModel? contact;
  final GroupModel? group;

  const ChatScreen({super.key, this.contact, this.group})
      : assert(contact != null || group != null,
  'Either a contact or a group must be provided');

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final String _chatId;
  late final bool _isGroupChat;
  late final String _chatName;
  late final String _chatAvatar;

  Map<String, UserModel> _groupMembers = {};
  UserModel? _myUser;
  bool _isLoadingMembers = false;
  bool _isLoadingMyUser = true;

  @override
  void initState() {
    super.initState();
    _isGroupChat = widget.group != null;

    final currentUser = FirebaseAuth.instance.currentUser!;

    if (_isGroupChat) {
      final group = widget.group!;
      _chatId = group.id;
      _chatName = group.name;
      _chatAvatar = group.avatarEmoji;
      _isLoadingMembers = true;
      _fetchGroupMembers(group.memberUids);
    } else {
      final contact = widget.contact!;
      var uids = [currentUser.uid, contact.uid]..sort();
      _chatId = uids.join('_');
      _chatName = "${contact.firstName} ${contact.lastName}";
      _chatAvatar = contact.avatarEmoji;
    }

    _fetchMyUser();
  }

  Future<void> _fetchMyUser() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser!;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (mounted) {
        setState(() {
          _myUser = UserModel.fromFirestore(doc);
          _isLoadingMyUser = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching my user: $e");
    }
  }

  Future<void> _fetchGroupMembers(List<String> uids) async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: uids)
          .get();

      final members = <String, UserModel>{};
      for (var doc in usersSnapshot.docs) {
        members[doc.id] = UserModel.fromFirestore(doc);
      }
      if (mounted) {
        setState(() {
          _groupMembers = members;
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching group members: $e");
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatCubit(
        chatId: _chatId,
        isGroupChat: _isGroupChat,
        recipientId: _isGroupChat ? null : widget.contact!.uid,
        recipient: _isGroupChat ? null : widget.contact,
      ),
      child: Scaffold(
        backgroundColor: Colors.grey.shade200,
        appBar: AppBar(
          elevation: 1,
          backgroundColor: Colors.lightBlueAccent,
          iconTheme: const IconThemeData(color: Colors.white),
          title: GestureDetector(
            onTap: () {
              if (_isGroupChat) {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => GroupInfoScreen(group: widget.group!),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) => SenderProfileScreen(user: widget.contact!),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              }
            },
            child: Row(
              children: [
                CircleAvatar(
                  backgroundColor: Colors.lightBlue.shade50,
                  child: CustomText(
                      text: _chatAvatar,
                      fontSize: 20.sp),
                ),
                SizedBox(width: 8.w),
                Expanded(
                  child: Text(
                    _chatName,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 18.sp,
                    ),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            IconButton(
              icon: Icon(
                  _isGroupChat ? Icons.group_outlined : Icons.person_outline,
                  color: Colors.white,
                  size: 28),
              onPressed: () {
                if (_isGroupChat && widget.group != null) {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => GroupInfoScreen(group: widget.group!),
                      transitionsBuilder: PageTransition.slideFromRight,
                    ),
                  );
                } else if (!_isGroupChat && widget.contact != null) {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) => SenderProfileScreen(user: widget.contact!),
                      transitionsBuilder: PageTransition.slideFromRight,
                    ),
                  );
                }
              },
            ),
            SizedBox(width: 8.w),
          ],
        ),
        body: Column(
          children: [
            Expanded(
              child: BlocConsumer<ChatCubit, ChatState>(
                listener: (context, state) {
                  if (state is ChatError) {
                    ScaffoldMessenger.of(context)
                      ..hideCurrentSnackBar()
                      ..showSnackBar(SnackBar(
                        content: Text(state.message),
                        backgroundColor: Colors.red,
                      ));
                  }
                },
                builder: (context, state) {
                  if (state is ChatLoading ||
                      state is ChatInitial ||
                      _isLoadingMyUser ||
                      _isLoadingMembers) {
                    return const Center(
                        child: CircularProgressIndicator(
                            color: Colors.lightBlueAccent));
                  }

                  if (state is ChatLoaded) {
                    if (state.messages.isEmpty) {
                      return const Center(child: CustomText(text: "Say hello! 👋"));
                    }
                    return ListView.builder(
                      reverse: true,
                      itemCount: state.messages.length,
                      itemBuilder: (context, index) {
                        final message = state.messages[index];
                        final isMe = message.senderId ==
                            FirebaseAuth.instance.currentUser!.uid;

                        final sender =
                        _isGroupChat ? _groupMembers[message.senderId] : null;

                        final senderAvatar = _isGroupChat
                            ? (sender?.avatarEmoji ?? '👤')
                            : (isMe
                            ? (_myUser?.avatarEmoji ?? '👤')
                            : widget.contact!.avatarEmoji);

                        final senderName = _isGroupChat
                            ? (sender != null ? '${sender.firstName} ${sender.lastName}' : 'Unknown')
                            : (isMe ? 'You' : _chatName ?? 'Unknown');

                        final messageWidget = MessageBubble(
                          message: message,
                          isMe: isMe,
                          isGroup: _isGroupChat,
                          sender: sender,
                          senderAvatar: senderAvatar,
                          contactName: _chatName,
                        );

                        if (message.isDeleted) {
                          return messageWidget;
                        }

                        return SwipeTo(
                          onRightSwipe: (details) {
                            context.read<ChatCubit>().setReplyingTo(message, senderName);
                          },
                          child: messageWidget,
                        );
                      },
                    );
                  }
                  return const Center(child: CustomText(text: "Something went wrong."));
                },
              ),
            ),
            MessageComposer(chatId: _chatId, isGroup: _isGroupChat),
          ],
        ),
      ),
    );
  }
}

class MessageBubble extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final bool isGroup;
  final UserModel? sender; // Sender info for group chats
  final String senderAvatar; // Avatar for the sender of this message
  final String? contactName;

  const MessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    required this.isGroup,
    this.sender,
    required this.senderAvatar,
    this.contactName,
  });

  @override
  Widget build(BuildContext context) {
    final alignment = isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = isMe ? Colors.lightBlueAccent : Colors.white;
    final textColor = isMe ? Colors.white : Colors.black87;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: 4.h,
        horizontal: 8.w,
      ).copyWith(bottom: message.reactions.isNotEmpty ? 15.h : 4.h),
      child: GestureDetector(
        onLongPress: () {
          if (message.isDeleted) return;
          _showMessageOptions(context);
        },
        child: Column(
          crossAxisAlignment: alignment,
          children: [
            if (isGroup && !isMe && sender != null)
              Padding(
                padding: EdgeInsets.only(left: 48.w, bottom: 4.h),
                child: CustomText(
                    text:  '${sender!.firstName} ${sender!.lastName}',
                    fontSize: 12.sp, textColor: Colors.grey.shade600),
              ),
            Row(
              mainAxisAlignment: isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!isMe)
                  Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: CircleAvatar(
                      radius: 18.r,
                      backgroundColor: Colors.transparent,
                      child: CustomText(text: senderAvatar, fontSize: 18.sp),
                    ),
                  ),
                Flexible(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        constraints: BoxConstraints(maxWidth: 0.7.sw),
                        padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 14.w),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(18.r),
                            topRight: Radius.circular(18.r),
                            bottomLeft: isMe ? Radius.circular(18.r) : Radius.circular(4.r),
                            bottomRight: isMe ? Radius.circular(4.r) : Radius.circular(18.r),
                          ),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (message.repliedTo != null)
                              Container(
                                margin: EdgeInsets.only(bottom: 8.h),
                                padding: EdgeInsets.all(8.w),
                                decoration: BoxDecoration(
                                  color: Colors.lightBlue.shade50,
                                  borderRadius: BorderRadius.circular(8.r),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CustomText(
                                      text: message.repliedTo!['senderName'] ?? 'Unknown',
                                      fontSize: 12.sp,
                                      textColor: Colors.grey.shade800,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    CustomText(
                                      text: message.repliedTo!['text'] ?? '',
                                      fontSize: 13.sp,
                                      textColor: Colors.grey.shade700,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            message.isDeleted
                                ? Text("This message was deleted", style: TextStyle(fontStyle: FontStyle.italic, color: textColor.withOpacity(0.7)))
                                : CustomText(text: message.text, textColor: textColor, fontSize: 15.sp),
                            SizedBox(height: 4.h),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (message.isEdited)
                                  CustomText(text: "Edited · ", textColor: textColor.withOpacity(0.7), fontSize: 11.sp),
                                Text(
                                  DateFormat('h:mm a').format(message.timestamp.toDate()),
                                  style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 11.sp),
                                ),
                                if (isMe && !message.isDeleted) ...[
                                  SizedBox(width: 4.w),
                                  Icon(
                                    message.status == 'seen' ? Icons.done_all : (message.status == 'delivered' ? Icons.done_all : Icons.done),
                                    size: 14.sp,
                                    color: message.status == 'seen' ? Colors.blue : textColor.withOpacity(0.7),
                                  ),
                                ]
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (message.reactions.isNotEmpty)
                        Positioned(
                          bottom: -15.h,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: Container(
                              padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                              decoration: BoxDecoration(
                                color: Colors.grey.shade200,
                                borderRadius: BorderRadius.circular(12.r),
                                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5, spreadRadius: 1)],
                              ),
                              child: CustomText(text: message.reactions.values.toSet().join(''),
                                  fontSize: 14.sp),
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
                      child: CustomText(text: senderAvatar, fontSize: 18.sp),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    final chatCubit = context.read<ChatCubit>();
    final currentUser = FirebaseAuth.instance.currentUser!;
    final currentReaction = message.reactions[currentUser.uid];

    final String senderName = isGroup
        ? (sender != null ? '${sender!.firstName} ${sender!.lastName}' : 'Unknown')
        : (isMe ? 'You' : contactName ?? 'Unknown');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final List<String> quickReactions = ['❤️', '😂', '😮', '😢', '👍'];
        return Container(
          margin: EdgeInsets.all(8.w),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(15.r)),
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
                            chatCubit.updateReaction(message.id, emoji);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: currentReaction == emoji ? Colors.lightBlue.shade100 : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: CustomText(text: emoji,fontSize: 24.sp),
                          ),
                        );
                      }),
                      IconButton(
                        icon: Icon(Icons.add_reaction_outlined, color: Colors.grey.shade600),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEmojiPicker(context, (selectedEmoji) {
                            chatCubit.updateReaction(message.id, selectedEmoji);
                          });
                        },
                      )
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: const Icon(Icons.reply, color: Colors.blueGrey),
                  title: const CustomText(text: 'Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    chatCubit.setReplyingTo(message, senderName);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.grey),
                  title: const CustomText(text: 'Copy'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: message.text));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 20.sp),
                            SizedBox(width: 12.w),
                            CustomText(text: 'Message copied to clipboard'),
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
                      _showInfoDialog(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.edit_outlined, color: Colors.green),
                    title: const CustomText(text: 'Edit'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEditDialog(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: const CustomText(text: 'Delete'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showDeleteConfirmation(context);
                    },
                  ),
                ]
              ],
            ),
          ),
        );
      },
    );
  }

  void _showEmojiPicker(BuildContext context, Function(String) onEmojiSelected) {
    showModalBottomSheet(
      context: context,
      builder: (context) => EmojiPicker(
        onEmojiSelected: (category, emoji) {
          onEmojiSelected(emoji.emoji);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _showInfoDialog(BuildContext context) {
    String statusText = "Sent";
    IconData statusIcon = Icons.done;
    Color statusColor = Colors.grey;

    if (message.status == 'delivered') {
      statusText = "Delivered";
      statusIcon = Icons.done_all;
    } else if (message.status == 'seen') {
      statusText = "Seen";
      statusIcon = Icons.done_all;
      statusColor = Colors.blue;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
        title: const CustomText(text: "Message Info",fontWeight: FontWeight.bold,textColor: Colors.black),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(statusIcon, color: statusColor),
              title: CustomText(text: statusText),
              subtitle: Text(DateFormat.yMMMd().add_jm().format(message.timestamp.toDate())),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent),
            onPressed: () => Navigator.of(context).pop(),
            child: const CustomText(text: "OK",fontWeight: FontWeight.bold,textColor: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: message.text);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const CustomText(text: "Edit Message"),
        content: TextField(
          decoration: InputDecoration(
            focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: const BorderSide(color: Colors.lightBlueAccent)),
            enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r), borderSide: BorderSide(color: Colors.grey.shade600)),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
            hintText: "Edit your message",
            filled: true,
            fillColor: Colors.grey.shade200,
            contentPadding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          ),
          cursorColor: Colors.black,
          maxLines: null,
          strutStyle: const StrutStyle(fontSize: 15),
          controller: controller,
          style: const TextStyle(color: Colors.black
          ),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const CustomText(text: "Cancel",textColor: Colors.black)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent),
            onPressed: () {
              final newText = controller.text.trim();
              if (newText.isNotEmpty && newText != message.text) {
                context.read<ChatCubit>().editMessage(message.id, newText);
              }
              Navigator.of(ctx).pop();
            },
            child: const CustomText(text: "Save",textColor: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showDeleteConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const CustomText(text: "Delete Message"),
        content: const CustomText(text: "Are you sure you want to delete this message?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const CustomText(text: "Cancel",textColor: Colors.black)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<ChatCubit>().deleteMessage(message.id);
              Navigator.of(ctx).pop();
            },
            child: const CustomText(text: "Delete",textColor: Colors.white),
          ),
        ],
      ),
    );
  }

}

class MessageComposer extends StatefulWidget {
  final String chatId;
  final bool isGroup;

  const MessageComposer({super.key, required this.chatId, required this.isGroup});

  @override
  State<MessageComposer> createState() => _MessageComposerState();
}

class _MessageComposerState extends State<MessageComposer> {
  final _controller = TextEditingController();
  UserModel? _sender;

  @override
  void initState() {
    super.initState();
    _loadSenderUser();
  }

  Future<void> _loadSenderUser() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final doc =
    await FirebaseFirestore.instance.collection('users').doc(user.uid).get();
    if (mounted) {
      setState(() {
        _sender = UserModel.fromFirestore(doc);
      });
    }
  }

  void _sendMessage() {
    final text = _controller.text.trim();
    if (text.isEmpty || _sender == null) return;

    context.read<ChatCubit>().sendMessage(text, _sender!);
    _controller.clear();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ChatCubit, ChatState>(
      builder: (context, state) {
        MessageModel? replyingTo;
        String? replyingToSenderName;
        if (state is ChatLoaded) {
          replyingTo = state.replyingTo;
          replyingToSenderName = state.replyingToSenderName;
        }

        return Container(
          padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 10.h),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                  color: Colors.grey.withOpacity(0.3),
                  spreadRadius: 2,
                  blurRadius: 5)
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (replyingTo != null)
                  Container(
                    padding: EdgeInsets.all(8.w),
                    color: Colors.lightBlue.shade50,
                    child: Row(
                      children: [
                        Container(
                          width: 4.w,
                          height: 40.h,
                          color: Colors.lightBlueAccent,
                        ),
                        SizedBox(width: 8.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CustomText(
                                text: replyingToSenderName ?? 'Unknown',
                                fontWeight: FontWeight.bold,
                                textColor: Colors.lightBlueAccent,
                              ),
                              CustomText(
                                text: replyingTo.text,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.close, color: Colors.grey),
                          onPressed: () {
                            context.read<ChatCubit>().setReplyingTo(null, null);
                          },
                        ),
                      ],
                    ),
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _controller,
                        textCapitalization: TextCapitalization.sentences,
                        keyboardType: TextInputType.multiline,
                        minLines: 1,
                        maxLines: 6,
                        decoration: InputDecoration(
                          hintText: 'Type a message...',
                          border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(20.r),
                              borderSide: BorderSide.none),
                          filled: true,
                          fillColor: Colors.grey.shade200,
                          contentPadding:
                          EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                        ),
                      ),
                    ),
                    SizedBox(width: 8.w),
                    IconButton(
                      icon: const Icon(Icons.send, color: Colors.lightBlueAccent),
                      onPressed: _sendMessage,
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}