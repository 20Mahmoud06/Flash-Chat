import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class ResendSection extends StatelessWidget {
  final int resendCount;
  final int maxResends;
  final bool isResending;
  final int countdown;
  final bool canResend;
  final VoidCallback? onResend;

  const ResendSection({
    super.key,
    required this.resendCount,
    required this.maxResends,
    required this.isResending,
    required this.countdown,
    required this.canResend,
    this.onResend,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);

    if (resendCount >= maxResends) {
      return CustomText(
        text: 'Too many resend attempts. Please try again later.',
        textColor: colors.textWeak,
        fontSize: 14.sp,
        textAlign: TextAlign.center,
      );
    }

    return Column(
      children: [
        CustomText(
          text: "Didn't receive the code?",
          textColor: colors.textSecondary,
          fontSize: 14.sp,
        ),
        SizedBox(height: 4.h),
        if (isResending)
          const SizedBox(
            height: 20,
            width: 20,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.lightBlueAccent,
            ),
          )
        else if (canResend)
          TextButton(
            onPressed: onResend,
            child: CustomText(
              text: 'Resend code',
              textColor: Colors.lightBlueAccent,
              fontSize: 15.sp,
              fontWeight: FontWeight.bold,
            ),
          )
        else
          CustomText(
            text: 'Resend code in ${countdown}s',
            textColor: colors.textWeak,
            fontSize: 14.sp,
          ),
      ],
    );
  }
}
