import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// Builds the chat AppBar (avatar + name + presence subtitle on the left,
/// search / voice / video actions on the right). Call buttons are only
/// rendered when [showCallButtons] is true.
AppBar buildChatAppBar({
  required BuildContext context,
  required String chatName,
  required String chatAvatar,
  required Widget subtitle,
  required VoidCallback? onTitleTap,
  required bool showCallButtons,
  required VoidCallback onSearch,
  required VoidCallback onVoiceCall,
  required VoidCallback onVideoCall,
}) {
  final colors = FcAppColors.of(context);

  return AppBar(
    elevation: 1,
    backgroundColor: Colors.lightBlueAccent,
    centerTitle: false,
    titleSpacing: 0,
    iconTheme: const IconThemeData(color: Colors.white),
    title: InkWell(
      onTap: onTitleTap,
      borderRadius: BorderRadius.circular(24.r),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 4.h),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            CircleAvatar(
              radius: 19.r,
              backgroundColor: colors.avatarBackground,
              child: CustomText(text: chatAvatar, fontSize: 16.sp),
            ),
            SizedBox(width: 8.w),
            Flexible(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    text: chatName,
                    textColor: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16.sp,
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  subtitle,
                ],
              ),
            ),
          ],
        ),
      ),
    ),
    actionsPadding: EdgeInsets.only(right: 6.w),
    actions: [
      IconButton(
        icon: const Icon(Icons.search, color: Colors.white, size: 22),
        tooltip: 'Search in chat',
        visualDensity: VisualDensity.compact,
        onPressed: onSearch,
      ),
      if (showCallButtons) ...[
        IconButton(
          icon: const Icon(Icons.call, color: Colors.white, size: 22),
          tooltip: 'Voice Call',
          visualDensity: VisualDensity.compact,
          onPressed: onVoiceCall,
        ),
        IconButton(
          icon: const Icon(Icons.videocam, color: Colors.white, size: 22),
          tooltip: 'Video Call',
          visualDensity: VisualDensity.compact,
          onPressed: onVideoCall,
        ),
      ],
    ],
  );
}
