import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/screens/profile/group_info_screen.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:flutter/services.dart';
import 'package:swipe_to/swipe_to.dart';
import '../../models/group_model.dart';
import '../../models/message_model.dart';
import '../../models/user_model.dart';
import '../../widgets/page_transition.dart';

class GroupChatScreen extends StatefulWidget {
  final GroupModel group;
  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  final _controller = TextEditingController();
  Map<String, UserModel> _members = {};
  bool _loadingMembers = true;
  MessageModel? _replyingTo;
  String? _replyingToSenderName;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    try {
      final usersSnapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: widget.group.memberUids)
          .get();

      final members = <String, UserModel>{};
      for (var doc in usersSnapshot.docs) {
        members[doc.id] = UserModel.fromFirestore(doc);
      }

      setState(() {
        _members = members;
        _loadingMembers = false;
      });
    } catch (e) {
      debugPrint("Error loading members: $e");
    }
  }

  Future<void> _sendMessage() async {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    final currentUser = _auth.currentUser!;
    final sender = _members[currentUser.uid];

    Map<String, dynamic>? repliedTo;
    if (_replyingTo != null) {
      repliedTo = {
        'id': _replyingTo!.id,
        'senderId': _replyingTo!.senderId,
        'senderName': _replyingToSenderName,
        'text': _replyingTo!.text,
      };
    }

    final newMsg = {
      'text': text,
      'senderId': currentUser.uid,
      'senderName': '${sender?.firstName ?? ''} ${sender?.lastName ?? ''}',
      'timestamp': FieldValue.serverTimestamp(),
      'isEdited': false,
      'isDeleted': false,
      'reactions': <String, String>{},
      'status': 'sent',
      if (repliedTo != null) 'repliedTo': repliedTo,
    };

    await _firestore
        .collection('groups')
        .doc(widget.group.id)
        .collection('messages')
        .add(newMsg);

    _controller.clear();
    setState(() {
      _replyingTo = null;
      _replyingToSenderName = null;
    });
  }

  void _setReplyingTo(MessageModel message, String senderName) {
    setState(() {
      _replyingTo = message;
      _replyingToSenderName = senderName;
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.pop(context),
        ),
        title: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.lightBlue.shade50,
              child: CustomText(text: widget.group.avatarEmoji, fontSize: 22.sp),
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: Text(
                widget.group.name,
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
        elevation: 0,
        backgroundColor: Colors.lightBlueAccent,
        actions: [
          IconButton(
            icon: const Icon(Icons.group_outlined, color: Colors.white),
            onPressed: () {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) => GroupInfoScreen(group: widget.group),
                  transitionsBuilder: PageTransition.slideFromRight,
                ),
              );
            },
          ),
        ],
      ),
      body: _loadingMembers
          ? const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent))
          : Column(
        children: [
          Expanded(
            child: StreamBuilder<QuerySnapshot>(
              stream: _firestore
                  .collection('groups')
                  .doc(widget.group.id)
                  .collection('messages')
                  .orderBy('timestamp', descending: true)
                  .snapshots(),
              builder: (context, snapshot) {
                if (!snapshot.hasData) {
                  return const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent));
                }
                if (snapshot.data!.docs.isEmpty) {
                  return const Center(child: CustomText(text: "No messages yet 👋"));
                }

                final messages = snapshot.data!.docs
                    .map((doc) => MessageModel.fromFirestore(doc))
                    .toList();

                return ListView.builder(
                  reverse: true,
                  itemCount: messages.length,
                  itemBuilder: (context, index) {
                    final msg = messages[index];
                    final sender = _members[msg.senderId];
                    final isMe = msg.senderId == _auth.currentUser!.uid;

                    final messageWidget = GroupMessageBubble(
                      message: msg,
                      isMe: isMe,
                      sender: sender,
                      group: widget.group,
                      members: _members,
                      onReply: _setReplyingTo,
                    );

                    if (msg.isDeleted) {
                      return messageWidget;
                    }

                    return SwipeTo(
                      onRightSwipe: (details) {
                        _setReplyingTo(msg, msg.senderName ?? 'Unknown');
                      },
                      child: messageWidget,
                    );
                  },
                );
              },
            ),
          ),
          _buildComposer(),
        ],
      ),
    );
  }

  Widget _buildComposer() {
    return SafeArea(
      child: Container(
        padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 8.h),
        color: Colors.white,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_replyingTo != null)
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
                            text: _replyingToSenderName ?? 'Unknown',
                            fontWeight: FontWeight.bold,
                            textColor: Colors.lightBlueAccent,
                          ),
                          CustomText(
                            text: _replyingTo!.text,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.close, color: Colors.grey),
                      onPressed: () {
                        setState(() {
                          _replyingTo = null;
                          _replyingToSenderName = null;
                        });
                      },
                    ),
                  ],
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _controller,
                    textCapitalization: TextCapitalization.sentences,
                    keyboardType: TextInputType.multiline,
                    minLines: 1,
                    maxLines: 6,
                    decoration: InputDecoration(
                      hintText: "Type a message...",
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20.r),
                        borderSide: BorderSide.none,
                      ),
                      filled: true,
                      fillColor: Colors.grey.shade200,
                      contentPadding:
                      EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
                SizedBox(width: 8.w),
                IconButton(
                  onPressed: _sendMessage,
                  icon: const Icon(Icons.send, color: Colors.lightBlueAccent),
                )
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class GroupMessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final UserModel? sender;
  final GroupModel group;
  final Map<String, UserModel> members;
  final Function(MessageModel, String) onReply;

  const GroupMessageBubble({
    super.key,
    required this.message,
    required this.isMe,
    this.sender,
    required this.group,
    required this.members,
    required this.onReply,
  });

  @override
  State<GroupMessageBubble> createState() => _GroupMessageBubbleState();
}

