import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transition.dart';
import '../models/group_model.dart';
import '../../profile/models/user_model.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../chat/screens/chat_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../cubit/group_cubit.dart';

/// Member list with role badges and admin management (promote/demote/remove).
class GroupMembersSection extends StatelessWidget {
  final GroupModel group;
  final List<UserModel> members;
  final bool isLoading;
  final ValueChanged<GroupModel> onGroupChanged;

  const GroupMembersSection({
    super.key,
    required this.group,
    required this.members,
    required this.isLoading,
    required this.onGroupChanged,
  });

  void _showRemoveMemberDialog(BuildContext context, UserModel member) {
    if (group.isDeleted) return;
    final isAdmin = group.adminUids.contains(member.uid);

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: CustomText(text: 'Remove ${member.firstName}?'),
        content: CustomText(
          text: isAdmin
              ? 'This member is an admin. Removing them will also remove their admin privileges.'
              : 'This member will no longer be able to see or send messages in this group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const CustomText(text: 'Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              context.read<GroupCubit>().removeMemberFromGroup(
                    group: group,
                    memberUidToRemove: member.uid,
                  );
            },
            child: const CustomText(text: 'Remove', textColor: Colors.red),
          ),
        ],
      ),
    );
  }

  void _showPromoteDialog(BuildContext context, UserModel member) {
    if (group.isDeleted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: CustomText(text: 'Promote ${member.firstName}?'),
        content: const CustomText(
          text:
              'This member will be able to add and remove members and change group settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const CustomText(text: 'Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final originalGroup = group;
              // Update the badge in place right away so the UI reflects the
              // change immediately instead of waiting for a full reload.
              onGroupChanged(
                group.copyWith(
                  adminUids: [...group.adminUids, member.uid],
                ),
              );
              context.read<GroupCubit>().promoteMemberToAdmin(
                    group: originalGroup,
                    memberUidToPromote: member.uid,
                  );
            },
            child: const CustomText(text: 'Promote'),
          ),
        ],
      ),
    );
  }

  void _showDemoteDialog(BuildContext context, UserModel member) {
    if (group.isDeleted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: CustomText(text: 'Demote ${member.firstName}?'),
        content: const CustomText(
          text: 'This member will no longer be able to manage the group.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const CustomText(text: 'Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final originalGroup = group;
              // Update the badge in place right away so the UI reflects the
              // change immediately instead of waiting for a full reload.
              onGroupChanged(
                group.copyWith(
                  adminUids: group.adminUids
                      .where((uid) => uid != member.uid)
                      .toList(),
                ),
              );
              context.read<GroupCubit>().demoteAdminToMember(
                    group: originalGroup,
                    adminUidToDemote: member.uid,
                  );
            },
            child: const CustomText(text: 'Demote'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.lightBlueAccent),
      );
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final viewerIsAdmin = group.adminUids.contains(currentUid) ||
        (group.adminUids.isEmpty && group.createdBy == currentUid);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        final isCreator = group.createdBy == member.uid;
        final isAdmin = group.adminUids.contains(member.uid);
        final isSelf = member.uid == currentUid;

        return Card(
          margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: colors.tile,
              child: CustomText(text: member.avatarEmoji, fontSize: 20.sp),
            ),
            title: CustomText(text: '${member.firstName} ${member.lastName}'),
            subtitle: CustomText(text: member.phoneNumber),
            trailing: _buildMemberTrailingWidget(
              member,
              isAdmin: isAdmin,
              isCreator: isCreator,
              isSelf: isSelf,
              viewerIsAdmin: viewerIsAdmin,
            ),
            onTap: () {
              if (isSelf) {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const ProfileScreen(),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        ChatScreen(contact: member),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              }
            },
          ),
        );
      },
    );
  }

  Widget _creatorBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: const CustomText(
        text: 'Creator',
        textColor: AppColors.adminGold,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    );
  }

  Widget? _buildMemberTrailingWidget(
    UserModel member, {
    required bool isAdmin,
    required bool isCreator,
    required bool isSelf,
    required bool viewerIsAdmin,
  }) {
    if (isCreator) {
      return _creatorBadge();
    }

    // A deleted group is an archive: show role badges only. All management
    // actions (promote/demote/remove) are locked for everyone, including the
    // creator — who is already covered by the creator badge above.
    if (group.isDeleted) {
      if (isAdmin) return _roleBadge('Admin', Colors.green);
      return null;
    }

    if (viewerIsAdmin && !isSelf) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAdmin) ...[
            _roleBadge('Admin', Colors.green),
            _managementMenu(member, isAdmin: true),
          ] else
            _managementMenu(member, isAdmin: false),
        ],
      );
    }

    if (isAdmin) return _roleBadge('Admin', Colors.green);
    return null;
  }

  Widget _roleBadge(String label, Color color) {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: CustomText(
        text: label,
        textColor: color,
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    );
  }

  Widget _managementMenu(UserModel member, {required bool isAdmin}) {
    return Builder(
      builder: (context) {
        return PopupMenuButton<String>(
          icon: Icon(Icons.more_vert,
              color: FcAppColors.of(context).textSecondary),
          onSelected: (value) {
            if (value == 'promote') {
              _showPromoteDialog(context, member);
            } else if (value == 'demote') {
              _showDemoteDialog(context, member);
            } else if (value == 'remove') {
              _showRemoveMemberDialog(context, member);
            }
          },
          itemBuilder: (context) => [
            if (isAdmin)
              const PopupMenuItem(
                value: 'demote',
                child: CustomText(text: 'Demote to Member'),
              )
            else
              const PopupMenuItem(
                value: 'promote',
                child: CustomText(text: 'Promote to Admin'),
              ),
            const PopupMenuItem(
              value: 'remove',
              child:
                  CustomText(text: 'Remove from Group', textColor: Colors.red),
            ),
          ],
        );
      },
    );
  }
}