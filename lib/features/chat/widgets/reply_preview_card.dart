import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/utils/reply_preview.dart';
import '../../../core/utils/video_playback_url.dart';
import '../../../models/message_model.dart';

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
    final Color accentColor = isMe ? Colors.white : const Color(0xFF0288D1);
    final Color nameColor = isMe ? Colors.white : const Color(0xFF0288D1);
    final Color contentColor =
        isMe ? Colors.white.withValues(alpha: 0.95) : colors.textPrimary;
    final Color containerColor = isMe
        ? Colors.white.withValues(alpha: 0.18)
        : colors.surfaceMuted;

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
                  Text(
                    senderName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: nameColor,
                      fontSize: 12.sp,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  SizedBox(height: 3.h),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          preview,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: contentColor,
                            fontSize: 13.sp,
                          ),
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
                        image: NetworkImage(thumb),
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
                    colors: [Color(0xFF4FC3F7), Color(0xFF0288D1)],
                  ),
          ),
          child: Icon(
            Icons.mic_rounded,
            color: isMe ? Colors.white : Colors.white.withValues(alpha: 0.95),
            size: 24.sp,
          ),
        );
      case MessageType.system:
        return const SizedBox.shrink();
      case MessageType.call:
        return const SizedBox.shrink();
      case MessageType.callActive:
        return const SizedBox.shrink();
    }
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
        child: Icon(icon, color: const Color(0xFF0288D1), size: 24.sp),
      );
    }
    return Stack(
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(10.r),
          child: SizedBox(
            width: 46.w,
            height: 46.w,
            child: Image.network(
              url,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                width: 46.w,
                height: 46.w,
                color: backgroundColor,
                child: Icon(icon, color: const Color(0xFF0288D1), size: 24.sp),
              ),
              loadingBuilder: (context, child, progress) => progress == null
                  ? child
                  : Container(
                      width: 46.w,
                      height: 46.w,
                      color: backgroundColor,
                      child: Icon(icon,
                          color: const Color(0xFF0288D1), size: 20.sp),
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
      child: Text(
        text,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w700,
          fontFeatures: [FontFeature.tabularFigures()],
        ),
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
      child: Text(
        _formatDuration(seconds),
        style: TextStyle(
          color: (isMe ? Colors.white : colors.textSecondary)
              .withValues(alpha: 0.9),
          fontSize: 10.sp,
          fontWeight: FontWeight.w700,
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }
}
