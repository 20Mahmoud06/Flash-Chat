import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:gal/gal.dart';
import 'package:path_provider/path_provider.dart';

/// Downloads a network image/video and saves it into the device gallery.
/// Shows feedback to the user (in the app's colors) through [context].

Future<void> saveImageToGallery(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    final response = await http.get(Uri.parse(url));
    if (response.statusCode != 200) {
      throw Exception('download failed (${response.statusCode})');
    }
    if (!await _ensureAccess()) return;
    await Gal.putImageBytes(response.bodyBytes);
    _showSnackbar(messenger,
        message: 'Photo saved to gallery', success: true);
  } catch (e) {
    debugPrint('Save image error: $e');
    _showSnackbar(messenger,
        message: 'Could not save photo', success: false);
  }
}

Future<void> saveVideoToGallery(BuildContext context, String url) async {
  final messenger = ScaffoldMessenger.of(context);
  try {
    if (!await _ensureAccess()) return;
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/flash_chat_${DateTime.now().millisecondsSinceEpoch}.mp4',
    );
    final request = http.Request('GET', Uri.parse(url));
    final streamed = await http.Client().send(request);
    if (streamed.statusCode != 200) {
      throw Exception('download failed (${streamed.statusCode})');
    }
    final sink = file.openWrite();
    await streamed.stream.pipe(sink);
    await sink.close();
    await Gal.putVideo(file.path);
    _showSnackbar(messenger,
        message: 'Video saved to gallery', success: true);
  } catch (e) {
    debugPrint('Save video error: $e');
    _showSnackbar(messenger,
        message: 'Could not save video', success: false);
  }
}

Future<bool> _ensureAccess() async {
  if (await Gal.hasAccess()) return true;
  final granted = await Gal.requestAccess();
  return granted && (await Gal.hasAccess());
}

void _showSnackbar(ScaffoldMessengerState messenger,
    {required String message, required bool success}) {
  messenger
    ..hideCurrentSnackBar()
    ..showSnackBar(
      SnackBar(
        content: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            gradient: success
                ? const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Colors.lightBlueAccent, Color(0xFF0288D1)],
                  )
                : const LinearGradient(
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                    colors: [Color(0xFFEF5350), Color(0xFFB71C1C)],
                  ),
            borderRadius: BorderRadius.circular(14),
            boxShadow: [
              BoxShadow(
                color: success
                    ? Colors.lightBlueAccent.withValues(alpha: 0.35)
                    : Colors.red.withValues(alpha: 0.35),
                blurRadius: 12,
                offset: const Offset(0, 4),
              ),
            ],
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                success ? Icons.check_circle : Icons.error_outline,
                color: Colors.white,
                size: 22,
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Text(
                  message,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
        padding: EdgeInsets.zero,
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        duration: const Duration(seconds: 2),
      ),
    );
}