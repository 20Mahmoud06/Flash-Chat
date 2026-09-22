import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../shared/widgets/custom_text.dart';

/// Inline warning banner (deleted-account / blocked-by contact).
class SenderProfileNoticeBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final Color color;
  final Color? textColor;

  const SenderProfileNoticeBanner({
    super.key,
    required this.icon,
    required this.text,
    required this.color,
    this.textColor,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
      padding: EdgeInsets.all(12.w),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12.r),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 20),
          SizedBox(width: 8.w),
          Expanded(
            child: CustomText(
              text: text,
              fontSize: 13.sp,
              textColor: textColor ?? color,
            ),
          ),
        ],
      ),
    );
  }
}
