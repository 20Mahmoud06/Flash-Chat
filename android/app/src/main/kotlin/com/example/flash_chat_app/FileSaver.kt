package com.example.flash_chat_app

import android.content.ContentValues
import android.content.Context
import android.os.Build
import android.os.Environment
import android.provider.MediaStore
import java.io.File
import java.io.FileOutputStream

/**
 * Native support for file messages: reports the Android SDK level to Dart (so
 * the Dart layer knows whether the legacy storage permission applies) and
 * writes downloaded files into the device's public Downloads folder.
 *
 * - Android 10+ (API 29): scoped storage is enforced, so files go through
 *   [MediaStore.Downloads] with a `Download/` relative path — no permission
 *   needed.
 * - Android 9 and below: public Downloads is addressed by a direct file path;
 *   the WRITE_EXTERNAL_STORAGE permission (declared with `maxSdkVersion=29`)
 *   is requested by the Dart layer before this is invoked.
 */
object FileSaver {

    fun sdkInt(): Int = Build.VERSION.SDK_INT

    fun saveToDownloads(
        context: Context,
        cachePath: String,
        fileName: String,
        mimeType: String
    ): String? {
        val src = File(cachePath)
        if (!src.exists()) return null
        val bytes = try {
            src.readBytes()
        } catch (e: Exception) {
            return null
        }

        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
            val values = ContentValues().apply {
                put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
                put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
                put(MediaStore.MediaColumns.RELATIVE_PATH, Environment.DIRECTORY_DOWNLOADS)
            }
            val uri = context.contentResolver
                .insert(MediaStore.Downloads.EXTERNAL_CONTENT_URI, values)
                ?: return null
            try {
                context.contentResolver.openOutputStream(uri)?.use { it.write(bytes) }
            } catch (e: Exception) {
                context.contentResolver.delete(uri, null, null)
                return null
            }
            fileName
        } else {
            val downloadDir = Environment.getExternalStoragePublicDirectory(
                Environment.DIRECTORY_DOWNLOADS
            ) ?: return null
            if (!downloadDir.exists() && !downloadDir.mkdirs()) return null
            val dest = File(downloadDir, fileName)
            try {
                FileOutputStream(dest).use { it.write(bytes) }
            } catch (e: Exception) {
                return null
            }
            dest.absolutePath
        }
    }
}