package com.example.flash_chat_app

import android.content.Context
import android.util.Log

/**
 * Records the per-conversation "last delivered message" watermark that the
 * Dart missed-notifications backfill reads on cold start.
 *
 * The value is written into the SAME SharedPreferences file the (legacy)
 * shared_preferences plugin uses on Android — `FlutterSharedPreferences` —
 * with the `flutter.` key prefix the plugin reserves for Dart keys. The key
 * body mirrors `lib/core/utils/notification_ids.dart`
 * `missedNotificationPrefKey` exactly, and the value is the delivery time in
 * milliseconds-since-epoch (always >= the message's server timestamp).
 *
 * Why: when the app is CLOSED the native FCM/HMS services render the chat
 * notification. If only the Dart side advanced the watermark, reopening the
 * app would re-notify those conversations — the backfill's only in-shade
 * dedup (getActiveNotifications) disappears the moment the user swipes the
 * notification away. Advancing the watermark at native delivery time makes
 * reopening idempotent: the next backfill sees no messages newer than the
 * watermark and never re-notifies what was already shown.
 */
object MissedNotifPrefs {
    private const val TAG = "MissedNotifPrefs"
    private const val PREFS_NAME = "FlutterSharedPreferences"
    private const val FLUTTER_PREFIX = "flutter."

    /** Marks a chat/group conversation as delivered at the current time. */
    fun markChatDelivered(context: Context, peerId: String, isGroup: Boolean) {
        val key = FLUTTER_PREFIX + peerKey(peerId, isGroup)
        try {
            context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
                .edit()
                .putLong(key, System.currentTimeMillis())
                .apply()
            Log.d(TAG, "Advanced delivered watermark for $peerId (group=$isGroup)")
        } catch (e: Exception) {
            Log.w(TAG, "Failed to advance delivered watermark: ${e.message}")
        }
    }

    /** Mirrors `missedNotificationPrefKey` in lib/core/utils/notification_ids.dart. */
    fun peerKey(peerId: String, isGroup: Boolean): String {
        val kind = if (isGroup) "group" else "chat"
        return "missed_notif_ts:$kind:$peerId"
    }
}