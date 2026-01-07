import 'dart:async';
import 'dart:math';
import 'dart:io';
import 'package:flutter/material.dart';
import '../services/voice_recorder_service.dart';

class VoiceRecordUI extends StatefulWidget {
  final Function(File file, int duration) onSend;
  final VoidCallback onCancel;

  const VoiceRecordUI({
    super.key,
    required this.onSend,
    required this.onCancel,
  });

  @override
  State<VoiceRecordUI> createState() => _VoiceRecordUIState();
}

class _VoiceRecordUIState extends State<VoiceRecordUI>
    with SingleTickerProviderStateMixin {
  final _recorder = VoiceRecorderService();
  int _seconds = 0;
  bool _isPaused = false;
  Timer? _timer;
  late AnimationController _waveController;

  @override
  void initState() {
    super.initState();
    _waveController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    );
    _startRecording();
  }

  Future<void> _startRecording() async {
    await _recorder.start();
    _startTimer();
    _waveController.repeat(reverse: true);
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused) {
        setState(() => _seconds++);
      }
    });
  }

  Future<void> _pauseResume() async {
    if (_isPaused) {
      await _recorder.resume();
      _startTimer();
      _waveController.repeat(reverse: true);
    } else {
      await _recorder.pause();
      _timer?.cancel();
      _waveController.stop();
    }
    setState(() => _isPaused = !_isPaused);
  }

  Future<void> _send() async {
    _timer?.cancel();
    _waveController.stop();
    final file = await _recorder.stop();
    if (file != null) {
      widget.onSend(file, _seconds);
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    _waveController.stop();
    await _recorder.stop();
    widget.onCancel();
  }

  @override
  void dispose() {
    _timer?.cancel();
    _waveController.dispose();
    super.dispose();
  }

  String get _formattedTime {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final waveColor = _isPaused ? Colors.grey : Colors.lightBlueAccent;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.grey[200],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          /// Cancel
          IconButton(
            icon: const Icon(Icons.close, color: Colors.red),
            onPressed: _cancel,
          ),

          /// Waveform
          Expanded(
            child: AnimatedBuilder(
              animation: _waveController,
              builder: (_, __) => LayoutBuilder(
                builder: (context, constraints) {
                  final availableWidth = constraints.maxWidth;
                  const numBars = 20;
                  final barWidth = min(3.0, availableWidth / numBars);
                  return Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: List.generate(numBars, (index) {
                      final phase = (index / (numBars - 1)) * 2 * pi;
                      final heightFactor = (sin(phase + _waveController.value * 2 * pi) + 1) / 2;
                      return Container(
                        width: barWidth,
                        height: 8 + 24 * heightFactor,
                        decoration: BoxDecoration(
                          color: waveColor.withOpacity(0.8),
                          borderRadius: BorderRadius.circular(barWidth / 2),
                        ),
                      );
                    }),
                  );
                },
              ),
            ),
          ),

          /// Timer
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Text(
              _formattedTime,
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
          ),

          /// Pause / Resume
          IconButton(
            icon: Icon(_isPaused ? Icons.play_arrow : Icons.pause, color: Colors.grey[800]),
            onPressed: _pauseResume,
          ),

          /// Send
          IconButton(
            icon: const Icon(Icons.send, color: Colors.lightBlueAccent),
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}