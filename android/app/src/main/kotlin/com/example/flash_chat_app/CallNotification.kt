package com.example.flash_chat_app

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.graphics.BitmapFactory
import android.os.Build
import android.os.Handler
import android.os.Looper
import androidx.core.app.NotificationCompat
import io.flutter.plugin.common.MethodChannel

/**
 * Sticky "call in progress" notification for VOICE calls (video calls use the
 * PiP window instead, so this is never shown during a video call).
 *
 * The notification is ongoing (non-dismissible), shows the live elapsed call
 * time (ticked from native every second) and carries two actions:
 *  - mute/unmute the microphone
 *  - end the call
 * Tapping the notification reopens the call page.
 *
 * Actions are delivered by [CallControlReceiver] back to the Flutter engine
 * on `flash_chat/call_notification`, which drives the same [CallCubit] calls.
 */
object CallNotification {

    private const val TAG = "CallNotification"

    const val NOTIFICATION_ID = 1001
    const val CHANNEL_ID = "flash_chat_call_v1"
    const val CHANNEL_NAME = "Ongoing calls"

    private const val ACTION_TOGGLE_MUTE = "com.example.flash_chat_app.CALL_TOGGLE_MUTE"
    private const val ACTION_END_CALL = "com.example.flash_chat_app.CALL_END"
    private const val ACTION_OPEN_CALL = "com.example.flash_chat_app.CALL_OPEN"
    private const val EXTRA_CALL_ID = "callId"

    // Native -> Flutter action names (see call_notif.dart).
    private const val EVENT_MUTE = "mute"
    private const val EVENT_END = "end"
    private const val EVENT_OPEN = "open"

    private val mainHandler = Handler(Looper.getMainLooper())

    var notificationChannel: MethodChannel? = null

    private var active = false
    private var muted = false
    private var activeTitle = "Call in progress"
    private var startTimeMs = 0L

    // Explicit type: the ticker re-posts itself, so the type can't be
    // inferred from its own initializer.
    private val timeTicker: Runnable = Runnable {
        if (!active) return@Runnable
        updateNotification(notificationManagerOrNull())
        mainHandler.postDelayed(timeTicker, 1000L)
    }

    private fun notificationManagerOrNull(): NotificationManager? {
        val context = MainActivity.applicationContextRef ?: return null
        return context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        runCatching {
            val channel = NotificationChannel(
                CHANNEL_ID,
                CHANNEL_NAME,
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Ongoing voice calls"
                setSound(null, null)
                enableVibration(false)
            }
            val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(channel)
        }
    }

    /** Creates/starts the sticky ongoing notification with a 1s live timer. */
    fun show(context: Context, title: String, callStartMs: Long) {
        mainHandler.removeCallbacks(timeTicker)
        active = true
        muted = false
        activeTitle = title
        startTimeMs = if (callStartMs > 0L) callStartMs else System.currentTimeMillis()
        ensureChannel(context)
        updateNotification(context.getSystemService(Context.NOTIFICATION_SERVICE) as? NotificationManager)
        mainHandler.postDelayed(timeTicker, 1000L)
    }

    /** Updates the mute action label (called from Flutter on every toggle). */
    fun setMuted(mutedState: Boolean) {
        muted = mutedState
        updateNotification(notificationManagerOrNull())
    }

    /** Removes the notification and stops the ticker. */
    fun hide() {
        mainHandler.removeCallbacks(timeTicker)
        active = false
        notificationManagerOrNull()?.cancel(NOTIFICATION_ID)
    }

    private fun updateNotification(nm: NotificationManager?) {
        if (!active || nm == null) return
        runCatching {
            nm.notify(NOTIFICATION_ID, buildNotification(nm))
        }
    }

    private fun buildNotification(nm: NotificationManager): android.app.Notification {
        val context = MainActivity.applicationContextRef!!.applicationContext
        val callId = MainActivity.activeCallId ?: ""

        val openIntent = Intent(context, CallControlReceiver::class.java)
            .setAction(ACTION_OPEN_CALL)
            .putExtra(EXTRA_CALL_ID, callId)
        val openPending = PendingIntent.getBroadcast(
            context, 0, openIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val muteIntent = Intent(context, CallControlReceiver::class.java)
            .setAction(ACTION_TOGGLE_MUTE)
            .putExtra(EXTRA_CALL_ID, callId)
        val mutePending = PendingIntent.getBroadcast(
            context, 1, muteIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val endIntent = Intent(context, CallControlReceiver::class.java)
            .setAction(ACTION_END_CALL)
            .putExtra(EXTRA_CALL_ID, callId)
        val endPending = PendingIntent.getBroadcast(
            context, 2, endIntent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE
        )

        val timeText = formatElapsed(System.currentTimeMillis() - startTimeMs)

        return NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notification)
            .setLargeIcon(BitmapFactory.decodeResource(context.resources, R.mipmap.ic_launcher))
            .setContentTitle(activeTitle)
            .setContentText(timeText)
            .setContentIntent(openPending)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .setSilent(true)
            .setShowWhen(false)
            .addAction(
                if (muted) {
                    NotificationCompat.Action.Builder(
                        R.drawable.ic_notification,
                        "Unmute",
                        mutePending
                    ).build()
                } else {
                    NotificationCompat.Action.Builder(
                        R.drawable.ic_notification,
                        "Mute",
                        mutePending
                    ).build()
                }
            )
            .addAction(
                NotificationCompat.Action.Builder(
                    R.drawable.ic_notification,
                    "End Call",
                    endPending
                ).build()
            )
            .build()
    }

    private fun formatElapsed(ms: Long): String {
        val totalSec = ms / 1000
        val minutes = totalSec / 60
        val seconds = totalSec % 60
        return if (totalSec >= 3600) {
            String.format(
                "%d:%02d:%02d", totalSec / 3600, minutes % 60, seconds
            )
        } else {
            String.format("%02d:%02d", minutes, seconds)
        }
    }

    /**
     * Receives the notification action taps and forwards them to the running
     * Flutter engine. The engine stays alive for the whole call (the cubit is
     * app-wide), so the mute/end actions reach the call even in background.
     */
    class CallControlReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            val event = when (intent.action) {
                ACTION_TOGGLE_MUTE -> EVENT_MUTE
                ACTION_END_CALL -> EVENT_END
                ACTION_OPEN_CALL -> EVENT_OPEN
                else -> return
            }
            val callId = intent.getStringExtra(EXTRA_CALL_ID) ?: ""
            mainHandler.post {
                try {
                    notificationChannel?.invokeMethod(
                        event,
                        mapOf("callId" to callId)
                    )
                } catch (e: Exception) {
                    // Engine gone: nothing to notify.
                }
            }
        }
    }
}