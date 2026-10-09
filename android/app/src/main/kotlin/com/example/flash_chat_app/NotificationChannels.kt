package com.example.flash_chat_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.graphics.Color
import android.media.AudioAttributes
import android.net.Uri
import android.os.Build
import android.os.Bundle
import android.util.Log
import androidx.core.app.NotificationCompat
import com.hiennv.flutter_callkit_incoming.CallkitConstants
import com.hiennv.flutter_callkit_incoming.CallkitIncomingActivity
import com.hiennv.flutter_callkit_incoming.CallkitIncomingBroadcastReceiver
import com.hiennv.flutter_callkit_incoming.TransparentActivity
import java.io.File

/**
 * Creates the chat notification channel with the app's CUSTOM sound.
 *
 * The sound is a bundled raw resource (`res/raw/alert.wav`) referenced through
 * an `android.resource://` URI — the reliable pattern on every Android version
 * and OEM. The previous `file://` copy in the app's internal storage was not
 * readable by the system media player (it runs under the system uid) and so
 * silently fell back to the default notification sound on most devices. The
 * internal copy is kept only as a last-resort fallback.
 *
 * Channel sound settings are frozen at first creation, so this helper must be
 * called as early as possible (MainActivity.onCreate) — before
 * flutter_local_notifications creates the same channel — and the channel id
 * must be bumped whenever the sound setup changes (v12 -> v13).
 */
object NotificationChannels {

    private const val TAG = "NotificationChannels"

    const val CHANNEL_ID = "flash_chat_custom_v13"
    const val CHANNEL_NAME = "Flash Chat Messages"

    const val CALL_CHANNEL_ID = "flash_chat_calls_v3"
    const val CALL_CHANNEL_NAME = "Incoming Calls"

    /// Matches the caller-side ring timeout.
    const val CALL_RING_TIMEOUT_MS = 30_000L

    private const val SOUND_DIR = "notification_sounds"
    private const val SOUND_FILE_NAME = "alert.wav"
    private const val SOUND_RES_ID = R.raw.alert

    private fun fileSoundUri(context: Context): Uri {
        val dir = File(context.filesDir, SOUND_DIR).apply { mkdirs() }
        val soundFile = File(dir, SOUND_FILE_NAME)
        if (!soundFile.exists() ||
            soundFile.length() != context.resources.openRawResource(SOUND_RES_ID).use { it.available().toLong() }
        ) {
            context.resources.openRawResource(SOUND_RES_ID).use { input ->
                soundFile.outputStream().use { output -> input.copyTo(output) }
            }
            Log.d(TAG, "Sound copied to ${soundFile.absolutePath}")
        }
        return Uri.fromFile(soundFile)
    }

    /**
     * Returns the sound URI used for the chat channel and notifications.
     *
     * The bundled raw resource is inside the APK and readable by the system on
     * every device, so `android.resource://` is used first; the file copy is
     * only a fallback if building the resource URI unexpectedly fails.
     */
    fun soundUri(context: Context): Uri {
        return try {
            Uri.Builder()
                .scheme("android.resource")
                .authority(context.packageName)
                .path(SOUND_RES_ID.toString())
                .build()
        } catch (e: Exception) {
            Log.w(TAG, "Falling back to file sound URI: ${e.message}")
            fileSoundUri(context)
        }
    }

