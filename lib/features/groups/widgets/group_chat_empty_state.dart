import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/theme/app_theme.dart';
import '../../../shared/widgets/custom_text.dart';

/// Empty-group-chat placeholder. When the user just joined (or created) the
/// group it explains the "joined" state; otherwise it keeps the generic
/// "Say hello! 👋" greeting.
class GroupChatEmptyState extends StatelessWidget {
  /// The timestamp I joined this group, or null when unknown.
  final DateTime? joinTimestamp;

  /// True when the current user is the group creator (only meaningful when
  /// [joinTimestamp] is set).
  final bool iCreatedGroup;

  const GroupChatEmptyState({
    super.key,
    required this.joinTimestamp,
    required this.iCreatedGroup,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);

    if (joinTimestamp != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.group_add,
              size: 56,
              color: Colors.lightBlue.shade200,
            ),
            SizedBox(height: 12.h),
            CustomText(
              text: iCreatedGroup
                  ? 'You created this group'
                  : 'You joined this group',
              textAlign: TextAlign.center,
              fontSize: 18.sp,
              fontWeight: FontWeight.bold,
              textColor: colors.textSecondary,
            ),
            SizedBox(height: 8.h),
            CustomText(
              text: iCreatedGroup
                  ? 'Start the conversation by sending the '
                      'first message!'
                  : 'You can only see messages sent after you '
                      'joined',
              textAlign: TextAlign.center,
              fontSize: 14.sp,
              textColor: colors.textWeak,
            ),
          ],
        ),
      );
    }

    return const Center(child: CustomText(text: "Say hello! 👋"));
  }
}
