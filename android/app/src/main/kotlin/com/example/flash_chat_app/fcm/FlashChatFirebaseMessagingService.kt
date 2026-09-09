package com.example.flash_chat_app.fcm

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
import com.example.flash_chat_app.hms.HmsMessageService
import com.example.flash_chat_app.hms.HmsPushBridge
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FirebaseFirestore
import com.google.firebase.messaging.RemoteMessage
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import io.flutter.plugins.firebase.messaging.FlutterFirebaseMessagingService
import org.json.JSONObject
import java.util.Date

/**
 * Renders notifications natively on Android so they reach the user when the
 * app is closed, backgrounded or the phone is locked — including and
 * especially the full-screen incoming CALL ring, which the Dart background
 * isolate cannot reliably present on modern Android (background activity-start
 * restrictions). Mirrors the proven HMS path in [HmsMessageService].
 *
 * The FCM SDK delivers data messages to the manifest-registered
 * FirebaseMessagingService that wins intent resolution. The Flutter plugin's
 * default FlutterFirebaseMessagingService is a no-op (messages are routed to
 * Dart through its broadcast receiver), which also shadows the FCM SDK's own
 * rendering service and silently drops the `notification` block. This service
 * (registered with a higher filter priority) takes over `onMessageReceived`
 * and displays the notification / launches the call ring itself. `onNewToken`
 * is forwarded to the plugin so the Dart-side token refresh keeps working.
 */
class FlashChatFirebaseMessagingService : FlutterFirebaseMessagingService() {

    private val notificationManager: NotificationManager
        get() = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager

    override fun onNewToken(token: String) {
        // Keep the plugin's Dart-side onTokenRefresh flow working.
        super.onNewToken(token)
        Log.d(TAG, "FCM token: $token")
    }

    override fun onMessageReceived(message: RemoteMessage) {
        super.onMessageReceived(message)
        HmsPushBridge.attach(applicationContext)

        val data = message.data
        if (data.isEmpty()) return

        if (HmsPushBridge.isAppInForeground) {
            // Flutter engine is visible; Dart renders via the onMessage
            // listener (with active-chat suppression). super is a no-op.
            return
        }

        // On dual-stack Huawei devices the HMS renderer already shows its own
        // push / ring; rendering here too would duplicate the notification.
        if (HmsPushBridge.isHmsAvailable(applicationContext)) return

        when (data["type"]) {
            "call" -> showCall(data)
            "chat", "group_chat" -> handleChatPush(data)
            else -> Log.w(TAG, "Ignoring FCM push of type: ${data["type"]}")
        }
    }

    // ==================== CALLS (app killed / background) ====================

    /**
     * Launches the full-screen CallKit incoming-call ring natively. This is
     * what makes incoming calls ring even when the app process was killed: it
     * starts [CallkitIncomingActivity] directly instead of relying on the
     * Dart background isolate (which modern Android prevents from starting
     * activities from the background).
     *
     * The display name is the receiver's nickname for the caller when one is
     * set (read from Firestore `users/{me}/nicknames`), otherwise the caller's
     * real name. The emoji avatar is passed through and rendered by the
     * vendored [CallkitIncomingActivity]. All reads are best-effort: any
     * failure falls back to the data in the push payload so the ring always
     * appears.
     */
    private fun showCall(payload: Map<String, String>) {
        val callId = payload["callId"] ?: return
        val isVideo = payload["isVideo"] == "true"
        val isGroup = payload["isGroup"] == "true"
        val callerId = payload["callerId"]

        val data = Bundle()
        data.putString(CallkitConstants.EXTRA_CALLKIT_ID, callId)
        data.putInt(CallkitConstants.EXTRA_CALLKIT_TYPE, if (isVideo) 1 else 0)
        data.putString(CallkitConstants.EXTRA_CALLKIT_HANDLE, "Flash Chat")
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

        // Resolve the final display name (receiver's nickname for the caller
        // when set, otherwise the caller's real name) on a worker thread, then
        // launch the ring once the name is known. The Activity reads the name
        // once from the Intent, so it must be final before the ring starts.
        resolveAndLaunchRing(data, isGroup, callerId, payload["callerName"], payload["groupName"])

        // Schedule a native no-answer timeout: if the call is still ringing in
        // Firestore after the ring window, mark it no_answer so the caller's
        // side and call history stay consistent even when the app is killed.
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

    /**
     * Resolves `users/{me}/nicknames.{callerId}` on the calling thread and
     * returns the nickname, or null when none is set / the lookup fails.
     */
    private fun resolveNickname(callerId: String): String? {
        return try {
            val me = FirebaseAuth.getInstance().currentUser?.uid ?: return null
            val doc = com.google.android.gms.tasks.Tasks.await(
                FirebaseFirestore.getInstance()
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

    /**
     * Best-effort Firestore safety net: after [RING_TIMEOUT_MS], if the call is
     * still ringing (nobody accepted / the receiver was offline / killed), mark
     * it `no_answer` so the caller gets a correct outcome and no call is orphaned.
     */
    private fun scheduleTimeoutAsync(callId: String) {
        Thread {
            Thread.sleep(RING_TIMEOUT_MS)
            try {
                val callDoc = com.google.android.gms.tasks.Tasks.await(
                    FirebaseFirestore.getInstance()
                        .collection("calls")
                        .document(callId)
                        .get()
                )
                val status = callDoc.data?.get("status") as? String
                if (status == "ringing") {
                    com.google.android.gms.tasks.Tasks.await(
                        FirebaseFirestore.getInstance()
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

    // ==================== CHAT / GROUP NOTIFICATIONS ====================

    /**
     * Entry point for chat/group pushes rendered natively (app killed or in
     * the background). For 1-to-1 chats it honors the per-contact mute stored
     * in `users/{me}/mutedChats.<peerUid>` — the same data the Dart side checks
     * in the foreground — so a muted contact stays silent even if a push
     * reaches this device (e.g. sent before the mute propagated).
     */
    private fun handleChatPush(payload: Map<String, String>) {
        if (!notificationsEnabled()) return

        val peerId = payload["senderId"] ?: payload["groupId"] ?: return
        val isGroup = payload["type"] == "group_chat"

        if (!isGroup) {
            // Read the mute state on a worker thread so the service thread is
            // never blocked, then render only when the contact is not muted.
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

        val id = HmsMessageService.notificationId(peerId, isGroup)
        val title = payload["title"] ?: "New message"
        val body = payload["body"] ?: ""

        val payloadJson = JSONObject(payload).toString()

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

        val builder = NotificationCompat.Builder(applicationContext, HmsMessageService.CHANNEL_ID)
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
            .setSound(NotificationChannels.soundUri(applicationContext))

        try {
            notificationManager.notify(id, builder.build())
            Log.d(TAG, "Notification shown for $peerId (id=$id)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to show notification: ${e.message}")
        }
    }

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

    companion object {
        private const val TAG = "FlashChatFirebaseMessagingService"

        /// 30 seconds, matching the caller's ring timeout (Messenger behaviour).
        private const val RING_TIMEOUT_MS = 30_000L
    }
}
