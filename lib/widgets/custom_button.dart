import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

class CustomButton extends StatelessWidget {
  const CustomButton({
    super.key,
    this.onPressed,
    required this.buttonColor,
    required this.child,
  });

  final VoidCallback? onPressed;
  final Color buttonColor;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: onPressed,
      style: ElevatedButton.styleFrom(
        backgroundColor: buttonColor,
        disabledBackgroundColor: buttonColor.withOpacity(0.7),
        padding: EdgeInsets.symmetric(horizontal: 20.0.w),
        minimumSize: Size(double.infinity, 50.0.w),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(30.0.r),
        ),
        elevation: 5.0,
      ),
      child: child,
    );
  }
}
