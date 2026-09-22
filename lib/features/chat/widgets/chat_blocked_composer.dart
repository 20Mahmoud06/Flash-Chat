import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// Replaces the composer when the chat is blocked or one of the two accounts
/// is deleted. Text/icon adapts to which restriction applies.
class ChatBlockedComposer extends StatelessWidget {
  final bool myAccountDeleted;
  final bool accountDeleted;
  final bool iBlockedContact;

  const ChatBlockedComposer({
    super.key,
    required this.myAccountDeleted,
    required this.accountDeleted,
    required this.iBlockedContact,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.3),
              spreadRadius: 2,
              blurRadius: 5),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              myAccountDeleted
                  ? Icons.remove_circle_outline
                  : (accountDeleted ? Icons.person_remove : Icons.lock_outline),
              color: colors.textWeak,
              size: 20,
            ),
            SizedBox(width: 8.w),
            Flexible(
              child: CustomText(
                text: myAccountDeleted
                    ? 'Your account is deleted — you can only read messages'
                    : accountDeleted
                        ? 'This user has deleted their account'
                        : iBlockedContact
                            ? 'You blocked this user'
                            : 'You cannot send messages to this user',
                fontSize: 14.sp,
                textColor: colors.textSecondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
