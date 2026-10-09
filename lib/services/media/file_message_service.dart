import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:open_filex/open_filex.dart';
import 'package:path_provider/path_provider.dart';
import 'package:permission_handler/permission_handler.dart';

/// Helpers for sending, downloading, saving and opening file/audio messages
/// (PDF, Word, Excel and audio files) inside the chat.
///
/// Uploads go through Cloudinary (see ChatCubit); this service owns everything
/// that happens on the RECEIVING side: downloading the bytes, persisting them
/// into the device's Downloads folder via a small native bridge, and handing
/// them to the right external app via [OpenFilex].
class FileMessageService {
  FileMessageService._();

  static const MethodChannel _saveChannel = MethodChannel('flash_chat/file_save');

  /// Document / presentation / archive / text types accepted by the attach
  /// button, mirroring the allowed formats of the `flash_chat_files` preset.
  static const Set<String> documentExtensions = {
    'pdf',
    'doc',
    'docx',
    'xls',
    'xlsx',
    'ppt',
    'pptx',
    'txt',
    'csv',
    'zip',
    'rar',
  };

  /// Audio types accepted by the attach button (played like voice messages).
  static const Set<String> audioExtensions = {
    'mp3',
    'm4a',
    'wav',
    'ogg',
    'aac',
    'flac',
    'amr',
  };

  /// Every extension the attach picker offers.
  static const List<String> allowedExtensions = [
    ...documentExtensions,
    ...audioExtensions,
  ];

  static bool isAudioFileName(String fileName) {
    final ext = fileExtension(fileName);
    return audioExtensions.contains(ext);
  }

  static bool isDocumentFileName(String fileName) {
    final ext = fileExtension(fileName);
    return documentExtensions.contains(ext);
  }

  /// Lower-cased extension of [fileName] without the dot (e.g. `report.pdf`
  /// -> `pdf`). Empty when the name has no extension.
  static String fileExtension(String fileName) {
    final dot = fileName.lastIndexOf('.');
    if (dot < 0 || dot == fileName.length - 1) return '';
    return fileName.substring(dot + 1).toLowerCase();
  }

  /// Best-effort MIME type guessed from the extension: used for the MediaStore
  /// insert and for opening the file in the correct external app.
  static String mimeTypeFromName(String fileName) {
    switch (fileExtension(fileName)) {
      case 'pdf':
        return 'application/pdf';
      case 'doc':
        return 'application/msword';
      case 'docx':
        return 'application/vnd.openxmlformats-officedocument.wordprocessingml.document';
      case 'xls':
        return 'application/vnd.ms-excel';
      case 'xlsx':
        return 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet';
      case 'ppt':
        return 'application/vnd.ms-powerpoint';
      case 'pptx':
        return 'application/vnd.openxmlformats-officedocument.presentationml.presentation';
      case 'txt':
        return 'text/plain';
      case 'csv':
        return 'text/csv';
      case 'zip':
        return 'application/zip';
      case 'rar':
        return 'application/vnd.rar';
      case 'mp3':
        return 'audio/mpeg';
      case 'm4a':
        return 'audio/mp4';
      case 'wav':
        return 'audio/wav';
      case 'ogg':
        return 'audio/ogg';
      case 'aac':
        return 'audio/aac';
      case 'flac':
        return 'audio/flac';
      case 'amr':
        return 'audio/amr';
    }
    return 'application/octet-stream';
  }

  /// Icon + accent color for a file bubble, chosen from the file type.
  static ({IconData icon, Color color}) iconFor(String fileName) {
    if (isAudioFileName(fileName)) {
      return (icon: Icons.music_note_rounded, color: Colors.deepPurpleAccent);
    }
    switch (fileExtension(fileName)) {
      case 'pdf':
        return (icon: Icons.picture_as_pdf_rounded, color: Colors.redAccent);
      case 'doc':
      case 'docx':
        return (icon: Icons.description_rounded, color: Colors.blueAccent);
      case 'xls':
      case 'xlsx':
      case 'csv':
        return (icon: Icons.table_chart_rounded, color: Colors.green.shade600);
      case 'ppt':
      case 'pptx':
        return (icon: Icons.slideshow_rounded, color: Colors.orangeAccent);
      case 'txt':
        return (icon: Icons.article_rounded, color: Colors.blueGrey);
      case 'zip':
      case 'rar':
        return (icon: Icons.folder_zip_rounded, color: Colors.amber.shade700);
    }
    return (icon: Icons.insert_drive_file_rounded, color: Colors.blueGrey);
  }

