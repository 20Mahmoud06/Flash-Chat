import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// Renders the banner above the chat body when the chat is blocked or one of
/// the two accounts is deleted. Which variant shows depends on the flags:
/// my account deleted > contact's account deleted > blocked.
class ChatBlockedBanner extends StatelessWidget {
  final bool myAccountDeleted;
  final bool accountDeleted;
  final bool iBlockedContact;
  final String chatName;
  final VoidCallback onUnblock;

  const ChatBlockedBanner({
    super.key,
    required this.myAccountDeleted,
    required this.accountDeleted,
    required this.iBlockedContact,
    required this.chatName,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    if (myAccountDeleted) return const _MyAccountDeletedBanner();
    if (accountDeleted) return const _DeletedAccountBanner();
    return _BlockedBanner(
      iBlockedContact: iBlockedContact,
      chatName: chatName,
      onUnblock: onUnblock,
    );
  }
}

class _MyAccountDeletedBanner extends StatelessWidget {
  const _MyAccountDeletedBanner();

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

class _DeletedAccountBanner extends StatelessWidget {
  const _DeletedAccountBanner();

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: colors.tile,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(
              Icons.person_remove,
              color: colors.textSecondary,
              size: 20,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: CustomText(
                text:
                    'This user has deleted their account. You cannot send messages or call them.',
                fontSize: 13.sp,
                textColor: colors.textSecondary,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _BlockedBanner extends StatelessWidget {
  final bool iBlockedContact;
  final String chatName;
  final VoidCallback onUnblock;

  const _BlockedBanner({
    required this.iBlockedContact,
    required this.chatName,
    required this.onUnblock,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: iBlockedContact ? Colors.red.shade50 : Colors.orange.shade50,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(
              Icons.block,
              color: iBlockedContact
                  ? Colors.red.shade400
                  : Colors.orange.shade700,
              size: 20,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: CustomText(
                text: iBlockedContact
                    ? 'You blocked $chatName. You cannot send messages to this user.'
                    : 'You cannot send messages to $chatName.',
                fontSize: 13.sp,
                textColor: iBlockedContact
                    ? Colors.red.shade700
                    : Colors.orange.shade900,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (iBlockedContact)
              TextButton(
                onPressed: onUnblock,
                child: CustomText(
                  text: 'Unblock',
                  fontSize: 13.sp,
                  fontWeight: FontWeight.bold,
                  textColor: Colors.red.shade400,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
