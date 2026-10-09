import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../shared/widgets/custom_text.dart';

/// Banner shown above the list when the creator has deleted the whole group:
/// the conversation stays fully readable but becomes read-only for everyone.
class GroupDeletedBanner extends StatelessWidget {
  const GroupDeletedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: Colors.grey.shade200,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
            SizedBox(width: 10.w),
            Expanded(
              child: CustomText(
                text: 'This group was deleted by its creator. You can still '
                    'read the messages, but you cannot send, call, or react.',
                fontSize: 13.sp,
                textColor: Colors.grey.shade800,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner shown above the list so a removed/left member understands the chat
/// is now read-only: they keep seeing their earlier messages but can no
/// longer send, call, or react.
class GroupRemovedBanner extends StatelessWidget {
  const GroupRemovedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: Colors.orange.shade50,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 20),
            SizedBox(width: 10.w),
            Expanded(
              child: CustomText(
                text: 'You are no longer a member of this group. You can '
                    'still read the messages from your time in the group, '
                    'but you cannot send, call, or react.',
                fontSize: 13.sp,
                textColor: Colors.orange.shade900,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Banner shown when my own account was deleted: the chat becomes read-only.
class GroupMyAccountDeletedBanner extends StatelessWidget {
  const GroupMyAccountDeletedBanner({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: Colors.red.shade50,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(
              Icons.remove_circle_outline,
              color: Colors.red,
              size: 20,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: CustomText(
                text: 'Your account was deleted. You can only read your '
                    'previous chats — you cannot send messages or call.',
                fontSize: 13.sp,
                textColor: Colors.red.shade900,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
