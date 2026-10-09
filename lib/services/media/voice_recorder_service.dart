import 'dart:io';
import 'dart:math' as math;
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

  /// Stream of normalized (0..1) loudness for the live waveform.
  /// The record plugin reports dBFS (negative values), so we convert to a
  /// linear scale the UI can draw nice bars with.
  Stream<double> get amplitudeStream =>
      _recorder
          .onAmplitudeChanged(const Duration(milliseconds: 100))
          .map((amp) {
        final linear = math.pow(10.0, amp.current / 20.0).toDouble();
        return linear.clamp(0.0, 1.0);
      });

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
