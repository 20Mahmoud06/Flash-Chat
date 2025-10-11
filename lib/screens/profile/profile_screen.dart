import 'package:flash_chat_app/screens/profile/edit_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:animate_do/animate_do.dart';
import 'package:quickalert/quickalert.dart';
import '../../cubits/profile_cubit/profile_cubit.dart';
import '../../cubits/profile_cubit/profile_state.dart';
import '../../widgets/custom_button.dart';
import '../../core/routes/route_names.dart';
import '../../models/user_model.dart';
import '../../widgets/custom_text.dart';
import '../../widgets/page_transition.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ProfileCubit()..loadUserProfile(),
      child: Scaffold(
        backgroundColor: Colors.white,
        appBar: AppBar(
          title: const CustomText(text: 'My Profile',textColor: Colors.white, fontWeight: FontWeight.bold),
          centerTitle: true,
          backgroundColor: Colors.lightBlueAccent,
          elevation: 1,
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            // The Builder is used to get a new context that is under the BlocProvider
            Builder(
              builder: (context) {
                return IconButton(
                  onPressed: () {
                    final state = context.read<ProfileCubit>().state;
                    if (state is ProfileLoaded) {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation, secondaryAnimation) => EditProfileScreen(user: state.user),
                          transitionsBuilder: PageTransition.slideFromRight,
                        ),
                      ).then((_) {
                        // After returning, reload the profile to see changes
                        context.read<ProfileCubit>().loadUserProfile();
                      });
                    }
                  },
                  icon: const Icon(Icons.edit_outlined, color: Colors.white),
                );              },
            ),
          ],
        ),
        body: BlocConsumer<ProfileCubit, ProfileState>(
          listener: (context, state) {
            if (state is ProfileLogoutSuccess) {
              Navigator.pushNamedAndRemoveUntil(context, RouteNames.welcome, (route) => false);
            }
            if (state is ProfileDeleteSuccess) {
              QuickAlert.show(
                context: context,
                type: QuickAlertType.success,
                title: 'Deleted!',
                text: 'Your account has been successfully deleted.',
                barrierDismissible: false,
                onConfirmBtnTap: () {
                  Navigator.pushNamedAndRemoveUntil(context, RouteNames.welcome, (route) => false);
                },
              );
            }
            if (state is ProfileError) {
              QuickAlert.show(context: context, type: QuickAlertType.error, title: 'Error', text: state.message);
            }
          },
          builder: (context, state) {
            if (state is ProfileLoading && state is! ProfileLoaded) {
              return const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent));
            }
            if (state is ProfileLoaded) {
              return _BuildProfileView(user: state.user);
            }
            if (state is ProfileError) {
              return Center(child: CustomText(text: 'Could not load profile.\n${state.message}'));
            }
            return const Center(child: CustomText(text: 'Welcome to your profile!'));
          },
        ),
      ),
    );
  }
}

// Extracted the main view into a separate widget for clarity
class _BuildProfileView extends StatelessWidget {
  final UserModel user;
  const _BuildProfileView({required this.user});

  void _showLogoutDialog(BuildContext context) {
    QuickAlert.show(
      context: context,
      type: QuickAlertType.confirm,
      title: 'Log Out?',
      text: 'Are you sure you want to log out?',
      confirmBtnText: 'Yes',
      cancelBtnText: 'No',
      confirmBtnColor: Colors.red.shade400,
      showCancelBtn: true,
      onConfirmBtnTap: () {
        Navigator.of(context, rootNavigator: true).pop();
        context.read<ProfileCubit>().logout();
      },
    );
  }

  void _showDeleteAccountDialog(BuildContext context) {
    QuickAlert.show(
      context: context,
      type: QuickAlertType.warning,
      title: 'Delete Account?',
      text: 'This is permanent! All your data will be erased forever.',
      confirmBtnText: 'Delete',
      cancelBtnText: 'Cancel',
      confirmBtnColor: Colors.red.shade700,
      showCancelBtn: true,
      onConfirmBtnTap: () {
        Navigator.of(context, rootNavigator: true).pop();
        context.read<ProfileCubit>().deleteAccount();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final fullName = '${user.firstName} ${user.lastName}';
    final email = user.email;
    final phone = user.phoneNumber;
    final String emoji = user.avatarEmoji;

    return FadeIn(
      child: ListView(
        padding: EdgeInsets.all(16.w),
        children: [
          SizedBox(height: 20.h),
          Center(
            child: CircleAvatar(
              radius: 60.r,
              backgroundColor: Colors.lightBlue.shade50,
              child: CustomText(text: emoji,fontSize: 60.sp),
            ),
          ),
          SizedBox(height: 16.h),
          Center(
            child: CustomText(text: fullName,fontSize: 24.sp, fontWeight: FontWeight.bold),
          ),
          SizedBox(height: 24.h),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16.r)),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
              child: Column(
                children: [
                  _buildInfoRow(Icons.email_outlined, email),
                  const Divider(height: 24),
                  _buildInfoRow(Icons.phone_outlined, phone),
                ],
              ),
            ),
          ),
          SizedBox(height: 40.h),
          CustomButton(
            onPressed: () => _showLogoutDialog(context),
            buttonColor: Colors.lightBlueAccent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout, color: Colors.white),
                SizedBox(width: 8.w),
                CustomText(text:'Log Out',textColor: Colors.white, fontSize: 18.sp),
              ],
            ),
          ),
          SizedBox(height: 16.h),
          CustomButton(
            onPressed: () => _showDeleteAccountDialog(context),
            buttonColor: Colors.red.shade400,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.delete_forever_outlined, color: Colors.white),
                SizedBox(width: 8.w),
                CustomText(text:'Delete Account',textColor: Colors.white, fontSize: 18.sp),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, color: Colors.grey.shade600),
        SizedBox(width: 16.w),
        Expanded(child: CustomText(text: text,fontSize: 16.sp,textColor: Colors.black87)),
      ],
    );
  }
}
