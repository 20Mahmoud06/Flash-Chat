import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';
import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/full_image_viewer.dart';
import '../../../../core/utils/full_video_viewer.dart';
import '../../../../core/utils/video_playback_url.dart';
import '../../../../services/media/file_message_service.dart';
import '../../../../shared/widgets/custom_text.dart';
import '../../../../shared/widgets/voice_message_player.dart';
import '../../models/message_model.dart';
import 'message_bubble_file.dart';
import 'message_bubble_reactions.dart';

/// The actual message payload inside a bubble: formatted text (with tappable
/// links), a single/grid photo, video, or voice message — plus the optional
/// text caption rendered underneath media.
class MessageBubbleContent extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final Color textColor;
  final Color bubbleColor;

  /// Opens the long-press menu. [mediaItemId] is set when a single photo or
  /// video of the message was targeted rather than the message as a whole.
  final void Function(int? replyMediaIndex, String? mediaItemId) onShowOptions;
  final void Function(String mediaItemId) onShowImageReactions;

  /// Re-uploads one failed tile of a partially failed media message.
  final void Function(String mediaItemId) onRetryMediaItem;

  const MessageBubbleContent({
    super.key,
    required this.message,
    required this.isMe,
    required this.textColor,
    required this.bubbleColor,
    required this.onShowOptions,
    required this.onShowImageReactions,
    required this.onRetryMediaItem,
  });

  static final _urlRegExp = RegExp(r'''(https?://|www\.)[^\s<>"']+''');

  @override
  Widget build(BuildContext context) {
    if (message.messageType == MessageType.text) {
      return _buildTextMessage(context);
    }

    Widget mediaWidget = const SizedBox.shrink();

    if (message.messageType == MessageType.image) {
      final items = message.resolvedMediaItems;
      final ready = [
        for (final item in items)
          if (item.isDone) item
      ];

      if (ready.isEmpty) {
        // Every slot is still uploading or failed — the grid below renders
        // those states, so only fall back to text when there is nothing at all.
        if (items.isEmpty) {
          mediaWidget = const CustomText(text: 'Photo unavailable');
        } else {
          mediaWidget = _buildMediaBubble(context, items, isVideo: false);
        }
      } else if (ready.length == 1 && items.length == 1) {
        // Single photo keeps its natural aspect ratio: no cropping, no
        // stretching, just capped to a comfortable bubble size.
        mediaWidget = ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 0.28.sw,
            maxWidth: 0.55.sw,
            maxHeight: 0.72.sw,
          ),
          child: _buildMediaImage(
            context,
            ready.first.url!,
            fit: BoxFit.contain,
            heroTag: '${message.id}_${ready.first.id}',
            mediaIndex: items.indexOf(ready.first),
            onTap: () => _openImage(
                context, ready.first.url!, '${message.id}_${ready.first.id}'),
            onLongPress: () =>
                onShowOptions(items.indexOf(ready.first), ready.first.id),
          ),
        );
      } else {
        mediaWidget = _buildMediaBubble(context, items, isVideo: false);
      }
    } else if (message.messageType == MessageType.video) {
      final items = message.resolvedMediaItems;
      final ready = [
        for (final item in items)
          if (item.isDone) item
      ];

      if (ready.isEmpty) {
        if (items.isEmpty) {
          mediaWidget = const CustomText(text: 'Video unavailable');
        } else {
          mediaWidget = _buildMediaBubble(context, items, isVideo: true);
        }
      } else if (ready.length == 1 && items.length == 1) {
        mediaWidget = ConstrainedBox(
          constraints: BoxConstraints(
            minWidth: 0.28.sw,
            maxWidth: 0.55.sw,
            maxHeight: 0.72.sw,
          ),
          child: AspectRatio(
            aspectRatio: 16 / 9,
            child: _buildVideoThumbnail(
              context,
              ready.first.url!,
              index: 0,
            ),
          ),
        );
      } else {
        mediaWidget = _buildMediaBubble(context, items, isVideo: true);
      }
    } else if (message.messageType == MessageType.voice) {
      final audioUrl = (message.mediaUrls?.isNotEmpty ?? false)
          ? message.mediaUrls!.first
          : null;
      if (audioUrl == null) {
        return const CustomText(text: 'Voice message unavailable');
      }
      return VoiceMessagePlayer(
        audioUrl: audioUrl,
        initialDuration: message.voiceDuration != null
            ? Duration(seconds: message.voiceDuration!)
            : null,
        playedColor: isMe
            ? FcAppColors.of(context).bubbleMineText
            : Colors.lightBlueAccent.shade700,
        idleColor:
            (isMe ? FcAppColors.of(context).bubbleMineText : Colors.blueGrey)
                .withValues(alpha: 0.35),
        textColor: textColor,
      );
    } else if (message.messageType == MessageType.audio) {
      // Sent audio files reuse the voice-message player UI with a small
      // touch of difference: a music-note + file name header above the wave.
      final audioUrl = (message.mediaUrls?.isNotEmpty ?? false)
          ? message.mediaUrls!.first
          : null;
      if (audioUrl == null) {
        return const CustomText(text: 'Audio file unavailable');
      }
      final fileName = message.fileName ?? 'Audio file';
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                Icons.music_note_rounded,
                size: 16.sp,
                color: textColor.withValues(alpha: 0.9),
              ),
              SizedBox(width: 4.w),
              Flexible(
                child: CustomText(
                  text: fileName,
                  textColor: textColor.withValues(alpha: 0.9),
                  fontSize: 12.sp,
                  fontWeight: FontWeight.w600,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              SizedBox(width: 6.w),
              _AudioSaveButton(
                audioUrl: audioUrl,
                fileName: fileName,
                isMe: isMe,
                textColor: textColor,
              ),
            ],
          ),
          SizedBox(height: 4.h),
          VoiceMessagePlayer(
            audioUrl: audioUrl,
            initialDuration: message.voiceDuration != null
                ? Duration(seconds: message.voiceDuration!)
                : null,
            playedColor: isMe
                ? FcAppColors.of(context).bubbleMineText
                : Colors.lightBlueAccent.shade700,
            idleColor: (isMe
                    ? FcAppColors.of(context).bubbleMineText
                    : Colors.blueGrey)
                .withValues(alpha: 0.35),
            textColor: textColor,
          ),
        ],
      );
    } else if (message.messageType == MessageType.file) {
      return MessageFileCard(
        message: message,
        isMe: isMe,
        textColor: textColor,
        bubbleColor: bubbleColor,
        onShowOptions: () => onShowOptions(null, null),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        mediaWidget,
        if (message.text.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: 4.h),
            child: _buildTextMessage(context),
          ),
      ],
    );
  }

  Widget _buildTextMessage(BuildContext context) {
    final text = message.text;
    // Pick the link color for contrast against the BUBBLE background (not
    // the text color). For the user's own bubbles (lightBlueAccent bg,
    // white text), links stay white with an underline so they blend with
    // the message text. For the other user's lighter bubbles we use the
    // app's primary accent so links feel consistent with the rest of the UI.
    final isDarkBubble =
        ThemeData.estimateBrightnessForColor(bubbleColor) == Brightness.dark;
    final linkColor = isDarkBubble
        ? Colors.white
        : (isMe ? Colors.white : Colors.lightBlueAccent);
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

  void _openImage(BuildContext context, String url, String heroTag) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => FullImageViewer(
        imageUrl: url,
        heroTag: heroTag,
      ),
    );
  }

  void _openVideo(BuildContext context, String url, int index) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => FullVideoViewer(
          videoUrl: url,
          initialDuration: _videoDurationAt(index),
        ),
      ),
    );
  }

  Duration? _videoDurationAt(int index) {
    final seconds = message.videoDurationAt(index);
    if (seconds == null || seconds <= 0) return null;
    return Duration(seconds: seconds);
  }

  /// Renders a media message that is not a single finished item: a grid for
  /// batches, or one square placeholder while a lone photo/video is in flight
  /// (a one-cell grid would render at half the bubble width and look broken).
  Widget _buildMediaBubble(
    BuildContext context,
    List<MediaItem> items, {
    required bool isVideo,
  }) {
    if (items.length == 1) {
      final item = items.first;
      return ClipRRect(
        borderRadius: BorderRadius.circular(12.r),
        child: SizedBox(
          width: 0.45.sw,
          height: 0.45.sw,
          child: item.isFailed
              ? (isMe
                  ? _buildFailedSlot(context, item.id)
                  : _buildUnavailableSlot(context))
              : _buildPendingSlot(context),
        ),
      );
    }
    return _buildMediaGrid(context, items, isVideo: isVideo);
  }

  /// Square grid of a media message's tiles.
  ///
  /// Every slot keeps its position for the whole send, so the grid is already
  /// its final shape while the batch uploads, and a failed tile becomes a retry
  /// button in place instead of a hole. Photos use 3 columns once there are
  /// more than 4 so the bubble stays compact; videos always use 2.
  Widget _buildMediaGrid(
    BuildContext context,
    List<MediaItem> items, {
    required bool isVideo,
  }) {
    final isLargeGrid = !isVideo && items.length > 4;
    return ClipRRect(
      borderRadius: BorderRadius.circular(12.r),
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: isLargeGrid ? 3 : 2,
          childAspectRatio: 1,
          crossAxisSpacing: 4.w,
          mainAxisSpacing: 4.h,
        ),
        itemCount: items.length > 9 ? 9 : items.length,
        itemBuilder: (_, i) {
          final item = items[i];
          if (item.isFailed) {
            return isMe
                ? _buildFailedSlot(context, item.id)
                : _buildUnavailableSlot(context);
          }
          if (!item.isDone) {
            return GestureDetector(
              onLongPress: () => onShowOptions(i, item.id),
              child: _buildPendingSlot(context),
            );
          }
          final url = item.url!;
          final heroTag = '${message.id}_${item.id}';
          return isVideo
              ? _buildVideoThumbnail(context, url, index: i)
              : _buildMediaImage(
                  context,
                  url,
                  fit: BoxFit.cover,
                  heroTag: heroTag,
                  mediaIndex: i,
                  onTap: () => _openImage(context, url, heroTag),
                  onLongPress: () => onShowOptions(i, item.id),
                );
        },
      ),
    );
  }

  /// Placeholder tile for a media slot of a batch that is still uploading.
  Widget _buildPendingSlot(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      color: colors.surfaceMuted,
      child: Center(
        child: SizedBox(
          width: 22,
          height: 22,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colors.textSecondary,
          ),
        ),
      ),
    );
  }

  /// Tile for an item whose upload failed from the other user's side.
  Widget _buildUnavailableSlot(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      color: colors.surfaceMuted,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.broken_image_outlined,
              color: colors.textSecondary, size: 24),
          SizedBox(height: 4.h),
          CustomText(
            text: 'Unavailable',
            textColor: colors.textSecondary,
            fontSize: 10.sp,
          ),
        ],
      ),
    );
  }

  /// Tile for an item whose upload failed. Tapping retries just this item;
  /// long-pressing opens its options (delete it instead of resending).
  Widget _buildFailedSlot(BuildContext context, String itemId) {
    final colors = FcAppColors.of(context);
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => onRetryMediaItem(itemId),
      onLongPress: () => onShowOptions(null, itemId),
      child: Container(
        color: colors.surfaceMuted,
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.refresh_rounded, color: colors.textSecondary, size: 26),
            SizedBox(height: 4.h),
            CustomText(
              text: 'Tap to retry',
              textColor: colors.textSecondary,
              fontSize: 10.sp,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVideoThumbnail(
    BuildContext context,
    String url, {
    required int index,
  }) {
    final thumbUrl = videoThumbnailUrl(url);
    final duration = _videoDurationAt(index);

    Widget tile = Container(
      color: Colors.black12,
      child: thumbUrl.isEmpty
          ? const Center(
              child: Icon(
                Icons.videocam_off_outlined,
                color: Colors.grey,
                size: 30,
              ),
            )
          : CachedNetworkImage(
              imageUrl: thumbUrl,
              fit: BoxFit.cover,
              placeholder: (context, _) => Container(
                color: Colors.black12,
                child: const Center(
                  child: SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.lightBlueAccent,
                    ),
                  ),
                ),
              ),
              errorWidget: (context, _, __) => Container(
                color: Colors.black12,
                child: const Center(
                  child: Icon(
                    Icons.videocam_off_outlined,
                    color: Colors.grey,
                    size: 30,
                  ),
                ),
              ),
            ),
    );

    tile = Stack(
      fit: StackFit.expand,
      children: [
        tile,
        const Positioned.fill(
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [Colors.transparent, Colors.black26],
                stops: [0.6, 1.0],
              ),
            ),
          ),
        ),
        Positioned.fill(
          child: Center(
            child: Container(
              width: 42.w,
              height: 42.w,
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.42),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.play_arrow_rounded,
                color: Colors.white,
                size: 28.w,
              ),
            ),
          ),
        ),
        if (duration != null)
          Positioned(
            right: 6.w,
            bottom: 6.h,
            child: _videoDurationBadge(duration),
          ),
      ],
    );

    // Reactions are keyed by the item's stable id (the plain index for older
    // documents, which stored them as `imageReactions.<index>`), so they stay
    // attached to this photo when siblings are deleted.
    final mediaReactions = message.imageReactions[message.mediaItemIdAt(index)];
    if (mediaReactions != null && mediaReactions.isNotEmpty) {
      tile = Stack(
        clipBehavior: Clip.none,
        children: [
          tile,
          Positioned(
            left: 6.w,
            bottom: 6.h,
            child: GestureDetector(
              onTap: () => onShowImageReactions(message.mediaItemIdAt(index)),
              child: MessageBubbleReactionPill(
                reactions: mediaReactions,
                backgroundColor: FcAppColors.of(context).surface,
              ),
            ),
          ),
        ],
      );
    }

    tile = ClipRRect(
      borderRadius: BorderRadius.circular(8.r),
      child: tile,
    );

    return GestureDetector(
      onTap: () => _openVideo(context, url, index),
      onLongPress: () => onShowOptions(index, message.mediaItemIdAt(index)),
      child: tile,
    );
  }

  Widget _videoDurationBadge(Duration duration) {
    final minutes = duration.inMinutes.toString().padLeft(2, '0');
    final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 5.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.65),
        borderRadius: BorderRadius.circular(6.r),
      ),
      child: CustomText(
        text: '$minutes:$seconds',
        textColor: Colors.white,
        fontSize: 10.sp,
        fontWeight: FontWeight.w700,
      ),
    );
  }

  Widget _buildMediaImage(
    BuildContext context,
    String url, {
    required BoxFit fit,
    required String heroTag,
    required int mediaIndex,
    VoidCallback? onTap,
    VoidCallback? onLongPress,
  }) {
    Widget image = CachedNetworkImage(
      imageUrl: url,
      fit: fit,
      placeholder: (context, _) => Container(
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
      ),
      errorWidget: (context, _, __) => Container(
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
    // bottom-left corner of THIS photo, showing who reacted to it. Keyed by the
    // item's stable id so the pill survives sibling deletion/reordering.
    final photoReactions =
        message.imageReactions[message.mediaItemIdAt(mediaIndex)];
    if (photoReactions != null && photoReactions.isNotEmpty) {
      image = Stack(
        clipBehavior: Clip.none,
        children: [
          image,
          Positioned(
            left: 6.w,
            bottom: 6.h,
            child: GestureDetector(
              onTap: () =>
                  onShowImageReactions(message.mediaItemIdAt(mediaIndex)),
              child: MessageBubbleReactionPill(
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
}

/// Compact "save to device" button on audio file bubbles: downloads the file
/// into the app cache and writes it into the device's public Downloads folder,
/// mirroring the save action of the document file card ([MessageFileCard]).
class _AudioSaveButton extends StatefulWidget {
  final String audioUrl;
  final String fileName;
  final bool isMe;
  final Color textColor;

  const _AudioSaveButton({
    required this.audioUrl,
    required this.fileName,
    required this.isMe,
    required this.textColor,
  });

  @override
  State<_AudioSaveButton> createState() => _AudioSaveButtonState();
}

class _AudioSaveButtonState extends State<_AudioSaveButton> {
  bool _busy = false;

  Future<void> _save() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final file = await FileMessageService.downloadToCache(
          widget.audioUrl, widget.fileName);
      final saved =
          await FileMessageService.saveToDownloads(file.path, widget.fileName);
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: CustomText(
            text: saved != null
                ? 'Saved to Downloads'
                : 'Could not save the file. Check storage permission.',
          ),
        ),
      );
    } catch (e) {
      debugPrint('Audio save failed: $e');
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: CustomText(text: 'Could not save the audio file.'),
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return GestureDetector(
      onTap: _save,
      child: Container(
        width: 26.w,
        height: 26.w,
        decoration: BoxDecoration(
          color: widget.isMe
              ? Colors.white.withValues(alpha: 0.22)
              : colors.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: widget.isMe
                ? Colors.white.withValues(alpha: 0.5)
                : AppColors.primaryDark.withValues(alpha: 0.35),
          ),
        ),
        child: _busy
            ? Padding(
                padding: EdgeInsets.all(5.w),
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: widget.isMe ? Colors.white : AppColors.primaryDark,
                ),
              )
            : Icon(
                Icons.save_alt_rounded,
                size: 16.sp,
                color: widget.isMe ? Colors.white : colors.textPrimary,
              ),
      ),
    );
  }
}
