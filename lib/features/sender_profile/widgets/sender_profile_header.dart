import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../profile/models/user_model.dart';
import 'sender_profile_notice_banner.dart';
import 'sender_profile_presence_status.dart';

/// Avatar, display name, presence status and (when relevant) the deleted /
/// blocked-me notice banners at the top of the contact info screen.
class SenderProfileHeader extends StatelessWidget {
  final UserModel user;
  final String displayName;
  final bool blockedMe;

  const SenderProfileHeader({
    super.key,
    required this.user,
    required this.displayName,
    required this.blockedMe,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SizedBox(height: 40.h),
        CircleAvatar(
          radius: 60.r,
          backgroundColor: colors.avatarBackground,
          child: CustomText(
            text: user.isDeleted ? '❌' : user.avatarEmoji,
            fontSize: 60.sp,
          ),
        ),
        SizedBox(height: 20.h),
        CustomText(
          text: displayName,
          fontSize: 24.sp,
          fontWeight: FontWeight.bold,
        ),
        SizedBox(height: 6.h),
        SenderProfilePresenceStatus(user: user),
        SizedBox(height: 14.h),
        if (user.isDeleted)
          const SenderProfileNoticeBanner(
            icon: Icons.remove_circle_outline,
            text: 'This user has deleted their account. '
                'You cannot message or call them.',
            color: Colors.red,
          ),
        if (blockedMe)
          const SenderProfileNoticeBanner(
            icon: Icons.block,
            text: 'This user has blocked you. '
                'You cannot message or call them.',
            color: Colors.orange,
            textColor: AppColors.warningOrange,
          ),
      ],
    );
  }
}