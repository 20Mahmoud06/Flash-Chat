import 'dart:async';
import 'dart:io';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../core/theme/app_theme.dart';
import '../../services/media/voice_recorder_service.dart';

/// Premium voice recording pill shown inside the composer.
/// Features a live amplitude waveform, timer, pause/resume and a gradient
/// send button that fits perfectly inside its own border.
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
  StreamSubscription<double>? _ampSub;
  double _amplitude = 0.0;
  bool _initializing = true;
  late AnimationController _pulseController;

  @override
  void initState() {
    super.initState();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    )..repeat(reverse: true);
    _startRecording();
  }

  Future<void> _startRecording() async {
    final status = await Permission.microphone.request();
    if (status != PermissionStatus.granted) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Microphone permission is required to record audio.'),
          ),
        );
      }
      widget.onCancel();
      return;
    }

    try {
      await _recorder.start();
      if (!mounted) return;
      _ampSub = _recorder.amplitudeStream.listen((amp) {
        if (!_isPaused && mounted) {
          setState(() => _amplitude = math.max(0.06, amp));
        }
      });
      _startTimer();
      setState(() => _initializing = false);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to start recording: $e')),
        );
      }
      widget.onCancel();
    }
  }

  void _startTimer() {
    _timer?.cancel();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_isPaused && mounted) {
        setState(() => _seconds++);
      }
    });
  }

  Future<void> _pauseResume() async {
    try {
      if (_isPaused) {
        await _recorder.resume();
        _startTimer();
      } else {
        await _recorder.pause();
        _timer?.cancel();
      }
      if (mounted) setState(() => _isPaused = !_isPaused);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error during pause/resume: $e')),
        );
      }
    }
  }

  Future<void> _send() async {
    _timer?.cancel();
    await _ampSub?.cancel();
    try {
      final file = await _recorder.stop();
      if (file != null) {
        widget.onSend(file, _seconds);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('No recording file available to send.'),
            ),
          );
        }
        widget.onCancel();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Failed to stop recording: $e')),
        );
      }
      widget.onCancel();
    }
  }

  Future<void> _cancel() async {
    _timer?.cancel();
    await _ampSub?.cancel();
    try {
      await _recorder.stop();
    } catch (e) {
      // Ignore errors on cancel
    }
    widget.onCancel();
  }

  @override
  void dispose() {
    _pulseController.dispose();
    _timer?.cancel();
    _ampSub?.cancel();
    _recorder.stop().catchError((_) => null); // Ignore errors
    super.dispose();
  }

  String get _formattedTime {
    final minutes = (_seconds ~/ 60).toString().padLeft(2, '0');
    final seconds = (_seconds % 60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 250),
      height: 54.h,
      padding: EdgeInsets.fromLTRB(4.w, 0, 4.w, 0),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: isDark
              ? [const Color(0xFF1C2B3D), const Color(0xFF141D29)]
              : const [Color(0xFFE1F5FE), Color(0xFFF3F9FF)],
        ),
        borderRadius: BorderRadius.circular(27.r),
        border: Border.all(color: Colors.lightBlue.shade200, width: 1.2),
        boxShadow: [
          BoxShadow(
            color: Colors.lightBlueAccent.withValues(alpha: 0.15),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        children: [
          // Cancel
          _CircleButton(
            size: 34.w,
            color: Colors.red.shade50,
            borderColor: Colors.red.shade100,
            onTap: _cancel,
            child: Icon(
              Icons.close_rounded,
              color: Colors.red.shade400,
              size: 18.sp,
            ),
          ),
          SizedBox(width: 4.w),

          // Live waveform
          Expanded(
            child: AnimatedBuilder(
              animation: _pulseController,
              builder: (context, _) {
                final pulse = _isPaused ? 0.0 : _pulseController.value;
                return LayoutBuilder(
                  builder: (context, constraints) {
                    final availableWidth = constraints.maxWidth;
                    const numBars = 18;
                    // Each bar occupies barWidth + 0.9*barWidth of margin on
                    // each side (barSpacing), so total per bar = 1.9*barWidth.
                    // Every bar uses the same margins, so the whole row needs
                    // numBars * 1.9 * barWidth which must be <= availableWidth.
                    // The extra 0.05 is a safety margin so rounding never
                    // overflows by a few pixels.
                    final barWidth = math.min(
                      3.w,
                      availableWidth / (numBars * 1.95),
                    );
                    final barSpacing = barWidth * 0.9;
                    return Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: List.generate(numBars, (index) {
                        // Deterministic organic shape + live loudness + pulse
                        final shape = 0.5 +
                            0.5 *
                                math.sin(
                                  index * 0.9 +
                                      (index % 5) * 0.35 +
                                      pulse * 0.8,
                                );
                        final live = _isPaused ? 0.25 : _amplitude;
                        final height = (6.h +
                            30.h *
                                shape *
                                (0.3 + 0.7 * live))
                            .clamp(4.h, 40.h);
                        return Container(
                          width: barWidth,
                          height: height,
                          margin:
                              EdgeInsets.symmetric(horizontal: barSpacing / 2),
                          decoration: BoxDecoration(
                            gradient: LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: _isPaused
                                  ? [colors.textWeak, colors.surfaceDim]
                                  : [
                                      Colors.lightBlueAccent,
                                      const Color(0xFF29B6F6),
                                    ],
                            ),
                            borderRadius: BorderRadius.circular(barWidth / 2),
                          ),
                        );
                      }),
                    );
                  },
                );
              },
            ),
          ),
          SizedBox(width: 4.w),

          // Timer (flexible so it shrinks on very narrow screens instead of
          // overflowing the row)
          Flexible(
            flex: 0,
            fit: FlexFit.loose,
            child: Text(
              _formattedTime,
              maxLines: 1,
              overflow: TextOverflow.clip,
              style: TextStyle(
                fontSize: 15.sp,
                fontWeight: FontWeight.w700,
                color: colors.textPrimary,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ),
          SizedBox(width: 4.w),

          // Pause / Resume
          _CircleButton(
            size: 34.w,
            color: colors.surface,
            borderColor: Colors.lightBlue.shade100,
            onTap: _pauseResume,
            child: Icon(
              _isPaused ? Icons.play_arrow_rounded : Icons.pause_rounded,
              color: colors.textPrimary,
              size: 20.sp,
            ),
          ),
          SizedBox(width: 4.w),

          // Send — gradient pill inside its own border
          GestureDetector(
            onTap: _initializing ? null : _send,
            child: Container(
              width: 38.w,
              height: 38.w,
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [Colors.lightBlueAccent, Color(0xFF0288D1)],
                ),
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.lightBlueAccent.withValues(alpha: 0.4),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Icon(
                Icons.send_rounded,
                color: Colors.white,
                size: 18.sp,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CircleButton extends StatelessWidget {
  final double size;
  final Color color;
  final Color borderColor;
  final Widget child;
  final VoidCallback onTap;

  const _CircleButton({
    required this.size,
    required this.color,
    required this.borderColor,
    required this.child,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: Border.all(color: borderColor),
        ),
        child: Center(child: child),
      ),
    );
  }
}
