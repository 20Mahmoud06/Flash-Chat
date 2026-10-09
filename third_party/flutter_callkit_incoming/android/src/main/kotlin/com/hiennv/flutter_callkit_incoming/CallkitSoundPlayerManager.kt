package com.hiennv.flutter_callkit_incoming

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.media.AudioAttributes
import android.media.AudioFocusRequest
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

    var isPlaying: Boolean = false
        private set

    /// Audio-focus bookkeeping so we can release when the ring stops.
    private var audioFocusRequest: AudioFocusRequest? = null


    fun play(data: Bundle) {
        this.isPlaying = true
        this.prepare()
        this.playSound(data)
        this.playVibrator()
    }

    fun stop() {
        this.isPlaying = false

        ringtone?.stop()
        releaseRingtonePlayer()
        vibrator?.cancel()
        abandonAudioFocus()
        ringtone = null
        vibrator = null
    }

    fun destroy() {
        this.isPlaying = false

        ringtone?.stop()
        releaseRingtonePlayer()
        vibrator?.cancel()
        abandonAudioFocus()
        ringtone = null
        vibrator = null
    }

    private fun prepare() {
        ringtone?.stop()
        releaseRingtonePlayer()
        vibrator?.cancel()
        abandonAudioFocus()
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

    // --------------- Audio focus ---------------

    /**
     * Requests audio focus on the given [streamType] with [attrs]. Uses
     * [AudioManager.AUDIOFOCUS_GAIN] (not GAIN_TRANSIENT) because MIUI /
     * HyperOS silently ignores transient requests on the RING stream.
     */
    private fun requestAudioFocus(
        attrs: AudioAttributes = ringtoneAudioAttributes(),
        streamType: Int = AudioManager.STREAM_RING
    ): Boolean {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as AudioManager
        audioManager = am
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val request = AudioFocusRequest.Builder(AudioManager.AUDIOFOCUS_GAIN)
                .setAudioAttributes(attrs)
                .setOnAudioFocusChangeListener { }
                .build()
            val result = am.requestAudioFocus(request)
            audioFocusRequest = request
            return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        } else {
            @Suppress("DEPRECATION")
            val result = am.requestAudioFocus(
                { },
                streamType,
                AudioManager.AUDIOFOCUS_GAIN
            )
            return result == AudioManager.AUDIOFOCUS_REQUEST_GRANTED
        }
    }

    private fun abandonAudioFocus() {
        val am = audioManager
            ?: (context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager)
            ?: return
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            audioFocusRequest?.let { am.abandonAudioFocusRequest(it) }
        } else {
            @Suppress("DEPRECATION")
            am.abandonAudioFocus { }
        }
        audioFocusRequest = null
    }

    // --------------- Vibration ---------------

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

    // --------------- Sound ---------------

    private fun playSound(data: Bundle?) {
        val am = context.getSystemService(Context.AUDIO_SERVICE) as? AudioManager
        val ringerMode = am?.ringerMode ?: AudioManager.RINGER_MODE_NORMAL
        if (ringerMode == AudioManager.RINGER_MODE_SILENT || ringerMode == AudioManager.RINGER_MODE_VIBRATE) {
            Log.d(TAG, "Device is in silent or vibrate mode ($ringerMode), skipping audible ringtone")
            return
        }

        val sound = data?.getString(
            CallkitConstants.EXTRA_CALLKIT_RINGTONE_PATH,
            ""
        )

        // Preferred path: play the bundled raw resource through a looping
        // MediaPlayer created straight from the raw resource fd. This bypasses
        // RingtoneManager entirely, whose handling of "android.resource://"
        // URIs returns a non-null-but-SILENT ringtone on several OEM skins
        // (most notably MIUI/HyperOS).
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
                ringtonePlayer = createFallbackMediaPlayer(uri)
                return
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                ringtone?.setAudioAttributes(alarmAudioAttributes())
            } else {
                ringtone?.streamType = AudioManager.STREAM_ALARM
            }
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                ringtone?.isLooping = true
            }
            ringtone?.play()
        } catch (e: Exception) {
            Log.e(TAG, "Ringtone fallback failed: ${e.message}")
            ringtonePlayer = createFallbackMediaPlayer(uri)
        }
    }

    /**
     * Plays the bundled raw [resId] ringtone with a looping [MediaPlayer].
     * Tries multiple audio streams in order of reliability:
     *
     *  1. RING — standard ringtone stream; honors ringer volume.
     *  2. ALARM — never ducked or suppressed by any OEM skin (MIUI, EMUI,
     *     OneUI, etc.), so it acts as a reliable fallback.
     *  3. NOTIFICATION — last-resort fallback.
     */
    private fun createResourceMediaPlayer(resId: Int): Boolean {
        // Attempt 1: RING stream
        requestAudioFocus(ringtoneAudioAttributes(), AudioManager.STREAM_RING)
        if (tryPlayResourceOnStream(
                resId,
                ringtoneAudioAttributes(),
                AudioManager.STREAM_RING
            )
        ) {
            Log.d(TAG, "Playing ring on RING stream")
            return true
        }

        // Attempt 2: ALARM stream fallback
        requestAudioFocus(alarmAudioAttributes(), AudioManager.STREAM_ALARM)
        if (tryPlayResourceOnStream(
                resId,
                alarmAudioAttributes(),
                AudioManager.STREAM_ALARM
            )
        ) {
            Log.d(TAG, "Playing ring on ALARM stream")
            return true
        }

        // Attempt 3: NOTIFICATION stream fallback
        val notifAttrs = AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_NOTIFICATION)
            .setLegacyStreamType(AudioManager.STREAM_NOTIFICATION)
            .build()
        requestAudioFocus(notifAttrs, AudioManager.STREAM_NOTIFICATION)
        if (tryPlayResourceOnStream(resId, notifAttrs, AudioManager.STREAM_NOTIFICATION)) {
            Log.d(TAG, "Playing ring on NOTIFICATION stream")
            return true
        }

        Log.e(TAG, "All audio streams failed for resId=$resId")
        return false
    }

    /**
     * Creates a looping [MediaPlayer] for [resId] on [streamType] with the
     * given [attrs]. Returns `true` and stores the player when playback
     * actually starts; returns `false` on any failure.
     */
    private fun tryPlayResourceOnStream(
        resId: Int,
        attrs: AudioAttributes,
        streamType: Int
    ): Boolean {
        return try {
            releaseRingtonePlayer()
            val afd = context.resources.openRawResourceFd(resId) ?: return false
            val player = MediaPlayer()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                player.setAudioAttributes(attrs)
            } else {
                @Suppress("DEPRECATION")
                player.setAudioStreamType(streamType)
            }
            player.setDataSource(afd.fileDescriptor, afd.startOffset, afd.length)
            afd.close()
            player.prepare()
            player.isLooping = true
            player.start()
            if (!player.isPlaying) {
                Log.w(TAG, "MediaPlayer.start() did not start playing on stream $streamType")
                try { player.release() } catch (_: Throwable) {}
                return false
            }
            ringtonePlayer = player
            true
        } catch (e: Exception) {
            Log.w(TAG, "MediaPlayer(resId=$resId, stream=$streamType) failed: ${e.message}")
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
     * ALARM audio attributes — used as a fallback when the RING stream is
     * silenced by the OEM skin. The ALARM stream is never ducked or
     * suppressed, ensuring the ring is always audible.
     */
    private fun alarmAudioAttributes(): AudioAttributes {
        return AudioAttributes.Builder()
            .setContentType(AudioAttributes.CONTENT_TYPE_SONIFICATION)
            .setUsage(AudioAttributes.USAGE_ALARM)
            .setLegacyStreamType(AudioManager.STREAM_ALARM)
            .build()
    }

    /**
     * Plays [uri] with a looping [MediaPlayer] on the ALARM stream.
     * Returns null when the resource cannot be played.
     */
    private fun createFallbackMediaPlayer(uri: Uri): MediaPlayer? {
        return try {
            val player = MediaPlayer()
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP) {
                player.setAudioAttributes(alarmAudioAttributes())
            } else {
                @Suppress("DEPRECATION")
                player.setAudioStreamType(AudioManager.STREAM_ALARM)
            }
            player.setDataSource(context, uri)
            player.prepare()
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
