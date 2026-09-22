import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../../core/theme/app_theme.dart';
import '../../../profile/models/user_model.dart';
import '../../../../shared/widgets/custom_text.dart';

/// Modal listing everyone who reacted to a message (or to one photo inside a
/// multi-image message). Tapping your own row removes your reaction.
void showMessageReactionsDialog(
  BuildContext context, {
  required Map<String, String> reactions,
  required Map<String, UserModel> members,
  required VoidCallback onRemoveMyReaction,
}) {
  final currentUser = FirebaseAuth.instance.currentUser!;
  showDialog(
    context: context,
    builder: (ctx) => AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15.r)),
      title: CustomText(
          text: "Reactions",
          fontWeight: FontWeight.bold,
          textColor: FcAppColors.of(ctx).textPrimary),
      content: SizedBox(
        width: double.maxFinite,
        child: ListView.builder(
          shrinkWrap: true,
          itemCount: reactions.length,
          itemBuilder: (context, index) {
            final uid = reactions.keys.elementAt(index);
            final emoji = reactions[uid]!;
            final user = members[uid];
            final isMe = uid == currentUser.uid;
            final name = isMe
                ? 'You'
                : (user != null
                    ? '${user.firstName} ${user.lastName}'
                    : 'Unknown');
            return ListTile(
              leading: CustomText(text: emoji, fontSize: 20.sp),
              title: CustomText(text: name),
              trailing: isMe
                  ? Icon(Icons.close,
                      size: 18.sp, color: FcAppColors.of(ctx).textWeak)
                  : null,
              onTap: isMe
                  ? () {
                      onRemoveMyReaction();
                      Navigator.of(ctx).pop();
                    }
                  : null,
            );
          },
        ),
      ),
      actions: [
        ElevatedButton(
          style: ElevatedButton.styleFrom(
              backgroundColor: Colors.lightBlueAccent),
          onPressed: () => Navigator.of(ctx).pop(),
          child: const CustomText(
              text: "OK",
              fontWeight: FontWeight.bold,
              textColor: Colors.white),
        ),
      ],
    ),
  );
}

/// Compact WhatsApp-style pill showing the reactions on a single photo.
class MessageBubbleReactionPill extends StatelessWidget {
  final Map<String, String> reactions;
  final Color backgroundColor;

  const MessageBubbleReactionPill({
    super.key,
    required this.reactions,
    required this.backgroundColor,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10.r),
        border: Border.all(color: colors.surfaceDim, width: 1),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 4,
            spreadRadius: 0.5,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          CustomText(
            text: reactions.values.toSet().join(''),
            fontSize: 12.sp,
          ),
          if (reactions.length > 1) ...[
            SizedBox(width: 3.w),
            CustomText(
              text: '${reactions.length}',
              textColor: colors.textSecondary,
              fontSize: 10.5.sp,
              fontWeight: FontWeight.bold,
            ),
          ],
        ],
      ),
    );
  }
}