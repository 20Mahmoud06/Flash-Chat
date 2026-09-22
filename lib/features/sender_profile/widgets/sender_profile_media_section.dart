import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// Media counts (photos/videos/voice/links) for the chat, computed from the
/// message stream, with tap targets that open the matching gallery tab.
class SenderProfileMediaSection extends StatelessWidget {
  static final _urlRegExp = RegExp(r'''(https?://|www\.)[^\s<>"']+''');

  final String chatId;
  final ValueChanged<int> onOpenGallery;

  const SenderProfileMediaSection({
    super.key,
    required this.chatId,
    required this.onOpenGallery,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(color: colors.divider),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .doc(chatId)
            .collection('messages')
            .snapshots(),
        builder: (context, snapshot) {
          var photos = 0, videos = 0, voice = 0, links = 0;
          final docs = snapshot.data?.docs ?? const [];
          for (final doc in docs) {
            final data = doc.data();
            if (data['isDeleted'] == true) continue;
            final type = data['messageType'];
            if (type == 'image') {
              photos += (data['mediaUrls'] as List?)?.length ?? 0;
            } else if (type == 'video') {
              videos++;
            } else if (type == 'voice') {
              voice++;
              // Text messages (also the legacy ones sent before the
              // `messageType` field existed, whose type is null) count as
              // links when their text contains a URL.
            } else if ((type == null || type == 'text') &&
                _urlRegExp.hasMatch(data['text'] ?? '')) {
              links++;
            }
          }
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Row(
              children: [
                _MediaTile(
                  icon: Icons.photo_library_outlined,
                  color: Colors.blue,
                  label: 'Photos',
                  count: photos,
                  onTap: () => onOpenGallery(0),
                ),
                _MediaTile(
                  icon: Icons.videocam_outlined,
                  color: Colors.deepOrange,
                  label: 'Videos',
                  count: videos,
                  onTap: () => onOpenGallery(1),
                ),
                _MediaTile(
                  icon: Icons.mic_none,
                  color: Colors.green,
                  label: 'Voice',
                  count: voice,
                  onTap: () => onOpenGallery(2),
                ),
                _MediaTile(
                  icon: Icons.link,
                  color: Colors.purple,
                  label: 'Links',
                  count: links,
                  onTap: () => onOpenGallery(3),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MediaTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _MediaTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 22.r,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 22.sp),
              ),
              SizedBox(height: 6.h),
              CustomText(
                text: '$count',
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                textColor: colors.textPrimary,
              ),
              CustomText(
                text: label,
                fontSize: 12.sp,
                textColor: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
