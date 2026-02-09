import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../models/user_model.dart';
import '../../../core/utils/page_transition.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../chat/screens/group_chat_screen.dart';
import '../cubit/group_cubit.dart';
import '../cubit/group_state.dart';

class CreateGroupScreen extends StatelessWidget {
  final List<UserModel> initialMembers;

  const CreateGroupScreen({super.key, required this.initialMembers});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GroupCubit(),
      child: _CreateGroupView(initialMembers: initialMembers),
    );
  }
}

class _CreateGroupView extends StatefulWidget {
  final List<UserModel> initialMembers;

  const _CreateGroupView({required this.initialMembers});

  @override
  State<_CreateGroupView> createState() => _CreateGroupViewState();
}

class _CreateGroupViewState extends State<_CreateGroupView> {
  final _groupNameController = TextEditingController();
  final _groupBioController = TextEditingController();
  String _groupEmoji = '👥';

  @override
  void initState() {
    super.initState();
    _groupNameController.text = widget.initialMembers
        .map((e) => e.firstName)
        .take(3)
        .join(', ');
  }

  @override
  void dispose() {
    _groupNameController.dispose();
    _groupBioController.dispose();
    super.dispose();
  }

  void _pickEmoji() {
    showModalBottomSheet(
      context: context,
      builder: (context) => EmojiPicker(
        onEmojiSelected: (category, emoji) {
          setState(() => _groupEmoji = emoji.emoji);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _createGroup() {
    context.read<GroupCubit>().createGroup(
      name: _groupNameController.text,
      emoji: _groupEmoji,
      initialMembers: widget.initialMembers,
      bio: _groupBioController.text,
    );
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: () => FocusScope.of(context).unfocus(),
      child: BlocConsumer<GroupCubit, GroupState>(
        listener: (context, state) {
          if (state is GroupCreated) {
            Navigator.pushAndRemoveUntil(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    GroupChatScreen(group: state.group),
                transitionsBuilder: PageTransition.slideFromRight,
              ),
                  (route) => route.isFirst,
            );
          } else if (state is GroupError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: CustomText(text: state.message)),
            );
          }
        },
        builder: (context, state) {
          final isCreating = state is GroupCreating;

          return Scaffold(
            appBar: AppBar(
              title: const CustomText(text: 'New Group'),
              titleTextStyle: const TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20,
              ),
              backgroundColor: Colors.lightBlueAccent,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                if (isCreating)
                  const Padding(
                    padding: EdgeInsets.only(right: 16.0),
                    child: Center(
                      child: CircularProgressIndicator(color: Colors.white),
                    ),
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
                          child: CustomText(
                            text: _groupEmoji,
                            fontSize: 40.sp,
                          ),
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
                  SizedBox(height: 16.h),
                  TextField(
                    controller: _groupBioController,
                    decoration: const InputDecoration(
                      labelText: 'Group Bio (optional)',
                      hintText: 'e.g., A group for family updates',
                    ),
                    maxLines: 3,
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
                            child: CustomText(
                              text: member.avatarEmoji,
                              fontSize: 24.sp,
                            ),
                          ),
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
        },
      ),
    );
  }
}