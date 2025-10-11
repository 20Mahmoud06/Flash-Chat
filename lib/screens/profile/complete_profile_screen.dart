import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:quickalert/quickalert.dart';
import '../../core/routes/route_names.dart';
import '../../cubits/profile_cubit/profile_cubit.dart';
import '../../cubits/profile_cubit/profile_state.dart';
import '../../widgets/custom_button.dart';
import '../../widgets/custom_text.dart';
import '../../widgets/custom_text_form_field.dart';
import '../../widgets/page_transition.dart';
import '../home/home_screen.dart';
import '../../models/user_model.dart';

class CompleteProfileScreen extends StatefulWidget {
  final UserModel? user;

  const CompleteProfileScreen({super.key, this.user});

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _firstNameController = TextEditingController();
  final _lastNameController = TextEditingController();
  final _phoneController = TextEditingController();
  bool _isGoogleUser = false;
  late AnimationController _animationController;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 500),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));
    _animationController.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final authUser = FirebaseAuth.instance.currentUser;
    final profileUser = ModalRoute.of(context)?.settings.arguments as UserModel?;

    if (profileUser != null && profileUser.firstName.isNotEmpty) {
      _isGoogleUser = true;
      _firstNameController.text = profileUser.firstName;
      _lastNameController.text = profileUser.lastName;
    } else if (authUser != null && authUser.displayName != null && authUser.displayName!.isNotEmpty) {
      _isGoogleUser = true;
      final names = authUser.displayName!.split(' ');
      _firstNameController.text = names.isNotEmpty ? names.first : '';
      _lastNameController.text = names.length > 1 ? names.sublist(1).join(' ') : '';
    }
  }

  @override
  void dispose() {
    _firstNameController.dispose();
    _lastNameController.dispose();
    _phoneController.dispose();
    _animationController.dispose();
    super.dispose();
  }

  void _saveProfile(BuildContext context) {
    if (!_formKey.currentState!.validate()) return;
    FocusScope.of(context).unfocus();
    context.read<ProfileCubit>().completeUserProfile(
      firstName: _firstNameController.text.trim(),
      lastName: _lastNameController.text.trim(),
      phoneNumber: _phoneController.text.trim(),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ProfileCubit(),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          resizeToAvoidBottomInset: true,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            title: SlideTransition(
              position: _slideAnimation,
              child: const CustomText(text: 'Complete Your Profile', textColor: Colors.white, fontWeight: FontWeight.bold),
            ),
            centerTitle: true,
            backgroundColor: Colors.lightBlueAccent,
          ),
          backgroundColor: Colors.white,
          body: BlocConsumer<ProfileCubit, ProfileState>(
            listener: (context, state) {
              if (state is ProfileUpdateSuccess) {
                QuickAlert.show(
                  context: context,
                  type: QuickAlertType.success,
                  title: 'Profile Complete!',
                  text: 'Welcome aboard!',
                  barrierDismissible: false,
                  onConfirmBtnTap: () {
                    Navigator.of(context, rootNavigator: true).pop();
                    Navigator.pushReplacement(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => HomeScreen(),
                          transitionsBuilder: PageTransition.slideFromRight,
                        ));
                  },
                );
              }
              if (state is ProfileError) {
                QuickAlert.show(context: context, type: QuickAlertType.error, title: "Update Failed", text: state.message);
              }
            },
            builder: (context, state) {
              return Center(
                child: SingleChildScrollView(
                  child: Padding(
                    padding: EdgeInsets.symmetric(horizontal: 24.0.w),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          SizedBox(height: 100.h, child: Image.asset('assets/logo.png', fit: BoxFit.contain)),
                          SizedBox(height: 16.h),
                          CustomText(textAlign: TextAlign.center, text: 'Almost There', fontSize: 24.sp, fontWeight: FontWeight.bold),
                          SizedBox(height: 8.h),
                          CustomText(text: 'Just a few more details to get you started.', textAlign: TextAlign.center, fontSize: 16.sp),
                          SizedBox(height: 32.h),
                          CustomTextFormField(controller: _firstNameController, text: 'First Name', enabled: !_isGoogleUser, validator: (v) => v!.trim().isEmpty ? 'Please enter your first name' : null),
                          SizedBox(height: 12.h),
                          CustomTextFormField(controller: _lastNameController, text: 'Last Name', enabled: !_isGoogleUser, validator: (v) => v!.trim().isEmpty ? 'Please enter your last name' : null),
                          SizedBox(height: 12.h),
                          CustomTextFormField(controller: _phoneController, text: 'Phone Number', keyboardType: TextInputType.phone, validator: (v) => v!.trim().isEmpty ? 'Please enter your phone number' : null),
                          SizedBox(height: 24.h),
                          state is ProfileLoading
                              ? const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent))
                              : CustomButton(
                            onPressed: () => _saveProfile(context),
                            buttonColor: Colors.lightBlueAccent,
                            child: CustomText(text: 'Save & Continue', textColor: Colors.white, fontSize: 18.sp),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}