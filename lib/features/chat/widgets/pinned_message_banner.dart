import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/message_preview.dart';
import '../../../shared/widgets/custom_text.dart';

/// WhatsApp-style strip pinned above the message list showing the pinned
/// message preview, with an optional tap-to-jump and unpin action.
class PinnedMessageBanner extends StatelessWidget {
  final Map<String, dynamic> pin;
  final bool canUnpin;
  final VoidCallback? onTap;
  final VoidCallback? onUnpin;

  const PinnedMessageBanner({
    super.key,
    required this.pin,
    this.canUnpin = false,
    this.onTap,
    this.onUnpin,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Material(
      color: colors.surfaceMuted,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          child: Row(
            children: [
              Icon(Icons.push_pin, color: colors.textWeak, size: 18),
              SizedBox(width: 10.w),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CustomText(
                      text: 'Pinned',
                      fontSize: 11.sp,
                      fontWeight: FontWeight.bold,
                      textColor: colors.textSecondary,
                    ),
                    SizedBox(height: 1.h),
                    CustomText(
                      text: messagePreviewText(pin),
                      fontSize: 13.sp,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textColor: colors.textPrimary,
                    ),
                  ],
                ),
              ),
              if (canUnpin)
                IconButton(
                  tooltip: 'Unpin',
                  icon: Transform.rotate(
                    angle: 0.785,
                    child: Icon(
                      Icons.push_pin,
                      size: 18,
                      color: colors.textWeak,
                    ),
                  ),
                  onPressed: onUnpin,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
