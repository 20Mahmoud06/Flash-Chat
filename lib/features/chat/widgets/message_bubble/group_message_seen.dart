import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../profile/models/user_model.dart';
import '../../models/message_model.dart';

/// One group member who had already read a message. `seenAt` is that member's
/// `lastSeen` watermark on the group doc.
class GroupMessageSeenByEntry {
  final UserModel user;
  final DateTime seenAt;

  const GroupMessageSeenByEntry({required this.user, required this.seenAt});
}

/// The group members (excluding [myUid]) who were present when [message] was
/// sent AND had already read it — i.e. their per-member `lastSeen` watermark on
/// the group doc is at or after the message timestamp. `memberJoinTimestamps`
/// prunes members who joined after the message was sent (they can never have
/// seen it, so they must not be counted at all).
///
/// Drives the blue double-tick on own bubbles and the "Seen by …" info lines.
List<GroupMessageSeenByEntry> groupMessageSeenBy({
  required MessageModel message,
  required Map<String, UserModel> members,
  required Map<String, Timestamp> memberLastSeen,
  required Map<String, Timestamp> memberJoinTimestamps,
  required String myUid,
}) {
  final sentAt = message.timestamp.toDate();
  final result = <GroupMessageSeenByEntry>[];

  for (final entry in members.entries) {
    final uid = entry.key;
    if (uid == myUid) continue;

    final joinTime = memberJoinTimestamps[uid];
    if (joinTime != null && joinTime.toDate().compareTo(sentAt) > 0) {
      continue; // Joined after the message was sent.
    }

    final lastSeen = memberLastSeen[uid];
    if (lastSeen == null) continue;
    final seenAt = lastSeen.toDate();
    if (seenAt.compareTo(sentAt) < 0) continue;

    result.add(GroupMessageSeenByEntry(user: entry.value, seenAt: seenAt));
  }

  return result;
}

/// The number of members who were present when [message] was sent and could
/// have seen it (excluding [myUid]) — the denominator for "seen by everyone".
int groupMessageSeenTotal({
  required MessageModel message,
  required Map<String, UserModel> members,
  required Map<String, Timestamp> memberJoinTimestamps,
  required String myUid,
}) {
  final sentAt = message.timestamp.toDate();
  int count = 0;

  for (final entry in members.entries) {
    if (entry.key == myUid) continue;
    final joinTime = memberJoinTimestamps[entry.key];
    if (joinTime != null && joinTime.toDate().compareTo(sentAt) > 0) {
      continue; // Joined after the message was sent.
    }
    count++;
  }

  return count;
}