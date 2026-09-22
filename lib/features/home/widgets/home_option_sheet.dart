import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// Shared chrome of the long-press option sheets on the home screen (Groups
/// tab and Chats tab): translucent rounded sheet with a drag handle, a bold
/// title and the option rows.
class HomeOptionSheet extends StatelessWidget {
  final String title;
  final List<Widget> children;

  const HomeOptionSheet({
    super.key,
    required this.title,
    required this.children,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      margin: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(20.r),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -3),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              margin: EdgeInsets.only(top: 12.h),
              width: 40.w,
              height: 4.h,
              decoration: BoxDecoration(
                color: colors.surfaceDim,
                borderRadius: BorderRadius.circular(2.r),
              ),
            ),
            SizedBox(height: 20.h),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 20.w),
              child: CustomText(
                text: title,
                fontSize: 18.sp,
                fontWeight: FontWeight.bold,
                textColor: colors.textPrimary,
              ),
            ),
            SizedBox(height: 16.h),
            ...children,
            SizedBox(height: 12.h),
          ],
        ),
      ),
    );
  }
}

/// The hairline separator between the option rows of a [HomeOptionSheet],
/// aligned to the icon chip (70) + padding (16) + 16 right padding.
class HomeSheetDivider extends StatelessWidget {
  final double indent;

  const HomeSheetDivider({super.key, this.indent = 70});

  @override
  Widget build(BuildContext context) {
    return Divider(height: 1.h, thickness: 1, indent: indent.w, endIndent: 20.w);
  }
}