import 'package:flutter/material.dart';
import 'package:quickalert/quickalert.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../profile/models/user_model.dart';
import '../cubit/sender_profile_cubit.dart';

/// Shows the "Block user?" confirmation dialog and performs the block when the
/// user confirms, reporting the outcome with a snack bar.
///
/// Mirrors the current channel state; the dialog reads the view's own theme
/// colors so it stays consistent with the rest of the app.
Future<void> showSenderProfileBlockConfirmation({
  required BuildContext context,
  required UserModel user,
  required SenderProfileCubit cubit,
}) async {
  await QuickAlert.show(
    context: context,
    type: QuickAlertType.confirm,
    title: 'Block ${user.fullName}?',
    text: 'You will no longer receive messages or calls from this user. '
        'You can unblock them anytime from your profile.',
    confirmBtnText: 'Block',
    cancelBtnText: 'Cancel',
    confirmBtnColor: Colors.red.shade400,
    showCancelBtn: true,
    backgroundColor: FcAppColors.of(context).surface,
    headerBackgroundColor: FcAppColors.of(context).surface,
    titleColor: FcAppColors.of(context).textPrimary,
    textColor: FcAppColors.of(context).textSecondary,
    onConfirmBtnTap: () async {
      Navigator.of(context, rootNavigator: true).pop();
      try {
        await cubit.blockUser();
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: CustomText(text: '${user.fullName} has been blocked'),
              backgroundColor: Colors.red.shade400,
            ),
          );
        }
      } catch (e) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: CustomText(text: 'Failed to block user. Try again.'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    },
  );
}