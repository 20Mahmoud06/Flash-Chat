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
import com.example.flash_chat_app.MainActivity
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
        val callerName = payload["callerName"] ?: "Unknown"
        val isVideo = payload["isVideo"] == "true"
        val isGroup = payload["isGroup"] == "true"
        val callerId = payload["callerId"]

        val data = Bundle()
        data.putString(CallkitConstants.EXTRA_CALLKIT_ID, callId)
        data.putString(CallkitConstants.EXTRA_CALLKIT_NAME_CALLER, callerName)
        data.putString(CallkitConstants.EXTRA_CALLKIT_HANDLE, "Flash Chat")
        data.putInt(CallkitConstants.EXTRA_CALLKIT_TYPE, if (isVideo) 1 else 0)
        data.putString(CallkitConstants.EXTRA_CALLKIT_AVATAR, payload["callerAvatar"].orEmpty())
        data.putLong(CallkitConstants.EXTRA_CALLKIT_DURATION, RING_TIMEOUT_MS)
        data.putString(CallkitConstants.EXTRA_CALLKIT_TEXT_ACCEPT, "Accept")
        data.putString(CallkitConstants.EXTRA_CALLKIT_TEXT_DECLINE, "Decline")
        data.putBoolean(CallkitConstants.EXTRA_CALLKIT_IS_CUSTOM_NOTIFICATION, true)
        data.putBoolean(CallkitConstants.EXTRA_CALLKIT_IS_SHOW_FULL_LOCKED_SCREEN, true)
        // The app's own incoming-call ringtone (res/raw/ringtone.wav). The
        // CallKit sound manager resolves this raw resource and loops it on the
        // RING stream, stopping it on accept/decline/timeout/end.
        data.putString(CallkitConstants.EXTRA_CALLKIT_RINGTONE_PATH, "ringtone")
        data.putString(CallkitConstants.EXTRA_CALLKIT_BACKGROUND_COLOR, "#000000")
        data.putString(CallkitConstants.EXTRA_CALLKIT_ACTION_COLOR, "#4CAF50")

        // The accept/decline events surface this map back to Dart via the
        // plugin's event channel (CallArguments.fromMap), so it must mirror
        // the extra map the Dart-side showIncomingCall() builds.
        val extra = HashMap<String, Any?>()
        extra["callId"] = callId
        extra["isVideo"] = isVideo.toString()
        extra["callerId"] = callerId
        extra["callerName"] = callerName
        extra["callerAvatar"] = payload["callerAvatar"]
        extra["isGroup"] = payload["isGroup"] ?: "false"
        if (payload.containsKey("groupId")) extra["groupId"] = payload["groupId"]
        if (payload.containsKey("groupName")) extra["groupName"] = payload["groupName"]
        if (payload.containsKey("groupAvatar")) extra["groupAvatar"] = payload["groupAvatar"]
        if (payload.containsKey("groupBio")) extra["groupBio"] = payload["groupBio"]
        if (payload.containsKey("receiverId")) extra["receiverId"] = payload["receiverId"]
        if (payload.containsKey("receiverAvatar")) extra["receiverAvatar"] = payload["receiverAvatar"]
        data.putSerializable(CallkitConstants.EXTRA_CALLKIT_EXTRA, extra)

        // Resolve the receiver's nickname for the caller (shown instead of the
        // real name in the ring) on a worker thread, then launch the ring once
        // the display name is final.
        resolveAndLaunchRing(data, isGroup, callerId, callerName, payload["groupName"])

        // Native no-answer safety net (mirrors the GMS path): if the call is
        // still ringing after the ring window, mark it no_answer.
        scheduleTimeoutAsync(callId)
    }

    private fun resolveAndLaunchRing(
        data: Bundle,
        isGroup: Boolean,
        callerId: String?,
        callerName: String?,
        groupName: String?
    ) {
        Thread {
            try {
                val baseName = if (isGroup) groupName else callerName
                val displayName = if (!isGroup && callerId != null) {
                    resolveNickname(callerId) ?: (baseName ?: "Unknown")
                } else {
                    baseName ?: "Unknown"
                }
                data.putString(CallkitConstants.EXTRA_CALLKIT_NAME_CALLER, displayName)
                launchRing(data)
            } catch (t: Throwable) {
                Log.w(TAG, "Failed to resolve name; launching with payload name: ${t.message}")
                launchRing(data)
            }
        }.start()
    }

    private fun launchRing(data: Bundle) {
        val callId = data.getString(CallkitConstants.EXTRA_CALLKIT_ID) ?: return
        // Marker: the ring screen plays the ringtone/vibration itself ONLY when
        // a native push launched it (the plugin path in the foreground already
        // plays it through CallkitNotificationManager — never double-ring).
        data.putBoolean(CallkitConstants.EXTRA_CALLKIT_IS_NATIVE_PUSH, true)
        NotificationChannels.postFullScreenCallRing(applicationContext, data, callId)
    }

    private fun resolveNickname(callerId: String): String? {
        return try {
            val me = com.google.firebase.auth.FirebaseAuth.getInstance().currentUser?.uid
                ?: return null
            val doc = com.google.android.gms.tasks.Tasks.await(
                com.google.firebase.firestore.FirebaseFirestore.getInstance()
                    .collection("users")
                    .document(me)
                    .get()
            )
            (doc.data?.get("nicknames") as? Map<*, *>)?.get(callerId)?.toString()
        } catch (t: Throwable) {
            Log.w(TAG, "Nickname lookup failed (using payload name): ${t.message}")
            null
        }
    }

    private fun scheduleTimeoutAsync(callId: String) {
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
                    com.google.android.gms.tasks.Tasks.await(
                        com.google.firebase.firestore.FirebaseFirestore.getInstance()
                            .collection("calls")
                            .document(callId)
                            .update("status", "no_answer")
                    )
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
