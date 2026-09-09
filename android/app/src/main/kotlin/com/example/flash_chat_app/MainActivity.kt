package com.example.flash_chat_app

import android.app.PictureInPictureParams
import android.content.Intent
import android.content.pm.PackageManager
import android.content.res.Configuration
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Rational
import android.view.WindowManager
import com.example.flash_chat_app.hms.HmsPushBridge
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

/**
 * Native Picture-in-Picture bridge.
 *
 * The previous `pip` plugin only reported "started/stopped" without the reason
 * the PiP window closed, so the Flutter side had to guess (expanded vs.
 * dismissed) with a fixed-delay lifecycle check — which cancelled the call
 * whenever the expand animation took longer than the delay.
 *
 * Here the OS callbacks are used directly and the exit cause is decided by a
 * deterministic signal instead of finish/destroy guessing (some OEMs destroy
 * and recreate the activity on expand): whenever the activity RESUMES after a
 * PiP exit it was an expand — a dismissed PiP window never resumes. The
 * decision is deferred a beat so a slow expand still reports `pipExpanded`.
 */
class MainActivity : FlutterActivity() {

    companion object {
        private const val CHANNEL = "flash_chat/pip"

        // Events pushed from native to Flutter.
        private const val EVENT_STARTED = "pipStarted"
        private const val EVENT_EXPANDED = "pipExpanded"
        private const val EVENT_DISMISSED = "pipDismissed"

        // How long to wait after PiP exit before deciding the cause. Long
        // enough for the expand transition (activity resume) to complete on
        // slow devices, short enough that a dismissal still lands promptly.
        private const val EXIT_SETTLE_MS = 2000L

        /// Modifiable by the call pages so the native sticky notification knows
        /// which call its action buttons belong to.
        @Volatile
        var activeCallId: String? = null

        /// App context kept alive for the notification service (may outlive a
        /// recreated activity).
        @Volatile
        var applicationContextRef: android.content.Context? = null
    }

    private val mainHandler = Handler(Looper.getMainLooper())
    private var channel: MethodChannel? = null
    private var pipSupported = false
    private var pipParams: PictureInPictureParams? = null
    private var autoEnterEnabled = false
    private var wasInPip = false
    private var pipExitPending = false

