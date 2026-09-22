import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart' as intl;
import 'package:url_launcher/url_launcher.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../../core/utils/full_image_viewer.dart';
import '../../../../shared/widgets/custom_text.dart';
import '../../../../shared/widgets/voice_message_player.dart';
import '../../models/message_model.dart';
import '../video_message_player/video_message_player.dart';
import 'message_bubble_reactions.dart';

/// The actual message payload inside a bubble: formatted text (with tappable
/// links), a single/grid photo, video, or voice message — plus the optional
/// text caption rendered underneath media.
class MessageBubbleContent extends StatelessWidget {
  final MessageModel message;
  final bool isMe;
  final Color textColor;
  final Color bubbleColor;
  final void Function(int? replyMediaIndex, int? mediaIndex) onShowOptions;
  final void Function(int mediaIndex) onShowImageReactions;

  const MessageBubbleContent({
    super.key,
    required this.message,
    required this.isMe,
    required this.textColor,
    required this.bubbleColor,
    required this.onShowOptions,
    required this.onShowImageReactions,
  });

  static final _urlRegExp = RegExp(r'''(https?://|www\.)[^\s<>"']+''');

  @override
  Widget build(BuildContext context) {
    if (message.messageType == MessageType.text) {
      return _buildTextMessage(context);
    }

    Widget mediaWidget = const SizedBox.shrink();

    if (message.messageType == MessageType.image) {
      final mediaUrls = message.mediaUrls ?? [];

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
            context,
            mediaUrls.first,
            fit: BoxFit.contain,
            heroTag: '${message.id}_0',
            mediaIndex: 0,
            onTap: () => _openImage(context, mediaUrls.first, 0),
            onLongPress: () => onShowOptions(0, 0),
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
              context,
              mediaUrls[i],
              fit: BoxFit.cover,
              heroTag: '${message.id}_$i',
              mediaIndex: i,
              onTap: () => _openImage(context, mediaUrls[i], i),
              onLongPress: () => onShowOptions(i, i),
            ),
          ),
        );
      }
    } else if (message.messageType == MessageType.video) {
      final videoUrl = (message.mediaUrls?.isNotEmpty ?? false)
          ? message.mediaUrls!.first
          : null;
      if (videoUrl == null) {
        mediaWidget = const CustomText(text: 'Video unavailable');
      } else {
        mediaWidget = GestureDetector(
          onLongPress: () => onShowOptions(null, null),
          child: VideoMessagePlayer(
            videoUrl: videoUrl,
            initialDuration: message.videoDuration != null
                ? Duration(seconds: message.videoDuration!)
                : null,
          ),
        );
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
        idleColor: (isMe
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

  void _openImage(BuildContext context, String url, int index) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => FullImageViewer(
        imageUrl: url,
        heroTag: '${message.id}_$index',
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
    final photoReactions = message.imageReactions['$mediaIndex'];
    if (photoReactions != null && photoReactions.isNotEmpty) {
      image = Stack(
        clipBehavior: Clip.none,
        children: [
          image,
          Positioned(
            left: 6.w,
            bottom: 6.h,
            child: GestureDetector(
              onTap: () => onShowImageReactions(mediaIndex),
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