  /// 1.2 MB / 850 KB / 320 B style, matching the display conventions used for
  /// video/file sizes.
  static String formatFileSize(int bytes) {
    if (bytes <= 0) return '';
    if (bytes < 1024) return '$bytes B';
    final kb = bytes / 1024;
    if (kb < 1024) return '${kb.toStringAsFixed(kb >= 100 ? 0 : 1)} KB';
    final mb = kb / 1024;
    return '${mb.toStringAsFixed(mb >= 100 ? 0 : 1)} MB';
  }

  /// Probes a local audio file and returns its total length in whole seconds.
  /// Used when sending audio attachments so the bubble can show the real
  /// duration immediately instead of starting at 0:00. Null when the file's
  /// duration can't be read.
  static Future<int?> audioDurationSeconds(String path) async {
    try {
      final player = AudioPlayer();
      try {
        await player.setFilePath(path);
        final duration = player.duration;
        if (duration != null && duration.inSeconds > 0) {
          return duration.inSeconds;
        }
      } finally {
        await player.dispose();
      }
    } catch (e) {
      debugPrint('Failed to read audio duration: $e');
    }
    return null;
  }

  /// Android SDK level reported by the native (Kotlin) side, so the Dart layer
  /// knows whether the public Downloads folder needs a storage permission
  /// (API < 29) or can be written through MediaStore without one (API >= 29).
  static Future<int?> sdkInt() async {
    try {
      return await _saveChannel.invokeMethod<int>('getSdkInt');
    } catch (e) {
      debugPrint('Failed to read Android SDK int: $e');
      return null;
    }
  }

  /// Local + downloadable file cache dir: lets receivers re-open a file
  /// without re-downloading and lets the native saver hand its bytes over
  /// without holding them in memory on the Dart side.
  static Future<Directory> _cacheDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/flash_files');
    await dir.create(recursive: true);
    return dir;
  }

  static Future<File?> cachedFile(String fileName) async {
    final dir = await _cacheDir();
    final file = File('${dir.path}/$fileName');
    return await file.exists() ? file : null;
  }

  /// Downloads [url] (a Cloudinary raw/media link) into the app cache and
  /// returns the local [File]. Existing cached copies are reused so tapping a
  /// file a second time opens instantly.
  static Future<File> downloadToCache(
    String url,
    String fileName, {
    void Function(double progress)? onProgress,
  }) async {
    final cached = await cachedFile(fileName);
    if (cached != null) return cached;

    final dir = await _cacheDir();
    final target = File('${dir.path}/$fileName');
    final response = await http.get(Uri.parse(url));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw Exception('Failed to download file (${response.statusCode})');
    }
    onProgress?.call(0.5);
    await target.writeAsBytes(response.bodyBytes, flush: true);
    onProgress?.call(1.0);
    return target;
  }

  /// Persists [cachePath] into the device's public Downloads folder (through
  /// MediaStore on Android 10+, direct write on older devices where the
  /// storage permission was previously granted/requested). Returns the display
  /// file name on success, null on failure.
  static Future<String?> saveToDownloads(String cachePath, String fileName) async {
    try {
      final sdk = await sdkInt();
      // Only Android 9 (API 28) and below need a storage permission to write
      // into public Downloads; newer versions go through MediaStore and need
      // none. Requesting the legacy permission on Android 13+ returns denied
      // unconditionally, which would wrongly abort the save.
      if (sdk != null && sdk < 29) {
        final status = await Permission.storage.request();
        if (status != PermissionStatus.granted) return null;
      }
      final saved = await _saveChannel.invokeMethod<String>('saveToDownloads', {
        'cachePath': cachePath,
        'fileName': fileName,
        'mimeType': mimeTypeFromName(fileName),
      });
      return (saved == null || saved.isEmpty) ? fileName : saved;
    } catch (e) {
      debugPrint('Failed to save file to Downloads: $e');
      return null;
    }
  }

  /// Resolves the right external app for [file] (PDF readers, Office, music
  /// players...) and opens it. Shows the standard "deleted file" fallback when
  /// the local copy is gone.
  static Future<void> open(String path) async {
    final result = await OpenFilex.open(path);
    if (result.type != ResultType.done) {
      debugPrint('OpenFilex failed: ${result.type} ${result.message}');
    }
  }
}