import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';

import '../../../core/utils/page_transition.dart';
import '../../../models/group_model.dart';
import '../../../models/user_model.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../../screens/profile/add_group_members_screen.dart';
import '../../chat/screens/chat_screen.dart';
import '../../profile/screens/media_gallery_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../cubit/group_cubit.dart';
import '../cubit/group_state.dart';
import 'edit_group_screen.dart';

class GroupInfoScreen extends StatelessWidget {
  final GroupModel group;

  const GroupInfoScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GroupCubit()..fetchGroupMembers(group),
      child: _GroupInfoView(initialGroup: group),
    );
  }
}

class _GroupInfoView extends StatefulWidget {
  final GroupModel initialGroup;

  const _GroupInfoView({required this.initialGroup});

  @override
  State<_GroupInfoView> createState() => _GroupInfoViewState();
}

class _GroupInfoViewState extends State<_GroupInfoView> {
  late GroupModel _currentGroup;
  List<UserModel> _members = [];
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.initialGroup;
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return BlocConsumer<GroupCubit, GroupState>(
      listener: (context, state) {
        if (state is GroupError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        } else if (state is GroupMembersLoaded) {
          setState(() {
            _currentGroup = state.group;
            _members = state.members;
            _isAdmin = state.isAdmin;
          });
        }
      },
       builder: (context, state) {
         if (state is GroupMemberRemoved || state is GroupDeleted) {
           WidgetsBinding.instance.addPostFrameCallback((_) {
             Navigator.pop(context);
           });
           return const SizedBox.shrink();
         }

         // Keep the last known member list on screen while the cubit
         // refreshes in the background; only show the spinner on first load.
         final isLoading = state is GroupLoading && _members.isEmpty;
         final isAdmin = _isAdmin;
         final members = _members;

         return Scaffold(
          backgroundColor: colors.surfaceMuted,
          appBar: AppBar(
            title: const CustomText(text: 'Group Info'),
            titleTextStyle: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 20,
            ),
            backgroundColor: Colors.lightBlueAccent,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              if (isAdmin && !_currentGroup.isDeleted)
                IconButton(
                  icon: const Icon(Icons.person_add_outlined, color: Colors.white),
                  onPressed: () async {
                    // Read the cubit from this button's context (a child of
                    // the BlocProvider). Using the `pageBuilder` context below
                    // would throw ProviderNotFoundException, because that
                    // context belongs to the pushed route, not to this screen.
                    final cubit = context.read<GroupCubit>();
                    await Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            AddGroupMembersScreen(
                          group: _currentGroup,
                          cubit: cubit,
                        ),
                        transitionsBuilder: PageTransition.slideFromRight,
                      ),
                    );
                  },
                ),
              if (isAdmin && !_currentGroup.isDeleted)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  onPressed: () async {
                    final updatedGroup = await Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            EditGroupScreen(group: _currentGroup),
                        transitionsBuilder: PageTransition.slideFromRight,
                      ),
                    );
                    if (!context.mounted || updatedGroup == null) return;
                    context.read<GroupCubit>().refreshGroup(updatedGroup);
                  },
                ),
            ],
          ),
          body: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                SizedBox(height: 30.h),
                CircleAvatar(
                  radius: 60.r,
                  backgroundColor: colors.avatarBackground,
                  child: CustomText(
                    text: _currentGroup.avatarEmoji,
                    fontSize: 60.sp,
                  ),
                ),
                SizedBox(height: 16.h),
                CustomText(
                  text: _currentGroup.name,
                  fontSize: 24.sp,
                  fontWeight: FontWeight.bold,
                ),
                if (_currentGroup.bio != null && _currentGroup.bio!.isNotEmpty)
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                    child: CustomText(
                      text: _currentGroup.bio!,
                      textColor: colors.textSecondary,
                      fontSize: 16.sp,
                      textAlign: TextAlign.center,
                    ),
                  ),
                CustomText(
                  text: '${_currentGroup.memberUids.length} Members',
                  fontSize: 16.sp,
                  textColor: colors.textSecondary,
                ),
                SizedBox(height: 20.h),
                _buildMediaSection(context),
                _buildMemberList(context, isLoading, members),
                SizedBox(height: 30.h),
                _buildLeaveGroupButton(context),
                SizedBox(height: 10.h),
                _buildDeleteGroupButton(context),
                SizedBox(height: 16.h),
              ],
            ),
          ),
        );
      },
    );
  }

  static final _urlRegExp = RegExp(r'''(https?://|www\.)[^\s<>"']+''');

  void _openGallery(BuildContext context, int tab) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MediaGalleryScreen(
          group: _currentGroup,
          chatId: _currentGroup.id,
          initialTab: tab,
        ),
        transitionsBuilder: PageTransition.slideFromRight,
      ),
    );
  }

  Widget _buildMediaSection(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(color: colors.divider),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('groups')
            .doc(_currentGroup.id)
            .collection('messages')
            .snapshots(),
        builder: (context, snapshot) {
          var photos = 0, videos = 0, voice = 0, links = 0;
          final docs = snapshot.data?.docs ?? const [];
          for (final doc in docs) {
            final data = doc.data();
            if (data['isDeleted'] == true) continue;
            final type = data['messageType'];
            if (type == 'image') {
              photos += (data['mediaUrls'] as List?)?.length ?? 0;
            } else if (type == 'video') {
              videos++;
            } else if (type == 'voice') {
              voice++;
            } else if ((type == null || type == 'text') &&
                _urlRegExp.hasMatch(data['text'] ?? '')) {
              links++;
            }
          }
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Row(
              children: [
                _MediaTile(
                  icon: Icons.photo_library_outlined,
                  color: Colors.blue,
                  label: 'Photos',
                  count: photos,
                  onTap: () => _openGallery(context, 0),
                ),
                _MediaTile(
                  icon: Icons.videocam_outlined,
                  color: Colors.deepOrange,
                  label: 'Videos',
                  count: videos,
                  onTap: () => _openGallery(context, 1),
                ),
                _MediaTile(
                  icon: Icons.mic_none,
                  color: Colors.green,
                  label: 'Voice',
                  count: voice,
                  onTap: () => _openGallery(context, 2),
                ),
                _MediaTile(
                  icon: Icons.link,
                  color: Colors.purple,
                  label: 'Links',
                  count: links,
                  onTap: () => _openGallery(context, 3),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  void _showRemoveMemberDialog(BuildContext context, UserModel member) {
    if (_currentGroup.isDeleted) return;
    final isAdmin = _currentGroup.adminUids.contains(member.uid);

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
                group: _currentGroup,
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
    if (_currentGroup.isDeleted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: CustomText(text: 'Promote ${member.firstName}?'),
        content: const CustomText(
          text: 'This member will be able to add and remove members and change group settings.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const CustomText(text: 'Cancel'),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(ctx);
              final originalGroup = _currentGroup;
              // Update the badge in place right away so the UI reflects the
              // change immediately instead of waiting for a full reload.
              setState(() {
                _currentGroup = _currentGroup.copyWith(
                  adminUids: [..._currentGroup.adminUids, member.uid],
                );
              });
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
    if (_currentGroup.isDeleted) return;
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
              final originalGroup = _currentGroup;
              // Update the badge in place right away so the UI reflects the
              // change immediately instead of waiting for a full reload.
              setState(() {
                _currentGroup = _currentGroup.copyWith(
                  adminUids: _currentGroup.adminUids
                      .where((uid) => uid != member.uid)
                      .toList(),
                );
              });
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

  Widget _buildMemberList(BuildContext context, bool isLoading, List members) {
    final colors = FcAppColors.of(context);
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.lightBlueAccent),
      );
    }

    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final viewerIsAdmin = _currentGroup.adminUids.contains(currentUid) ||
        (_currentGroup.adminUids.isEmpty &&
            _currentGroup.createdBy == currentUid);

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        final isCreator = _currentGroup.createdBy == member.uid;
        final isAdmin = _currentGroup.adminUids.contains(member.uid);
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
                context,
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

  Widget _buildLeaveGroupButton(BuildContext context) {
    // A deleted group has no actionable buttons left: it is simply an
    // archive that everyone can keep reading.
    if (_currentGroup.isDeleted) return const SizedBox.shrink();
    final colors = FcAppColors.of(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () => _confirmLeaveGroup(context),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.logout, color: Colors.red.shade400, size: 22),
                SizedBox(width: 10.w),
                const CustomText(
                  text: 'Leave Group',
                  textColor: Colors.red,
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

  void _confirmLeaveGroup(BuildContext context) {
    if (_currentGroup.isDeleted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
        title: const CustomText(
            text: 'Leave Group', fontWeight: FontWeight.bold),
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
              context.read<GroupCubit>().leaveGroup(_currentGroup);
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

  Widget _buildDeleteGroupButton(BuildContext context) {
    final colors = FcAppColors.of(context);
    // Any admin (or the creator, who is always an admin) can delete the
    // group, and only while it is still active. A deleted group has no
    // further actions.
    if (!_isAdmin || _currentGroup.isDeleted) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 20.w),
      child: Material(
        color: colors.surface,
        borderRadius: BorderRadius.circular(14.r),
        child: InkWell(
          borderRadius: BorderRadius.circular(14.r),
          onTap: () => _confirmDeleteGroup(context),
          child: Padding(
            padding: EdgeInsets.symmetric(vertical: 18.h),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.delete_forever, color: Colors.red.shade400, size: 22),
                SizedBox(width: 10.w),
                const CustomText(
                  text: 'Delete Group',
                  textColor: Colors.red,
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

  void _confirmDeleteGroup(BuildContext context) {
    if (!_isAdmin || _currentGroup.isDeleted) return;
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
        title: const CustomText(
            text: 'Delete Group', fontWeight: FontWeight.bold),
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
              context.read<GroupCubit>().deleteGroup(_currentGroup);
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

  Widget _creatorBadge() {
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 10.w, vertical: 4.h),
      decoration: BoxDecoration(
        color: Colors.amber.withValues(alpha: 0.15),
        borderRadius: BorderRadius.circular(12.r),
      ),
      child: const CustomText(
        text: 'Creator',
        textColor: Color(0xFFB8860B),
        fontWeight: FontWeight.bold,
        fontSize: 12,
      ),
    );
  }

  Widget? _buildMemberTrailingWidget(
    BuildContext context,
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
    if (_currentGroup.isDeleted) {
      if (isAdmin) return _roleBadge('Admin', Colors.green);
      return null;
    }

    // Only admins get management controls.
    if (viewerIsAdmin && !isSelf) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (isAdmin) ...[
            _roleBadge('Admin', Colors.green),
            _managementMenu(context, member, isAdmin: true),
          ] else
            _managementMenu(context, member, isAdmin: false),
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

  Widget _managementMenu(
    BuildContext context,
    UserModel member, {
    required bool isAdmin,
  }) {
    return PopupMenuButton<String>(
      icon: Icon(Icons.more_vert, color: FcAppColors.of(context).textSecondary),
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
          child: CustomText(text: 'Remove from Group', textColor: Colors.red),
        ),
      ],
    );
  }
}

class _MediaTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _MediaTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(12.r),
        onTap: onTap,
        child: Column(
          children: [
            CircleAvatar(
              radius: 24.r,
              backgroundColor: color.withValues(alpha: 0.12),
              child: Icon(icon, color: color, size: 24.sp),
            ),
            SizedBox(height: 6.h),
            CustomText(
              text: label,
              fontSize: 12.sp,
              fontWeight: FontWeight.w600,
              textColor: colors.textSecondary,
            ),
            SizedBox(height: 2.h),
            CustomText(
              text: count.toString(),
              fontSize: 15.sp,
              fontWeight: FontWeight.bold,
            ),
          ],
        ),
      ),
    );
  }
}
