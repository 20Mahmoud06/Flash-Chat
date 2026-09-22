import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:animate_do/animate_do.dart';
import 'package:quickalert/quickalert.dart';
import '../../../core/constants/app_colors.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/page_transition.dart';
import '../../../features/settings/cubit/theme_cubit.dart';
import '../models/user_model.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text.dart';
import '../cubit/profile_cubit.dart';
import 'blocked_users_screen.dart';
import 'favorite_messages_screen.dart';
import 'profile_notification_toggle_tile.dart';
import 'profile_presence_toggle_tile.dart';
import 'profile_reauth_flow.dart';

/// Full profile content: avatar, info card, setting tiles, and action buttons.
/// Displayed inside [ProfileScreen]'s [BlocBuilder] once the profile is loaded.
class ProfileView extends StatelessWidget {
  final UserModel user;

  const ProfileView({super.key, required this.user});

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
      backgroundColor: FcAppColors.of(context).surface,
      headerBackgroundColor: FcAppColors.of(context).surface,
      titleColor: FcAppColors.of(context).textPrimary,
      textColor: FcAppColors.of(context).textSecondary,
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
      backgroundColor: FcAppColors.of(context).surface,
      headerBackgroundColor: FcAppColors.of(context).surface,
      titleColor: FcAppColors.of(context).textPrimary,
      textColor: FcAppColors.of(context).textSecondary,
      onConfirmBtnTap: () {
        Navigator.of(context, rootNavigator: true).pop();
        beginDeleteAccount(context);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
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
              backgroundColor: colors.avatarBackground,
              child: CustomText(text: emoji, fontSize: 60.sp),
            ),
          ),
          SizedBox(height: 16.h),
          Center(
            child: CustomText(
              text: fullName,
              fontSize: 24.sp,
              fontWeight: FontWeight.bold,
            ),
          ),
          SizedBox(height: 24.h),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
              side: BorderSide(color: colors.divider),
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: 16.h, horizontal: 20.w),
              child: Column(
                children: [
                  _buildInfoRow(Icons.email_outlined, email),
                  const Divider(height: 24),
                  _buildInfoRow(Icons.phone_outlined, phone),
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const Divider(height: 24),
                    _buildInfoRow(Icons.info_outline, user.bio!),
                  ],
                ],
              ),
            ),
          ),
          SizedBox(height: 24.h),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
              side: BorderSide(color: colors.divider),
            ),
            child: ListTile(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              leading: const CircleAvatar(
                backgroundColor: AppColors.amberGlow,
                child: Icon(Icons.star, color: AppColors.amber),
              ),
              title: CustomText(
                text: 'Favorite Messages',
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                textColor: colors.textPrimary,
              ),
              subtitle: CustomText(
                text: 'Messages you starred',
                fontSize: 13.sp,
                textColor: colors.textSecondary,
              ),
              trailing: Icon(Icons.chevron_right, color: colors.textWeak),
              onTap: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const FavoriteMessagesScreen(),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 16.h),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
              side: BorderSide(color: colors.divider),
            ),
            child: ListTile(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              leading: CircleAvatar(
                backgroundColor: Colors.red.shade50,
                child: Icon(Icons.block, color: Colors.red.shade400),
              ),
              title: CustomText(
                text: 'Blocked Users',
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                textColor: colors.textPrimary,
              ),
              subtitle: StreamBuilder<DocumentSnapshot>(
                stream: FirebaseFirestore.instance
                    .collection('users')
                    .doc(user.uid)
                    .snapshots(),
                builder: (context, snapshot) {
                  final data = snapshot.data?.data() as Map<String, dynamic>?;
                  final blockedUids = snapshot.hasData
                      ? List<String>.from(data?['blockedUids'] ?? const [])
                      : <String>[];
                  return CustomText(
                    text: blockedUids.isEmpty
                        ? 'No blocked users'
                        : '${blockedUids.length} user${blockedUids.length == 1 ? '' : 's'} blocked',
                    fontSize: 13.sp,
                    textColor: colors.textSecondary,
                  );
                },
              ),
              trailing: Icon(Icons.chevron_right, color: colors.textWeak),
              onTap: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        const BlockedUsersScreen(),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              },
            ),
          ),
          SizedBox(height: 16.h),
          Card(
            elevation: 2,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16.r),
              side: BorderSide(color: colors.divider),
            ),
            child: BlocBuilder<ThemeCubit, ThemeState>(
              builder: (context, themeState) {
                final isDark = Theme.of(context).brightness == Brightness.dark;
                return ListTile(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                  leading: CircleAvatar(
                    backgroundColor: Colors.blueGrey.shade50,
                    child: Icon(
                      isDark ? Icons.dark_mode : Icons.light_mode,
                      color: Colors.blueGrey,
                    ),
                  ),
                  title: CustomText(
                    text: 'Night Mode',
                    fontSize: 16.sp,
                    fontWeight: FontWeight.w600,
                    textColor: colors.textPrimary,
                  ),
                  subtitle: CustomText(
                    text: isDark ? 'Dark theme enabled' : 'Dark theme disabled',
                    fontSize: 13.sp,
                    textColor: colors.textSecondary,
                  ),
                  trailing: Switch(
                    value: isDark,
                    onChanged: (value) {
                      context.read<ThemeCubit>().setDarkMode(value);
                    },
                  ),
                  onTap: () {
                    context.read<ThemeCubit>().setDarkMode(!isDark);
                  },
                );
              },
            ),
          ),
          SizedBox(height: 16.h),
          const ProfileNotificationToggleTile(),
          SizedBox(height: 16.h),
          ProfilePresenceToggleTile(initialValue: user.presenceEnabled),
          SizedBox(height: 40.h),
          CustomButton(
            onPressed: () => _showLogoutDialog(context),
            buttonColor: Colors.lightBlueAccent,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(Icons.logout, color: Colors.white),
                SizedBox(width: 8.w),
                CustomText(
                  text: 'Log Out',
                  textColor: Colors.white,
                  fontSize: 18.sp,
                ),
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
                CustomText(
                  text: 'Delete Account',
                  textColor: Colors.white,
                  fontSize: 18.sp,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(IconData icon, String text) {
    return Builder(
      builder: (context) {
        final colors = FcAppColors.of(context);
        return Row(
          children: [
            Icon(icon, color: colors.textSecondary),
            SizedBox(width: 16.w),
            Expanded(
              child: CustomText(
                text: text,
                fontSize: 16.sp,
                textColor: colors.textPrimary,
              ),
            ),
          ],
        );
      },
    );
  }
}