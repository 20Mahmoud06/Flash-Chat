import 'package:flutter/material.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../shared/widgets/custom_text.dart';

/// Calls need a live connection; show a friendly message instead of
/// starting a call that would immediately fail. Returns whether the call
/// may proceed.
bool ensureOnlineForCall(BuildContext context) {
  if (ConnectivityService.instance.isConnected.value) return true;
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
      content:
          CustomText(text: 'You are offline. You cannot make calls right now.'),
      backgroundColor: Colors.orange,
    ));
  return false;
}

/// Snackbar shown when my own account was deleted and I try to call.
void showMyDeletedCallMessage(BuildContext context) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(const SnackBar(
      content: CustomText(
          text: 'Your account was deleted. You can no longer make calls.'),
      backgroundColor: Colors.red,
    ));
}

/// Snackbar shown when the chat is blocked or the contact's account was
/// deleted, explaining why the call cannot start.
void showBlockedCallMessage(
  BuildContext context, {
  required bool accountDeleted,
  required bool iBlockedContact,
}) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: CustomText(
        text: accountDeleted
            ? 'This user has deleted their account. You cannot call them.'
            : iBlockedContact
                ? 'Unblock this user before calling.'
                : 'You cannot call this user.',
      ),
      backgroundColor: Colors.red.shade400,
    ));
}
