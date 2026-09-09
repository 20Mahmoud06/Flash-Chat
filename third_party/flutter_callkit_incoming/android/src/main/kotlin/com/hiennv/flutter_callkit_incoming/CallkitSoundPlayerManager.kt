package com.hiennv.flutter_callkit_incoming

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioManager
import android.media.MediaPlayer
import android.media.Ringtone
import android.media.RingtoneManager
import android.net.Uri
import android.os.*
import android.text.TextUtils
import android.util.Log

class CallkitSoundPlayerManager(private val context: Context) {

    private val TAG = "CallkitSoundPlayer"

    private var vibrator: Vibrator? = null
    private var audioManager: AudioManager? = null

    private var ringtone: Ringtone? = null

    /// Looping MediaPlayer fallback used when RingtoneManager can't resolve
    /// the android.resource:// URI on a given OEM (silent ring otherwise).
    private var ringtonePlayer: MediaPlayer? = null

    private var isPlaying: Boolean = false


    inner class ScreenOffCallkitIncomingBroadcastReceiver : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (isPlaying){
                stop()
            }
        }
    }

    private var screenOffCallkitIncomingBroadcastReceiver = ScreenOffCallkitIncomingBroadcastReceiver()


    fun play(data: Bundle) {
        this.isPlaying = true
        this.prepare()
        this.playSound(data)
        this.playVibrator()

        val filter = IntentFilter(Intent.ACTION_SCREEN_OFF)
        context.registerReceiver(screenOffCallkitIncomingBroadcastReceiver, filter)
    }

    fun stop() {
        this.isPlaying = false

        ringtone?.stop()
        releaseRingtonePlayer()
        vibrator?.cancel()
        ringtone = null
        vibrator = null
        try {
            context.unregisterReceiver(screenOffCallkitIncomingBroadcastReceiver)
        }catch (_: Exception){}
    }

    fun destroy() {
        this.isPlaying = false

        ringtone?.stop()
        releaseRingtonePlayer()
        vibrator?.cancel()
        ringtone = null
        vibrator = null
        try {
            context.unregisterReceiver(screenOffCallkitIncomingBroadcastReceiver)
        }catch (_: Exception){}
    }

    private fun prepare() {
        ringtone?.stop()
        releaseRingtonePlayer()
        vibrator?.cancel()
    }

    private fun releaseRingtonePlayer() {
        try {
            if (ringtonePlayer?.isPlaying == true) {
                ringtonePlayer?.stop()
            }
        } catch (_: Exception) {
        }
        try {
            ringtonePlayer?.release()
        } catch (_: Exception) {
        }
        ringtonePlayer = null
    }

    private fun playVibrator() {
        vibrator = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
            val vibratorManager =
                context.getSystemService(Context.VIBRATOR_MANAGER_SERVICE) as VibratorManager
            vibratorManager.defaultVibrator
        } else {
            context.getSystemService(Context.VIBRATOR_SERVICE) as Vibrator
        }
        audioManager = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        when (audioManager?.ringerMode) {
            AudioManager.RINGER_MODE_SILENT -> {
            }

            else -> {
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                    vibrator?.vibrate(
                        VibrationEffect.createWaveform(
                            longArrayOf(0L, 1000L, 1000L),
                            0
                        )
                    )
                } else {
                    vibrator?.vibrate(longArrayOf(0L, 1000L, 1000L), 0)
                }
            }
        }
    }

    private fun playSound(data: Bundle?) {
        val sound = data?.getString(
            CallkitConstants.EXTRA_CALLKIT_RINGTONE_PATH,
            ""
        )

        // Preferred path: play the bundled raw resource through a looping
        // MediaPlayer created straight from the resource *id*. This bypasses
        // RingtoneManager entirely, whose handling of "android.resource://"
        // URIs returns a non-null-but-SILENT ringtone on several OEM skins
        // (most notably MIUI/HyperOS). Because that path "succeeded", the old
        // code never reached the MediaPlayer fallback and the call rang muted.
        val resId = if (TextUtils.isEmpty(sound) ||
            sound.equals("system_ringtone_default", true)) {
            0
        } else {
            try {
                context.resources.getIdentifier(sound, "raw", context.packageName)
            } catch (e: Exception) {
                Log.w(TAG, "Failed to resolve raw resource '$sound': ${e.message}")
                0
            }
        }
        if (resId != 0) {
            if (createResourceMediaPlayer(resId)) return
            Log.w(TAG, "Raw resource $resId not playable, falling back to uri path")
        }

        // Fallback: default/system ringtone (or a URI-based raw resource).
        val uri = sound?.let { getRingtoneUri(it) }
        if (uri == null) {
            // Failed to get ringtone url, can't play sound
            return
        }
        try {
            ringtone = RingtoneManager.getRingtone(context, uri)
            if (ringtone == null) {
                // RingtoneManager.getRingtone() can still return null on some
                // OEM skins even for valid URIs; thin deeply into a looping
                // MediaPlayer before giving up.
                ringtonePlayer = createFallbackMediaPlayer(uri)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                ringtone?.setAudioAttributes(ringtoneAudioAttributes())
            } else {
                ringtone?.streamType = AudioManager.STREAM_RING
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ringtone?.isLooping = true
            }
            ringtone?.play()
        } catch (e: Exception) {
            e.printStackTrace()
        }
    }

    /**
     * Plays the bundled raw [resId] ringtone with a looping [MediaPlayer] on
     * the RING stream (honoring the ringer volume). Unlike the
     * RingtoneManager path this works reliably on every OEM, including
     * MIUI/HyperOS. Returns false when the resource cannot be played.
     */
    private fun createResourceMediaPlayer(resId: Int): Boolean {
        return try {
            val player: MediaPlayer? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    MediaPlayer.create(
                        context,
                        resId,
                        ringtoneAudioAttributes(),
                        -1
                    )
                } else {
                    MediaPlayer.create(context, resId)
                }
            if (player == null) return false
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
                @Suppress("DEPRECATION")
                player.setAudioStreamType(AudioManager.STREAM_RING)
            }
            player.isLooping = true
            player.start()
            ringtonePlayer = player
            true
        } catch (e: Exception) {
            Log.w(TAG, "MediaPlayer(resId=$resId) ringtone failed: ${e.message}")
            try { releaseRingtonePlayer() } catch (_: Throwable) {}
            false
        }
    }

    private fun ringtoneAudioAttributes(): AudioAttributes {
        return AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION_RINGTONE)
            .setLegacyStreamType(AudioManager.STREAM_RING)
            .build()
    }

    /**
     * Plays [uri] (expected to be an `android.resource://` raw resource) with a
     * looping [MediaPlayer] on the RING stream, honoring the ringer volume.
     * Returns null when the resource cannot be played.
     */
    private fun createFallbackMediaPlayer(uri: Uri): MediaPlayer? {
        return try {
            val player: MediaPlayer? =
                if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                    MediaPlayer.create(
                        context,
                        uri,
                        null,
                        ringtoneAudioAttributes(),
                        -1
                    )
                } else {
                    MediaPlayer.create(context, uri)
                }
            if (player == null) return null
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.LOLLIPOP) {
                @Suppress("DEPRECATION")
                player.setAudioStreamType(AudioManager.STREAM_RING)
            }
            player.isLooping = true
            player.start()
            player
        } catch (e: Exception) {
            Log.w(TAG, "MediaPlayer ringtone fallback failed: ${e.message}")
            null
        }
    }

    private fun getRingtoneUri(fileName: String): Uri? {
        if (TextUtils.isEmpty(fileName)) {
            return getDefaultRingtoneUri()
        }
        
        // If system_ringtone_default is explicitly requested, bypass resource check
        if (fileName.equals("system_ringtone_default", true)) {
            return getDefaultRingtoneUri(useSystemDefault = true)
        }

        try {
            val resId = context.resources.getIdentifier(fileName, "raw", context.packageName)
            if (resId != 0) {
                return Uri.parse("android.resource://${context.packageName}/$resId")
            }

            // For any other unresolved filename, return the default ringtone
            return getDefaultRingtoneUri()
        } catch (e: Exception) {
            // If anything fails, try to return the system default ringtone
            return getDefaultRingtoneUri()
        }
    }

    private fun getDefaultRingtoneUri(useSystemDefault: Boolean = false): Uri? {
        try {
            if (!useSystemDefault) {
                // First try to use ringtone_default resource if it exists
                val resId = context.resources.getIdentifier("ringtone_default", "raw", context.packageName)
                if (resId != 0) {
                    return Uri.parse("android.resource://${context.packageName}/$resId")
                }
            }

            // Fall back to system default ringtone
            return RingtoneManager.getActualDefaultRingtoneUri(
                context,
                RingtoneManager.TYPE_RINGTONE
            )
        } catch (e: Exception) {
            // getActualDefaultRingtoneUri can throw an exception on some devices
            // for custom ringtones
            return getSafeSystemRingtoneUri()
        }
    }

    private fun getSafeSystemRingtoneUri(): Uri? {
        try {
            val defaultUri = RingtoneManager.getActualDefaultRingtoneUri(
                context,
                RingtoneManager.TYPE_RINGTONE
            )

            val rm = RingtoneManager(context)
            rm.setType(RingtoneManager.TYPE_RINGTONE)
            val cursor = rm.cursor
            if (defaultUri != null && cursor != null) {
                while (cursor.moveToNext()) {
                    val uri = rm.getRingtoneUri(cursor.position)
                    if (uri == defaultUri) {
                        cursor.close()
                        return defaultUri
                    }
                }
            }

            // Default isn't system-provided → fallback to first available
            if (cursor != null && cursor.moveToFirst()) {
                val fallback = rm.getRingtoneUri(cursor.position)
                cursor.close()
                return fallback
            }
        } catch (e: Exception) {
            e.printStackTrace()
        }
        return null
    }
}