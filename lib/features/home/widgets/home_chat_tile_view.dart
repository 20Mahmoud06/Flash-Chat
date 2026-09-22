import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// The visual chat-row itself (avatar, title + status pills, message preview
/// and unread badge) inside an [AnimatedContainer] that highlights brand-new
/// and unread chats. Pure UI: all values are computed by the owning
/// `HomeChatListTile` state (per-row live stream, preview / unread logic).
class HomeChatTileView extends StatelessWidget {
  final String avatar;
  final String title;
  final bool isPinned;
  final bool isDeleted;
  final bool isBlocked;
  final bool isNewHighlight;
  final bool isUnread;
  final int badgeCount;
  final String prefix;
  final String lastMessage;
  final String time;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const HomeChatTileView({
    super.key,
    required this.avatar,
    required this.title,
    required this.isPinned,
    required this.isDeleted,
    required this.isBlocked,
    required this.isNewHighlight,
    required this.isUnread,
    required this.badgeCount,
    required this.prefix,
    required this.lastMessage,
    required this.time,
    required this.onTap,
    this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 700),
      curve: Curves.easeOut,
      margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
      padding: EdgeInsets.symmetric(vertical: 8.h),
      decoration: BoxDecoration(
        color: isNewHighlight
            ? Colors.lightBlue.withValues(alpha: 0.22)
            : (isUnread ? colors.avatarBackground : colors.surface),
        borderRadius: BorderRadius.circular(16.r),
        border: Border.all(
          color: isNewHighlight || isUnread
              ? Colors.lightBlueAccent
              : Colors.transparent,
          width: 2.5,
        ),
        boxShadow: [
          BoxShadow(
            color: isNewHighlight
                ? Colors.lightBlueAccent.withValues(alpha: 0.35)
                : (isUnread
                    ? Colors.lightBlueAccent.withValues(alpha: 0.25)
                    : Colors.black.withValues(alpha: 0.08)),
            blurRadius: isNewHighlight ? 16 : 10,
            offset: const Offset(0, 3),
          ),
        ],
      ),
      child: ListTile(
        contentPadding:
            EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
        leading: Container(
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
              color: Colors.lightBlueAccent.withValues(alpha: 0.65),
              width: 2.w,
            ),
            boxShadow: [
              BoxShadow(
                color: Colors.lightBlueAccent.withValues(alpha: 0.35),
                blurRadius: 8,
                offset: const Offset(0, 2),
              ),
            ],
          ),
          padding: const EdgeInsets.all(1),
          child: CircleAvatar(
            radius: 26.r,
            backgroundColor: colors.avatarBackground,
            child: CustomText(text: avatar, fontSize: 26.sp),
          ),
        ),
        title: Row(
          children: [
            if (isPinned) ...[
              const Icon(Icons.push_pin,
                  size: 14, color: Colors.lightBlueAccent),
              SizedBox(width: 4.w),
            ],
            Flexible(
              child: CustomText(
                text: title,
                fontWeight: FontWeight.bold,
                fontSize: 16.sp,
                textColor:
                    isDeleted ? colors.textSecondary : colors.textPrimary,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (isNewHighlight) ...[
              SizedBox(width: 8.w),
              AnimatedOpacity(
                duration: const Duration(milliseconds: 500),
                opacity: isNewHighlight ? 1 : 0,
                child: Container(
                  padding:
                      EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                  decoration: BoxDecoration(
                    color: Colors.lightBlueAccent.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(8.r),
                  ),
                  child: CustomText(
                    text: 'NEW',
                    fontSize: 11.sp,
                    fontWeight: FontWeight.bold,
                    textColor: Colors.lightBlueAccent,
                  ),
                ),
              ),
            ],
            if (isDeleted) ...[
              SizedBox(width: 8.w),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
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
            ],
            if (isBlocked && !isDeleted) ...[
              SizedBox(width: 8.w),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
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
            ],
          ],
        ),
        subtitle: Padding(
          padding: EdgeInsets.only(top: 4.h),
          child: Row(
            children: [
              if (prefix.isNotEmpty)
                CustomText(
                  text: prefix,
                  fontWeight: FontWeight.bold,
                  textColor: Colors.lightBlueAccent,
                  fontSize: 14.sp,
                ),
              Expanded(
                child: CustomText(
                  text: lastMessage,
                  textColor: isDeleted
                      ? colors.textWeak
                      : (isUnread ? colors.textPrimary : colors.textSecondary),
                  fontSize: 14.sp,
                  fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        trailing: Column(
          mainAxisSize: MainAxisSize.min,
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            CustomText(
              text: time,
              textColor:
                  isUnread ? Colors.lightBlueAccent : colors.textSecondary,
              fontSize: 12.sp,
              fontWeight: isUnread ? FontWeight.bold : FontWeight.normal,
            ),
            if (isUnread && badgeCount > 0) ...[
              SizedBox(height: 6.h),
              Container(
                padding:
                    EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                constraints:
                    BoxConstraints(minWidth: 22.w, minHeight: 22.h),
                decoration: BoxDecoration(
                  gradient: const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [
                      Colors.lightBlueAccent,
                      AppColors.primaryDark,
                    ],
                  ),
                  borderRadius: BorderRadius.circular(12.r),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.lightBlueAccent.withValues(alpha: 0.4),
                      blurRadius: 6,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                child: CustomText(
                  text: badgeCount > 9 ? '9+' : '$badgeCount',
                  textColor: Colors.white,
                  fontSize: 11.sp,
                  fontWeight: FontWeight.bold,
                  textAlign: TextAlign.center,
                ),
              ),
            ],
          ],
        ),
        onTap: onTap,
        onLongPress: onLongPress,
      ),
    );
  }
}