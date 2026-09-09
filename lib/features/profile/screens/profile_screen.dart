import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:animate_do/animate_do.dart';
import 'package:quickalert/quickalert.dart';

import '../../../core/routes/route_names.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/onboarding_permissions.dart';
import '../../../core/utils/page_transition.dart';
import '../../../features/settings/cubit/theme_cubit.dart';
import '../../../models/user_model.dart';
import '../../../services/auth/auth.dart';
import '../../../shared/widgets/custom_button.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../../shared/widgets/custom_text_form_field.dart';
import '../cubit/profile_cubit.dart';
import '../cubit/profile_state.dart';
import 'edit_profile_screen.dart';
import 'blocked_users_screen.dart';
import 'favorite_messages_screen.dart';

class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return BlocProvider(
      create: (context) => ProfileCubit()..loadUserProfile(),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: colors.surface,
          appBar: AppBar(
            title: const CustomText(
                text: 'My Profile',
                textColor: Colors.white,
                fontWeight: FontWeight.bold),
            centerTitle: true,
            backgroundColor: Colors.lightBlueAccent,
            elevation: 1,
            iconTheme: const IconThemeData(color: Colors.white),
            actions: [
              Builder(
                builder: (context) {
                  return IconButton(
                    onPressed: () async {
                      final state = context.read<ProfileCubit>().state;
                      if (state is ProfileLoaded) {
                        await Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder:
                                (context, animation, secondaryAnimation) =>
                                    EditProfileScreen(user: state.user),
                            transitionsBuilder: PageTransition.slideFromRight,
                          ),
                        );
                        if (!context.mounted) return;
                        context.read<ProfileCubit>().loadUserProfile();
                      }
                    },
                    icon: const Icon(Icons.edit_outlined, color: Colors.white),
                  );
                },
              ),
            ],
          ),
          body: BlocConsumer<ProfileCubit, ProfileState>(
            listener: (context, state) {
              if (state is ProfileLogoutSuccess) {
                Navigator.pushNamedAndRemoveUntil(
                    context, RouteNames.welcome, (route) => false);
              }
              if (state is ProfileReauthRequired) {
                _handleReauth(context);
              }
              if (state is ProfileError) {
                // Body keeps showing the last loaded profile (see builder);
                // surface the message as a dialog. Delete/logout errors here
                // already carry a user-friendly message.
                if (!context.mounted) return;
                QuickAlert.show(
                  context: context,
                  type: QuickAlertType.error,
                  title: 'Error',
                  text: state.message,
                  backgroundColor: FcAppColors.of(context).surface,
                  headerBackgroundColor: FcAppColors.of(context).surface,
                  titleColor: FcAppColors.of(context).textPrimary,
                  textColor: FcAppColors.of(context).textSecondary,
                );
              }
              if (state is ProfileDeleteSuccess) {
                QuickAlert.show(
                  context: context,
                  type: QuickAlertType.success,
                  title: 'Deleted!',
                  text: 'Your account has been successfully deleted.',
                  barrierDismissible: false,
                  backgroundColor: FcAppColors.of(context).surface,
                  headerBackgroundColor: FcAppColors.of(context).surface,
                  titleColor: FcAppColors.of(context).textPrimary,
                  textColor: FcAppColors.of(context).textSecondary,
                  onConfirmBtnTap: () {
                    Navigator.pushNamedAndRemoveUntil(
                        context, RouteNames.welcome, (route) => false);
                  },
                );
              }
            },
            builder: (context, state) {
              // Keep showing the loaded profile during transient delete/logout
              // errors instead of flipping to a bare error screen.
              if (state is ProfileError &&
                  context.read<ProfileCubit>().lastLoadedUser != null) {
                final user = context.read<ProfileCubit>().lastLoadedUser!;
                return _BuildProfileView(user: user);
              }
              if (state is ProfileLoading && state is! ProfileLoaded) {
                return const Center(
                    child: CircularProgressIndicator(
                        color: Colors.lightBlueAccent));
              }
              if (state is ProfileLoaded) {
                return _BuildProfileView(user: state.user);
              }
              if (state is ProfileError) {
                return Center(
                    child: CustomText(
                        text: 'Could not load profile.\n${state.message}'));
              }
              return const Center(
                  child: CustomText(text: 'Welcome to your profile!'));
            },
          ),
        ),
      ),
    );
  }
}

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
        _beginDeleteAccount(context);
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
                text: fullName, fontSize: 24.sp, fontWeight: FontWeight.bold),
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
                  _buildInfoRow(context, Icons.email_outlined, email),
                  const Divider(height: 24),
                  _buildInfoRow(context, Icons.phone_outlined, phone),
                  if (user.bio != null && user.bio!.isNotEmpty) ...[
                    const Divider(height: 24),
                    _buildInfoRow(context, Icons.info_outline, user.bio!),
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
                side: BorderSide(color: colors.divider)),
            child: ListTile(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              leading: const CircleAvatar(
                backgroundColor: Color(0x33FFC107),
                child: Icon(Icons.star, color: Color(0xFFFFC107)),
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
                side: BorderSide(color: colors.divider)),
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
                side: BorderSide(color: colors.divider)),
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
          const _NotificationToggleTile(),
          SizedBox(height: 16.h),
          _PresenceToggleTile(initialValue: user.presenceEnabled),
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
                    text: 'Log Out', textColor: Colors.white, fontSize: 18.sp),
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
                    fontSize: 18.sp),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoRow(BuildContext context, IconData icon, String text) {
    final colors = FcAppColors.of(context);
    return Row(
      children: [
        Icon(icon, color: colors.textSecondary),
        SizedBox(width: 16.w),
        Expanded(
            child: CustomText(
                text: text, fontSize: 16.sp, textColor: colors.textPrimary)),
      ],
    );
  }
}

