import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';

/// Informational dialog shown when the user denies notifications during
/// onboarding, so they know where to enable them later.
Future<void> showPermissionDeniedDialog(BuildContext context) async {
  final colors = FcAppColors.of(context);
  await showDialog(
    context: context,
    barrierDismissible: true,
    builder: (ctx) => AlertDialog(
      backgroundColor: colors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20.r),
      ),
      contentPadding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 72.w,
            height: 72.h,
            decoration: BoxDecoration(
              color: Colors.orange.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.notifications_off_rounded,
              color: Colors.orange,
              size: 38.w,
            ),
          ),
          SizedBox(height: 18.h),
          CustomText(
            text: 'You\'ll miss out!',
            textColor: colors.textPrimary,
            fontSize: 20.sp,
            fontWeight: FontWeight.bold,
          ),
          SizedBox(height: 10.h),
          CustomText(
            text: 'Without notifications you won\'t know when someone messages '
                'or calls you. You can turn them on later from:\n\n'
                '  \u2022  Your phone\'s Settings > Flash Chat\n'
                '  \u2022  Profile > Notifications',
            textColor: colors.textSecondary,
            fontSize: 14.sp,
            height: 1.5,
            textAlign: TextAlign.left,
          ),
          SizedBox(height: 20.h),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () => Navigator.of(ctx).pop(),
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.lightBlueAccent,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                ),
                padding: EdgeInsets.symmetric(vertical: 12.h),
              ),
              child: CustomText(
                text: 'Got it',
                fontSize: 15.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    ),
  );
}
