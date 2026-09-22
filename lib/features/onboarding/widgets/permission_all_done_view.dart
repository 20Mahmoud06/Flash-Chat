import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/shared/widgets/custom_button.dart';

/// Shown when every permission is already granted — the onboarding has
/// nothing to ask for, so it just celebrates and lets the user continue.
class PermissionAllDoneView extends StatelessWidget {
  const PermissionAllDoneView({super.key, required this.onDone});

  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Center(
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 32.w),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              width: 120.w,
              height: 120.h,
              decoration: const BoxDecoration(
                color: AppColors.mint,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.check_circle_rounded,
                color: Colors.green,
                size: 64,
              ),
            ),
            SizedBox(height: 24.h),
            CustomText(
              text: 'You\'re all set!',
              textColor: colors.textPrimary,
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
            ),
            SizedBox(height: 8.h),
            CustomText(
              text:
                  'Everything you need is already enabled.\nEnjoy Flash Chat!',
              textColor: colors.textSecondary,
              fontSize: 14.sp,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 28.h),
            CustomButton(
              buttonColor: Colors.lightBlueAccent,
              onPressed: onDone,
              child: CustomText(
                text: 'Let\'s go',
                textColor: Colors.white,
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
