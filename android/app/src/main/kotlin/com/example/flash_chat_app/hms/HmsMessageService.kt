package com.example.flash_chat_app.hms

import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.os.Bundle
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import com.example.flash_chat_app.CallGuardStore
import com.example.flash_chat_app.MainActivity
import com.example.flash_chat_app.MissedNotifPrefs
import com.example.flash_chat_app.NotificationChannels
import com.example.flash_chat_app.R
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import com.huawei.hms.push.HmsMessageService
import com.huawei.hms.push.RemoteMessage
import org.json.JSONObject
import java.util.Date

/**
 * Receives HMS Push Kit messages even when the app is killed or in the
 * background. Because chat pushes are sent data-only on HMS, this service
 * renders the notification natively (including the direct REPLY action that a
 * system-delivered notification cannot offer) and launches the full CallKit
 * incoming-call UI for call pushes.
 */
class HmsMessageService : HmsMessageService() {

    private val notificationManager: NotificationManager
        get() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override fun onNewToken(token: String?) {
        super.onNewToken(token)
        HmsPushBridge.attach(applicationContext)
        if (token.isNullOrEmpty()) return
        HmsPushBridge.storeToken(applicationContext, token)
        Log.d(TAG, "HMS token: $token")
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        HmsPushBridge.attach(applicationContext)

        val data = message.dataOfMap
        if (data.isEmpty()) return

        // The v1 messages:send API delivers the data payload as a JSON string
        // under the "data" key; the SDK usually parses it into dataOfMap, but
        // fall back to parsing it here when it is still a string.
        val payload = if (data.containsKey("type")) {
            data
        } else {
            data["data"]?.let { parsePayload(it) } ?: return
        }

        if (HmsPushBridge.isAppInForeground) {
            // The Flutter engine is running; let Dart render with the same
            // active-chat suppression and CallKit logic as FCM messages.
            HmsPushBridge.emitForegroundMessage(payload)
            return
        }

        when (payload["type"]) {
            "call" -> showCall(payload)
            "chat", "group_chat" -> handleChatPush(payload)
            else -> Log.w(TAG, "Ignoring unknown push type: ${payload["type"]}")
        }
    }

    // ---------------- CALLS ----------------

    private fun showCall(payload: Map<String, String>) {
        val callId = payload["callId"] ?: return
        val isVideo = payload["isVideo"] == "true"
        val isGroup = payload["isGroup"] == "true"

        // Never re-ring an already-handled call (a ring was shown before, it
        // timed out to no_answer, it was accepted/declined via the decision
        // receiver, or Dart marked it through the call-guard bridge). For
        // 1-to-1 calls post the single missed-call notification and leave it
        // at the same per-call notification id so it never stacks. Group calls
        // are suppressed silently — the group call doc keeps ringing for the
        // other members and no missed-call notification is shown natively.
        if (CallGuardStore.isHandled(applicationContext, callId)) {
            if (!isGroup) {
                val callerName = payload["callerName"] ?: "Unknown"
                NotificationChannels.postMissedCallNotification(
                    applicationContext, callId, callerName, isVideo
                )
            }
            Log.d(TAG, "Suppressed re-ring for handled call: $callId")
            return
        }

        val callerName = if (isGroup) {
            payload["groupName"] ?: "Unknown"
        } else {
            payload["callerName"] ?: "Unknown"
        }

        val data = Bundle()
        data.putString(CallkitConstants.EXTRA_CALLKIT_ID, callId)
        data.putString(CallkitConstants.EXTRA_CALLKIT_NAME_CALLER, callerName)
        data.putString(CallkitConstants.EXTRA_CALLKIT_HANDLE, "Flash Chat")
        data.putInt(CallkitConstants.EXTRA_CALLKIT_TYPE, if (isVideo) 1 else 0)
        // For group calls show the group emoji; for 1-to-1 calls show the caller's avatar.
        val avatarToShow = if (isGroup) payload["groupAvatar"].orEmpty()
                           else payload["callerAvatar"].orEmpty()
        data.putString(CallkitConstants.EXTRA_CALLKIT_AVATAR, avatarToShow)
        data.putLong(CallkitConstants.EXTRA_CALLKIT_DURATION, RING_TIMEOUT_MS)
        data.putString(CallkitConstants.EXTRA_CALLKIT_TEXT_ACCEPT, "Accept")
        data.putString(CallkitConstants.EXTRA_CALLKIT_TEXT_DECLINE, "Decline")
        data.putBoolean(CallkitConstants.EXTRA_CALLKIT_IS_CUSTOM_NOTIFICATION, true)
        data.putBoolean(CallkitConstants.EXTRA_CALLKIT_IS_SHOW_FULL_LOCKED_SCREEN, true)
        data.putString(CallkitConstants.EXTRA_CALLKIT_RINGTONE_PATH, "ringtone")
        data.putString(CallkitConstants.EXTRA_CALLKIT_BACKGROUND_COLOR, "#000000")
        data.putString(CallkitConstants.EXTRA_CALLKIT_ACTION_COLOR, "#4CAF50")
        data.putBoolean(CallkitConstants.EXTRA_CALLKIT_IS_NATIVE_PUSH, true)

        val extra = HashMap<String, Any?>()
        extra["callId"] = callId
        extra["isVideo"] = isVideo.toString()
        extra["callerId"] = payload["callerId"]
        extra["callerName"] = payload["callerName"]
        extra["callerAvatar"] = payload["callerAvatar"]
        extra["isGroup"] = payload["isGroup"] ?: "false"
        if (payload.containsKey("groupId")) extra["groupId"] = payload["groupId"]
        if (payload.containsKey("groupName")) extra["groupName"] = payload["groupName"]
        if (payload.containsKey("groupAvatar")) extra["groupAvatar"] = payload["groupAvatar"]
        if (payload.containsKey("groupBio")) extra["groupBio"] = payload["groupBio"]
        if (payload.containsKey("receiverId")) extra["receiverId"] = payload["receiverId"]
        if (payload.containsKey("receiverAvatar")) extra["receiverAvatar"] = payload["receiverAvatar"]
        data.putSerializable(CallkitConstants.EXTRA_CALLKIT_EXTRA, extra)

        NotificationChannels.postFullScreenCallRing(applicationContext, data, callId)

        // Persist the guard so a re-delivered push or a Firestore snapshot on the
        // next app open never re-rings the same call. Applied to both 1-to-1 and
        // group calls: for groups this only suppresses re-ring on THIS device —
        // other members' devices have their own guard entries.
        CallGuardStore.markHandled(applicationContext, callId)

        scheduleTimeoutAsync(callId, callerName, isVideo, isGroup, payload["receiverId"])
    }

