import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_theme.dart';
import '../models/group_model.dart';
import '../../../shared/widgets/custom_text.dart';
import '../cubit/group_cubit.dart';

/// Red full-width action row used for "Leave Group" / "Delete Group".
class GroupDangerTile extends StatelessWidget {
  final String label;
  final IconData icon;
  final Color iconColor;
  final Color textColor;
  final VoidCallback onTap;

  const GroupDangerTile({
    super.key,
    required this.label,
    required this.icon,
    required this.iconColor,
    required this.textColor,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(icon, color: iconColor, size: 22),
                SizedBox(width: 10.w),
                CustomText(
                  text: label,
                  textColor: textColor,
                  fontWeight: FontWeight.bold,
                  fontSize: 15,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> confirmLeaveGroup(BuildContext context, GroupModel group) async {
  if (group.isDeleted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
      title: const CustomText(text: 'Leave Group', fontWeight: FontWeight.bold),
      content: const CustomText(
        text: 'You will no longer be able to send or receive messages in '
            'this group, but you can still read the messages from before '
            'you left.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const CustomText(text: 'Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            context.read<GroupCubit>().leaveGroup(group);
          },
          child: const CustomText(
              text: 'Leave',
              textColor: Colors.red,
              fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}

Future<void> confirmDeleteGroup(BuildContext context, GroupModel group) async {
  if (group.isDeleted) return;
  await showDialog<void>(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
      title:
          const CustomText(text: 'Delete Group', fontWeight: FontWeight.bold),
      content: const CustomText(
        text: 'Deleting this group makes it read-only for all members. '
            'Nobody can send messages or make calls anymore, but everyone '
            'can still read the conversation from before the deletion. '
            'This action cannot be undone.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(ctx).pop(),
          child: const CustomText(text: 'Cancel'),
        ),
        TextButton(
          onPressed: () {
            Navigator.of(ctx).pop();
            context.read<GroupCubit>().deleteGroup(group);
          },
          child: const CustomText(
              text: 'Delete',
              textColor: Colors.red,
              fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}