class _PresenceToggleTile extends StatefulWidget {
  const _PresenceToggleTile({required this.initialValue});

  final bool initialValue;

  @override
  State<_PresenceToggleTile> createState() => _PresenceToggleTileState();
}

class _PresenceToggleTileState extends State<_PresenceToggleTile> {
  late bool _value = widget.initialValue;

  void _toggle(bool value) {
    setState(() {
      _value = value;
    });
    context.read<ProfileCubit>().updatePresenceEnabled(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(color: colors.divider),
      ),
      child: ListTile(
        contentPadding: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
        leading: CircleAvatar(
          backgroundColor: Colors.lightBlueAccent.withValues(alpha: 0.15),
          child: const Icon(Icons.visibility_outlined,
              color: Colors.lightBlueAccent),
        ),
        title: CustomText(
          text: 'Show Online Status',
          fontSize: 16.sp,
          fontWeight: FontWeight.w600,
          textColor: colors.textPrimary,
        ),
        subtitle: CustomText(
          text: 'Let others see when you are online and your last seen',
          fontSize: 13.sp,
          textColor: colors.textSecondary,
        ),
        trailing: Switch(
          value: _value,
          onChanged: _toggle,
        ),
        onTap: () => _toggle(!_value),
      ),
    );
  }
}

class _NotificationToggleTile extends StatefulWidget {
  const _NotificationToggleTile();

  @override
  State<_NotificationToggleTile> createState() =>
      _NotificationToggleTileState();
}

