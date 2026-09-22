import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:url_launcher/url_launcher.dart';

import 'media_gallery_helpers.dart';

/// List of text messages that contain URLs, with host, raw link, sender info,
/// and an external-launch trailing icon.
class MediaGalleryLinksTab extends StatelessWidget {
  static final _urlRegExp = RegExp(r'''(https?://|www\.)[^\s<>"']+''');
  static final _trailingPunct = RegExp(r'[.,;:!?)]+$');

  final List<MessageModel> messages;
  final GallerySender sender;

  const MediaGalleryLinksTab({
    super.key,
    required this.messages,
    required this.sender,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final links = messages
        .where((m) => m.messageType == MessageType.text)
        .map((m) {
          final match = _urlRegExp.firstMatch(m.text);
          if (match == null) return null;
          final raw = match.group(0)!.replaceAll(_trailingPunct, '');
          return (message: m, url: raw);
        })
        .whereType<({MessageModel message, String url})>()
        .toList();
    if (links.isEmpty) {
      return const MediaGalleryEmptyState(
        label: 'No links',
        icon: Icons.link,
      );
    }
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      itemCount: links.length,
      itemBuilder: (context, i) {
        final item = links[i];
        final msg = item.message;
        final uri = Uri.tryParse(item.url);
        final host = uri != null && uri.hasScheme
            ? uri.host
            : Uri.tryParse('https://${item.url}')?.host ?? item.url;
        return Card(
          elevation: 1,
          margin: EdgeInsets.only(bottom: 10.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
            side: BorderSide(color: colors.divider),
          ),
          child: ListTile(
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
            leading: CircleAvatar(
              backgroundColor: Colors.lightBlueAccent.withValues(alpha: 0.15),
              child: const Icon(Icons.link, color: Colors.lightBlueAccent),
            ),
            title: CustomText(
              text: host,
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              textColor: colors.textPrimary,
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 2.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    text: item.url,
                    fontSize: 13.sp,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textColor: colors.textSecondary,
                  ),
                  SizedBox(height: 2.h),
                  CustomText(
                    text:
                        '${sender.nameOf(msg)} \u00b7 ${formatGalleryTime(msg.timestamp)}',
                    fontSize: 11.sp,
                    textColor: colors.textWeak,
                  ),
                ],
              ),
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.open_in_new,
                size: 18, color: Colors.lightBlueAccent),
            onTap: () async {
              var uri = Uri.tryParse(item.url);
              if (uri == null || !uri.hasScheme) {
                uri = Uri.parse('https://${item.url}');
              }
              try {
                final launched =
                    await launchUrl(uri, mode: LaunchMode.externalApplication);
                if (!launched) {
                  debugPrint('Failed to launch URL: ${item.url}');
                }
              } catch (e) {
                debugPrint('Error launching URL ${item.url}: $e');
              }
            },
          ),
        );
      },
    );
  }
}