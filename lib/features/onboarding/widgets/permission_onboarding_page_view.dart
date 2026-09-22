import 'package:animate_do/animate_do.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';

import 'permission_page.dart';

/// Content of a single permission step: large tinted icon, title and subtitle.
class PermissionOnboardingPageView extends StatelessWidget {
  const PermissionOnboardingPageView({super.key, required this.page});

  final PermissionPage page;

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 28.w),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Large icon in a soft tinted circle (matches avatar tint style).
          ZoomIn(
            duration: const Duration(milliseconds: 400),
            child: Container(
              width: 132.w,
              height: 132.h,
              decoration: BoxDecoration(
                color: page.iconBackground,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: page.iconColor.withValues(alpha: 0.18),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Icon(page.icon, color: page.iconColor, size: 62.w),
            ),
          ),
          SizedBox(height: 30.h),
          FadeInUp(
            duration: const Duration(milliseconds: 400),
            delay: const Duration(milliseconds: 120),
            child: CustomText(
              text: page.title,
              textColor: colors.textPrimary,
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              textAlign: TextAlign.center,
            ),
          ),
          SizedBox(height: 12.h),
          FadeInUp(
            duration: const Duration(milliseconds: 400),
            delay: const Duration(milliseconds: 200),
            child: CustomText(
              text: page.subtitle,
              textColor: colors.textSecondary,
              fontSize: 14.sp,
              height: 1.5,
              textAlign: TextAlign.center,
            ),
          ),
        ],
      ),
    );
  }
}