    /// True when the activity resumed after leaving PiP. A resumed activity
    /// proves the user EXPANDED the window; a dismissed window never resumes.
    private var pipExitResumed = false

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        applicationContextRef = applicationContext
        // Create the notification channel NOW (before the Flutter engine and
        // flutter_local_notifications run) so the custom file-based sound is
        // baked in on every device — channel sound is frozen at first creation.
        NotificationChannels.createChatChannel(this)
        // Kick off the HMS push token registration immediately (HMS — unlike
        // FCM — needs an explicit getToken() call, or a fresh device never
        // registers and receives zero pushes). Runs on its own worker thread.
        HmsPushBridge.requestToken(applicationContext)
        CallNotification.ensureChannel(this)
        HmsPushBridge.attach(this)
        HmsPushBridge.attachTap(intent)
        pipSupported = Build.VERSION.SDK_INT >= Build.VERSION_CODES.O &&
            packageManager.hasSystemFeature(PackageManager.FEATURE_PICTURE_IN_PICTURE)
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        HmsPushBridge.attachTap(intent)
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        HmsPushBridge.registerChannels(flutterEngine.dartExecutor.binaryMessenger)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "isSupported" -> result.success(pipSupported)
                "isInPip" -> result.success(wasInPip)
                "setup" ->
                    result.success(setupPip(call.arguments as? Map<*, *>))
                "start" -> result.success(enterPip())
                "disableAutoEnter" -> {
                    disableAutoEnter()
                    result.success(null)
                }
                "setCallMode" -> {
                    setCallMode(call.arguments as? Boolean ?: false)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        // Sticky voice-call notification bridge (`flash_chat/call_notification`).
        // The receiver forwards the notification action taps back through this
        // channel so the Dart side can drive the call cubit.
        CallNotification.notificationChannel = MethodChannel(
            flutterEngine.dartExecutor.binaryMessenger,
            "flash_chat/call_notification"
        )
        CallNotification.notificationChannel?.setMethodCallHandler { call, result ->
            when (call.method) {
                "show" -> {
                    val args = call.arguments as? Map<*, *>
                    activeCallId = args?.get("callId") as? String
                    CallNotification.show(
                        this,
                        title = args?.get("title") as? String ?: "Call in progress",
                        callStartMs = (args?.get("startTimeMs") as? Number)?.toLong()
                            ?: System.currentTimeMillis()
                    )
                    result.success(null)
                }
                "setMuted" -> {
                    CallNotification.setMuted(call.arguments as? Boolean ?: false)
                    result.success(null)
                }
                "hide" -> {
                    CallNotification.hide()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }

    override fun onResume() {
        super.onResume()
        HmsPushBridge.isAppInForeground = true
        // Coming back after a PiP exit (expand) — never after a dismissal.
        pipExitResumed = true
    }

    override fun onStop() {
        HmsPushBridge.isAppInForeground = false
        super.onStop()
    }

    // ===============================
    // 📽️ PICTURE-IN-PICTURE
    // ===============================

    private fun setupPip(args: Map<*, *>?): Boolean {
        if (!pipSupported) return false
        val ratioX = (args?.get("aspectRatioX") as? Number)?.toInt() ?: 9
        val ratioY = (args?.get("aspectRatioY") as? Number)?.toInt() ?: 16
        val seamless = (args?.get("seamlessResizeEnabled") as? Boolean) ?: true
        autoEnterEnabled = (args?.get("autoEnterEnabled") as? Boolean) ?: false

        val builder = PictureInPictureParams.Builder()
            .setAspectRatio(Rational(ratioX, ratioY))
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            builder
                .setSeamlessResizeEnabled(seamless)
                .setAutoEnterEnabled(autoEnterEnabled)
        }
        pipParams = builder.build()
        setPictureInPictureParams(pipParams!!)
        return true
    }

    private fun enterPip(): Boolean {
        val params = pipParams ?: return false
        if (!isInPictureInPictureMode) {
            return enterPictureInPictureMode(params)
        }
        return true
    }

    private fun disableAutoEnter() {
        autoEnterEnabled = false
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            setPictureInPictureParams(
                PictureInPictureParams.Builder()
                    .setAutoEnterEnabled(false)
                    .build()
            )
        }
    }

    /**
     * Flips the activity into "in-call" mode while a call UI is on screen, so
     * answering while the phone is locked shows the call page directly above
     * the keyguard instead of forcing the user to unlock first. Toggled by the
     * call pages (NativePip.setCallMode) on their initState/dispose: the app
     * may show over the lock screen ONLY while the call page exists.
     */
    private fun setCallMode(inCall: Boolean) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1) {
            setShowWhenLocked(inCall)
            setTurnScreenOn(inCall)
        } else {
            if (inCall) {
                window.addFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
                window.addFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
            } else {
                window.clearFlags(WindowManager.LayoutParams.FLAG_SHOW_WHEN_LOCKED)
                window.clearFlags(WindowManager.LayoutParams.FLAG_TURN_SCREEN_ON)
            }
        }
        if (inCall) {
            window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        } else {
            window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
        }
    }

    /**
     * Auto-enter PiP when the user presses Home on API < 31; API >= 31 uses
     * [PictureInPictureParams.Builder.setAutoEnterEnabled] set in [setupPip].
     */
    override fun onUserLeaveHint() {
        if (autoEnterEnabled && !isInPictureInPictureMode) {
            enterPip()
        }
        super.onUserLeaveHint()
    }

    override fun onPictureInPictureModeChanged(
        isInPictureInPictureMode: Boolean,
        newConfig: Configuration
    ) {
        super.onPictureInPictureModeChanged(isInPictureInPictureMode, newConfig)
        if (!pipSupported) return

        if (isInPictureInPictureMode) {
            wasInPip = true
            pipExitPending = false
            pipExitResumed = false
            sendEvent(EVENT_STARTED)
        } else if (wasInPip || pipExitPending) {
            // Leaving PiP: expanding resumes the activity, dismissing does
            // not. Defer the decision so onResume (or its absence) settles
            // it — no finish/destroy guessing, which misfires on devices
            // that recreate the activity on expand.
            pipExitPending = true
            pipExitResumed = false
            mainHandler.postDelayed(PIP_EXIT_CHECK, EXIT_SETTLE_MS)
        }
    }

    private val PIP_EXIT_CHECK = Runnable {
        if (!pipExitPending) return@Runnable
        pipExitPending = false
        if (pipExitResumed) {
            wasInPip = false
            sendEvent(EVENT_EXPANDED)
        } else {
            wasInPip = false
            sendEvent(EVENT_DISMISSED)
        }
    }

    private fun sendEvent(event: String) {
        try {
            channel?.invokeMethod(event, null)
        } catch (e: Exception) {
            // Engine already gone (e.g. process teardown): nothing to notify.
        }
    }
}