    /**
     * Creates (or no-ops on) the chat channel with the custom sound and max
     * importance. Safe to call repeatedly; Android ignores updates.
     */
    fun createChatChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_MAX
            ).apply {
                description = "Notifications for chat messages"
                enableVibration(true)
                setSound(
                    soundUri(context),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create channel: ${e.message}")
        }
    }

    /**
     * Creates the incoming-call channel used by the native full-screen-intent
     * ring. IMPORTANCE_HIGH is required for full-screen-intent (FSI)
     * notifications to be launched by the system over the lock screen.
     *
     * The channel plays the bundled ringtone. On MIUI / HyperOS a HIGH-
     * importance channel created with [setSound][NotificationChannel.setSound]
     * `(null, null)` is silently downgraded: the FSI launches but the system
     * suppresses audio from the resulting Activity. Giving the channel a real
     * sound keeps the importance intact and the ring audible. The
     * [CallkitIncomingActivity] cancels the notification as soon as it
     * appears, so any overlap with the Activity's own MediaPlayer ring is
     * negligible.
     */
    fun createCallChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            // Delete old v1 and v2 channels (v1 was created with setSound(null,null),
            // v2 may have frozen incorrect settings on MIUI/HyperOS). A fresh v3
            // channel with the correct ringtone is created below.
            try { nm.deleteNotificationChannel("flash_chat_calls_v1") } catch (_: Exception) {}
            try { nm.deleteNotificationChannel("flash_chat_calls_v2") } catch (_: Exception) {}
            val channel = NotificationChannel(
                CALL_CHANNEL_ID,
                CALL_CHANNEL_NAME,
                NotificationManager.IMPORTANCE_HIGH
            ).apply {
                description = "Incoming call alerts"
                setSound(
                    Uri.parse("android.resource://${context.packageName}/${R.raw.ringtone}"),
                    AudioAttributes.Builder()
                        .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
                        .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
                        .build()
                )
                enableVibration(true)
            }
            nm.createNotificationChannel(channel)
        } catch (e: Exception) {
            Log.e(TAG, "Failed to create call channel: ${e.message}")
        }
    }

    /**
     * Stable per-call notification id, in a bucket separate from the chat
     * notification ids (HmsMessageService.notificationId) so both can coexist.
     * The ring screen cancels this id when it launches (see
     * CallkitIncomingActivity.onCreate).
     */
    fun callNotificationId(callId: String): Int = 3_000_000 + (callId.hashCode() and 0xFFFFF)

    /**
     * Posts the SINGLE, non-ringing "missed call" notification for [callId],
     * using the same stable per-call id as [postFullScreenCallRing]. Any
     * leftover ring notification for the same call is replaced instead of
     * stacked, so across Dart + native and repeated app opens there is at most
     * ONE active notification per call. Uses the chat channel (not the
     * ringing call channel): a missed call must never re-ring the device.
     */
    fun postMissedCallNotification(
        context: Context,
        callId: String,
        callerName: String,
        isVideo: Boolean
    ) {
        createChatChannel(context)
        val id = callNotificationId(callId)
        val caller = if (callerName.isBlank()) "Incoming call" else callerName
        val builder = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher))
            .setContentTitle(caller)
            .setContentText(if (isVideo) "Missed video call" else "Missed voice call")
            .setCategory(NotificationCompat.CATEGORY_MESSAGE)
            .setPriority(NotificationCompat.PRIORITY_HIGH)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(Color.parseColor("#4CAF50"))
            .setAutoCancel(true)
            .setSound(soundUri(context))
        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(id, builder.build())
            Log.d(TAG, "Missed-call notification posted (id=$id)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to post missed-call notification: ${e.message}")
        }
    }

    /**
     * Posts the notification that makes an incoming call ring when the app is
     * NOT in the foreground — including when the process was KILLED.
     *
     * A direct `startActivity` for the ring screen is silently blocked by
     * Android's background-activity-start restrictions once the app is killed,
     * so the GMS and HMS services use a full-screen-intent (FSI) notification
     * instead: the system launches [CallkitIncomingActivity] itself (a
     * full-screen intent is exempt from the restriction) whenever the call
     * arrives with the device locked/ambient. The same PendingIntent is also
     * fired immediately so a backgrounded-but-alive app still rings instantly
     * (notification interactions are always exempt).
     */
    fun postFullScreenCallRing(context: Context, data: Bundle, callId: String) {
        createCallChannel(context)

        val intent = CallkitIncomingActivity.getIntent(context, data)
        // The same intent can arrive twice (system FSI + our immediate send):
        // reuse the existing ring screen instead of stacking another.
        intent.addFlags(Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_NEW_TASK)

        val id = callNotificationId(callId)
        val fullScreen = PendingIntent.getActivity(
            context,
            id,
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val callerName = data.getString(CallkitConstants.EXTRA_CALLKIT_NAME_CALLER)
            ?: data.getString(CallkitConstants.EXTRA_CALLKIT_HANDLE)
            ?: "Incoming call"
        val isVideo = data.getInt(CallkitConstants.EXTRA_CALLKIT_TYPE, 0) > 0

        // Heads-up fallback actions (when the FSI can only show as a heads-up
        // because the device is unlocked): Accept opens the app through the
        // transparent bridge, Decline fires the plugin's decline receiver.
        val acceptTap = TransparentActivity.getIntent(
            context,
            CallkitConstants.ACTION_CALL_ACCEPT,
            data
        )
        val declineTap = CallkitIncomingBroadcastReceiver.getIntentDecline(context, data)

        val notification = NotificationCompat.Builder(context, CALL_CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher))
            .setContentTitle(callerName)
            .setContentText(if (isVideo) "Incoming video call" else "Incoming voice call")
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_MAX)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(Color.parseColor("#4CAF50"))
            .setContentIntent(fullScreen)
            .setFullScreenIntent(fullScreen, true)
            .setAutoCancel(true)
            .setTimeoutAfter(CALL_RING_TIMEOUT_MS)
            .addAction(
                0,
                "Accept",
                PendingIntent.getActivity(
                    context,
                    id + 1,
                    acceptTap,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            .addAction(
                0,
                "Decline",
                PendingIntent.getBroadcast(
                    context,
                    id + 2,
                    declineTap,
                    PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
                )
            )
            .build()

        try {
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.notify(id, notification)
            // Fire the ring now: allowed from the background via a notification
            // interaction; a no-op once the system FSI already launched it.
            fullScreen.send()
            Log.d(TAG, "Full-screen call ring posted (id=$id)")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to post full-screen call ring: ${e.message}")
        }
    }
}