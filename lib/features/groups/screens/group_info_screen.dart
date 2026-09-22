import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transition.dart';
import '../models/group_model.dart';
import '../../profile/models/user_model.dart';
import 'add_group_members_screen.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../profile/screens/media_gallery_screen.dart';
import '../cubit/group_cubit.dart';
import '../cubit/group_state.dart';
import '../widgets/group_action_buttons.dart';
import '../widgets/group_members_section.dart';
import '../widgets/group_media_section.dart';
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

  void _openGallery(int tab) {
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

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return BlocConsumer<GroupCubit, GroupState>(
      listener: (context, state) {
        if (state is GroupError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: CustomText(text: state.message)),
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

        // Keep the last known member list on screen while the bloc
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
                  icon: const Icon(Icons.person_add_outlined,
                      color: Colors.white),
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
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
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
                GroupMediaSection(
                  chatId: _currentGroup.id,
                  onOpenGallery: _openGallery,
                ),
                GroupMembersSection(
                  group: _currentGroup,
                  members: members,
                  isLoading: isLoading,
                  onGroupChanged: (group) =>
                      setState(() => _currentGroup = group),
                ),
                SizedBox(height: 30.h),
                if (!_currentGroup.isDeleted)
                  GroupDangerTile(
                    label: 'Leave Group',
                    icon: Icons.logout,
                    iconColor: Colors.red.shade400,
                    textColor: Colors.red,
                    onTap: () => confirmLeaveGroup(context, _currentGroup),
                  ),
                SizedBox(height: 10.h),
                if (isAdmin && !_currentGroup.isDeleted)
                  GroupDangerTile(
                    label: 'Delete Group',
                    icon: Icons.delete_forever,
                    iconColor: Colors.red.shade400,
                    textColor: Colors.red,
                    onTap: () => confirmDeleteGroup(context, _currentGroup),
                  ),
                SizedBox(height: 16.h),
              ],
            ),
          ),
        );
      },
    );
  }
}