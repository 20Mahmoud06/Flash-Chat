package com.hiennv.flutter_callkit_incoming

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.Bundle
import android.os.IBinder
import android.text.TextUtils
import android.util.Log
import androidx.core.app.NotificationCompat
import androidx.core.content.ContextCompat

class CallkitNotificationService : Service() {

    companion object {

        private val ActionForeground = listOf(
            CallkitConstants.ACTION_CALL_START,
            CallkitConstants.ACTION_CALL_ACCEPT
        )

        /** Stable id for the fallback notification, distinct from the ids the
         *  notification manager hands out (which are generated/bit-shifted). */
        private const val FALLBACK_ONGOING_NOTIFICATION_ID = 51423


        fun startServiceWithAction(context: Context, action: String, data: Bundle?) {
            // When a native full-screen ring launched the app from a KILLED
            // process, the Flutter engine is not attached yet and the plugin's
            // notification manager is unavailable. Starting a foreground
            // service then could never call startForeground(), so Android
            // crashes the whole process within ~5s (RemoteServiceException).
            // Skip it: the engine takes over the accepted-call UI once the app
            // boots (and its own ongoing-call notification lives in Dart).
            if (FlutterCallkitIncomingPlugin.getInstance()?.getCallkitNotificationManager() == null) {
                return
            }
            val intent = Intent(context, CallkitNotificationService::class.java).apply {
                this.action = action
                putExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA, data)
            }
            try {
                val shouldStartForeground =
                    data?.getBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_SHOW, true) ?: true
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
                    intent.action in ActionForeground && shouldStartForeground
                ) {
                    ContextCompat.startForegroundService(context, intent)
                } else {
                    // pre-O always uses startService; on O+ this is the
                    // callingShow=false path where startForeground() is never
                    // expected, so a plain start is correct.
                    context.startService(intent)
                }
            } catch (e: Exception) {
                Log.w(TAG, "Failed to start call notification service: ${e.message}")
            }
        }

        fun stopService(context: Context) {
            val intent = Intent(context, CallkitNotificationService::class.java)
            context.stopService(intent)
        }

        private const val TAG = "CallkitNotificationService"

    }

    // Get notification manager dynamically to handle plugin lifecycle properly
    private fun getCallkitNotificationManager(): CallkitNotificationManager? {
        return FlutterCallkitIncomingPlugin.getInstance()?.getCallkitNotificationManager()
    }


    override fun onCreate() {
        super.onCreate()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val action = intent?.action
        val data = intent?.getBundleExtra(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA)
        if (action != CallkitConstants.ACTION_CALL_START &&
            action != CallkitConstants.ACTION_CALL_ACCEPT
        ) {
            // Restarted by START_STICKY without a valid intent (or unknown
            // action) — nothing meaningful to foreground.
            stopSelf()
            return START_NOT_STICKY
        }
        try {
            if (action == CallkitConstants.ACTION_CALL_ACCEPT && data != null) {
                getCallkitNotificationManager()?.clearIncomingNotification(data, true)
            }
            if (data != null &&
                data.getBoolean(CallkitConstants.EXTRA_CALLKIT_CALLING_SHOW, true)
            ) {
                getCallkitNotificationManager()?.createNotificationChanel(data)
                showOngoingCallNotification(data)
            } else {
                stopSelf()
            }
        } catch (e: Exception) {
            Log.w(TAG, "onStartCommand crashed: ${e.message}")
            stopSelf()
        }
        return START_STICKY
    }

    @SuppressLint("MissingPermission")
    private fun showOngoingCallNotification(bundle: Bundle) {

        // Build a resilient fallback first. A service launched via
        // startForegroundService() that never calls startForeground() gets the
        // whole process killed by RemoteServiceException after ~5s, and a
        // foregroundServiceType="phoneCall" startForeground() can itself throw
        // on a few OEM/GMS builds — both must never crash the app.
        var notification: Notification = buildFallbackOngoingNotification(bundle)
        var notificationId = FALLBACK_ONGOING_NOTIFICATION_ID

        try {
            getCallkitNotificationManager()?.getOnGoingCallNotification(bundle, false)?.let {
                notification = it.notification
                notificationId = it.id
            }
        } catch (e: Exception) {
            Log.w(TAG, "Failed to build ongoing notification: ${e.message}")
        }

        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                startForeground(
                    notificationId,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_PHONE_CALL
                )
            } else {
                startForeground(notificationId, notification)
            }
        } catch (e: Exception) {
            // phoneCall FGS type rejected (some Xiaomi/MIUI + GMS combos) —
            // degrade to a plain foreground service rather than crash.
            Log.w(TAG, "startForeground(phoneCall) failed: ${e.message}")
            try {
                startForeground(notificationId, notification)
            } catch (e2: Exception) {
                Log.w(TAG, "startForeground fallback failed: ${e2.message}")
                stopSelf()
            }
        }
    }

    /** Minimal ongoing notification used when the plugin cannot build one, so
     *  startForeground() is always called for a started service. */
    private fun buildFallbackOngoingNotification(bundle: Bundle): Notification {
        val channelId = CallkitNotificationManager.NOTIFICATION_CHANNEL_ID_ONGOING
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val nm = getSystemService(NOTIFICATION_SERVICE) as NotificationManager
            nm.createNotificationChannel(
                NotificationChannel(
                    channelId,
                    "Ongoing calls",
                    NotificationManager.IMPORTANCE_LOW
                )
            )
        }
        val caller = bundle.getString(CallkitConstants.EXTRA_CALLKIT_NAME_CALLER, "")
        return NotificationCompat.Builder(this, channelId)
            .setSmallIcon(R.drawable.ic_accept)
            .setContentTitle(if (TextUtils.isEmpty(caller)) "Call in progress" else caller)
            .setContentText("Ongoing call")
            .setOngoing(true)
            .setCategory(NotificationCompat.CATEGORY_CALL)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .build()
    }


    override fun onDestroy() {
        super.onDestroy()
        // Don't destroy the notification manager here as it's shared across the app
        // The plugin will handle cleanup when all engines are detached
    }

    override fun onBind(p0: Intent?): IBinder? {
        return null
    }


    override fun onTaskRemoved(rootIntent: Intent?) {
        super.onTaskRemoved(rootIntent)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            stopForeground(STOP_FOREGROUND_REMOVE)
        }else {
            stopForeground(true)
        }
        stopSelf()
    }



}

