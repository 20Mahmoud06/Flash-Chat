import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../../../core/utils/last_seen_formatter.dart';
import '../../../services/presence/presence_service.dart';

/// App-bar subtitle for one-on-one chats.
///
/// Priority: Deleted Account / Blocked (static), then "typing…" while the
/// other person is typing, then "Online" (green), then "last seen …".
/// When the other user disabled their online status (no presence doc) or
/// has never been online, nothing is shown.
class ChatPresenceSubtitle extends StatelessWidget {
  const ChatPresenceSubtitle({
    super.key,
    required this.recipientUid,
    required this.typingStream,
    this.isDeleted = false,
    this.isBlocked = false,
  });

  final String? recipientUid;
  final Stream<List<String>> typingStream;
  final bool isDeleted;
  final bool isBlocked;

  @override
  Widget build(BuildContext context) {
    if (isDeleted) {
      return const _SubtitleText(text: 'Deleted Account');
    }
    if (isBlocked) {
      return const _SubtitleText(text: 'Blocked');
    }
    final uid = recipientUid;
    if (uid == null) return const SizedBox.shrink();

    return StreamBuilder<List<String>>(
      stream: typingStream,
      initialData: const <String>[],
      builder: (context, snapshot) {
        final typingUids = snapshot.data ?? const <String>[];
        if (typingUids.contains(uid)) {
          return const _SubtitleText(text: 'typing…', highlighted: true);
        }
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('presence')
              .doc(uid)
              .snapshots(),
          builder: (context, presenceSnapshot) {
            final data = presenceSnapshot.data;
            if (data == null || !data.exists) return const SizedBox.shrink();
            final lastSeen = data['lastSeen'];
            final isOnline = data['online'] == true;
            // If the owner was killed without going offline, the heartbeat
            // stops and the stale lastSeen reveals they're really offline.
            final isStale = lastSeen is Timestamp &&
                DateTime.now()
                        .difference(lastSeen.toDate())
                        .compareTo(PresenceService.presenceStaleAfter) >
                    0;
            if (isOnline && !isStale) {
              return const _SubtitleText(text: 'Online', highlighted: true);
            }
            if (lastSeen is Timestamp) {
              return _SubtitleText(
                text: formatLastSeenCompact(lastSeen.toDate()),
              );
            }
            return const SizedBox.shrink();
          },
        );
      },
    );
  }
}

class _SubtitleText extends StatelessWidget {
  const _SubtitleText({required this.text, this.highlighted = false});

  final String text;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(height: 1.h),
        CustomText(
          text: text,
          textColor: highlighted
              ? Colors.greenAccent
              : Colors.white.withValues(alpha: 0.85),
          fontWeight: FontWeight.w400,
          fontSize: 11.5.sp,
          overflow: TextOverflow.ellipsis,
          maxLines: 1,
        ),
      ],
    );
  }
}
