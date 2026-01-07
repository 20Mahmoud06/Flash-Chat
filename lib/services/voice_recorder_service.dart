import 'dart:io';
import 'package:path_provider/path_provider.dart';
import 'package:record/record.dart';

class VoiceRecorderService {
  final AudioRecorder _recorder = AudioRecorder();
  String? _path;

  Future<void> start() async {
    if (!await _recorder.hasPermission()) {
      throw Exception('Microphone permission denied');
    }

    final dir = await getTemporaryDirectory();
    _path = '${dir.path}/voice_${DateTime.now().millisecondsSinceEpoch}.m4a';

    await _recorder.start(
      const RecordConfig(
        encoder: AudioEncoder.aacLc,
        bitRate: 128000,
        sampleRate: 44100,
      ),
      path: _path!,
    );
  }

  Future<void> pause() => _recorder.pause();

  Future<void> resume() => _recorder.resume();

  Future<File?> stop() async {
    final path = await _recorder.stop();
    if (path == null) return null;
    return File(path);
  }

  Future<void> dispose() async {
    await _recorder.dispose();
  }
}