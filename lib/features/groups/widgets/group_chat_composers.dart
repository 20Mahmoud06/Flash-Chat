import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// Bottom bar replacing the composer when my own account was deleted.
class GroupMyAccountDeletedComposer extends StatelessWidget {
  const GroupMyAccountDeletedComposer({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.3),
              spreadRadius: 2,
              blurRadius: 5),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.remove_circle_outline,
              color: colors.textWeak,
              size: 20,
            ),
            SizedBox(width: 8.w),
            Flexible(
              child: CustomText(
                text: 'Your account is deleted — you can only read messages',
                fontSize: 14.sp,
                textColor: colors.textSecondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom bar replacing the composer once the group has been deleted.
class GroupDeletedComposer extends StatelessWidget {
  const GroupDeletedComposer({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.3),
            spreadRadius: 2,
            blurRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: colors.textWeak, size: 20),
            SizedBox(width: 8.w),
            Flexible(
              child: CustomText(
                text: 'you can only read messages',
                fontSize: 14.sp,
                textColor: colors.textSecondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Bottom bar replacing the composer for removed/left members.
class GroupRemovedComposer extends StatelessWidget {
  const GroupRemovedComposer({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.3),
            spreadRadius: 2,
            blurRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, color: colors.textWeak, size: 20),
            SizedBox(width: 8.w),
            Flexible(
              child: CustomText(
                text: 'You can only read messages',
                fontSize: 14.sp,
                textColor: colors.textSecondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
