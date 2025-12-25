import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:quickalert/quickalert.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import '../../cubits/profile_cubit/profile_cubit.dart';
import '../../cubits/profile_cubit/profile_state.dart';
import '../../models/user_model.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text_form_field.dart';

class EditProfileScreen extends StatefulWidget {
  final UserModel user;
  const EditProfileScreen({super.key, required this.user});

  @override
  State<EditProfileScreen> createState() => _EditProfileScreenState();
}

class _EditProfileScreenState extends State<EditProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _firstNameController;
  late final TextEditingController _lastNameController;
  late final TextEditingController _phoneController;
  late final TextEditingController _emailController;
  late final TextEditingController _bioController;
  String? _selectedEmoji;

  @override
  void initState() {
    super.initState();
    _firstNameController = TextEditingController(text: widget.user.firstName);
    _lastNameController = TextEditingController(text: widget.user.lastName);
    _phoneController = TextEditingController(text: widget.user.phoneNumber);
    _emailController = TextEditingController(text: widget.user.email);
    _bioController = TextEditingController(text: widget.user.bio ?? '');
    _selectedEmoji = widget.user.avatarEmoji;
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _emailController.dispose();
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

  void _saveProfile(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();

    final newBio = _bioController.text.trim();
    context.read<ProfileCubit>().updateUserProfile(
      originalUser: widget.user,
      newFirstName: _firstNameController.text.trim(),
      newLastName: _lastNameController.text.trim(),
      newPhone: _phoneController.text.trim(),
      newEmail: _emailController.text.trim(),
      newEmoji: _selectedEmoji,
      newBio: newBio.isNotEmpty ? newBio : null,
    );
  }

  @override
  Widget build(BuildContext context) {
    // This screen gets its own provider to manage its specific update flow.
    return BlocProvider(
      create: (context) => ProfileCubit(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          iconTheme: const IconThemeData(color: Colors.white),
          backgroundColor: Colors.lightBlueAccent,
          title: const CustomText(text:'Edit Profile',textColor: Colors.white, fontWeight: FontWeight.bold),
        ),
        body: BlocConsumer<ProfileCubit, ProfileState>(
          listener: (context, state) {
            if (state is ProfileUpdateSuccess) {
              QuickAlert.show(
                context: context,
                type: QuickAlertType.success,
                title: 'Success!',
                text: state.message,
                barrierDismissible: false,
                onConfirmBtnTap: () {
                  // Pop the alert, then pop the edit screen
                  Navigator.of(context).pop();
                  Navigator.of(context).pop();
                },
              );
            }
            if (state is ProfileError) {
              QuickAlert.show(context: context, type: QuickAlertType.error, title: 'Update Failed', text: state.message);
            }
          },
          builder: (context, state) {
            return Form(
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
                  CustomTextFormField(controller: _firstNameController, text: 'First Name', validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                  SizedBox(height: 16.h),
                  CustomTextFormField(controller: _lastNameController, text: 'Last Name', validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                  SizedBox(height: 16.h),
                  CustomTextFormField(controller: _phoneController, text: 'Phone Number', keyboardType: TextInputType.phone, validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                  SizedBox(height: 16.h),
                  CustomTextFormField(controller: _emailController, text: 'Email Address', isEmail: true, validator: (v) => v!.trim().isEmpty ? 'Required' : null),
                  SizedBox(height: 16.h),
                  CustomTextFormField(
                    controller: _bioController,
                    text: 'Bio',
                    hintText: 'Add your bio (optional)',
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    validator: (String? p1) {  },
                  ),
                  SizedBox(height: 40.h),
                  state is ProfileLoading
                      ? const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent))
                      : CustomButton(
                    onPressed: () => _saveProfile(context),
                    buttonColor: Colors.lightBlueAccent,
                    child: CustomText(text: 'Save Changes', textColor: Colors.white, fontSize: 18.sp),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}