    /**
     * Best-effort Firestore safety net: after [RING_TIMEOUT_MS], if the call is
     * still ringing (nobody accepted / the receiver was offline / killed), mark
     * it `no_answer` so the caller gets a correct outcome and no call is orphaned.
     * Also marks the id handled and posts the single missed-call notification so
     * a re-delivered push does not ring again.
     *
     * For GROUP calls the timeout is member-scoped: `participantStatus.<uid>` is
     * set to `no_answer` for THIS device's member and the shared `status` is left
     * alone. The caller's own ring timeout (or the orphan resolver) is the only
     * thing allowed to flip a group call globally, so one member ignoring the
     * ring never kills a call the rest of the group is in.
     */
    private fun scheduleTimeoutAsync(
        callId: String,
        callerName: String,
        isVideo: Boolean,
        isGroup: Boolean,
        receiverId: String?
    ) {
        Thread {
            Thread.sleep(RING_TIMEOUT_MS)
            try {
                val callDoc = com.google.android.gms.tasks.Tasks.await(
                    com.google.firebase.firestore.FirebaseFirestore.getInstance()
                        .collection("calls")
                        .document(callId)
                        .get()
                )
                val status = callDoc.data?.get("status") as? String
                if (status == "ringing") {
                    if (isGroup) {
                        // 1:1 behaviour is untouched; a group member's ignored
                        // ring only records that member's own no-answer.
                        if (!receiverId.isNullOrEmpty()) {
                            com.google.android.gms.tasks.Tasks.await(
                                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                                    .collection("calls")
                                    .document(callId)
                                    .update("participantStatus.$receiverId", "no_answer")
                            )
                        }
                    } else {
                        com.google.android.gms.tasks.Tasks.await(
                            com.google.firebase.firestore.FirebaseFirestore.getInstance()
                                .collection("calls")
                                .document(callId)
                                .update("status", "no_answer")
                        )
                        // Single missed-call notification + guard: a re-delivered
                        // push must never ring this call again.
                        CallGuardStore.markHandled(applicationContext, callId)
                        NotificationChannels.postMissedCallNotification(
                            applicationContext, callId, callerName, isVideo
                        )
                    }
                    Log.d(TAG, "Ring timed out natively: $callId")
                }
            } catch (t: Throwable) {
                Log.w(TAG, "Native ring timeout update failed: ${t.message}")
            }
        }.start()
    }

    // ---------------- CHAT / GROUP NOTIFICATIONS ----------------

    /**
     * Entry point for HMS chat/group pushes rendered natively (app killed or
     * in the background). Honors the per-contact mute stored in
     * `users/{me}/mutedChats.<peerUid>` for 1-to-1 chats, mirroring the Dart
     * foreground check, so a muted contact stays silent even when a push
     * reaches this device.
     */
    private fun handleChatPush(payload: Map<String, String>) {
        if (!notificationsEnabled()) return

        val peerId = payload["senderId"] ?: payload["groupId"] ?: return
        val isGroup = payload["type"] == "group_chat"

        if (!isGroup) {
            Thread {
                if (peerIsMuted(payload["senderId"])) {
                    Log.d(TAG, "Suppressed notification from muted contact $peerId")
                    return@Thread
                }
                renderChatNotification(payload, peerId, isGroup)
            }.start()
            return
        }
        renderChatNotification(payload, peerId, isGroup)
    }

