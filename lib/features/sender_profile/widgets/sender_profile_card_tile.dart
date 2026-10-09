import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// Shared Card>ListTile shell used by the nickname and block rows on the
/// contact-info screen.
class SenderProfileCardTile extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color iconBackground;
  final String title;
  final String subtitle;
  final Color? titleColor;
  final Color? subtitleColor;
  final FontWeight subtitleWeight;
  final Widget? trailing;
  final VoidCallback? onTap;

  const SenderProfileCardTile({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.iconBackground,
    required this.title,
    required this.subtitle,
    this.titleColor,
    this.subtitleColor,
    this.subtitleWeight = FontWeight.normal,
    this.trailing,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12.r),
        side: BorderSide(color: colors.divider),
      ),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: iconBackground,
          child: Icon(icon, color: iconColor),
        ),
        title: CustomText(
          text: title,
          fontSize: 16.sp,
          fontWeight: FontWeight.w600,
          textColor: titleColor ?? colors.textPrimary,
        ),
        subtitle: CustomText(
          text: subtitle,
          fontSize: 13.sp,
          textColor: subtitleColor ?? colors.textSecondary,
          fontWeight: subtitleWeight,
        ),
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