class _GroupMessageBubbleState extends State<GroupMessageBubble> {
  @override
  Widget build(BuildContext context) {
    final alignment = widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = widget.isMe ? Colors.lightBlueAccent : Colors.white;
    final textColor = widget.isMe ? Colors.white : Colors.black87;

    return Padding(
      padding: EdgeInsets.symmetric(
        vertical: 4.h,
        horizontal: 8.w,
      ).copyWith(bottom: widget.message.reactions.isNotEmpty ? 15.h : 4.h),
      child: GestureDetector(
        onLongPress: () {
          if (widget.message.isDeleted) return;
          _showMessageOptions(context);
        },
        child: Column(
          crossAxisAlignment: alignment,
          children: [
            if (!widget.isMe && widget.sender != null)
              Padding(
                padding: EdgeInsets.only(left: 48.w, bottom: 4.h),
                child: CustomText(
                    text: '${widget.sender!.firstName} ${widget.sender!.lastName}',
                    fontSize: 12.sp, textColor: Colors.grey.shade600),
              ),
            Row(
              mainAxisAlignment: widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!widget.isMe)
                  Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: CircleAvatar(
                      radius: 18.r,
                      backgroundColor: Colors.transparent,
                      child: CustomText(text: widget.sender?.avatarEmoji ?? '🤔', fontSize: 18.sp),
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
                            bottomLeft: widget.isMe ? Radius.circular(18.r) : Radius.circular(4.r),
                            bottomRight: widget.isMe ? Radius.circular(4.r) : Radius.circular(18.r),
                          ),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withOpacity(0.1),
                              blurRadius: 4,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            if (widget.message.repliedTo != null)
                              Container(
                                margin: EdgeInsets.only(bottom: 8.h),
                                padding: EdgeInsets.all(8.w),
                                decoration: BoxDecoration(
                                  color: Colors.lightBlue.shade50.withOpacity(0.8),
                                  borderRadius: BorderRadius.circular(8.r),
                                  border: Border(
                                    left: BorderSide(
                                      color: widget.isMe ? Colors.white : Colors.lightBlueAccent,
                                      width: 4.w,
                                    ),
                                  ),
                                ),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    CustomText(
                                      text: widget.message.repliedTo!['senderName'] ?? 'Unknown',
                                      fontSize: 12.sp,
                                      textColor: Colors.lightBlueAccent,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    CustomText(
                                      text: widget.message.repliedTo!['text'] ?? '',
                                      fontSize: 13.sp,
                                      textColor: Colors.grey.shade700,
                                      maxLines: 3,
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            widget.message.isDeleted
                                ? Text("This message was deleted", style: TextStyle(fontStyle: FontStyle.italic, color: textColor.withOpacity(0.7)))
                                : CustomText(text: widget.message.text,textColor: textColor, fontSize: 15.sp),
                            SizedBox(height: 4.h),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.message.isEdited)
                                  CustomText(text: "Edited · ",textColor: textColor.withOpacity(0.7), fontSize: 11.sp),
                                Text(
                                  DateFormat('h:mm a').format(widget.message.timestamp.toDate()),
                                  style: TextStyle(color: textColor.withOpacity(0.7), fontSize: 11.sp),
                                ),
                                if (widget.isMe && !widget.message.isDeleted) ...[
                                  SizedBox(width: 4.w),
                                  Icon(
                                    widget.message.status == 'seen' ? Icons.done_all : (widget.message.status == 'delivered' ? Icons.done_all : Icons.done),
                                    size: 14.sp,
                                    color: widget.message.status == 'seen' ? Colors.blue : textColor.withOpacity(0.7),
                                  ),
                                ]
                              ],
                            ),
                          ],
                        ),
                      ),
                      if (widget.message.reactions.isNotEmpty)
                        Positioned(
                          bottom: -12.h,
                          left: 0,
                          right: 0,
                          child: Center(
                            child: GestureDetector(
                              onTap: () => _showReactionsDialog(context),
                              child: Container(
                                padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12.r),
                                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.1), blurRadius: 5, spreadRadius: 1)],
                                ),
                                child: CustomText(
                                    text: widget.message.reactions.values.toSet().join(''),
                                    fontSize: 14.sp),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                if (widget.isMe)
                  Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: CircleAvatar(
                      radius: 18.r,
                      backgroundColor: Colors.transparent,
                      child: CustomText(text: widget.sender?.avatarEmoji ?? '🤔', fontSize: 18.sp),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  void _showReactionsDialog(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
        title: const CustomText(text: "Reactions", fontWeight: FontWeight.bold, textColor: Colors.black),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: widget.message.reactions.length,
            itemBuilder: (context, index) {
              final uid = widget.message.reactions.keys.elementAt(index);
              final emoji = widget.message.reactions[uid]!;
              final user = widget.members[uid];
              final name = (uid == currentUser.uid)
                  ? 'You'
                  : (user != null ? '${user.firstName} ${user.lastName}' : 'Unknown');
              return ListTile(
                leading: CustomText(text: emoji, fontSize: 20.sp),
                title: CustomText(text: name),
              );
            },
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const CustomText(text: "OK", fontWeight: FontWeight.bold, textColor: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    final currentReaction = widget.message.reactions[currentUser.uid];

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
                            _updateReaction(widget.message.id, emoji);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: currentReaction == emoji ? Colors.lightBlue.shade100 : Colors.transparent,
                              shape: BoxShape.circle,
                            ),
                            child: CustomText(text: emoji, fontSize: 24.sp),
                          ),
                        );
                      }),
                      IconButton(
                        icon: Icon(Icons.add_reaction_outlined, color: Colors.grey.shade600),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEmojiPicker(context, (selectedEmoji) {
                            _updateReaction(widget.message.id, selectedEmoji);
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
                    widget.onReply(widget.message, widget.message.senderName ?? 'Unknown');
                    Navigator.pop(ctx);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.grey),
                  title: const CustomText(text: 'Copy'),
                  onTap: () async {
                    await Clipboard.setData(ClipboardData(text: widget.message.text));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Row(
                          children: [
                            Icon(Icons.check_circle, color: Colors.white, size: 20.sp),
                            SizedBox(width: 12.w),
                            const CustomText(text: 'Message copied to clipboard'),
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
                if (widget.isMe) ...[
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
                    title: const CustomText(text:'Edit'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEditDialog(context);
                    },
                  ),
                  ListTile(
                    leading: const Icon(Icons.delete_outline, color: Colors.red),
                    title: const CustomText(text:'Delete'),
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

  Future<void> _updateReaction(String messageId, String emoji) async {
    final currentUser = FirebaseAuth.instance.currentUser!.uid;
    final docRef = FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.group.id)
        .collection('messages')
        .doc(messageId);

    final doc = await docRef.get();
    final reactions = Map<String, String>.from(doc['reactions'] ?? {});

    if (reactions[currentUser] == emoji) {
      reactions.remove(currentUser);
    } else {
      reactions[currentUser] = emoji;
    }

    await docRef.update({'reactions': reactions});
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
    // For groups, show only timestamp since status may not be tracked per member
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
        title: const CustomText(text: "Message Info", fontWeight: FontWeight.bold),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.access_time, color: Colors.grey),
              title: const CustomText(text: "Sent"),
              subtitle: Text(DateFormat.yMMMd().add_jm().format(widget.message.timestamp.toDate())),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent),
            onPressed: () => Navigator.of(context).pop(),
            child: const CustomText(text: "OK",textColor: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context) {
    final controller = TextEditingController(text: widget.message.text);
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
          style: const TextStyle(color: Colors.black),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(ctx).pop(), child: const CustomText(text: "Cancel",textColor: Colors.black)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.lightBlueAccent),
            onPressed: () async {
              final newText = controller.text.trim();
              if (newText.isNotEmpty && newText != widget.message.text) {
                final docRef = FirebaseFirestore.instance
                    .collection('groups')
                    .doc(widget.group.id)
                    .collection('messages')
                    .doc(widget.message.id);
                await docRef.update({'text': newText, 'isEdited': true});
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
            onPressed: () async {
              final docRef = FirebaseFirestore.instance
                  .collection('groups')
                  .doc(widget.group.id)
                  .collection('messages')
                  .doc(widget.message.id);
              await docRef.update({'isDeleted': true});
              Navigator.of(ctx).pop();
            },
            child: const CustomText(text: "Delete",textColor: Colors.white),
          ),
        ],
      ),
    );
  }
}