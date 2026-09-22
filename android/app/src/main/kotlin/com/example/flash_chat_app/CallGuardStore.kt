package com.example.flash_chat_app

import android.content.Context
import android.util.Log

/**
 * Local, native-side record of 1-to-1 call ids that have already been handled
 * (a full-screen ring was shown, the ring timed out to `no_answer`, or Dart
 * marked it through the `flash_chat/call_guard` bridge). Persisted in the
 * app's own SharedPreferences so a re-delivered FCM/HMS call push — or a
 * cold-start Firestore re-fire of the same `ringing` doc — can never ring the
 * same stale call again.
 */
object CallGuardStore {

    private const val TAG = "CallGuardStore"
    private const val PREFS_NAME = "flash_chat_call_guard"
    private const val KEY = "handled_call_ids"

    fun isHandled(context: Context, callId: String): Boolean =
        callId in read(context)

    fun read(context: Context): Set<String> =
        context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
            .getStringSet(KEY, emptySet()) ?: emptySet()

    fun markHandled(context: Context, callId: String) {
        val prefs = context.getSharedPreferences(PREFS_NAME, Context.MODE_PRIVATE)
        val updated = prefs.getStringSet(KEY, emptySet())?.toMutableSet()
            ?: mutableSetOf()
        if (updated.add(callId)) {
            prefs.edit().putStringSet(KEY, updated).apply()
            Log.d(TAG, "Marked handled: $callId")
        }
    }
}