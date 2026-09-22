import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flash_chat_app/shared/widgets/voice_message_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import 'media_gallery_helpers.dart';

/// Voice-message list mirroring the chat voice bubbles: own messages pinned
/// right with the mine-bubble palette, received ones on the left with the
/// incoming palette. Each row embeds a [VoiceMessagePlayer].
class MediaGalleryVoiceTab extends StatelessWidget {
  final List<MessageModel> messages;
  final GallerySender sender;

  const MediaGalleryVoiceTab({
    super.key,
    required this.messages,
    required this.sender,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final voiceMessages = messages
        .where((m) => m.messageType == MessageType.voice && m.mediaUrls != null)
        .toList();
    if (voiceMessages.isEmpty) {
      return const MediaGalleryEmptyState(
        label: 'No voice messages',
        icon: Icons.mic_none,
      );
    }
    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      itemCount: voiceMessages.length,
      separatorBuilder: (context, i) => Divider(
        height: 16.h,
        thickness: 1.5,
        color: FcAppColors.of(context).divider,
      ),
      itemBuilder: (context, i) {
        final msg = voiceMessages[i];
        final isMe = msg.senderId == sender.myUid;
        final senderEmoji = sender.emojiOf(msg);
        final senderName = sender.nameOf(msg);

        final Color textColor =
            isMe ? colors.bubbleMineText : colors.textPrimary;
        final Color timeColor = isMe
            ? colors.bubbleMineText.withValues(alpha: 0.75)
            : colors.textWeak;
        final Color playedColor =
            isMe ? colors.bubbleMineText : Colors.lightBlueAccent.shade700;
        final Color idleColor = (isMe ? colors.bubbleMineText : Colors.blueGrey)
            .withValues(alpha: 0.35);

        final avatar = CircleAvatar(
          radius: 18.r,
          backgroundColor: colors.avatarBackground,
          child: CustomText(text: senderEmoji, fontSize: 16.sp),
        );
        final info = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: CustomText(
                      text: senderName,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      textColor: textColor,
                    ),
                  ),
                  CustomText(
                    text: formatGalleryTime(msg.timestamp),
                    fontSize: 11.sp,
                    textColor: timeColor,
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              VoiceMessagePlayer(
                audioUrl: msg.mediaUrls!.first,
                initialDuration: msg.voiceDuration != null
                    ? Duration(seconds: msg.voiceDuration!)
                    : null,
                playedColor: playedColor,
                idleColor: idleColor,
                textColor: textColor,
              ),
            ],
          ),
        );

        final maxCardWidth = MediaQuery.of(context).size.width * 0.82;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxCardWidth),
            child: Card(
              elevation: 1,
              margin: EdgeInsets.only(bottom: 10.h),
              color: isMe ? colors.bubbleMine : colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.r),
                side:
                    isMe ? BorderSide.none : BorderSide(color: colors.divider),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
                child: isMe
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [
                          info,
                          SizedBox(width: 10.w),
                          avatar,
                        ],
                      )
                    : Row(
                        children: [
                          avatar,
                          SizedBox(width: 10.w),
                          info,
                        ],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }
}