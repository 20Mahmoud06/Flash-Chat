import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class OtpVerificationHeader extends StatelessWidget {
  const OtpVerificationHeader({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Column(
      children: [
        SizedBox(height: 24.h),
        Container(
          width: 96.w,
          height: 96.w,
          decoration: BoxDecoration(
            color: colors.avatarBackground,
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.sms_outlined,
            size: 44.w,
            color: Colors.lightBlueAccent,
          ),
        ),
        SizedBox(height: 24.h),
        CustomText(
          text: 'Enter the 6-digit code',
          textColor: colors.textPrimary,
          fontSize: 22.sp,
          fontWeight: FontWeight.bold,
        ),
        SizedBox(height: 8.h),
        CustomText(
          text:
              'Please check your email\na verification code has been sent to you',
          textAlign: TextAlign.center,
          textColor: colors.textSecondary,
          fontSize: 15.sp,
        ),
        SizedBox(height: 32.h),
      ],
    );
  }
}
