import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/screens/profile/add_group_members_screen.dart';
import 'package:flash_chat_app/screens/profile/edit_group_screen.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../models/user_model.dart';
import '../../utils/page_transition.dart';
import '../home/chat_screen.dart';
import 'profile_screen.dart';

class GroupInfoScreen extends StatefulWidget {
  final GroupModel group;
  const GroupInfoScreen({super.key, required this.group});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  late GroupModel _currentGroup;
  List<UserModel> _members = [];
  bool _isLoading = true;
  bool _isAdmin = false;

  @override
  void initState() {
    super.initState();
    _currentGroup = widget.group;
    _checkAdmin();
    _fetchMembers();
  }

  void _checkAdmin() {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser != null) {
      _isAdmin = _currentGroup.adminUids.contains(currentUser.uid);
    }
  }

  Future<void> _fetchMembers() async {
    try {
      if (_currentGroup.memberUids.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }
      final snapshots = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: _currentGroup.memberUids)
          .get();
      final memberModels =
      snapshots.docs.map((doc) => UserModel.fromFirestore(doc)).toList();
      if (mounted) {
        setState(() {
          _members = memberModels;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('Error fetching members: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        title: const CustomText(text: 'Group Info'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        backgroundColor: Colors.lightBlueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isAdmin)
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
                    setState(() {
                      _currentGroup = updatedGroup;
                      _fetchMembers();
                    });
                  }
                });
              },
            ),
          if (_isAdmin)
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
                    setState(() {
                      _currentGroup = updatedGroup;
                      _fetchMembers();
                    });
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
                textColor: Colors.grey.shade600),
            SizedBox(height: 20.h),
            _buildMemberList(),
          ],
        ),
      ),
    );
  }

  Widget _buildMemberList() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.lightBlueAccent));
    }
    return ListView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: _members.length,
      itemBuilder: (context, index) {
        final member = _members[index];
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
                fontWeight: FontWeight.bold)
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