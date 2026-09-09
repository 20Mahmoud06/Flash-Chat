import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';

class CallEndedOverlay extends StatefulWidget {
  final String? reason;
  final Duration? duration;
  final VoidCallback onDismiss;

  const CallEndedOverlay({
    super.key,
    this.reason,
    this.duration,
    required this.onDismiss,
  });

  static const Map<String, String> _titles = {
    'cancelled': 'Call Cancelled',
    'busy': 'User is Busy',
    'declined': 'Call Declined',
    'rejected': 'Call Declined',
    'timeout': 'Call Timed Out',
    'no_answer': 'Call Timed Out',
    'unavailable': 'User Unavailable',
    'offline': 'User is Offline',
    'missed': 'Missed Call',
    'failed': 'Call Failed',
    'ended': 'Call Ended',
    'left': 'You Left the Call',
  };

  static const Map<String, String> _subtitles = {
    'cancelled': 'The call was cancelled',
    'busy': 'The user is currently busy\nPlease try again later',
    'declined': 'The recipient declined the call',
    'rejected': 'The recipient declined the call',
    'timeout': 'No answer from recipient\nCall timed out',
    'no_answer': 'No answer from recipient\nCall timed out',
    'unavailable': 'The user is offline or not reachable\nPlease try again later',
    'offline': 'The user is offline or not reachable\nPlease try again later',
    'missed': 'You missed a call',
    'failed': 'We could not connect your call\nPlease try again',
    'ended': 'The call has ended',
    'left': 'The call is still going\nwith the other members',
  };

  static const Map<String, IconData> _icons = {
    'cancelled': Icons.call_end_rounded,
    'busy': Icons.phone_paused_rounded,
    'declined': Icons.phone_disabled_rounded,
    'rejected': Icons.phone_disabled_rounded,
    'timeout': Icons.timer_off_rounded,
    'no_answer': Icons.phone_missed_rounded,
    'unavailable': Icons.cloud_off_rounded,
    'offline': Icons.cloud_off_rounded,
    'missed': Icons.phone_missed_rounded,
    'failed': Icons.error_outline_rounded,
    'ended': Icons.call_end_rounded,
    'left': Icons.logout_rounded,
  };

  static const Map<String, Color> _colors = {
    'cancelled': Color(0xFFFF5252),
    'busy': Color(0xFFFF7675),
    'declined': Color(0xFFFF7675),
    'rejected': Color(0xFFFF7675),
    'timeout': Color(0xFFFDCB6E),
    'no_answer': Color(0xFFFDCB6E),
    'unavailable': Color(0xFFFDCB6E),
    'offline': Color(0xFFFDCB6E),
    'missed': Color(0xFFFDCB6E),
    'failed': Color(0xFFFF5252),
    'ended': Color(0xFFFF5252),
    'left': Color(0xFF4FC3F7),
  };

  static String statusLabel(String? reason) {
    switch (reason) {
      case 'cancelled':
        return 'Call Cancelled';
      case 'busy':
        return 'User is Busy';
      case 'declined':
      case 'rejected':
        return 'Call Declined';
      case 'timeout':
      case 'no_answer':
        return 'Call Timed Out';
      case 'unavailable':
        return 'User Unavailable';
      case 'offline':
        return 'User is Offline';
      case 'missed':
        return 'Missed Call';
      case 'failed':
        return 'Call Failed';
      case 'left':
        return 'You Left the Call';
      default:
        return 'Call Ended';
    }
  }

  @override
  State<CallEndedOverlay> createState() => _CallEndedOverlayState();
}

class _CallEndedOverlayState extends State<CallEndedOverlay> {
  Timer? _dismissTimer;

  @override
  void initState() {
    super.initState();
    _dismissTimer = Timer(const Duration(milliseconds: 2500), () {
      if (mounted) {
        widget.onDismiss();
      }
    });
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    super.dispose();
  }

  IconData _getIcon() {
    return CallEndedOverlay._icons[widget.reason] ?? Icons.call_end_rounded;
  }

  Color _getColor() {
    return CallEndedOverlay._colors[widget.reason] ?? const Color(0xFFFF5252);
  }

  String _getTitle() {
    return CallEndedOverlay._titles[widget.reason] ?? 'Call Ended';
  }

  String _getSubtitle() {
    return CallEndedOverlay._subtitles[widget.reason] ?? 'The call has ended';
  }

  String _formatDuration(Duration duration) {
    final hours = duration.inHours;
    final minutes = duration.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = duration.inSeconds.remainder(60).toString().padLeft(2, '0');
    if (hours > 0) {
      return '$hours:$minutes:$seconds';
    }
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final iconColor = _getColor();

    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          // Blur backdrop
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
              child: Container(
                color: Colors.black.withValues(alpha: 0.7),
              ),
            ),
          ),
          Center(
            child: TweenAnimationBuilder<double>(
              tween: Tween(begin: 0.8, end: 1),
              duration: const Duration(milliseconds: 350),
              curve: Curves.easeOutBack,
              builder: (context, scale, child) =>
                  Transform.scale(scale: scale, child: child),
              child: Container(
                margin: const EdgeInsets.symmetric(horizontal: 40),
                padding: const EdgeInsets.all(28),
                decoration: BoxDecoration(
                  color: const Color(0xFF1E1E2E).withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.15),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: iconColor.withValues(alpha: 0.3),
                      blurRadius: 30,
                      spreadRadius: 2,
                    ),
                  ],
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 72,
                      height: 72,
                      decoration: BoxDecoration(
                        color: iconColor.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: iconColor.withValues(alpha: 0.4),
                          width: 2,
                        ),
                      ),
                      child: Center(
                        child: Icon(
                          _getIcon(),
                          color: iconColor,
                          size: 36,
                        ),
                      ),
                    ),
                    const SizedBox(height: 20),
                    Text(
                      _getTitle(),
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      _getSubtitle(),
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.7),
                        fontSize: 14,
                        height: 1.4,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (widget.duration != null &&
                        widget.duration!.inSeconds > 0) ...[
                      const SizedBox(height: 16),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 8,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(20),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Icon(
                              Icons.timer_outlined,
                              color: Colors.white70,
                              size: 16,
                            ),
                            const SizedBox(width: 8),
                            Text(
                              'Duration: ${_formatDuration(widget.duration!)}',
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    SizedBox(
                      width: double.infinity,
                      child: TextButton.icon(
                        style: TextButton.styleFrom(
                          backgroundColor: Colors.white.withValues(alpha: 0.08),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: Colors.white.withValues(alpha: 0.2),
                            ),
                          ),
                        ),
                        icon: Icon(Icons.check_rounded, color: iconColor, size: 20),
                        label: const Text(
                          'OK',
                          style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        onPressed: widget.onDismiss,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
