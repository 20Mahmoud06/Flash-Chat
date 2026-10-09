import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// Prompts for a contact nickname.
///
/// Returns `''` to remove the current nickname, the new nickname, or `null`
/// if the dialog was cancelled.
Future<String?> showSenderProfileNicknameDialog(
  BuildContext context, {
  required String? currentNickname,
  required String contactFullName,
}) async {
  final colors = FcAppColors.of(context);
  final controller = TextEditingController(text: currentNickname ?? '');
  final result = await showDialog<String>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      backgroundColor: colors.surface,
      title: CustomText(
        text: 'Nickname',
        fontSize: 18.sp,
        fontWeight: FontWeight.bold,
        textColor: colors.textPrimary,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomText(
            text: 'Only you can see this name. It replaces $contactFullName '
                'in your chats.',
            fontSize: 13.sp,
            textColor: colors.textSecondary,
          ),
          SizedBox(height: 14.h),
          TextField(
            controller: controller,
            autofocus: true,
            maxLength: 30,
            decoration: InputDecoration(
              hintText: 'Enter a nickname',
              hintStyle: TextStyle(color: colors.textWeak),
              filled: true,
              fillColor: colors.tile,
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide.none,
              ),
            ),
          ),
        ],
      ),
      actions: [
        if (currentNickname != null)
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, ''),
            child: CustomText(
              text: 'Remove',
              textColor: Colors.red.shade400,
              fontSize: 14.sp,
            ),
          ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext),
          child: CustomText(
            text: 'Cancel',
            textColor: Colors.grey,
            fontSize: 14.sp,
          ),
        ),
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, controller.text),
          child: CustomText(
            text: 'Save',
            textColor: Colors.lightBlueAccent,
            fontSize: 14.sp,
          ),
        ),
      ],
    ),
  );
  controller.dispose();
  return result;
}
