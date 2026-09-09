import 'dart:async';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../calls/cubit/call_cubit.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/full_image_viewer.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../../shared/widgets/voice_message_player.dart';
import '../cubit/chat_cubit.dart';
import 'reply_preview_card.dart';
import 'video_message_player.dart';

class MessageBubble extends StatefulWidget {
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
  State<MessageBubble> createState() => _MessageBubbleState();
}

class _MessageBubbleState extends State<MessageBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _livePulse;

  @override
  void initState() {
    super.initState();
    _livePulse = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1100),
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _livePulse.dispose();
    super.dispose();
  }

  Widget _buildContent(Color textColor, Color bubbleColor) {
    Widget mediaWidget = const SizedBox.shrink();

    if (widget.message.messageType == MessageType.text) {
      return _buildTextMessage(textColor, bubbleColor);
    }

    if (widget.message.messageType == MessageType.image) {
      final mediaUrls = widget.message.mediaUrls ?? [];

      if (mediaUrls.isEmpty) {
        mediaWidget = const CustomText(text: 'Photo unavailable');
      } else if (mediaUrls.length == 1) {
        // Single photo keeps its natural aspect ratio: no cropping, no
        // stretching, just capped to a comfortable bubble size.
        mediaWidget = ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 0.28.sw,
            maxWidth: 0.55.sw,
            maxHeight: 0.72.sw,
          ),
          child: _buildMediaImage(
            mediaUrls.first,
            fit: BoxFit.contain,
            heroTag: '${widget.message.id}_0',
            mediaIndex: 0,
            onTap: () => _openImage(mediaUrls.first, 0),
            onLongPress: () =>
                _showMessageOptions(context, replyMediaIndex: 0, mediaIndex: 0),
          ),
        );
      } else {
        // Multiple photos render as a WhatsApp-style square grid.
        mediaWidget = ClipRRect(
          borderRadius: BorderRadius.circular(12.r),
          child: GridView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
              crossAxisCount: 2,
              childAspectRatio: 1,
              crossAxisSpacing: 4.w,
              mainAxisSpacing: 4.h,
            ),
            itemCount: mediaUrls.length,
            itemBuilder: (_, i) => _buildMediaImage(
              mediaUrls[i],
              fit: BoxFit.cover,
              heroTag: '${widget.message.id}_$i',
              mediaIndex: i,
              onTap: () => _openImage(mediaUrls[i], i),
              onLongPress: () => _showMessageOptions(context,
                  replyMediaIndex: i, mediaIndex: i),
            ),
          ),
        );
      }
    } else if (widget.message.messageType == MessageType.video) {
      final videoUrl = (widget.message.mediaUrls?.isNotEmpty ?? false)
          ? widget.message.mediaUrls!.first
          : null;
      if (videoUrl == null) {
        mediaWidget = const CustomText(text: 'Video unavailable');
      } else {
        mediaWidget = GestureDetector(
          onLongPress: () => _showMessageOptions(context),
          child: VideoMessagePlayer(videoUrl: videoUrl),
        );
      }
    } else if (widget.message.messageType == MessageType.voice) {
      final audioUrl = (widget.message.mediaUrls?.isNotEmpty ?? false)
          ? widget.message.mediaUrls!.first
          : null;
      if (audioUrl == null) {
        return const CustomText(text: 'Voice message unavailable');
      }
      return VoiceMessagePlayer(
        audioUrl: audioUrl,
        initialDuration: widget.message.voiceDuration != null
            ? Duration(seconds: widget.message.voiceDuration!)
            : null,
        playedColor: widget.isMe
            ? FcAppColors.of(context).bubbleMineText
            : Colors.lightBlueAccent.shade700,
        idleColor: (widget.isMe
                ? FcAppColors.of(context).bubbleMineText
                : Colors.blueGrey)
            .withValues(alpha: 0.35),
        textColor: textColor,
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mediaWidget,
        if (widget.message.text.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: _buildTextMessage(textColor, bubbleColor),
          ),
      ],
    );
  }

  static final _urlRegExp = RegExp(r'''(https?://|www\.)[^\s<>"']+''');

  Widget _buildTextMessage(Color textColor, Color bubbleColor) {
    final text = widget.message.text;
    // Pick the link color for contrast against the BUBBLE background (not
    // the text color). For the user's own bubbles (lightBlueAccent bg,
    // white text), links stay white with an underline so they blend with
    // the message text. For the other user's lighter bubbles we use the
    // app's primary accent so links feel consistent with the rest of the UI.
    final isDarkBubble =
        ThemeData.estimateBrightnessForColor(bubbleColor) == Brightness.dark;
    final linkColor = isDarkBubble
        ? Colors.white
        : (widget.isMe ? Colors.white : Colors.lightBlueAccent);
    final textDirection = intl.Bidi.detectRtlDirectionality(text)
        ? TextDirection.rtl
        : TextDirection.ltr;

    final spans = <InlineSpan>[];
    var lastEnd = 0;
    for (final match in _urlRegExp.allMatches(text)) {
      if (match.start > lastEnd) {
        spans.add(TextSpan(text: text.substring(lastEnd, match.start)));
      }
      final rawUrl = match.group(0)!;
      final cleanUrl = rawUrl.replaceAll(RegExp(r'[.,;:!?)]+$'), '');
      spans.add(TextSpan(
        text: rawUrl,
        style: TextStyle(
          color: linkColor,
          decoration: TextDecoration.underline,
          decorationColor: linkColor,
        ),
        recognizer: TapGestureRecognizer()..onTap = () => _openLink(cleanUrl),
      ));
      lastEnd = match.end;
    }
    if (lastEnd < text.length) {
      spans.add(TextSpan(text: text.substring(lastEnd)));
    }

    return Text.rich(
      TextSpan(children: spans),
      textDirection: textDirection,
      style: TextStyle(color: textColor, fontSize: 15.sp),
    );
  }

  Future<void> _openLink(String url) async {
    var uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      uri = Uri.parse('https://$url');
    }
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) {
        debugPrint('Failed to launch URL: $url');
      }
    } catch (e) {
      debugPrint('Error launching URL $url: $e');
    }
  }

  void _openImage(String url, int index) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => FullImageViewer(
        imageUrl: url,
        heroTag: '${widget.message.id}_$index',
      ),
    );
  }

  Widget _buildMediaImage(
    String url, {
    required BoxFit fit,
    required String heroTag,
    required int mediaIndex,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    Widget image = Image.network(
      url,
      fit: fit,
      loadingBuilder: (context, child, progress) {
        if (progress == null) return child;
        return Container(
          color: Colors.black12,
          child: const Center(
            child: SizedBox(
              width: 22,
              height: 22,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Colors.lightBlueAccent,
              ),
            ),
          ),
        );
      },
      errorBuilder: (context, error, stackTrace) => Container(
        color: Colors.black12,
        child: const Center(
          child: Icon(
            Icons.broken_image_outlined,
            color: Colors.grey,
            size: 32,
          ),
        ),
      ),
    );

    // Per-photo reactions (WhatsApp style): a small pill pinned to the
    // bottom-left corner of THIS photo, showing who reacted to it.
    final photoReactions = widget.message.imageReactions['$mediaIndex'];
    if (photoReactions != null && photoReactions.isNotEmpty) {
      image = Stack(
        clipBehavior: Clip.none,
        children: [
          image,
          Positioned(
            left: 6.w,
            bottom: 6.h,
            child: GestureDetector(
              onTap: () => _showImageReactionsDialog(context, mediaIndex),
              child: _ReactionPill(
                reactions: photoReactions,
                backgroundColor: FcAppColors.of(context).surface,
              ),
            ),
          ),
        ],
      );
    }

    image = ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: image,
    );

    image = Hero(tag: heroTag, child: image);

    if (onTap != null || onLongPress != null) {
      image = GestureDetector(
        onTap: onTap,
        onLongPress: onLongPress,
        child: image,
      );
    }
    return image;
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);

    if (widget.message.messageType == MessageType.system) {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 24.w),
        child: Center(
          child: CustomText(
            text: widget.message.text,
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
    if (widget.message.messageType == MessageType.call) {
      return _buildCallNotice(colors);
    }

    // Active group call message with a "Join call" button — WhatsApp /
    // Messenger style inline card so latecomers can join in one tap. Only
    // shown to members who are NOT in the call (they are the only ones who
    // need the Join button); the caller and anyone already connected don't
    // need a card that simply says they're in the call.
    if (widget.message.messageType == MessageType.callActive) {
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      final inThisCall = widget.message.callerId == myUid ||
          CallCubit.instance.isCallActive;
      if (inThisCall) return const SizedBox.shrink();
      return _buildActiveCallMessage(colors);
    }

    final alignment =
        widget.isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start;
    final color = widget.isMe ? colors.bubbleMine : colors.bubbleOther;
    final textColor =
        widget.isMe ? colors.bubbleMineText : colors.bubbleOtherText;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isStarred =
        myUid != null && widget.message.starredBy.contains(myUid);
    // Gold is used for the favorite highlight on every bubble. On the other
    // person's light bubbles it pops nicely, and on my own bubbles (light blue
    // in light mode, medium blue in dark mode) a gold star icon + border keeps
    // the highlight clearly visible — white was invisible in light mode.
    const starColor = Color(0xFFFFC107);

    return ValueListenableBuilder<Map<String, dynamic>?>(
      valueListenable: context.read<ChatCubit>().pinnedMessageNotifier,
      builder: (context, pin, _) {
        final isPinned = pin?['messageId'] == widget.message.id;
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
                if (isPinned)
                  Padding(
                    padding: EdgeInsets.only(bottom: 2.h),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.push_pin,
                          size: 11.sp,
                          color: textColor.withValues(alpha: 0.7),
                        ),
                        SizedBox(width: 3.w),
                        CustomText(
                          text: 'Pinned',
                          fontSize: 10.sp,
                          fontWeight: FontWeight.w600,
                          textColor: textColor.withValues(alpha: 0.7),
                        ),
                      ],
                    ),
                  ),
                if (widget.isGroup && !widget.isMe && widget.sender != null)
                  Padding(
                    padding: EdgeInsets.only(left: 48.w, bottom: 4.h),
                    child: CustomText(
                        text:
                            '${widget.sender!.firstName} ${widget.sender!.lastName}',
                        fontSize: 12.sp,
                        textColor: colors.textWeak),
                  ),
                Row(
                  mainAxisAlignment: widget.isMe
                      ? MainAxisAlignment.end
                      : MainAxisAlignment.start,
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
                          AnimatedContainer(
                            duration: const Duration(milliseconds: 300),
                            constraints: BoxConstraints(maxWidth: 0.7.sw),
                            padding: EdgeInsets.symmetric(
                                vertical: 10.h, horizontal: 14.w),
                            decoration: BoxDecoration(
                              color: widget.highlighted &&
                                      widget.message.status != 'pending'
                                  ? Color.alphaBlend(
                                      const Color(0xFF4FC3F7)
                                          .withValues(alpha: 0.35),
                                      color,
                                    )
                                  : isStarred &&
                                          widget.message.status != 'pending'
                                      ? Color.alphaBlend(
                                          starColor.withValues(alpha: 0.22),
                                          color,
                                        )
                                      : widget.message.status == 'pending'
                                          ? color.withValues(alpha: 0.55)
                                          : color,
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
                              border: widget.highlighted
                                  ? Border.all(
                                      color: const Color(0xFF0288D1),
                                      width: 2,
                                    )
                                  : isStarred
                                      ? Border.all(color: starColor, width: 2)
                                      : Border.all(
                                          color: Colors.transparent,
                                          width: 0,
                                        ),
                              boxShadow: [
                                BoxShadow(
                                  color: widget.highlighted
                                      ? const Color(0xFF4FC3F7)
                                          .withValues(alpha: 0.65)
                                      : isStarred
                                          ? starColor.withValues(alpha: 0.5)
                                          : Colors.black
                                              .withValues(alpha: 0.1),
                                  blurRadius:
                                      (widget.highlighted || isStarred) ? 16 : 4,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (widget.message.repliedTo != null)
                                  Padding(
                                    padding: EdgeInsets.only(bottom: 8.h),
                                    child: ReplyPreviewCard.fromReplyMeta(
                                      repliedTo: widget.message.repliedTo!,
                                      isOwnMessage: widget.isMe,
                                      resolvedSenderName: widget.message
                                                  .repliedTo!['senderName']
                                              as String? ??
                                          'Unknown',
                                      onTap: widget.onTapReplied,
                                    ),
                                  ),
                                widget.message.isDeleted
                                    ? Text("This message was deleted",
                                        style: TextStyle(
                                            fontStyle: FontStyle.italic,
                                            color: textColor.withValues(
                                                alpha: 0.7)))
                                    : _buildContent(textColor, color),
                                SizedBox(height: 4.h),
                                Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    if (isStarred) ...[
                                      Icon(Icons.star,
                                          size: 12.sp, color: starColor),
                                      SizedBox(width: 3.w),
                                    ],
                                    if (widget.message.isEdited)
                                      CustomText(
                                          text: "Edited · ",
                                          textColor:
                                              textColor.withValues(alpha: 0.7),
                                          fontSize: 11.sp),
                                    Text(
                                      intl.DateFormat('h:mm a').format(
                                          widget.message.timestamp.toDate()),
                                      style: TextStyle(
                                          color:
                                              textColor.withValues(alpha: 0.7),
                                          fontSize: 11.sp),
                                    ),
                                    if (widget.isMe &&
                                        !widget.message.isDeleted) ...[
                                      SizedBox(width: 4.w),
                                      if (widget.message.status == 'pending')
                                        Icon(
                                          Icons.schedule,
                                          size: 14.sp,
                                          color: Colors.orange.shade600,
                                        )
                                      else
                                        Icon(
                                          widget.message.status == 'seen'
                                              ? Icons.done_all
                                              : (widget.message.status ==
                                                      'delivered'
                                                  ? Icons.done_all
                                                  : Icons.done),
                                          size: 14.sp,
                                          color: widget.message.status == 'seen'
                                              ? Colors.blue
                                              : textColor.withValues(
                                                  alpha: 0.7),
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
                                        horizontal: 8.w, vertical: 2.5.h),
                                    decoration: BoxDecoration(
                                      color: colors.surface,
                                      borderRadius: BorderRadius.circular(12.r),
                                      border: Border.all(
                                        color: colors.surfaceDim,
                                        width: 1,
                                      ),
                                      boxShadow: [
                                        BoxShadow(
                                          color: Colors.black
                                              .withValues(alpha: 0.12),
                                          blurRadius: 6,
                                          spreadRadius: 1,
                                        ),
                                      ],
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Text(
                                          widget.message.reactions.values
                                              .toSet()
                                              .join(''),
                                          style: TextStyle(fontSize: 13.sp),
                                        ),
                                        SizedBox(width: 4.w),
                                        Text(
                                          '${widget.message.reactions.length}',
                                          style: TextStyle(
                                            color: colors.textSecondary,
                                            fontSize: 11.5.sp,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
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
      },
    );
  }

  void _showReactionsDialog(BuildContext context) {
    _showReactionsFor(
      context,
      widget.message.reactions,
      onRemoveMyReaction: () =>
          context.read<ChatCubit>().removeReaction(widget.message.id),
    );
  }

  /// Shows who reacted to a specific photo inside a (multi-)image message.
  void _showImageReactionsDialog(BuildContext context, int mediaIndex) {
    _showReactionsFor(
      context,
      widget.message.imageReactions['$mediaIndex'] ?? const {},
      onRemoveMyReaction: () => context
          .read<ChatCubit>()
          .removeImageReaction(widget.message.id, mediaIndex),
    );
  }

  void _showReactionsFor(
    BuildContext context,
    Map<String, String> reactions, {
    required VoidCallback onRemoveMyReaction,
  }) {
    final currentUser = FirebaseAuth.instance.currentUser!;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
        title: CustomText(
            text: "Reactions",
            fontWeight: FontWeight.bold,
            textColor: FcAppColors.of(ctx).textPrimary),
        content: SizedBox(
          width: double.maxFinite,
          child: ListView.builder(
            shrinkWrap: true,
            itemCount: reactions.length,
            itemBuilder: (context, index) {
              final uid = reactions.keys.elementAt(index);
              final emoji = reactions[uid]!;
              final user = widget.members[uid];
              final isMe = uid == currentUser.uid;
              final name = isMe
                  ? 'You'
                  : (user != null
                      ? '${user.firstName} ${user.lastName}'
                      : 'Unknown');
              return ListTile(
                leading: CustomText(text: emoji, fontSize: 20.sp),
                title: CustomText(text: name),
                trailing: isMe
                    ? Icon(Icons.close,
                        size: 18.sp, color: FcAppColors.of(ctx).textWeak)
                    : null,
                onTap: isMe
                    ? () {
                        onRemoveMyReaction();
                        Navigator.of(ctx).pop();
                      }
                    : null,
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

  void _showMessageOptions(BuildContext context,
      {int? replyMediaIndex, int? mediaIndex}) {
    if (widget.readOnly) return;
    final chatCubit = context.read<ChatCubit>();
    final currentUser = FirebaseAuth.instance.currentUser!;

    // True when the options were opened by long-pressing a specific photo,
    // so reactions apply to that photo (imageReactions) instead of the
    // whole message (reactions).
    final bool targetingImage = mediaIndex != null &&
        widget.message.messageType == MessageType.image;
    final currentReaction = targetingImage
        ? (widget.message.imageReactions['$mediaIndex'] ?? const {})[
            currentUser.uid]
        : widget.message.reactions[currentUser.uid];

    // Specific photo being replied to (null = reply to the whole group).
    // For whole-group replies the first photo is used as the thumbnail and
    // the count is attached so the preview shows a "📷 Photos" badge.
    final String? replyMediaUrl;
    final int? replyMediaCount;
    final mediaUrls = widget.message.mediaUrls;
    if (replyMediaIndex != null &&
        mediaUrls != null &&
        replyMediaIndex < mediaUrls.length) {
      replyMediaUrl = mediaUrls[replyMediaIndex];
      replyMediaCount = null;
    } else if (mediaUrls != null && mediaUrls.isNotEmpty) {
      replyMediaUrl = mediaUrls.first;
      replyMediaCount = widget.message.messageType == MessageType.image &&
              mediaUrls.length > 1
          ? mediaUrls.length
          : null;
    } else {
      replyMediaUrl = null;
      replyMediaCount = null;
    }

    final String senderName = widget.isGroup
        ? (widget.sender != null
            ? '${widget.sender!.firstName} ${widget.sender!.lastName}'
            : 'Unknown')
        : (widget.isMe ? 'You' : widget.contactName ?? 'Unknown');

    void toggleReaction(String emoji) {
      final chatCubit = context.read<ChatCubit>();
      if (targetingImage) {
        if (currentReaction == emoji) {
          chatCubit.removeImageReaction(widget.message.id, mediaIndex);
        } else {
          chatCubit.updateImageReaction(widget.message.id, mediaIndex, emoji);
        }
      } else {
        if (currentReaction == emoji) {
          chatCubit.removeReaction(widget.message.id);
        } else {
          chatCubit.updateReaction(widget.message.id, emoji);
        }
      }
    }

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = FcAppColors.of(ctx);
        final List<String> quickReactions = ['❤️', '😂', '😮', '😢', '👍'];
        return Container(
          margin: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
              color: colors.surface, borderRadius: BorderRadius.circular(15.r)),
          child: SingleChildScrollView(
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
                            toggleReaction(emoji);
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
                      if (currentReaction != null &&
                          !quickReactions.contains(currentReaction))
                        GestureDetector(
                          onTap: () {
                            toggleReaction(currentReaction);
                            Navigator.pop(ctx);
                          },
                          child: Container(
                            padding: EdgeInsets.all(8.w),
                            decoration: BoxDecoration(
                              color: Colors.lightBlue.shade100,
                              shape: BoxShape.circle,
                            ),
                            child: CustomText(
                                text: currentReaction, fontSize: 24.sp),
                          ),
                        ),
                      IconButton(
                        icon: Icon(Icons.add_reaction_outlined,
                            color: colors.textWeak),
                        onPressed: () {
                          Navigator.pop(ctx);
                          _showEmojiPicker(context, (selectedEmoji) {
                            toggleReaction(selectedEmoji);
                          });
                        },
                      )
                    ],
                  ),
                ),
                const Divider(height: 1),
                ListTile(
                  leading: Icon(Icons.reply, color: colors.textSecondary),
                  title: const CustomText(text: 'Reply'),
                  onTap: () {
                    Navigator.pop(ctx);
                    chatCubit.setReplyingTo(widget.message, senderName,
                        mediaUrl: replyMediaUrl, mediaCount: replyMediaCount);
                  },
                ),
                ListTile(
                  leading: Icon(
                    widget.message.starredBy.contains(currentUser.uid)
                        ? Icons.star
                        : Icons.star_border,
                    color: widget.message.starredBy.contains(currentUser.uid)
                        ? const Color(0xFFFFC107)
                        : colors.textWeak,
                  ),
                  title: CustomText(
                    text: widget.message.starredBy.contains(currentUser.uid)
                        ? 'Remove from favorites'
                        : 'Favorite',
                  ),
                  onTap: () {
                    Navigator.pop(ctx);
                    if (widget.message.starredBy.contains(currentUser.uid)) {
                      chatCubit.unstarMessage(widget.message.id);
                    } else {
                      chatCubit.starMessage(widget.message.id);
                    }
                  },
                ),
                if (chatCubit.canPin)
                  ListTile(
                    leading: SizedBox(
                      width: 24.w,
                      child: chatCubit.pinnedMessageNotifier
                                      .value?['messageId'] ==
                                  widget.message.id
                              ? Transform.rotate(
                                  angle: 0.785,
                                  child: Icon(Icons.push_pin,
                                      color: colors.textWeak, size: 24),
                                )
                              : Icon(Icons.push_pin_outlined,
                                  color: colors.textWeak, size: 24),
                    ),
                    title: CustomText(
                      text:
                          chatCubit.pinnedMessageNotifier.value?['messageId'] ==
                                  widget.message.id
                              ? 'Unpin'
                              : 'Pin',
                    ),
                    onTap: () {
                      Navigator.pop(ctx);
                      if (chatCubit.pinnedMessageNotifier.value?['messageId'] ==
                          widget.message.id) {
                        chatCubit.unpinMessage();
                      } else {
                        _showPinDurationPicker(context);
                      }
                    },
                  ),
                if (widget.message.messageType == MessageType.text ||
                    widget.message.text.trim().isNotEmpty)
                  ListTile(
                    leading: Icon(Icons.copy, color: colors.textWeak),
                    title: const CustomText(text: 'Copy'),
                    onTap: () async {
                      final messenger = ScaffoldMessenger.of(context);
                      await Clipboard.setData(
                          ClipboardData(text: widget.message.text));
                      if (ctx.mounted) {
                        Navigator.pop(ctx);
                      }
                      messenger.showSnackBar(
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
                ],
                if (!widget.isMe) ...[
                  const Divider(height: 1),
                  ListTile(
                    leading: Icon(Icons.delete_sweep_outlined,
                        color: colors.textWeak),
                    title: const CustomText(text: 'Delete for me'),
                    onTap: () {
                      Navigator.pop(ctx);
                      _showDeleteForMeConfirmation(context);
                    },
                  ),
                ]
              ],
            ),
            ),
          ),
        );
      },
    );
  }

  void _showPinDurationPicker(BuildContext context) {
    final chatCubit = context.read<ChatCubit>();
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        final colors = FcAppColors.of(ctx);
        return Container(
          margin: EdgeInsets.all(8.w),
          decoration: BoxDecoration(
              color: colors.surface, borderRadius: BorderRadius.circular(15.r)),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Padding(
                  padding: EdgeInsets.all(16.w),
                  child: CustomText(
                    text: 'Pin message for',
                    fontSize: 16.sp,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const Divider(height: 1),
                for (final (label, duration) in [
                  ('1 day', const Duration(days: 1)),
                  ('7 days', const Duration(days: 7)),
                  ('30 days', const Duration(days: 30)),
                ])
                  ListTile(
                    leading: Icon(Icons.schedule, color: colors.textSecondary),
                    title: CustomText(text: label),
                    onTap: () {
                      Navigator.pop(ctx);
                      chatCubit.pinMessage(widget.message, duration);
                    },
                  ),
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

    if (widget.message.status == 'pending') {
      statusText = "Pending";
      statusIcon = Icons.schedule;
      statusColor = Colors.orange;
    } else if (widget.message.status == 'delivered') {
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
        title: CustomText(
            text: "Message Info",
            fontWeight: FontWeight.bold,
            textColor: FcAppColors.of(context).textPrimary),
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
            fillColor: FcAppColors.of(ctx).inputFill,
            contentPadding:
                EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
          ),
          cursorColor: FcAppColors.of(ctx).textPrimary,
          maxLines: null,
          strutStyle: const StrutStyle(fontSize: 15),
          controller: controller,
          style: TextStyle(color: FcAppColors.of(ctx).textPrimary),
          textDirection: intl.Bidi.detectRtlDirectionality(controller.text)
              ? TextDirection.rtl
              : TextDirection.ltr,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: CustomText(
                  text: "Cancel", textColor: FcAppColors.of(ctx).textPrimary)),
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
              child: CustomText(
                  text: "Cancel", textColor: FcAppColors.of(ctx).textPrimary)),
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

  void _showDeleteForMeConfirmation(BuildContext context) {
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const CustomText(text: "Delete for me"),
        content: const CustomText(
            text: "Delete this message only from your chat? The other person "
                "will still see it."),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: CustomText(
                  text: "Cancel", textColor: FcAppColors.of(ctx).textPrimary)),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              context.read<ChatCubit>().deleteMessageForMe(widget.message.id);
              Navigator.of(ctx).pop();
            },
            child: const CustomText(text: "Delete", textColor: Colors.white),
          ),
        ],
      ),
    );
  }

  Widget _buildCallNotice(FcAppColors colors) {
    final message = widget.message;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isVideo = message.callType == 'video';
    final isCompleted = message.callOutcome == 'completed';

    // Viewer-aware caller name: "You" for the participant who placed the call,
    // otherwise the caller's display name.
    String caller;
    if (message.callerId != null && message.callerId == myUid) {
      caller = 'You';
    } else if (!widget.isGroup) {
      caller = widget.contactName ?? message.senderName ?? 'Caller';
    } else {
      caller = widget.sender != null
          ? '${widget.sender!.firstName} ${widget.sender!.lastName}'
          : (message.senderName ?? 'Caller');
    }

    final typeLabel = isVideo ? 'Video call' : 'Voice call';
    final String detail;
    if (isCompleted) {
      detail = _formatCallDuration(message.callDuration ?? 0);
    } else {
      detail = _callOutcomeLabel(message.callOutcome);
    }

    // For group call history, mention how many members were offline at call
    // time (they never saw the ring).
    final String summaryDetail =
        (widget.isGroup && (message.offlineCount ?? 0) > 0)
            ? '$detail · ${message.offlineCount} offline'
            : detail;

    final accent = isCompleted ? const Color(0xFF34C759) : Colors.redAccent;
    final icon = isVideo ? Icons.videocam_rounded : Icons.call_rounded;

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 24.w),
      child: Center(
        child: Container(
          padding:
              EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
          decoration: BoxDecoration(
            color: accent.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(14.r),
            border: Border.all(
              color: accent.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 15.sp, color: accent),
              SizedBox(width: 6.w),
              Flexible(
                child: CustomText(
                  text: '$caller · $typeLabel · $summaryDetail',
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w500,
                  textColor: colors.textPrimary,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// WhatsApp / Messenger-style active group call card rendered as a real
  /// message in the chat list. Shows the caller name, a pulsing LIVE dot,
  /// and a full-width "Join call" button that taps into the ongoing call.
  Widget _buildActiveCallMessage(FcAppColors colors) {
    final message = widget.message;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    final isVideo = message.callType == 'video';
    final callerId = message.callerId;
    final isCaller = callerId == myUid;
    final typeLabel = isVideo ? 'Video call' : 'Voice call';

    String caller;
    if (isCaller) {
      caller = 'You';
    } else if (widget.sender != null) {
      caller =
          '${widget.sender!.firstName} ${widget.sender!.lastName}';
    } else {
      caller = message.senderName ?? 'Someone';
    }

    final LinearGradient avatarGradient = LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: isVideo
          ? const [Color(0xFF0288D1), Color(0xFF4FC3F7)]
          : const [Color(0xFF00BFA5), Color(0xFF64FFDA)],
    );

    return Padding(
      padding: EdgeInsets.symmetric(vertical: 6.h, horizontal: 20.w),
      child: Center(
        child: Container(
          padding: EdgeInsets.fromLTRB(14.w, 12.h, 14.w, 12.h),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(18.r),
            border: Border.all(color: colors.surfaceDim),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.10),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  Container(
                    width: 46,
                    height: 46,
                    decoration: BoxDecoration(
                      gradient: avatarGradient,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      isVideo
                          ? Icons.videocam_rounded
                          : Icons.call_rounded,
                      color: Colors.white,
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$caller started a $typeLabel',
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: colors.textPrimary,
                            fontSize: 14.5,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            FadeTransition(
                              opacity: Tween<double>(begin: 0.35, end: 1)
                                  .animate(_livePulse),
                              child: Container(
                                width: 8,
                                height: 8,
                                decoration: const BoxDecoration(
                                  color: Color(0xFF34C759),
                                  shape: BoxShape.circle,
                                ),
                              ),
                            ),
                            const SizedBox(width: 5),
                            Flexible(
                              child: Text(
                                'LIVE · $typeLabel',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: colors.textSecondary,
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              SizedBox(height: 10.h),
              const Divider(height: 1),
              SizedBox(height: 10.h),
              SizedBox(
                width: double.infinity,
                height: 42,
                child: isCaller
                    ? Container(
                        height: 42,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: colors.surfaceMuted,
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colors.surfaceDim),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.headset_rounded,
                              size: 17,
                              color: colors.textSecondary,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'In this call',
                              style: TextStyle(
                                color: colors.textSecondary,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: colors.bubbleMine,
                          foregroundColor: colors.bubbleMineText,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          textStyle: const TextStyle(
                            fontSize: 14,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        onPressed: widget.onJoinCall,
                        child: const Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.call_rounded, size: 18),
                            SizedBox(width: 8),
                            Text('Join call'),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _formatCallDuration(int seconds) {
    final h = seconds ~/ 3600;
    final m = (seconds % 3600) ~/ 60;
    final s = seconds % 60;
    String two(int v) => v.toString().padLeft(2, '0');
    if (h > 0) return '$h:${two(m)}:${two(s)}';
    return '${two(m)}:${two(s)}';
  }

  String _callOutcomeLabel(String? outcome) {
    switch (outcome) {
      case 'missed':
        return 'Missed';
      case 'declined':
        return 'Declined';
      case 'cancelled':
        return 'Cancelled';
      case 'busy':
        return 'Busy';
      default:
        return 'Call ended';
    }
  }
}

/// Compact WhatsApp-style pill showing the reactions on a single photo.
class _ReactionPill extends StatelessWidget {
  final Map<String, String> reactions;
  final Color backgroundColor;

  const _ReactionPill({
    required this.reactions,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: colors.surfaceDim, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            reactions.values.toSet().join(''),
            style: TextStyle(fontSize: 12.sp),
          ),
          if (reactions.length > 1) ...[
            SizedBox(width: 3.w),
            Text(
              '${reactions.length}',
              style: TextStyle(
                color: colors.textSecondary,
                fontSize: 10.5.sp,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ],
      ),
    );
  }
}