class _NotificationToggleTileState extends State<_NotificationToggleTile> {
  bool _enabled = true;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _checkStatus();
  }

  Future<void> _checkStatus() async {
    final granted = await OnboardingPermissions.instance.notificationsGranted();
    if (mounted) {
      setState(() {
        _enabled = granted;
        _loading = false;
      });
    }
  }

  Future<void> _toggle(bool value) async {
    if (value) {
      // Turning ON — request through FCM service so token gets saved.
      final granted =
          await OnboardingPermissions.instance.requestFullNotificationPermission();
      if (granted) {
        await OnboardingPermissions.instance.clearNotificationsDenied();
      }
      if (mounted) {
        setState(() => _enabled = granted);
        if (!granted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text(
                'Notification permission denied. Enable it from your phone\'s Settings.',
              ),
              backgroundColor: Colors.orange.shade700,
              behavior: SnackBarBehavior.floating,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(10.r)),
              margin: EdgeInsets.all(16.w),
              duration: const Duration(seconds: 3),
              action: SnackBarAction(
                label: 'Open Settings',
                textColor: Colors.white,
                onPressed: () =>
                    OnboardingPermissions.instance.openAppSettings(),
              ),
            ),
          );
        }
      }
    } else {
      // Turning OFF — can't programmatically revoke; open OS settings.
      await OnboardingPermissions.instance.openAppSettings();
      // Re-check actual state when they return.
      await _checkStatus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(color: colors.divider),
      ),
      child: _loading
          ? ListTile(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              leading: CircleAvatar(
                backgroundColor:
                    Colors.lightBlueAccent.withValues(alpha: 0.15),
                child: const Icon(Icons.notifications_outlined,
                    color: Colors.lightBlueAccent),
              ),
              title: CustomText(
                text: 'Notifications',
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                textColor: colors.textPrimary,
              ),
              subtitle: CustomText(
                text: 'Loading...',
                fontSize: 13.sp,
                textColor: colors.textSecondary,
              ),
            )
          : ListTile(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
              leading: CircleAvatar(
                backgroundColor:
                    Colors.lightBlueAccent.withValues(alpha: 0.15),
                child: Icon(
                  _enabled
                      ? Icons.notifications_active_outlined
                      : Icons.notifications_off_outlined,
                  color: Colors.lightBlueAccent,
                ),
              ),
              title: CustomText(
                text: 'Notifications',
                fontSize: 16.sp,
                fontWeight: FontWeight.w600,
                textColor: colors.textPrimary,
              ),
              subtitle: CustomText(
                text: _enabled
                    ? 'Enabled'
                    : 'Disabled — tap to enable',
                fontSize: 13.sp,
                textColor: _enabled
                    ? colors.textSecondary
                    : Colors.orange.shade700,
              ),
              trailing: Switch(
                value: _enabled,
                onChanged: _toggle,
              ),
              onTap: () => _toggle(!_enabled),
            ),
    );
  }
}

/// Starts the account-deletion flow. For email/password accounts the user is
/// first asked to re-enter their password; for Google accounts a fresh
/// Google sign-in is triggered. This re-authentication prevents the
/// `requires-recent-login` failure when Firebase actually deletes the user.
void _beginDeleteAccount(BuildContext context) {
  final cubit = context.read<ProfileCubit>();
  final authService = AuthService();
  if (authService.primaryProvider == 'google.com') {
    // Cubit triggers a fresh Google sign-in then deletes.
    cubit.reauthenticateAndDelete();
  } else {
    _promptForPasswordAndDelete(context);
  }
}

/// Defensive handler for `ProfileReauthRequired`: prompts for credentials
/// again and retries the delete. Used when a direct `deleteAccount()` call
/// hits `requires-recent-login`.
Future<void> _handleReauth(BuildContext context) async {
  final authService = AuthService();
  if (authService.primaryProvider == 'google.com') {
    final ok = await authService.reauthenticateWithGoogle();
    if (ok && context.mounted) {
      context.read<ProfileCubit>().deleteAccount();
    }
  } else {
    await _promptForPasswordAndDelete(context);
  }
}

/// Shows a password dialog for email/password accounts and, on success,
/// asks the cubit to re-authenticate and delete.
Future<void> _promptForPasswordAndDelete(BuildContext context) async {
  final controller = TextEditingController();
  final formKey = GlobalKey<FormState>();
  String? password;

  final entered = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (dialogContext) {
      final colors = FcAppColors.of(dialogContext);
      return AlertDialog(
        backgroundColor: colors.surface,
        title: Text(
          'Confirm Password',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: colors.textPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Form(
          key: formKey,
          child: CustomTextFormField(
            controller: controller,
            text: 'Enter your password',
            hintText: 'Your password',
            isPassword: true,
            textInputAction: TextInputAction.done,
            validator: (value) => (value == null || value.isEmpty)
                ? 'Password is required'
                : null,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text('Cancel', style: TextStyle(color: colors.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                password = controller.text;
                Navigator.pop(dialogContext, true);
              }
            },
            child: const Text('Continue',
                style: TextStyle(color: Colors.lightBlueAccent)),
          ),
        ],
      );
    },
  );

  if (entered != true || !context.mounted) return;
  context.read<ProfileCubit>().reauthenticateAndDelete(password: password);
}
