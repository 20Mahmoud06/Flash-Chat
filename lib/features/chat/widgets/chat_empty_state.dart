import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// Empty-chat placeholder for a blocked/deleted chat: explains why there is
/// nothing to send, matching the banner + composer above.
class ChatEmptyState extends StatelessWidget {
  final bool myAccountDeleted;
  final bool accountDeleted;
  final bool isBlockedChat;
  final bool iBlockedContact;
  final String chatName;

  const ChatEmptyState({
    super.key,
    required this.myAccountDeleted,
    required this.accountDeleted,
    required this.isBlockedChat,
    required this.iBlockedContact,
    required this.chatName,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);

    if (myAccountDeleted) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.remove_circle_outline,
              size: 56,
              color: Colors.red,
            ),
            SizedBox(height: 12.h),
            CustomText(
              text: 'Your account was deleted.',
              textAlign: TextAlign.center,
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              textColor: colors.textSecondary,
            ),
            SizedBox(height: 8.h),
            CustomText(
              text: 'You can only read your previous chats.',
              textAlign: TextAlign.center,
              fontSize: 14.sp,
              textColor: colors.textWeak,
            ),
          ],
        ),
      );
    }

    if (accountDeleted) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.person_remove,
              size: 56,
              color: colors.textWeak,
            ),
            SizedBox(height: 12.h),
            CustomText(
              text: 'This user has deleted their account.',
              textAlign: TextAlign.center,
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              textColor: colors.textSecondary,
            ),
            SizedBox(height: 8.h),
            CustomText(
              text: 'You cannot send messages or call them.',
              textAlign: TextAlign.center,
              fontSize: 14.sp,
              textColor: colors.textWeak,
            ),
          ],
        ),
      );
    }

    if (isBlockedChat) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.block,
              size: 56,
              color: iBlockedContact
                  ? Colors.red.shade200
                  : Colors.orange.shade200,
            ),
            SizedBox(height: 12.h),
            CustomText(
              text: iBlockedContact
                  ? 'You blocked $chatName. Unblock to start chatting again.'
                  : '$chatName has blocked you.',
              textAlign: TextAlign.center,
              fontSize: 15.sp,
              textColor: colors.textSecondary,
            ),
          ],
        ),
      );
    }

    return const Center(child: CustomText(text: "Say hello! 👋"));
  }
}
