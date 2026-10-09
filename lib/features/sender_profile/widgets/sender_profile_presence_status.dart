import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/utils/last_seen_formatter.dart';
import '../../profile/models/user_model.dart';
import '../../../services/presence/presence_service.dart';
import '../../../shared/widgets/custom_text.dart';

/// Live presence status shown right under the contact's name.
///
/// "Online" (green) while the user is actively online; otherwise a relative
/// "active X minutes ago" from their last seen. Nothing is shown when they
/// disabled their online status or have never been online.
class SenderProfilePresenceStatus extends StatelessWidget {
  final UserModel user;

  const SenderProfilePresenceStatus({super.key, required this.user});

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    if (user.isDeleted) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('presence')
          .doc(user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || !data.exists) return const SizedBox.shrink();
        final lastSeen = data['lastSeen'];
        final isOnline = data['online'] == true;
        final isStale = lastSeen is Timestamp &&
            DateTime.now()
                    .difference(lastSeen.toDate())
                    .compareTo(PresenceService.presenceStaleAfter) >
                0;
        if (isOnline && !isStale) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8.w,
                height: 8.w,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 6.w),
              CustomText(
                text: 'Online',
                fontSize: 14.sp,
                textColor: Colors.greenAccent,
                fontWeight: FontWeight.w600,
              ),
            ],
          );
        }
        if (lastSeen is Timestamp) {
          return CustomText(
            text: formatLastSeenCompact(lastSeen.toDate()),
            fontSize: 14.sp,
            textColor: colors.textSecondary,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }
}