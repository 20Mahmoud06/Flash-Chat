import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter/services.dart';
import '../../cubits/chat_cubit/chat_cubit.dart';
import '../../utils/full_image_viewer.dart';
import '../../utils/full_video_viewer.dart';
import 'package:audioplayers/audioplayers.dart';
import 'package:video_player/video_player.dart';

class MessageBubble extends StatefulWidget {
  final MessageModel message;
  final bool isMe;
  final bool isGroup;
  final UserModel? sender;
  final String senderAvatar;
  final String? contactName;
  final Map<String, UserModel> members;
  final VoidCallback? onTapReplied;

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
  });

  @override
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble> {
  VideoPlayerController? _videoController;
  AudioPlayer? _audioPlayer;
  bool _isPlaying = false;
  Duration _position = Duration.zero;
  Duration _duration = Duration.zero;

  @override
  void initState() {
    super.initState();
    if (widget.message.messageType == MessageType.video &&
        (widget.message.mediaUrls?.isNotEmpty ?? false)) {
      _videoController = VideoPlayerController.network(widget.message.mediaUrls!.first)
        ..initialize().then((_) => setState(() {}));
    } else if (widget.message.messageType == MessageType.voice &&
        (widget.message.mediaUrls?.isNotEmpty ?? false)) {
      _audioPlayer = AudioPlayer();
      _audioPlayer!.onPositionChanged.listen((pos) {
        setState(() => _position = pos);
      });
      _audioPlayer!.onDurationChanged.listen((dur) {
        setState(() => _duration = dur);
      });
      _audioPlayer!.onPlayerComplete.listen((_) {
        setState(() {
          _isPlaying = false;
          _position = Duration.zero;
        });
      });
    }
  }

  @override
  void dispose() {
    _videoController?.dispose();
    _audioPlayer?.dispose();
    super.dispose();
  }

  Widget _buildContent(Color textColor) {
    Widget mediaWidget = const SizedBox.shrink();

    if (widget.message.messageType == MessageType.text) {
      return CustomText(
        text: widget.message.text,
        textColor: textColor,
        fontSize: 15.sp,
        textDirection: intl.Bidi.detectRtlDirectionality(widget.message.text)
            ? TextDirection.rtl
            : TextDirection.ltr,
      );
    }

    if (widget.message.messageType == MessageType.image) {
      final mediaUrls = widget.message.mediaUrls ?? [];

      mediaWidget = GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: mediaUrls.length > 2 ? 2 : 1,
          childAspectRatio: 1,
          crossAxisSpacing: 4.w,
          mainAxisSpacing: 4.h,
        ),
        itemCount: mediaUrls.length,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              barrierColor: Colors.transparent,
              builder: (_) => FullImageViewer(
                imageUrl: mediaUrls[i],
                heroTag: '${widget.message.id}_$i',
              ),
            );
          },
          child: Hero(
            tag: '${widget.message.id}_$i',
            child: ClipRRect(
              borderRadius: BorderRadius.circular(8.r),
              child: Image.network(
                mediaUrls[i],
                fit: BoxFit.cover,
              ),
            ),
          ),
        ),
      );
    } else if (widget.message.messageType == MessageType.video) {
      if (_videoController == null || !_videoController!.value.isInitialized) {
        mediaWidget = const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent));
      } else {
        mediaWidget = GestureDetector(
          onTap: () {
            showDialog(
              context: context,
              barrierColor: Colors.black.withOpacity(0.8),
              builder: (_) => FullVideoViewer(videoUrl: widget.message.mediaUrls!.first),
            );
          },
          child: Stack(
            alignment: Alignment.center,
            children: [
              AspectRatio(
                aspectRatio: _videoController!.value.aspectRatio,
                child: VideoPlayer(_videoController!),
              ),
              const Icon(Icons.play_circle_fill, size: 50, color: Colors.white),
            ],
          ),
        );
      }
    } else if (widget.message.messageType == MessageType.voice) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                icon: Icon(
                  _isPlaying ? Icons.pause_circle_filled : Icons.play_circle_filled,
                  size: 32.sp,
                ),
                color: textColor,
                onPressed: () async {
                  if (_isPlaying) {
                    await _audioPlayer?.pause();
                  } else {
                    if (widget.message.mediaUrls?.isNotEmpty ?? false) {
                      try {
                        await _audioPlayer?.play(UrlSource(widget.message.mediaUrls!.first));
                      } catch (e) {
                        debugPrint('Audio play error: $e');
                      }
                    }
                  }
                  setState(() => _isPlaying = !_isPlaying);
                },
              ),
              Expanded(
                child: Slider(
                  value: _position.inMilliseconds.toDouble(),
                  max: _duration.inMilliseconds.toDouble(),
                  onChanged: (value) async {
                    final newPosition = Duration(milliseconds: value.toInt());
                    await _audioPlayer?.seek(newPosition);
                  },
                  activeColor: textColor,
                  inactiveColor: textColor.withOpacity(0.3),
                ),
              ),
              CustomText(
                text: '${_position.inSeconds}s / ${widget.message.voiceDuration ?? _duration.inSeconds}s',
                textColor: textColor,
                fontSize: 12.sp,
              ),
            ],
          ),
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mediaWidget,
        if (widget.message.text.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: CustomText(
              text: widget.message.text,
              textColor: textColor,
              fontSize: 15.sp,
              textDirection: intl.Bidi.detectRtlDirectionality(widget.message.text)
                  ? TextDirection.rtl
                  : TextDirection.ltr,
            ),
          ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final alignment =
    widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
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
            if (widget.isGroup && !widget.isMe && widget.sender != null)
              Padding(
                padding: EdgeInsets.only(left: 48.w, bottom: 4.h),
                child: CustomText(
                    text:
                    '${widget.sender!.firstName} ${widget.sender!.lastName}',
                    fontSize: 12.sp,
                    textColor: Colors.grey.shade600),
              ),
            Row(
              mainAxisAlignment:
              widget.isMe ? MainAxisAlignment.end : MainAxisAlignment.start,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (!widget.isMe)
                  Padding(
                    padding: EdgeInsets.only(right: 8.w),
                    child: CircleAvatar(
                      radius: 18.r,
                      backgroundColor: Colors.transparent,
                      child: CustomText(
                          text: widget.senderAvatar, fontSize: 18.sp),
                    ),
                  ),
                Flexible(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Container(
                        constraints: BoxConstraints(maxWidth: 0.7.sw),
                        padding: EdgeInsets.symmetric(
                            vertical: 10.h, horizontal: 14.w),
                        decoration: BoxDecoration(
                          color: color,
                          borderRadius: BorderRadius.only(
                            topLeft: Radius.circular(18.r),
                            topRight: Radius.circular(18.r),
                            bottomLeft: widget.isMe
                                ? Radius.circular(18.r)
                                : Radius.circular(4.r),
                            bottomRight: widget.isMe
                                ? Radius.circular(4.r)
                                : Radius.circular(18.r),
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
                              GestureDetector(
                                onTap: widget.onTapReplied,
                                child: Container(
                                  margin: EdgeInsets.only(bottom: 8.h),
                                  padding: EdgeInsets.all(8.w),
                                  decoration: BoxDecoration(
                                    color: Colors.lightBlue.shade50
                                        .withOpacity(0.8),
                                    borderRadius: BorderRadius.circular(8.r),
                                    border: Border(
                                      left: BorderSide(
                                        color: widget.isMe
                                            ? Colors.white
                                            : Colors.lightBlueAccent,
                                        width: 4.w,
                                      ),
                                    ),
                                  ),
                                  child: Column(
                                    crossAxisAlignment:
                                    CrossAxisAlignment.start,
                                    children: [
                                      CustomText(
                                        text: widget.message
                                            .repliedTo!['senderName'] ??
                                            'Unknown',
                                        fontSize: 12.sp,
                                        textColor: Colors.lightBlueAccent,
                                        fontWeight: FontWeight.bold,
                                      ),
                                      CustomText(
                                        text:
                                        widget.message.repliedTo!['text'] ??
                                            'Media message',
                                        fontSize: 13.sp,
                                        textColor: Colors.grey.shade700,
                                        maxLines: 3,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            widget.message.isDeleted
                                ? Text("This message was deleted",
                                style: TextStyle(
                                    fontStyle: FontStyle.italic,
                                    color: textColor.withOpacity(0.7)))
                                : _buildContent(textColor),
                            SizedBox(height: 4.h),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (widget.message.isEdited)
                                  CustomText(
                                      text: "Edited · ",
                                      textColor: textColor.withOpacity(0.7),
                                      fontSize: 11.sp),
                                Text(
                                  intl.DateFormat('h:mm a').format(
                                      widget.message.timestamp.toDate()),
                                  style: TextStyle(
                                      color: textColor.withOpacity(0.7),
                                      fontSize: 11.sp),
                                ),
                                if (widget.isMe &&
                                    !widget.message.isDeleted) ...[
                                  SizedBox(width: 4.w),
                                  Icon(
                                    widget.message.status == 'seen'
                                        ? Icons.done_all
                                        : (widget.message.status == 'delivered'
                                        ? Icons.done_all
                                        : Icons.done),
                                    size: 14.sp,
                                    color: widget.message.status == 'seen'
                                        ? Colors.blue
                                        : textColor.withOpacity(0.7),
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
                                padding: EdgeInsets.symmetric(
                                    horizontal: 6.w, vertical: 2.h),
                                decoration: BoxDecoration(
                                  color: Colors.grey.shade200,
                                  borderRadius: BorderRadius.circular(12.r),
                                  boxShadow: [
                                    BoxShadow(
                                        color: Colors.black.withOpacity(0.1),
                                        blurRadius: 5,
                                        spreadRadius: 1)
                                  ],
                                ),
                                child: CustomText(
                                    text: widget.message.reactions.values
                                        .toSet()
                                        .join(''),
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
                      child: CustomText(
                          text: widget.senderAvatar, fontSize: 18.sp),
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
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
        title: const CustomText(
            text: "Reactions",
            fontWeight: FontWeight.bold,
            textColor: Colors.black),
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
                  : (user != null
                  ? '${user.firstName} ${user.lastName}'
                  : 'Unknown');
              return ListTile(
                leading: CustomText(text: emoji, fontSize: 20.sp),
                title: CustomText(text: name),
              );
            },
          ),
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlueAccent),
            onPressed: () => Navigator.of(ctx).pop(),
            child: const CustomText(
                text: "OK",
                fontWeight: FontWeight.bold,
                textColor: Colors.white),
          ),
        ],
      ),
    );
  }

  void _showMessageOptions(BuildContext context) {
    final chatCubit = context.read<ChatCubit>();
    final currentUser = FirebaseAuth.instance.currentUser!;
    final currentReaction = widget.message.reactions[currentUser.uid];

    final String senderName = widget.isGroup
        ? (widget.sender != null
        ? '${widget.sender!.firstName} ${widget.sender!.lastName}'
        : 'Unknown')
        : (widget.isMe ? 'You' : widget.contactName ?? 'Unknown');

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final List<String> quickReactions = ['❤️', '😂', '😮', '😢', '👍'];
        return Container(
          margin: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
              color: Colors.white, borderRadius: BorderRadius.circular(15.r)),
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
                            if (currentReaction == emoji) {
                              chatCubit.removeReaction(widget.message.id);
                            } else {
                              chatCubit.updateReaction(
                                  widget.message.id, emoji);
                            }
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
                      IconButton(
                        icon: Icon(Icons.add_reaction_outlined,
                            color: Colors.grey.shade600),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEmojiPicker(context, (selectedEmoji) {
                            if (currentReaction == selectedEmoji) {
                              chatCubit.removeReaction(widget.message.id);
                            } else {
                              chatCubit.updateReaction(
                                  widget.message.id, selectedEmoji);
                            }
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
                    chatCubit.setReplyingTo(widget.message, senderName);
                  },
                ),
                ListTile(
                  leading: const Icon(Icons.copy, color: Colors.grey),
                  title: const CustomText(text: 'Copy'),
                  onTap: () async {
                    await Clipboard.setData(
                        ClipboardData(text: widget.message.text));
                    Navigator.pop(ctx);
                    ScaffoldMessenger.of(context).showSnackBar(
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
                    leading:
                    const Icon(Icons.edit_outlined, color: Colors.green),
                    title: const CustomText(text: 'Edit'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showEditDialog(context);
                    },
                  ),
                  ListTile(
                    leading:
                    const Icon(Icons.delete_outline, color: Colors.red),
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

  void _showEmojiPicker(
      BuildContext context, Function(String) onEmojiSelected) {
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

    if (widget.message.status == 'delivered') {
      statusText = "Delivered";
      statusIcon = Icons.done_all;
    } else if (widget.message.status == 'seen') {
      statusText = "Seen";
      statusIcon = Icons.done_all;
      statusColor = Colors.blue;
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
        title: const CustomText(
            text: "Message Info",
            fontWeight: FontWeight.bold,
            textColor: Colors.black),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: Icon(statusIcon, color: statusColor),
              title: CustomText(text: statusText),
              subtitle: Text(intl.DateFormat.yMMMd()
                  .add_jm()
                  .format(widget.message.timestamp.toDate())),
            ),
          ],
        ),
        actions: [
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlueAccent),
            onPressed: () => Navigator.of(context).pop(),
            child: const CustomText(
                text: "OK",
                fontWeight: FontWeight.bold,
                textColor: Colors.white),
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
            focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: const BorderSide(color: Colors.lightBlueAccent)),
            enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10.r),
                borderSide: BorderSide(color: Colors.grey.shade600)),
            border:
            OutlineInputBorder(borderRadius: BorderRadius.circular(10.r)),
            hintText: "Edit your message",
            filled: true,
            fillColor: Colors.grey.shade200,
            contentPadding:
            EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          ),
          cursorColor: Colors.black,
          maxLines: null,
          strutStyle: const StrutStyle(fontSize: 15),
          controller: controller,
          style: const TextStyle(color: Colors.black),
          textDirection: intl.Bidi.detectRtlDirectionality(controller.text)
              ? TextDirection.rtl
              : TextDirection.ltr,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const CustomText(text: "Cancel", textColor: Colors.black)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlueAccent),
            onPressed: () {
              final newText = controller.text.trim();
              if (newText.isNotEmpty && newText != widget.message.text) {
                context
                    .read<ChatCubit>()
                    .editMessage(widget.message.id, newText);
              }
              Navigator.of(ctx).pop();
            },
            child: const CustomText(text: "Save", textColor: Colors.white),
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
        content: const CustomText(
            text: "Are you sure you want to delete this message?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const CustomText(text: "Cancel", textColor: Colors.black)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<ChatCubit>().deleteMessage(widget.message.id);
              Navigator.of(ctx).pop();
            },
            child: const CustomText(text: "Delete", textColor: Colors.white),
          ),
        ],
      ),
    );
  }
}