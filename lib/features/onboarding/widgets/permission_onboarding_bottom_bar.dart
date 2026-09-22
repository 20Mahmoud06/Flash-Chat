import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/shared/widgets/custom_button.dart';

import 'permission_page.dart';

/// Bottom action bar: the primary "Allow / Done" button for the current step
/// plus a "Skip for now" link.
class PermissionOnboardingBottomBar extends StatelessWidget {
  const PermissionOnboardingBottomBar({
    super.key,
    required this.page,
    required this.isLast,
    required this.onSkip,
  });

  final PermissionPage page;
  final bool isLast;
  final VoidCallback onSkip;

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.fromLTRB(24.w, 12.h, 24.w, 16.h),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24.r)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Matches the app's CustomButton look (lightBlueAccent, white,
          // fully rounded).
          CustomButton(
            buttonColor: Colors.lightBlueAccent,
            onPressed: page.action,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                CustomText(
                  text: isLast ? 'Done' : 'Allow',
                  textColor: Colors.white,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.w600,
                ),
                SizedBox(width: 8.w),
                Icon(
                  isLast ? Icons.check_rounded : Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 20.w,
                ),
              ],
            ),
          ),
          SizedBox(height: 6.h),
          TextButton(
            onPressed: onSkip,
            child: CustomText(
              text: 'Skip for now',
              textColor: colors.textSecondary,
              fontSize: 14.sp,
            ),
          ),
        ],
      ),
    );
  }
}
