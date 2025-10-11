import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../models/user_model.dart';

class GroupInfoScreen extends StatefulWidget {
  final GroupModel group;
  const GroupInfoScreen({super.key, required this.group});

  @override
  State<GroupInfoScreen> createState() => _GroupInfoScreenState();
}

class _GroupInfoScreenState extends State<GroupInfoScreen> {
  List<UserModel> _members = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _fetchMembers();
  }

  Future<void> _fetchMembers() async {
    try {
      if (widget.group.memberUids.isEmpty) {
        setState(() => _isLoading = false);
        return;
      }
      final snapshots = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: widget.group.memberUids)
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
                text: widget.group.avatarEmoji,
                fontSize: 60.sp,
              ),
            ),
            SizedBox(height: 16.h),
            CustomText(
              text: widget.group.name,
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
            ),
            CustomText(
                text: '${widget.group.memberUids.length} Members',
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
        final isAdmin = widget.group.adminUids.contains(member.uid);
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
          ),
        );
      },
    );
  }
}
