import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';

/// Caption input row pinned to the bottom of the sheet, plus the round
/// send/processing button.
class MediaPreviewCaptionBar extends StatelessWidget {
  final TextEditingController captionController;
  final bool isSending;
  final VoidCallback onSend;

  const MediaPreviewCaptionBar({
    super.key,
    required this.captionController,
    required this.isSending,
    required this.onSend,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12.w, 10.h, 12.w, 10.h),
      child: Container(
        decoration: BoxDecoration(
          color: colors.surfaceMuted,
          borderRadius: BorderRadius.circular(26.r),
          border: Border.all(color: colors.divider),
        ),
        padding: EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: captionController,
                minLines: 1,
                maxLines: 3,
                style: TextStyle(
                  color: colors.textPrimary,
                  fontSize: 15,
                ),
                cursorColor: AppColors.primaryDark,
                decoration: InputDecoration(
                  hintText: 'Add a caption...',
                  hintStyle: TextStyle(color: colors.textWeak),
                  border: InputBorder.none,
                  isCollapsed: true,
                  contentPadding: EdgeInsets.symmetric(vertical: 12.h),
                ),
                onSubmitted: (_) => onSend(),
              ),
            ),
            const SizedBox(width: 8),
            _MediaPreviewSendButton(isSending: isSending, onTap: onSend),
          ],
        ),
      ),
    );
  }
}

/// Round send button showing either a spinner or the up-arrow icon.
class _MediaPreviewSendButton extends StatelessWidget {
  final bool isSending;
  final VoidCallback onTap;

  const _MediaPreviewSendButton({
    required this.isSending,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            colors: [AppColors.sky, AppColors.primaryDark],
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
          ),
          boxShadow: [
            BoxShadow(
              color: AppColors.primaryDark.withValues(alpha: 0.35),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        child: isSending
            ? const Padding(
                padding: EdgeInsets.all(11),
                child: CircularProgressIndicator(
                  strokeWidth: 2.5,
                  color: Colors.white,
                ),
              )
            : const Icon(
                Icons.arrow_upward_rounded,
                color: Colors.white,
                size: 24,
              ),
      ),
    );
  }
}