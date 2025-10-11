import 'package:flutter/material.dart';
import 'custom_text.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class GoogleSigninButton extends StatelessWidget {
  final String text;
  final double fontSize;
  final bool isLoading;
  final void Function()? onPressed;

  const GoogleSigninButton({
    super.key,
    required this.text,
    this.fontSize = 18.0,
    this.isLoading = false,
    this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDarkMode = theme.brightness == Brightness.dark;

    return GestureDetector(
      onTap: isLoading ? null : onPressed,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(50.0.r),
          border: Border.all(
              color: isDarkMode ? Colors.grey.shade700 : Colors.grey.shade300,
              width: 1.5.w),
        ),
        width: double.infinity,
        height: 50.h,
        child: Center(
          child: isLoading
              ? SizedBox(
            height: 25.h,
            width: 25.w,
            child: const CircularProgressIndicator(
              strokeWidth: 3.0,
              color: Colors.grey,
            ),
          )
              : Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Image.asset(
                'assets/google.png',
                width: 30.w,
                height: 30.h,
              ),
              SizedBox(width: 10.0.w),
              CustomText(
                text: text,
                fontSize: fontSize,
              ),
            ],
          ),
        ),
      ),
    );
  }
}