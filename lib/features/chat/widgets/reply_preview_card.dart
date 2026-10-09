import 'package:cached_network_image/cached_network_image.dart';
import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/services/media/file_message_service.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'reply_preview.dart';
import '../../../core/utils/video_playback_url.dart';
import '../models/message_model.dart';

/// Premium WhatsApp-style reply preview.
/// Rendered both on the composer (before sending) and inside message
/// bubbles (received replies). Shows a thumbnail / media icon, the original
/// sender and the original media / text preview:
/// - Photo: thumbnail (+ count badge for whole-group replies) and caption.
/// - Video: thumbnail with a play overlay, duration badge and caption.
/// - Voice: gradient voice tile and duration.
/// - Text: plain sender + preview, unchanged.
class ReplyPreviewCard extends StatelessWidget {
  final String senderName;
  final MessageType type;
  final String preview;
  final String? mediaUrl;
  final int? duration;
  final int? mediaCount;
  final bool isOwnMessage;
  final VoidCallback? onTap;

  const ReplyPreviewCard({
    super.key,
    required this.senderName,
    required this.type,
    required this.preview,
    this.mediaUrl,
    this.duration,
    this.mediaCount,
    required this.isOwnMessage,
    this.onTap,
  });

  /// Builds a card straight from the `repliedTo` metadata persisted on a
  /// message, which keeps the bubble and composer previews in sync and makes
  /// media replies (photo / video / voice) look rich instead of plain text.
  factory ReplyPreviewCard.fromReplyMeta({
    required Map<String, dynamic> repliedTo,
    required bool isOwnMessage,
    required String resolvedSenderName,
    VoidCallback? onTap,
  }) {
    final type = replyPreviewType(repliedTo);
    return ReplyPreviewCard(
      senderName: resolvedSenderName,
      type: type,
      preview: replyPreviewForType(
        type,
        (repliedTo['text'] as String?) ?? '',
      ),
      mediaUrl: repliedTo['mediaUrl'] as String?,
      duration: repliedTo['duration'] as int?,
      mediaCount: repliedTo['count'] as int?,
      isOwnMessage: isOwnMessage,
      onTap: onTap,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isMe = isOwnMessage;
    final colors = FcAppColors.of(context);
    final Color accentColor = isMe ? Colors.white : AppColors.primaryDark;
    final Color nameColor = isMe ? Colors.white : AppColors.primaryDark;
    final Color contentColor =
        isMe ? Colors.white.withValues(alpha: 0.95) : colors.textPrimary;
    final Color containerColor =
        isMe ? Colors.white.withValues(alpha: 0.18) : colors.surfaceMuted;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        constraints: BoxConstraints(maxWidth: 250.w),
        padding: EdgeInsets.fromLTRB(10.w, 8.w, 12.w, 8.w),
        decoration: BoxDecoration(
          color: containerColor,
          borderRadius: BorderRadius.circular(12.r),
          border: Border(
            left: BorderSide(color: accentColor, width: 3.w),
          ),
          boxShadow: isMe
              ? null
              : [
                  BoxShadow(
                    color: Colors.lightBlueAccent.withValues(alpha: 0.10),
                    blurRadius: 8,
                    offset: const Offset(0, 3),
                  ),
                ],
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (type != MessageType.text) ...[
              _buildThumbnail(context),
              SizedBox(width: 10.w),
            ],
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    text: senderName,
                    textColor: nameColor,
                    fontSize: 12.sp,
                    fontWeight: FontWeight.w700,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  SizedBox(height: 3.h),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: CustomText(
                          text: preview,
                          textColor: contentColor,
                          fontSize: 13.sp,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      if ((type == MessageType.voice ||
                              type == MessageType.video) &&
                          duration != null) ...[
                        SizedBox(width: 8.w),
                        _durationChip(context, duration!),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildThumbnail(BuildContext context) {
    final bool isMe = isOwnMessage;
    final colors = FcAppColors.of(context);

    switch (type) {
      case MessageType.text:
        return const SizedBox.shrink();
      case MessageType.image:
        return _mediaTile(
          url: mediaUrl,
          backgroundColor:
              isMe ? Colors.white.withValues(alpha: 0.25) : colors.surfaceDim,
          icon: Icons.photo_outlined,
          child: (mediaCount != null && mediaCount! > 1)
              ? Positioned(
                  right: 4,
                  bottom: 4,
                  child: _badge('$mediaCount'),
                )
              : const SizedBox.shrink(),
        );
      case MessageType.video:
        final thumb = (mediaUrl != null && mediaUrl!.isNotEmpty)
            ? videoThumbnailUrl(mediaUrl!)
            : null;
        return Stack(
          children: [
            Container(
              width: 46.w,
              height: 46.w,
              decoration: BoxDecoration(
                color: isMe
                    ? Colors.white.withValues(alpha: 0.25)
                    : colors.surfaceDim,
                borderRadius: BorderRadius.circular(10.r),
                image: thumb != null
                    ? DecorationImage(
                        image: CachedNetworkImageProvider(thumb),
                        fit: BoxFit.cover,
                        onError: (exception, stackTrace) {},
                      )
                    : null,
              ),
            ),
            if (thumb != null)
              Positioned.fill(
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(10.r),
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.35),
                      ],
                    ),
                  ),
                ),
              ),
            Positioned.fill(
              child: Center(
                child: Icon(
                  Icons.play_circle_fill_rounded,
                  color: Colors.white.withValues(alpha: 0.95),
                  size: 26.w,
                  shadows: const [
                    Shadow(color: Colors.black45, blurRadius: 6),
                  ],
                ),
              ),
            ),
            if (duration != null)
              Positioned(
                right: 4,
                bottom: 4,
                child: _badge(_formatDuration(duration!)),
              ),
            if ((mediaCount ?? 0) > 1)
              Positioned(
                top: 4,
                right: 4,
                child: _badge('$mediaCount'),
              ),
          ],
        );
      case MessageType.voice:
        return Container(
          width: 46.w,
          height: 46.w,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(10.r),
            gradient: isMe
                ? LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.white.withValues(alpha: 0.30),
                      Colors.white.withValues(alpha: 0.18),
                    ],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [AppColors.sky, AppColors.primaryDark],
                  ),
          ),
          child: Icon(
            Icons.mic_rounded,
            color: isMe ? Colors.white : Colors.white.withValues(alpha: 0.95),
            size: 24.sp,
          ),
        );
      case MessageType.audio: {
        final visual = FileMessageService.iconFor('name.mp3');
        return _iconTile(
          backgroundColor:
              isMe ? Colors.white.withValues(alpha: 0.25) : colors.surfaceDim,
          icon: Icons.music_note_rounded,
          iconColor: visual.color,
        );
      }
      case MessageType.file: {
        final ext = (mediaUrl?.isEmpty ?? true) ? 'pdf' : 'file';
        final visual = FileMessageService.iconFor(ext);
        return _iconTile(
          backgroundColor:
              isMe ? Colors.white.withValues(alpha: 0.25) : colors.surfaceDim,
          icon: visual.icon,
          iconColor: visual.color,
        );
      }
      case MessageType.system:
        return const SizedBox.shrink();
      case MessageType.call:
        return const SizedBox.shrink();
      case MessageType.callActive:
        return const SizedBox.shrink();
    }
  }

  /// Small squared icon tile used for file / audio reply thumbnails.
  Widget _iconTile({
    required Color backgroundColor,
    required IconData icon,
    required Color iconColor,
  }) {
    return Container(
      width: 46.w,
      height: 46.w,
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10.r),
      ),
      child: Icon(icon, color: iconColor, size: 24.sp),
    );
  }

  /// Shared photo tile: thumbnail when a URL exists, tinted icon box otherwise.
  Widget _mediaTile({
    required String? url,
    required Color backgroundColor,
    required IconData icon,
    required Widget child,
  }) {
    if (url == null || url.isEmpty) {
      return Container(
        width: 46.w,
        height: 46.w,
        decoration: BoxDecoration(
          color: backgroundColor,
          borderRadius: BorderRadius.circular(10.r),
        ),
        child: Icon(icon, color: AppColors.primaryDark, size: 24.sp),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10.r),
          child: SizedBox(
            width: 46.w,
            height: 46.w,
            child: CachedNetworkImage(
              imageUrl: url,
              fit: BoxFit.cover,
              errorWidget: (context, error, stackTrace) => Container(
                width: 46.w,
                height: 46.w,
                color: backgroundColor,
                child: Icon(icon, color: AppColors.primaryDark, size: 24.sp),
              ),
              placeholder: (context, _) => Container(
                width: 46.w,
                height: 46.w,
                color: backgroundColor,
                child:
                    Icon(icon, color: AppColors.primaryDark, size: 20.sp),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }

  /// Small dark pill used for the video duration and photo group count.
  Widget _badge(String text) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: CustomText(
        text: text,
        textColor: Colors.white,
        fontSize: 9,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  /// Soft chip with the duration shown next to the voice / video label.
  Widget _durationChip(BuildContext context, int seconds) {
    final bool isMe = isOwnMessage;
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: isMe
            ? Colors.white.withValues(alpha: 0.20)
            : colors.surfaceDim.withValues(alpha: 0.8),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: CustomText(
        text: _formatDuration(seconds),
        textColor:
            (isMe ? Colors.white : colors.textSecondary).withValues(alpha: 0.9),
        fontSize: 10.sp,
        fontWeight: FontWeight.w700,
        fontFeatures: const [FontFeature.tabularFigures()],
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}