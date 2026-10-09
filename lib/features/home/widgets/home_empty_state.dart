import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import '../../../core/theme/app_theme.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../shared/widgets/custom_text.dart';

/// Friendly empty-state placeholder for the Chats / Groups tab.
class HomeEmptyState extends StatelessWidget {
  final String type; // 'Chats' | 'Groups'
  final String buttonLabel; // 'message' | 'add group'
  final String actionLabel; // 'chat' | 'group'

  const HomeEmptyState({
    super.key,
    required this.type,
    required this.buttonLabel,
    required this.actionLabel,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset('assets/animations/empty_chat.json',
              width: 250.w, height: 250.h),
          SizedBox(height: 24.h),
          CustomText(
              text: 'No $type Yet',
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              textColor: colors.textPrimary),
          SizedBox(height: 8.h),
          CustomText(
              text:
                  'Tap the $buttonLabel button to start a new $actionLabel 👇',
              textAlign: TextAlign.center,
              fontSize: 16.sp,
              textColor: colors.textSecondary),
        ],
      ),
    );
  }
}

/// Error / offline placeholder shown when a home query fails, explaining the
/// situation (offline saved data, or the raw error).
class HomeOfflineOrError extends StatelessWidget {
  final String error;
  final String thing;

  const HomeOfflineOrError({
    super.key,
    required this.error,
    required this.thing,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final offline = !ConnectivityService.instance.isConnected.value;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: CustomText(
          text: offline
              ? 'No saved $thing to read offline yet. Connect to the '
                  'internet once to save them for offline reading.'
              : 'Could not load $thing.\n$error',
          fontSize: 14.sp,
          textAlign: TextAlign.center,
          textColor: colors.textSecondary,
        ),
      ),
    );
  }
}
