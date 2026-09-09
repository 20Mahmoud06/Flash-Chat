package com.example.flash_chat_app

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log
import com.google.android.gms.tasks.Tasks
import com.google.firebase.auth.FirebaseAuth
import com.google.firebase.firestore.FieldValue
import com.google.firebase.firestore.FirebaseFirestore
import com.hiennv.flutter_callkit_incoming.CallkitConstants

/**
 * Persists a native accept/decline decision to Firestore before the Flutter
 * engine is running.
 *
 * When the app is KILLED the Dart event channel that normally handles
 * accept/decline is dead, so the vendored callkit plugin re-broadcasts the
 * decision here. Writing the outcome natively makes both sides work:
 *
 *  - ACCEPT: `calls/{id}` flips to `accepted`, so the Dart cold-boot recovery
 *    (CallService._resumeAcceptedCall) finds the call and opens the call page
 *    instead of dropping to the home screen (the "deep link doesn't work" bug).
 *  - DECLINE: the caller sees "Call Declined" immediately instead of waiting
 *    for the 30s no-answer timeout (the "Decline button does nothing" bug).
 *
 * Mirrors exactly what the Dart callkit event handler writes, so this is a
 * no-op safety net in the foreground (the values are the same / conditions
 * already satisfied).
 */
class CallDecisionReceiver : BroadcastReceiver() {

    override fun onReceive(context: Context, intent: Intent) {
        val decision = intent.getStringExtra(CallkitConstants.EXTRA_CALLKIT_DECISION)
        if (decision != "accepted" && decision != "declined") return
        val data = intent.extras?.getBundle(CallkitConstants.EXTRA_CALLKIT_INCOMING_DATA)
            ?: return
        val callId = data.getString(CallkitConstants.EXTRA_CALLKIT_ID) ?: return
        val extra = runCatching {
            data.getSerializable(CallkitConstants.EXTRA_CALLKIT_EXTRA) as? Map<*, *>
        }.getOrNull()
        val isGroup = extra?.get("isGroup")?.toString() == "true"

        // A plain BroadcastReceiver may be frozen/paused as soon as onReceive
        // returns, which would kill the persisted decision mid-write.
        // goAsync() keeps the process alive (up to ~10s) for the worker thread.
        val pendingResult = goAsync()
        Thread {
            try {
                val me = waitForSignedInUser()
                if (me != null) {
                    persistDecisionWithRetry(callId, me, isGroup, decision)
                } else {
                    Log.w(TAG, "No signed-in user; cannot persist $decision for $callId")
                }
            } catch (t: Throwable) {
                Log.w(TAG, "Failed to persist $decision for $callId: ${t.message}")
            } finally {
                pendingResult.finish()
            }
        }.start()
    }

    /**
     * Waits for the restored FirebaseAuth session. On a cold-started process
     * (full-screen-intent before the engine boots) the token restore can take
     * well over the old 2s budget on a mid-range device, which silently
     * dropped every accept/decline (see "decline does nothing" / "deep link
     * doesn't work"). 120 x 100ms = 12s covers the slowest legit cold start.
     */
    private fun waitForSignedInUser(): String? {
        val auth = FirebaseAuth.getInstance()
        var me = auth.currentUser?.uid
        var attempts = 0
        while (me == null && attempts < 120) {
            Thread.sleep(100)
            me = auth.currentUser?.uid
            attempts++
        }
        return me
    }

    private fun persistDecisionWithRetry(
        callId: String,
        me: String,
        isGroup: Boolean,
        decision: String
    ) {
        var attempt = 0
        while (attempt < 3) {
            if (attempt > 0) Thread.sleep(500L * attempt)
            try {
                persistDecision(callId, me, isGroup, decision)
                return
            } catch (t: Throwable) {
                attempt++
                Log.w(TAG, "Decision write attempt $attempt failed: ${t.message}")
            }
        }
    }

    @Throws(Exception::class)
    private fun persistDecision(callId: String, me: String, isGroup: Boolean, decision: String) {
        val callRef = FirebaseFirestore.getInstance().collection("calls").document(callId)
        val doc = Tasks.await(callRef.get())
        if (!doc.exists()) return
        val status = doc.getString("status")

        when (decision) {
            "accepted" -> {
                // Accepting always flips the call to accepted (matches the Dart
                // event handler) and joins the participant, so the accepted-call
                // recovery and the caller's side both see it.
                if (status != "ringing") {
                    Log.d(TAG, "Not accepting $callId from $status")
                    return
                }
                Tasks.await(
                    callRef.update(
                        mapOf(
                            "status" to "accepted",
                            "participants" to FieldValue.arrayUnion(me),
                        )
                    )
                )
            }
            "declined" -> {
                if (isGroup) {
                    // Member-only: the group call keeps ringing for everyone else.
                    Tasks.await(
                        callRef.update(mapOf("participantStatus.$me" to "declined"))
                    )
                } else if (status == "ringing") {
                    Tasks.await(callRef.update(mapOf("status" to "declined")))
                } else {
                    Log.d(TAG, "Not declining $callId from $status")
                }
            }
        }
    }

    companion object {
        private const val TAG = "CallDecisionReceiver"
    }
}