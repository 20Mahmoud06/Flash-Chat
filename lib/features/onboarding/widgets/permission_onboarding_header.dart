import 'package:animate_do/animate_do.dart';
import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Gradient hero header with the brand row and welcome copy.
class PermissionOnboardingHeader extends StatelessWidget {
  const PermissionOnboardingHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.fromLTRB(24.w, 20.h, 24.w, 28.h),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Colors.lightBlueAccent,
            AppColors.skySoft,
          ],
        ),
        borderRadius: BorderRadius.only(
          bottomLeft: Radius.circular(28.r),
          bottomRight: Radius.circular(28.r),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Brand row: logo + wordmark (matches Welcome screen identity).
          Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(14.r),
                child: Image.asset(
                  'assets/logo.png',
                  width: 44.w,
                  height: 44.h,
                  fit: BoxFit.cover,
                ),
              ),
              SizedBox(width: 12.w),
              CustomText(
                text: 'Flash Chat',
                textColor: Colors.white,
                fontSize: 24.sp,
                fontWeight: FontWeight.w900,
              ),
            ],
          ),
          SizedBox(height: 22.h),
          FadeInDown(
            duration: const Duration(milliseconds: 450),
            child: CustomText(
              text: 'Welcome!',
              textColor: Colors.white,
              fontSize: 26.sp,
              fontWeight: FontWeight.w800,
            ),
          ),
          SizedBox(height: 6.h),
          FadeInDown(
            duration: const Duration(milliseconds: 450),
            delay: const Duration(milliseconds: 100),
            child: CustomText(
              text: 'A couple of quick settings\nto get the best experience.',
              textColor: Colors.white.withValues(alpha: 0.92),
              fontSize: 14.sp,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}
