import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_theme.dart';
import '../../models/message_model.dart';
import '../reply_preview_card.dart';

/// The "replying to" banner shown above the composer's text field, with a
/// [ReplyPreviewCard] on the left and a close button on the right.
class MessageComposerReplyBar extends StatelessWidget {
  final String senderName;
  final MessageType type;
  final String preview;
  final String? mediaUrl;
  final int? mediaCount;
  final int? duration;
  final VoidCallback onClose;

  const MessageComposerReplyBar({
    super.key,
    required this.senderName,
    required this.type,
    required this.preview,
    this.mediaUrl,
    this.mediaCount,
    this.duration,
    required this.onClose,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(6.w, 4.h, 6.w, 4.h),
      decoration: BoxDecoration(
        color: colors.surfaceMuted,
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: colors.divider),
      ),
      margin: EdgeInsets.only(bottom: 8.h),
      child: Row(
        children: [
          Expanded(
            child: ReplyPreviewCard(
              senderName: senderName,
              type: type,
              preview: preview,
              mediaUrl: mediaUrl,
              mediaCount: mediaCount,
              duration: duration,
              isOwnMessage: false,
            ),
          ),
          IconButton(
            icon: Icon(Icons.close, color: colors.textSecondary),
            onPressed: onClose,
          ),
        ],
      ),
    );
  }
}