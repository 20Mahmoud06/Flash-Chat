import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:quickalert/quickalert.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';

import '../../../models/group_model.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../../shared/widgets/custom_text_form_field.dart';
import '../cubit/group_cubit.dart';
import '../cubit/group_state.dart';

class EditGroupScreen extends StatelessWidget {
  final GroupModel group;

  const EditGroupScreen({super.key, required this.group});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => GroupCubit(),
      child: _EditGroupView(group: group),
    );
  }
}

class _EditGroupView extends StatefulWidget {
  final GroupModel group;

  const _EditGroupView({required this.group});

  @override
  State<_EditGroupView> createState() => _EditGroupViewState();
}

class _EditGroupViewState extends State<_EditGroupView> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _bioController;
  String? _selectedEmoji;

  @override
  void initState() {
    super.initState();
    _nameController = TextEditingController(text: widget.group.name);
    _bioController = TextEditingController(text: widget.group.bio ?? '');
    _selectedEmoji = widget.group.avatarEmoji;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _bioController.dispose();
    super.dispose();
  }

  void _pickEmoji() {
    showModalBottomSheet(
      context: context,
      builder: (context) => EmojiPicker(
        onEmojiSelected: (category, emoji) {
          setState(() => _selectedEmoji = emoji.emoji);
          Navigator.pop(context);
        },
      ),
    );
  }

  void _saveGroup() {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    context.read<GroupCubit>().updateGroup(
          currentGroup: widget.group,
          name: _nameController.text,
          emoji: _selectedEmoji ?? widget.group.avatarEmoji,
          bio: _bioController.text,
        );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return BlocConsumer<GroupCubit, GroupState>(
      listener: (context, state) {
        if (state is GroupUpdated) {
          QuickAlert.show(
            context: context,
            type: QuickAlertType.success,
            title: 'Success!',
            text: 'Group updated successfully.',
            barrierDismissible: false,
            backgroundColor: FcAppColors.of(context).surface,
            headerBackgroundColor: FcAppColors.of(context).surface,
            titleColor: FcAppColors.of(context).textPrimary,
            textColor: FcAppColors.of(context).textSecondary,
            onConfirmBtnTap: () {
              Navigator.pop(context); // Close QuickAlert
              Navigator.pop(context, state.group); // Return updated group
            },
          );
        } else if (state is GroupError) {
          QuickAlert.show(
            context: context,
            type: QuickAlertType.error,
            title: 'Update Failed',
            text: state.message,
            backgroundColor: FcAppColors.of(context).surface,
            headerBackgroundColor: FcAppColors.of(context).surface,
            titleColor: FcAppColors.of(context).textPrimary,
            textColor: FcAppColors.of(context).textSecondary,
          );
        }
      },
      builder: (context, state) {
        return GestureDetector(
          onTap: () => FocusScope.of(context).unfocus(),
          child: Scaffold(
            backgroundColor: colors.surface,
            appBar: AppBar(
              iconTheme: const IconThemeData(color: Colors.white),
              backgroundColor: Colors.lightBlueAccent,
              title: const CustomText(
                text: 'Edit Group',
                textColor: Colors.white,
                fontWeight: FontWeight.bold,
              ),
            ),
            body: Form(
              key: _formKey,
              child: ListView(
                padding: EdgeInsets.symmetric(horizontal: 24.w, vertical: 20.h),
                children: [
                  Center(
                    child: GestureDetector(
                      onTap: _pickEmoji,
                      child: Stack(
                        children: [
                          CircleAvatar(
                            radius: 60.r,
                            backgroundColor: colors.avatarBackground,
                            child: _selectedEmoji != null
                                ? Text(
                                    _selectedEmoji!,
                                    style: TextStyle(fontSize: 60.sp),
                                  )
                                : Icon(
                                    Icons.add_reaction_outlined,
                                    size: 60.sp,
                                    color: Colors.lightBlue.shade200,
                                  ),
                          ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: CircleAvatar(
                              radius: 20.r,
                              backgroundColor: Colors.lightBlueAccent,
                              child: Icon(
                                Icons.edit,
                                color: Colors.white,
                                size: 20.r,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  SizedBox(height: 32.h),
                  CustomTextFormField(
                    controller: _nameController,
                    text: 'Group Name',
                    validator: (v) => v!.trim().isEmpty ? 'Required' : null,
                  ),
                  SizedBox(height: 16.h),
                  CustomTextFormField(
                    controller: _bioController,
                    text: 'Bio',
                    hintText: 'Add group bio (optional)',
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    maxLetters: 70,
                    validator: (String? p1) {
                      final bioLength = p1?.trim().length ?? 0;
                      if (bioLength > 70) {
                        return 'Bio must be 70 characters or less';
                      }
                      return null;
                    },
                  ),
                  SizedBox(height: 40.h),
                  if (state is GroupUpdating)
                    const Center(
                      child: CircularProgressIndicator(
                        color: Colors.lightBlueAccent,
                      ),
                    )
                  else
                    CustomButton(
                      onPressed: _saveGroup,
                      buttonColor: Colors.lightBlueAccent,
                      child: CustomText(
                        text: 'Save Changes',
                        textColor: Colors.white,
                        fontSize: 18.sp,
                      ),
                    ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
