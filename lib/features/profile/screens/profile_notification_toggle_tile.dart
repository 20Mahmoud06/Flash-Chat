import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/onboarding_permissions.dart';
import '../../../shared/widgets/custom_text.dart';

class ProfileNotificationToggleTile extends StatefulWidget {
  const ProfileNotificationToggleTile({super.key});

  @override
  State<ProfileNotificationToggleTile> createState() =>
      _ProfileNotificationToggleTileState();
}

class _ProfileNotificationToggleTileState
    extends State<ProfileNotificationToggleTile> {
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
      final granted = await OnboardingPermissions.instance
          .requestFullNotificationPermission();
      if (granted) {
        await OnboardingPermissions.instance.clearNotificationsDenied();
      }
      if (mounted) {
        setState(() => _enabled = granted);
        if (!granted && mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const CustomText(
                text:
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
      await OnboardingPermissions.instance.openAppSettings();
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
                backgroundColor: Colors.lightBlueAccent.withValues(alpha: 0.15),
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
                backgroundColor: Colors.lightBlueAccent.withValues(alpha: 0.15),
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
                text: _enabled ? 'Enabled' : 'Disabled \u2014 tap to enable',
                fontSize: 13.sp,
                textColor:
                    _enabled ? colors.textSecondary : Colors.orange.shade700,
              ),
              trailing: Switch(value: _enabled, onChanged: _toggle),
              onTap: () => _toggle(!_enabled),
            ),
    );
  }
}
