import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

/// Resolves a message sender's display name and avatar emoji within the gallery
/// context (differs for self, 1-on-1 contacts, and group members).
class GallerySender {
  final String myUid;
  final bool isGroup;
  final UserModel? contact;
  final UserModel? myUser;
  final Map<String, UserModel> groupMembers;

  const GallerySender({
    required this.myUid,
    required this.isGroup,
    this.contact,
    this.myUser,
    this.groupMembers = const {},
  });

  String nameOf(MessageModel message) {
    if (message.senderId == myUid) return 'You';
    if (isGroup) {
      final sender = groupMembers[message.senderId];
      return sender != null ? sender.fullName : 'Unknown';
    }
    return contact!.fullName;
  }

  String emojiOf(MessageModel message) {
    if (message.senderId == myUid) return myUser?.avatarEmoji ?? '\u{1f464}';
    if (isGroup) {
      return groupMembers[message.senderId]?.avatarEmoji ?? '\u{1f464}';
    }
    return contact!.avatarEmoji;
  }
}

String formatGalleryDuration(int seconds) {
  final d = Duration(seconds: seconds);
  final m = d.inMinutes.toString();
  final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return '$m:$s';
}

String formatGalleryTime(Timestamp timestamp) {
  return DateFormat('d MMM, h:mm a').format(timestamp.toDate());
}

/// Centered empty-tab placeholder icon + label.
class MediaGalleryEmptyState extends StatelessWidget {
  final String label;
  final IconData icon;

  const MediaGalleryEmptyState({
    super.key,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: colors.textWeak),
          SizedBox(height: 12.h),
          CustomText(
            text: label,
            fontSize: 15.sp,
            textColor: colors.textSecondary,
          ),
        ],
      ),
    );
  }
}