import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import '../../core/utils/video_playback_url.dart';

/// Disk caching service for chat videos.
///
/// Ensures videos are downloaded once and replayed/reopened directly from local
/// disk storage without consuming network data or causing Cloudinary transcode
/// latency.
class VideoCacheService {
  VideoCacheService._();
  static final VideoCacheService instance = VideoCacheService._();

  static const String _cacheSubdir = 'flash_videos';
  final Map<String, Future<File?>> _inFlightDownloads = {};

  Future<Directory> _getCacheDir() async {
    final tmp = await getTemporaryDirectory();
    final dir = Directory('${tmp.path}/$_cacheSubdir');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  String _cacheKey(String url) {
    return md5.convert(utf8.encode(url.trim())).toString();
  }

  /// Checks if a video URL is already cached locally and returns the [File],
  /// or `null` if not yet cached.
  ///
  /// Checks both the exact URL and its canonical raw URL equivalent (if
  /// Cloudinary transforms were applied) so pre-cached uploads or alternate
  /// stream variants match the same file.
  Future<File?> getCachedFile(String url) async {
    if (url.isEmpty) return null;
    try {
      final dir = await _getCacheDir();
      final key = _cacheKey(url);
      final file = File('${dir.path}/$key.mp4');
      if (await file.exists() && (await file.length()) > 0) {
        return file;
      }

      // Check canonical raw URL fallback
      final rawUrl = videoRawUrl(url);
      if (rawUrl.isNotEmpty && rawUrl != url) {
        final rawKey = _cacheKey(rawUrl);
        final rawFile = File('${dir.path}/$rawKey.mp4');
        if (await rawFile.exists() && (await rawFile.length()) > 0) {
          return rawFile;
        }
      }
    } catch (e) {
      debugPrint('VideoCacheService.getCachedFile error: $e');
    }
    return null;
  }

  /// Downloads [url] to the local video cache if not already present.
  /// Deduplicates concurrent download requests for the same URL.
  Future<File?> downloadAndCache(String url) async {
    if (url.isEmpty) return null;

    final existing = await getCachedFile(url);
    if (existing != null) return existing;

    final key = _cacheKey(url);
    if (_inFlightDownloads.containsKey(key)) {
      return _inFlightDownloads[key]!;
    }

    final future = _doDownload(url, key);
    _inFlightDownloads[key] = future;
    try {
      final result = await future;
      return result;
    } finally {
      _inFlightDownloads.remove(key);
    }
  }

  Future<File?> _doDownload(String url, String key) async {
    try {
      final dir = await _getCacheDir();
      final targetFile = File('${dir.path}/$key.mp4');
      final tempFile = File('${dir.path}/$key.tmp');

      final uri = Uri.tryParse(url);
      if (uri == null) return null;

      final response = await http.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        debugPrint(
            'VideoCacheService download failed (${response.statusCode}): $url');
        return null;
      }

      if (response.bodyBytes.isEmpty) return null;

      await tempFile.writeAsBytes(response.bodyBytes, flush: true);
      if (await targetFile.exists()) {
        await targetFile.delete();
      }
      await tempFile.rename(targetFile.path);

      // Also create an alias/link for the canonical raw URL if different
      final raw = videoRawUrl(url);
      if (raw.isNotEmpty && raw != url) {
        final rawKey = _cacheKey(raw);
        final rawFile = File('${dir.path}/$rawKey.mp4');
        if (!await rawFile.exists()) {
          try {
            await targetFile.copy(rawFile.path);
          } catch (_) {}
        }
      }

      return targetFile;
    } catch (e) {
      debugPrint('VideoCacheService _doDownload error for $url: $e');
      return null;
    }
  }

  /// Pre-caches a local [sourceFile] for [url].
  ///
  /// Called immediately when a user sends a video, saving the sender from
  /// having to download their own freshly uploaded video back from Cloudinary.
  Future<void> putLocalFile(String url, File sourceFile) async {
    if (url.isEmpty || !await sourceFile.exists()) return;
    try {
      final dir = await _getCacheDir();
      final key = _cacheKey(url);
      final targetFile = File('${dir.path}/$key.mp4');

      if (!await targetFile.exists() || (await targetFile.length()) == 0) {
        await sourceFile.copy(targetFile.path);
      }

      final raw = videoRawUrl(url);
      if (raw.isNotEmpty && raw != url) {
        final rawKey = _cacheKey(raw);
        final rawFile = File('${dir.path}/$rawKey.mp4');
        if (!await rawFile.exists()) {
          await sourceFile.copy(rawFile.path);
        }
      }

      final compat = videoCompatUrl(url);
      if (compat.isNotEmpty && compat != url) {
        final compatKey = _cacheKey(compat);
        final compatFile = File('${dir.path}/$compatKey.mp4');
        if (!await compatFile.exists()) {
          await sourceFile.copy(compatFile.path);
        }
      }
    } catch (e) {
      debugPrint('VideoCacheService.putLocalFile error: $e');
    }
  }
}
