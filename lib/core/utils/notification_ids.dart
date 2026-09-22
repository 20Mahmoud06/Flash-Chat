/// FNV-1a 64-bit hashing for deterministic notification ids.
///
/// The native HMS notification code in
/// android/app/src/main/kotlin/com/example/flash_chat_app/hms/HmsMessageService.kt
/// implements the exact same algorithm, so Dart can cancel notifications that
/// the native service showed (and vice versa) without sharing state.
library;

int fnv1a64(String input) {
  // 0xcbf29ce484222325 as a signed 64-bit int (same bit pattern).
  var hash = -3750763034362895579;
  const prime = 1099511628211; // 0x100000001b3
  for (final unit in input.codeUnits) {
    hash = (hash ^ unit) * prime;
  }
  return hash;
}

/// Stable notification id for a conversation. `peerId` is the contact uid for
/// 1-to-1 chats and the group id for group chats.
int conversationNotificationId(String peerId, {required bool isGroup}) {
  final base = fnv1a64(peerId) & 0xFFFFF;
  return isGroup ? 2000000 + base : base;
}

/// The JVM `String.hashCode()` polynomial (`h = h * 31 + c`, 32-bit
/// overflow), byte-for-byte identical to the Kotlin `String.hashCode()` that
/// `NotificationChannels.callNotificationId()` uses. This lets Dart reproduce
/// the native per-call notification id so a missed-call notification replaces
/// the same Android `CallNotification` slot instead of stacking a second one.
int javaStringHash(String input) {
  var hash = 0;
  for (final unit in input.codeUnits) {
    hash = (hash * 31 + unit) & 0xFFFFFFFF;
  }
  return hash;
}

/// Stable notification id for a specific call — a bucket separate from chat
/// ids, identical to `NotificationChannels.callNotificationId()` on the native
/// side. The ring and the missed-call notification for the same call share this
/// one id, so across Dart + native and across app opens there is at most ONE
/// active notification per call.
int callNotificationId(String callId) =>
    3000000 + (javaStringHash(callId) & 0xFFFFF);

/// SharedPreferences key prefix for the per-conversation "last delivered
/// message" watermark used by the offline backfill.
const String missedNotificationsPrefsPrefix = 'missed_notif_ts';

/// Device-local key tracking the latest message already delivered/notified for
/// a conversation. Advanced by the Dart backfill and foreground listeners AND
/// by the native FCM/HMS services when they render a notification while the
/// app is closed — so a message that was already shown on the lock screen is
/// never re-notified by the next app-open backfill, even after the user swiped
/// the notification away (when `getActiveNotifications` can no longer dedup).
///
/// The Android side writes the exact same key (prefixed with `flutter.`, the
/// prefix the shared_preferences legacy API reserves) into the
/// `FlutterSharedPreferences` XML — see `android/.../MissedNotifPrefs.kt`.
String missedNotificationPrefKey(String peerId, {required bool isGroup}) =>
    '$missedNotificationsPrefsPrefix:${isGroup ? 'group' : 'chat'}:$peerId';
