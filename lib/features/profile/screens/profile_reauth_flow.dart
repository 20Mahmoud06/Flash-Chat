import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/theme/app_theme.dart';
import '../../auth/services/auth.dart';
import '../../../shared/widgets/custom_text_form_field.dart';
import '../cubit/profile_cubit.dart';

/// Starts the account-deletion flow. For email/password accounts the user is
/// first asked to re-enter their password; for Google accounts a fresh
/// Google sign-in is triggered.
void beginDeleteAccount(BuildContext context) {
  final cubit = context.read<ProfileCubit>();
  final authService = AuthService();
  if (authService.primaryProvider == 'google.com') {
    cubit.reauthenticateAndDelete();
  } else {
    promptForPasswordAndDelete(context);
  }
}

/// Defensive handler for `ProfileReauthRequired`: prompts for credentials
/// again and retries the delete.
Future<void> handleReauth(BuildContext context) async {
  final authService = AuthService();
  if (authService.primaryProvider == 'google.com') {
    final ok = await authService.reauthenticateWithGoogle();
    if (ok && context.mounted) {
      context.read<ProfileCubit>().deleteAccount();
    }
  } else {
    await promptForPasswordAndDelete(context);
  }
}

/// Shows a password dialog for email/password accounts and, on success,
/// asks the bloc to re-authenticate and delete.
Future<void> promptForPasswordAndDelete(BuildContext context) async {
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
        title: CustomText(
          text: 'Confirm Password',
          textColor: colors.textPrimary,
          fontWeight: FontWeight.bold,
          textAlign: TextAlign.center,
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
            child: CustomText(text: 'Cancel', textColor: colors.textSecondary),
          ),
          TextButton(
            onPressed: () {
              if (formKey.currentState!.validate()) {
                password = controller.text;
                Navigator.pop(dialogContext, true);
              }
            },
            child: const CustomText(
              text: 'Continue',
              textColor: Colors.lightBlueAccent,
            ),
          ),
        ],
      );
    },
  );

  if (entered != true || !context.mounted) return;
  context.read<ProfileCubit>().reauthenticateAndDelete(password: password);
}