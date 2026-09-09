package com.example.flash_chat_app.hms

import android.app.Activity
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.util.Log
import com.huawei.agconnect.AGConnectOptionsBuilder
import com.huawei.hms.aaid.HmsInstanceId
import com.huawei.hms.api.ConnectionResult
import com.huawei.hms.api.HuaweiApiAvailability
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodChannel

/**
 * Bridges HMS Push Kit state between the native side (HmsMessageService,
 * MainActivity) and Dart (HmsPushService).
 *
 * - MethodChannel "flash_chat/hms":
 *   - isHmsAvailable        -> whether Push Kit is usable on this device
 *   - getHmsToken           -> the cached HMS push token (or null)
 *   - getNotificationPayload-> one-shot payload of a notification tap that
 *                              happened before Dart was ready (clears it)
 *   - cancelNotification(id) -> cancels a native notification by id
 * - EventChannel "flash_chat/hms_push_events": emits {"event":"message","data":{...}}
 *   for messages received while the app is in the foreground and for
 *   notification taps while the app is already running.
 */
object HmsPushBridge {

    private const val TAG = "HmsPushBridge"
    private const val PREFS_NAME = "hms_push_state"
    private const val KEY_TOKEN = "hms_token"
    const val EXTRA_PAYLOAD = "hms_payload"

    @Volatile
    private var appContext: Context? = null

    private var pendingPayload: String? = null
    private var eventSink: EventChannel.EventSink? = null

    @Volatile
    var isAppInForeground: Boolean = false

    /** Sets the app context once (HmsMessageService may run before the UI). */
    fun attach(context: Context) {
        appContext = context.applicationContext
    }

    fun registerChannels(messenger: BinaryMessenger) {
        MethodChannel(messenger, "flash_chat/hms").setMethodCallHandler { call, result ->
            val context = appContext
            when (call.method) {
                "isHmsAvailable" -> result.success(context != null && isHmsAvailable(context))
                "getHmsToken" -> result.success(if (context != null) getToken(context) else null)
                "getNotificationPayload" -> {
                    val payload = pendingPayload
                    pendingPayload = null
                    result.success(payload)
                }
                "cancelNotification" -> {
                    val id = (call.arguments as? Number)?.toInt() ?: -1
                    if (id >= 0 && context != null) {
                        val nm = context.getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                        nm.cancel(id)
                    }
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        EventChannel(messenger, "flash_chat/hms_push_events").setStreamHandler(
            object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    eventSink = null
                }
            }
        )
    }

    /** Called by MainActivity on create/new-intent with a tapped notification. */
    fun attachTap(intent: Intent) {
        val payload = intent.getStringExtra(EXTRA_PAYLOAD) ?: return
        pendingPayload = payload
        emit("message", payload)
    }

    /** Called by HmsMessageService for data messages while the app is foreground. */
    fun emitForegroundMessage(payloadMap: Map<String, String>) {
        emit("message", payloadMap)
    }

    private fun emit(event: String, payload: String) {
        val parsed = try {
            org.json.JSONObject(payload).toMap()
        } catch (e: Exception) {
            mapOf("raw" to payload)
        }
        emit(event, parsed)
    }

    private fun emit(event: String, payloadMap: Map<String, String>) {
        val sink = eventSink ?: return
        try {
            sink.success(mapOf("event" to event, "data" to payloadMap))
        } catch (e: Exception) {
            Log.w(TAG, "Event emit failed: ${e.message}")
        }
    }

    private fun org.json.JSONObject.toMap(): Map<String, String> {
        val result = LinkedHashMap<String, String>()
        val keys = this.keys()
        while (keys.hasNext()) {
            val key = keys.next() as String
            val value = this.optString(key)
            if (value.isNotEmpty()) result[key] = value
        }
        return result
    }

    fun storeToken(context: Context, token: String) {
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .edit().putString(KEY_TOKEN, token).apply()
    }

    /**
     * Explicitly requests the HMS Push token so a brand-new install registers
     * with the push server before any message can reach it. Unlike FCM, HMS
     * does NOT generate a token on its own shortly after launch: the app must
     * call HmsInstanceId.getToken(appId, "HCM") — the onNewToken callback
     * alone only fires once a token already exists or gets refreshed. Without
     * this, a fresh HMS-only device never obtains a token, never uploads it to
     * Firestore, and never receives a single push.
     *
     * Runs on a worker thread (getToken blocks) and caches the result in the
     * same prefs the Dart bridge reads ([getToken]).
     */
    fun requestToken(context: Context) {
        Thread {
            try {
                if (HuaweiApiAvailability.getInstance()
                        .isHuaweiMobileServicesAvailable(context) != ConnectionResult.SUCCESS
                ) {
                    Log.w(TAG, "HMS Core not available — skipping token request")
                    return@Thread
                }
                val appId = AGConnectOptionsBuilder().build(context).getString("client/app_id")
                if (appId.isNullOrEmpty()) {
                    // agconnect-services.json is required for real HMS builds; its
                    // absence means this binary has no HMS push config at all.
                    Log.w(TAG, "HMS app id missing (agconnect-services.json not bundled) — HMS push disabled")
                    return@Thread
                }
                val token = HmsInstanceId.getInstance(context).getToken(appId, "HCM")
                if (!token.isNullOrEmpty()) {
                    storeToken(context, token)
                    Log.d(TAG, "HMS token requested: ${token.take(12)}...")
                } else {
                    Log.w(TAG, "HMS getToken returned empty — falling back to onNewToken")
                }
            } catch (e: Exception) {
                Log.w(TAG, "HMS token request failed: ${e.message}")
            }
        }.start()
    }

    fun getToken(context: Context): String? {
        val token = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getString(KEY_TOKEN, null)
        return if (token.isNullOrEmpty()) null else token
    }

    fun isHmsAvailable(context: Context): Boolean {
        return try {
            val available =
                HuaweiApiAvailability.getInstance().isHuaweiMobileServicesAvailable(context) ==
                    ConnectionResult.SUCCESS
            val token = getToken(context)
            available && token != null
        } catch (e: Exception) {
            Log.w(TAG, "Availability check failed: ${e.message}")
            false
        }
    }
}
