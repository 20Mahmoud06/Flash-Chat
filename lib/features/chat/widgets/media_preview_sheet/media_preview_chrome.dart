import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_text.dart';
import 'media_circle_button.dart';

/// The slim draggable grip at the very top of the sheet.
class MediaPreviewDragHandle extends StatelessWidget {
  const MediaPreviewDragHandle({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.only(top: 10.h, bottom: 6.h),
      child: Container(
        width: 40.w,
        height: 4,
        decoration: BoxDecoration(
          color: colors.surfaceDim,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }
}

/// Top bar: back button + "Photo/Video Preview" title with a contextual
/// subtitle (ready to send / selection counter).
class MediaPreviewHeader extends StatelessWidget {
  final bool isVideo;
  final int mediaCount;
  final int currentIndex;
  final VoidCallback onBack;

  const MediaPreviewHeader({
    super.key,
    required this.isVideo,
    required this.mediaCount,
    required this.currentIndex,
    required this.onBack,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 12.w),
      child: Row(
        children: [
          MediaCircleButton(
            size: 34,
            icon: Icons.arrow_back_rounded,
            iconColor: colors.textPrimary,
            backgroundColor: colors.inputFill,
            onTap: onBack,
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CustomText(
                  text: isVideo ? 'Video Preview' : 'Photo Preview',
                  textColor: colors.textPrimary,
                  fontSize: 16.sp,
                  fontWeight: FontWeight.bold,
                ),
                SizedBox(height: 2.h),
                CustomText(
                  text: isVideo
                      ? 'Ready to send'
                      : mediaCount > 1
                          ? '${currentIndex + 1} of $mediaCount selected'
                          : '1 photo, ready to send',
                  textColor: colors.textSecondary,
                  fontSize: 12.sp,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Chip shown only for multi-photo selections, letting the user open the
/// gallery to add more photos (capped at [maxCount] total).
class MediaPreviewAddMoreButton extends StatelessWidget {
  final int mediaCount;
  final int maxCount;
  final VoidCallback onTap;

  const MediaPreviewAddMoreButton({
    super.key,
    required this.mediaCount,
    required this.maxCount,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 8.h, 12.w, 0),
      child: GestureDetector(
        onTap: onTap,
        child: Container(
          padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 8.h),
          decoration: BoxDecoration(
            color: colors.surfaceMuted,
            borderRadius: BorderRadius.circular(20.r),
            border: Border.all(color: colors.divider),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(
                Icons.add_photo_alternate_outlined,
                color: AppColors.primaryDark,
                size: 18,
              ),
              SizedBox(width: 6.w),
              CustomText(
                text: 'Add More Photos',
                textColor: AppColors.primaryDark,
                fontSize: 13.sp,
                fontWeight: FontWeight.w600,
              ),
              SizedBox(width: 6.w),
              CustomText(
                text: '$mediaCount/$maxCount',
                textColor: colors.textWeak,
                fontSize: 12.sp,
              ),
            ],
          ),
        ),
      ),
    );
  }
}