    /**
     * True when the current user muted [peerUid] (per-contact `mutedChats` on
     * my own user doc). `until == null` means muted forever; a stored Timestamp
     * means muted until that moment. Best-effort: if the lookup fails we show
     * the notification rather than risk dropping a message.
     */
    private fun peerIsMuted(peerUid: String?): Boolean {
        if (peerUid.isNullOrEmpty()) return false
        return try {
            val me = FirebaseAuth.getInstance().currentUser?.uid ?: return false
            val doc = com.google.android.gms.tasks.Tasks.await(
                FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(me)
                    .get()
            )
            val entry = (doc.data?.get("mutedChats") as? Map<*, *>)?.get(peerUid)
            if (entry !is Map<*, *>) return false
            val until = entry["until"]
            if (until == null) return true
            val ts = until as? com.google.firebase.Timestamp ?: return true
            ts.toDate().after(Date())
        } catch (t: Throwable) {
            Log.w(TAG, "Mute lookup failed (showing notification): ${t.message}")
            false
        }
    }

    private fun renderChatNotification(
        payload: Map<String, String>,
        peerId: String,
        isGroup: Boolean
    ) {
        createChannel()

        val id = notificationId(peerId, isGroup)
        val title = payload["title"] ?: "New message"
        val body = payload["body"] ?: ""

        val payloadJson = JSONObject(payload).toString()

        // Tap -> open the chat (FlutterActivity picks it up via onCreate /
        // onNewIntent and forwards it through HmsPushBridge).
        val tapIntent = Intent(applicationContext, MainActivity::class.java).apply {
            action = Intent.ACTION_MAIN
            addCategory(Intent.CATEGORY_LAUNCHER)
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(HmsPushBridge.EXTRA_PAYLOAD, payloadJson)
        }
        val contentIntent = PendingIntent.getActivity(
            applicationContext,
            id,
            tapIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val builder = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(BitmapFactory.decodeResource(applicationContext.resources, R.mipmap.ic_launcher))
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setContentIntent(contentIntent)
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(Color.parseColor("#4CAF50"))
            // Pre-Oreo devices have no channel sound; set it per-notification
            // (single-arg setSound also sets USAGE_NOTIFICATION attributes).
            .setSound(NotificationChannels.soundUri(applicationContext))

        try {
            notificationManager.notify(id, builder.build())
            Log.d(TAG, "Notification shown for $peerId (id=$id)")
            // Advance the Dart-side delivered watermark so the next app-open
            // backfill never re-notifies this conversation — even after the
            // user swipes this notification away.
            MissedNotifPrefs.markChatDelivered(applicationContext, peerId, isGroup)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show notification: ${e.message}")
        }
    }

    // ---------------- HELPERS ----------------

    private fun createChannel() {
        NotificationChannels.createChatChannel(applicationContext)
    }

    private fun notificationsEnabled(): Boolean {
        return try {
            NotificationManagerCompat.from(applicationContext).areNotificationsEnabled()
        } catch (e: Exception) {
            true
        }
    }

    private fun parsePayload(json: String): Map<String, String> {
        return try {
            val obj = JSONObject(json)
            val result = LinkedHashMap<String, String>()
            val keys = obj.keys()
            while (keys.hasNext()) {
                val key = keys.next() as String
                val value = obj.optString(key)
                if (value.isNotEmpty()) result[key] = value
            }
            result
        } catch (e: Exception) {
            emptyMap()
        }
    }

    companion object {
        private const val TAG = "HmsMessageService"
        const val CHANNEL_ID = NotificationChannels.CHANNEL_ID
        const val CHANNEL_NAME = NotificationChannels.CHANNEL_NAME

        /// 30 seconds, matching the caller-side ring timeout.
        private const val RING_TIMEOUT_MS = 30_000L

        /**
         * FNV-1a 64-bit hash, byte-for-byte identical to
         * lib/core/utils/notification_ids.dart so Dart can cancel the native
         * notification ids when a chat is opened.
         */
        fun fnv1a64(input: String): Long {
            var hash = -3750763034362895579L // 0xcbf29ce484222325
            val prime = 1099511628211L // 0x100000001b3
            for (unit in input) {
                hash = (hash xor unit.code.toLong()) * prime
            }
            return hash
        }

        fun notificationId(peerId: String, isGroup: Boolean): Int {
            val base = (fnv1a64(peerId) and 0xFFFFF).toInt()
            return if (isGroup) 2000000 + base else base
        }
    }
}
