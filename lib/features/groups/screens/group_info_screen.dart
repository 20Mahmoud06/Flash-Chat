import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/utils/page_transition.dart';
import '../../../models/group_model.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../../screens/profile/add_group_members_screen.dart';
import '../../chat/screens/chat_screen.dart';
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

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.initialGroup;
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<GroupCubit, GroupState>(
      listener: (context, state) {
        if (state is GroupError) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        } else if (state is GroupMembersLoaded) {
          setState(() => _currentGroup = state.group);
        }
      },
      builder: (context, state) {
        final isLoading = state is GroupLoading;
        final isAdmin = state is GroupMembersLoaded ? state.isAdmin : false;
        final members = state is GroupMembersLoaded ? state.members : [];

        return Scaffold(
          backgroundColor: Colors.grey.shade100,
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
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.person_add_outlined, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            AddGroupMembersScreen(group: _currentGroup),
                        transitionsBuilder: PageTransition.slideFromRight,
                      ),
                    ).then((updatedGroup) {
                      if (updatedGroup != null) {
                        context.read<GroupCubit>().refreshGroup(updatedGroup);
                      }
                    });
                  },
                ),
              if (isAdmin)
                IconButton(
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  onPressed: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) =>
                            EditGroupScreen(group: _currentGroup),
                        transitionsBuilder: PageTransition.slideFromRight,
                      ),
                    ).then((updatedGroup) {
                      if (updatedGroup != null) {
                        context.read<GroupCubit>().refreshGroup(updatedGroup);
                      }
                    });
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
                  backgroundColor: Colors.lightBlue.shade50,
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
                      textColor: Colors.grey.shade700,
                      fontSize: 16.sp,
                      textAlign: TextAlign.center,
                    ),
                  ),
                CustomText(
                  text: '${_currentGroup.memberUids.length} Members',
                  fontSize: 16.sp,
                  textColor: Colors.grey.shade600,
                ),
                SizedBox(height: 20.h),
                _buildMemberList(isLoading, members),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMemberList(bool isLoading, List members) {
    if (isLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.lightBlueAccent),
      );
    }

    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: members.length,
      itemBuilder: (context, index) {
        final member = members[index];
        final isAdmin = _currentGroup.adminUids.contains(member.uid);

        return Card(
          margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: Colors.grey.shade200,
              child: CustomText(text: member.avatarEmoji, fontSize: 20.sp),
            ),
            title: CustomText(text: '${member.firstName} ${member.lastName}'),
            subtitle: CustomText(text: member.phoneNumber),
            trailing: isAdmin
                ? const CustomText(
              text: 'Admin',
              textColor: Colors.green,
              fontWeight: FontWeight.bold,
            )
                : null,
            onTap: () {
              final currentUid = FirebaseAuth.instance.currentUser!.uid;
              if (member.uid != currentUid) {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        ChatScreen(contact: member),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              } else {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                    const ProfileScreen(),
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
}