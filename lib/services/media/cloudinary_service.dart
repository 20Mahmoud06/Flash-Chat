import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../../config/cloudinary_config.dart';

class CloudinaryService {
  static const Duration _uploadTimeout = Duration(minutes: 5);

  static Future<String> uploadFileWithProgress({
    required File file,
    required String preset,
    required String resourceType,
    required void Function(double progress) onProgress,
  }) async {
    final fileLength = await file.length();
    if (fileLength <= 0) {
      throw Exception('Cannot upload an empty file.');
    }

    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/$resourceType/upload',
    );

    var uploadedBytes = 0;
    onProgress(0);

    final uploadStream = file.openRead().transform(
      StreamTransformer<List<int>, List<int>>.fromHandlers(
        handleData: (chunk, sink) {
          uploadedBytes += chunk.length;
          final progress = uploadedBytes / fileLength;
          onProgress(progress.clamp(0.0, 0.95).toDouble());
          sink.add(chunk);
        },
      ),
    );

    final fileName = file.uri.pathSegments.isNotEmpty
        ? file.uri.pathSegments.last
        : 'upload';

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = preset
      ..files.add(http.MultipartFile(
        'file',
        uploadStream,
        fileLength,
        filename: fileName,
      ));

    final streamedResponse = await request.send().timeout(_uploadTimeout);
    final body =
        await streamedResponse.stream.bytesToString().timeout(_uploadTimeout);

    final json = jsonDecode(body);

    if (streamedResponse.statusCode >= 200 &&
        streamedResponse.statusCode < 300) {
      final secureUrl = json['secure_url'] as String?;
      if (secureUrl == null || secureUrl.isEmpty) {
        throw Exception('Cloudinary upload did not return a URL.');
      }
      onProgress(1);
      return secureUrl;
    }

    throw Exception('Cloudinary upload failed: $body');
  }
}
