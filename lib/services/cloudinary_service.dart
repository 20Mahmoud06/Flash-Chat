import 'dart:convert';
import 'dart:io';
import 'package:http/http.dart' as http;
import '../utils/cloudinary_config.dart';

class CloudinaryService {
  static Future<String> uploadFileWithProgress({
    required File file,
    required String preset,
    required String resourceType,
    required void Function(double progress) onProgress,
  }) async {
    final uri = Uri.parse(
      'https://api.cloudinary.com/v1_1/${CloudinaryConfig.cloudName}/$resourceType/upload',
    );

    final request = http.MultipartRequest('POST', uri)
      ..fields['upload_preset'] = preset
      ..files.add(await http.MultipartFile.fromPath('file', file.path));

    final streamedResponse = await request.send();

    final totalBytes = streamedResponse.contentLength ?? file.lengthSync();
    int bytesTransferred = 0;

    final bytes = <int>[];

    await for (final chunk in streamedResponse.stream) {
      bytesTransferred += chunk.length;
      onProgress(bytesTransferred / totalBytes);
      bytes.addAll(chunk);
    }

    final body = utf8.decode(bytes);
    final json = jsonDecode(body);

    if (streamedResponse.statusCode == 200) {
      return json['secure_url'];
    } else {
      throw Exception('Cloudinary upload failed: $body');
    }
  }
}
