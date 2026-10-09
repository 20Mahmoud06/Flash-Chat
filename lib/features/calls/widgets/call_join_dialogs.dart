import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/core/routes/navigation_service.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import '../services/call_service.dart';

/// Themed "call is full" dialog shown when a user tries to join a group call
/// that is already at its 9-participant limit.
Future<void> showCallFullDialog(BuildContext context) {
  return showDialog<void>(
    context: context,
    builder: (dialogContext) => const _CallNoticeDialog(
      icon: Icons.group_off_rounded,
      iconColor: AppColors.callStatusAmber,
      title: 'Call is full',
      message:
          'This call has reached its limit of '
          '${CallService.maxCallParticipants} participants.\n'
          'Please try joining again later.',
    ),
  );
}

/// Global variant that needs no caller-held [BuildContext]. Used from
/// background / CallKit paths where only the app-level navigator is available.
Future<void> showCallFullDialogGlobal() async {
  final context = navigatorKey.currentContext;
  if (context == null) return;
  await showCallFullDialog(context);
}

/// Themed snackbar for messages raised outside a widget (warnings, join
/// feedback). Uses the app-level navigator so it works from the call bloc and
/// background services. Falls back silently when no messenger is mounted.
void showAppSnackBar(
  String message, {
  Color? background,
  Color textColor = Colors.white,
}) {
  final context = navigatorKey.currentContext;
  final messenger = context == null
      ? null
      : ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: background ?? AppColors.callBackgroundMiddle,
        margin: const EdgeInsets.only(left: 16, right: 16, bottom: 90),
        duration: const Duration(seconds: 4),
        content: CustomText(
          text: message,
          textColor: textColor,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
}

class _CallNoticeDialog extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;
  final String message;

  const _CallNoticeDialog({
    required this.icon,
    required this.iconColor,
    required this.title,
    required this.message,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: AppColors.callCardBg,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 28, 24, 20),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 64,
              height: 64,
              decoration: BoxDecoration(
                color: iconColor.withValues(alpha: 0.16),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: iconColor, size: 32),
            ),
            const SizedBox(height: 18),
            CustomText(
              text: title,
              textColor: Colors.white,
              fontSize: 18,
              fontWeight: FontWeight.bold,
            ),
            const SizedBox(height: 10),
            CustomText(
              text: message,
              textColor: Colors.white70,
              fontSize: 13.5,
              height: 1.4,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            SizedBox(
              width: double.infinity,
              height: 46,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: AppColors.primary,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(14),
                  ),
                ),
                onPressed: () => Navigator.of(context).pop(),
                child: const CustomText(
                  text: 'Got it',
                  textColor: Colors.black,
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}