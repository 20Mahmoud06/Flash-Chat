import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../models/user_model.dart';
import 'group_chat_screen.dart';
import '../../widgets/page_transition.dart';

class CreateGroupScreen extends StatefulWidget {
  final List<UserModel> initialMembers;
  const CreateGroupScreen({super.key, required this.initialMembers});

  @override
  State<CreateGroupScreen> createState() => _CreateGroupScreenState();
}

class _CreateGroupScreenState extends State<CreateGroupScreen> {
  final _groupNameController = TextEditingController();
  String _groupEmoji = '👥';
  bool _isCreating = false;

  @override
  void initState() {
    super.initState();
    _groupNameController.text = widget.initialMembers
        .map((e) => e.firstName)
        .take(3)
        .join(', ');
  }

  void _pickEmoji() {
    showModalBottomSheet(
      context: context,
      builder: (context) => EmojiPicker(
        onEmojiSelected: (category, emoji) {
          setState(() {
            _groupEmoji = emoji.emoji;
          });
          Navigator.pop(context);
        },
      ),
    );
  }

  Future<void> _createGroup() async {
    final groupName = _groupNameController.text.trim();
    if (groupName.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: CustomText(text: 'Please enter a group name.')),
      );
      return;
    }

    setState(() => _isCreating = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser!;
      final memberUids = {
        currentUser.uid,
        ...widget.initialMembers.map((e) => e.uid)
      }.toList();

      final newGroup = GroupModel(
        id: '',
        name: groupName,
        avatarEmoji: _groupEmoji,
        memberUids: memberUids,
        adminUids: [currentUser.uid],
        createdBy: currentUser.uid,
        createdAt: Timestamp.now(),
      );

      final docRef = await FirebaseFirestore.instance
          .collection('groups')
          .add(newGroup.toFirestore());

      final createdGroup = GroupModel(
        id: docRef.id,
        name: newGroup.name,
        avatarEmoji: newGroup.avatarEmoji,
        memberUids: newGroup.memberUids,
        adminUids: newGroup.adminUids,
        createdBy: newGroup.createdBy,
        createdAt: newGroup.createdAt,
      );


      if (mounted) {
        Navigator.pushAndRemoveUntil(
          context,
          PageRouteBuilder(
            pageBuilder: (context, animation, secondaryAnimation) => GroupChatScreen(
              group: createdGroup,
            ),
            transitionsBuilder: PageTransition.slideFromRight,
          ),
              (route) => route.isFirst,
        );
      }

    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: CustomText(text: 'Failed to create group: $e')),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isCreating = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const CustomText(text: 'New Group'),
        titleTextStyle:
        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        backgroundColor: Colors.lightBlueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (_isCreating)
            const Padding(
              padding: EdgeInsets.only(right: 16.0),
              child: Center(child: CircularProgressIndicator(color: Colors.white)),
            )
          else
            IconButton(
              icon: const Icon(Icons.check),
              onPressed: _createGroup,
            )
        ],
      ),
      body: SingleChildScrollView(
        padding: EdgeInsets.all(16.w),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                GestureDetector(
                  onTap: _pickEmoji,
                  child: CircleAvatar(
                    radius: 35.r,
                    backgroundColor: Colors.lightBlue.shade50,
                    child: CustomText(text: _groupEmoji,fontSize: 40.sp),
                  ),
                ),
                SizedBox(width: 16.w),
                Expanded(
                  child: TextField(
                    controller: _groupNameController,
                    decoration: const InputDecoration(
                      labelText: 'Group Name',
                      hintText: 'e.g., Family, Work Team',
                    ),
                    textCapitalization: TextCapitalization.sentences,
                  ),
                ),
              ],
            ),
            SizedBox(height: 24.h),
            CustomText(
              text: '${widget.initialMembers.length + 1} Members',
              fontSize: 16.sp,
              fontWeight: FontWeight.bold,
              textColor: Colors.grey.shade700,
            ),
            SizedBox(height: 8.h),
            GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 4,
                crossAxisSpacing: 8.w,
                mainAxisSpacing: 8.h,
              ),
              itemCount: widget.initialMembers.length,
              itemBuilder: (context, index) {
                final member = widget.initialMembers[index];
                return Column(
                  children: [
                    CircleAvatar(
                        radius: 25.r,
                        backgroundColor: Colors.grey.shade200,
                        child: CustomText(text: member.avatarEmoji,
                            fontSize: 24.sp)),
                    SizedBox(height: 4.h),
                    Text(
                      member.firstName,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(fontSize: 12.sp),
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}