import 'package:intl/intl.dart';

/// Formats a "last seen" timestamp the WhatsApp way:
/// "last seen today at 3:42 PM", "last seen yesterday at 9:15 PM",
/// "last seen on 12 Aug at 8:05 AM", or with the year when older.
String formatLastSeen(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final local = time.toLocal();
  final today = DateTime(current.year, current.month, current.day);
  final day = DateTime(local.year, local.month, local.day);
  final dayDiff = today.difference(day).inDays;
  final timeText = DateFormat('h:mm a').format(local);

  if (dayDiff == 0) return 'last seen today at $timeText';
  if (dayDiff == 1) return 'last seen yesterday at $timeText';

  final dateText = current.year == local.year
      ? DateFormat('d MMM').format(local)
      : DateFormat('d MMM yyyy').format(local);
  return 'last seen on $dateText at $timeText';
}

/// A short, relative variant meant for narrow places (e.g. the chat app-bar
/// subtitle) where the full "last seen today at h:mm" sentence would be
/// clipped. Returns things like "active 5 minutes ago"/"active 3 hours ago".
String formatLastSeenCompact(DateTime time, {DateTime? now}) {
  final current = now ?? DateTime.now();
  final local = time.toLocal();
  final diff = current.difference(local);

  if (diff.inMinutes < 1) return 'active now';
  if (diff.inMinutes < 60) return 'active ${diff.inMinutes} minutes ago';
  if (diff.inHours < 24) return 'active ${diff.inHours} hours ago';
  if (diff.inDays < 2) return 'active yesterday';
  return 'active ${diff.inDays} days ago';
}
