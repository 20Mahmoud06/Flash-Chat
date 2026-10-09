import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../shared/widgets/custom_text.dart';

/// A single row on the ContactsScreen (or the add-group-members picker):
/// avatar with selection check, name (+ my nickname / (You) / Deleted /
/// Blocked chips), status subtitle, and tap/long-press handlers.
class ContactsListTile extends StatelessWidget {
  const ContactsListTile({
    super.key,
    required this.user,
    required this.isCurrentUser,
    required this.isSelected,
    required this.isBlocked,
    required this.isDeleted,
    required this.isMine,
    required this.myNicknames,
    required this.onTap,
    required this.onLongPress,
  });

  final UserModel user;
  final bool isCurrentUser;
  final bool isSelected;
  final bool isBlocked;
  final bool isDeleted;

  /// Whether this list is headed by my own model (my nickname map is only
  /// read from it, so it must belong to the current user).
  final bool isMine;
  final Map<String, String> myNicknames;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final myNickname = isMine && !isCurrentUser ? myNicknames[user.uid] : null;

    return ListTile(
      contentPadding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
      leading: CircleAvatar(
        radius: 28.r,
        backgroundColor: isSelected
            ? Colors.lightBlueAccent.withValues(alpha: 0.3)
            : colors.avatarBackground,
        child: Stack(
          alignment: Alignment.center,
          children: [
            CustomText(
              text: isDeleted
                  ? '❌'
                  : (user.avatarEmoji.isNotEmpty ? user.avatarEmoji : '?'),
              fontSize: 24.sp,
            ),
            if (isSelected)
              const Icon(Icons.check_circle, color: Colors.white),
          ],
        ),
      ),
      title: Row(
        children: [
          Flexible(
            child: CustomText(
              text: '${user.firstName} ${user.lastName}',
              fontWeight: FontWeight.w600,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (myNickname != null)
            Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: CustomText(
                    text: '($myNickname)',
                    textColor: colors.textSecondary,
                    fontWeight: FontWeight.normal)),
          if (isCurrentUser)
            Padding(
                padding: EdgeInsets.only(left: 8.w),
                child: CustomText(
                    text: '(You)',
                    textColor: colors.textSecondary,
                    fontWeight: FontWeight.normal)),
          if (isDeleted)
            Padding(
              padding: EdgeInsets.only(left: 8.w),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: colors.tile,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: CustomText(
                  text: 'Deleted',
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                  textColor: colors.textSecondary,
                ),
              ),
            ),
          if (isBlocked && !isDeleted)
            Padding(
              padding: EdgeInsets.only(left: 8.w),
              child: Container(
                padding: EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  borderRadius: BorderRadius.circular(8.r),
                ),
                child: CustomText(
                  text: 'Blocked',
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                  textColor: Colors.red.shade400,
                ),
              ),
            ),
        ],
      ),
      subtitle: CustomText(
          text: isCurrentUser
              ? "Message yourself"
              : (isDeleted
                  ? 'This user has deleted their account'
                  : (isBlocked
                      ? 'Blocked - you cannot message or call'
                      : user.phoneNumber)),
          textColor: isDeleted
              ? colors.textSecondary
              : (isBlocked ? Colors.red.shade400 : null)),
      onTap: onTap,
      onLongPress: onLongPress,
      tileColor: isSelected ? colors.avatarBackground : null,
    );
  }
}