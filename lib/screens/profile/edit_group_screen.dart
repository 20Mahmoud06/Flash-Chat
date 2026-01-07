import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:quickalert/quickalert.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_form_field.dart';

class EditGroupScreen extends StatefulWidget {
  final GroupModel group;

  const EditGroupScreen({super.key, required this.group});

  @override
  State<EditGroupScreen> createState() => _EditGroupScreenState();
}

class _EditGroupScreenState extends State<EditGroupScreen> {
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

    final newName = _nameController.text.trim();
    final newBio = _bioController.text.trim();

    if (newName == widget.group.name &&
        newBio == (widget.group.bio ?? '') &&
        _selectedEmoji == widget.group.avatarEmoji) {
      Navigator.pop(context);
      return;
    }

    FirebaseFirestore.instance
        .collection('groups')
        .doc(widget.group.id)
        .update({
      'name': newName,
      'avatarEmoji': _selectedEmoji,
      'bio': newBio.isEmpty ? FieldValue.delete() : newBio,
    }).then((_) {
      QuickAlert.show(
        context: context,
        type: QuickAlertType.success,
        title: 'Success!',
        text: 'Group updated successfully.',
        barrierDismissible: false,
        onConfirmBtnTap: () {
          Navigator.pop(context);
          Navigator.pop(context, GroupModel(
            id: widget.group.id,
            name: newName,
            avatarEmoji: _selectedEmoji ?? widget.group.avatarEmoji,
            memberUids: widget.group.memberUids,
            adminUids: widget.group.adminUids,
            createdBy: widget.group.createdBy,
            createdAt: widget.group.createdAt,
            bio: newBio.isEmpty ? null : newBio,
          ));
        },
      );
    }).catchError((e) {
      QuickAlert.show(context: context, type: QuickAlertType.error, title: 'Update Failed', text: e.toString());
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        iconTheme: const IconThemeData(color: Colors.white),
        backgroundColor: Colors.lightBlueAccent,
        title: const CustomText(text: 'Edit Group', textColor: Colors.white, fontWeight: FontWeight.bold),
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
                      backgroundColor: Colors.lightBlue.shade50,
                      child: _selectedEmoji != null
                          ? Text(_selectedEmoji!, style: TextStyle(fontSize: 60.sp))
                          : Icon(Icons.add_reaction_outlined, size: 60.sp, color: Colors.lightBlue.shade200),
                    ),
                    Positioned(
                      bottom: 0,
                      right: 0,
                      child: CircleAvatar(
                        radius: 20.r,
                        backgroundColor: Colors.lightBlueAccent,
                        child: Icon(Icons.edit, color: Colors.white, size: 20.r),
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
              validator: (String? p1) {  },
            ),
            SizedBox(height: 40.h),
            CustomButton(
              onPressed: _saveGroup,
              buttonColor: Colors.lightBlueAccent,
              child: CustomText(text: 'Save Changes', textColor: Colors.white, fontSize: 18.sp),
            ),
          ],
        ),
      ),
    );
  }
}