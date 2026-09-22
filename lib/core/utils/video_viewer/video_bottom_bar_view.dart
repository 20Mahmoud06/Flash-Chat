import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';

/// Bottom glass panel with the interactive progress slider and the current /
/// total time labels. The position value is owned by the parent so dragging
/// keeps the viewer's control auto-hide timer in sync.
class VideoBottomBarView extends StatelessWidget {
  final bool visible;
  final double value;
  final Duration duration;
  final VoidCallback onDragStart;
  final void Function(double millis) onDragChanged;
  final void Function(double millis) onDragEnd;

  const VideoBottomBarView({
    super.key,
    required this.visible,
    required this.value,
    required this.duration,
    required this.onDragStart,
    required this.onDragChanged,
    required this.onDragEnd,
  });

  static const _accent = AppColors.sky;

  @override
  Widget build(BuildContext context) {
    final durationMs = duration.inMilliseconds.toDouble();
    final max = durationMs > 0 ? durationMs : 1.0;

    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: SafeArea(
            child: Container(
              margin: const EdgeInsets.all(16),
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 10),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.65),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Colors.white.withValues(alpha: 0.15)),
                boxShadow: const [
                  BoxShadow(
                    color: Colors.black38,
                    blurRadius: 16,
                    offset: Offset(0, 4),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SliderTheme(
                    data: SliderTheme.of(context).copyWith(
                      trackHeight: 4,
                      thumbShape:
                          const RoundSliderThumbShape(enabledThumbRadius: 7),
                      overlayShape:
                          const RoundSliderOverlayShape(overlayRadius: 14),
                      activeTrackColor: _accent,
                      inactiveTrackColor: Colors.white24,
                      thumbColor: Colors.white,
                      overlayColor: _accent.withValues(alpha: 0.3),
                    ),
                    child: Slider(
                      value: value.clamp(0.0, max),
                      max: max,
                      onChangeStart: (_) => onDragStart(),
                      onChanged: onDragChanged,
                      onChangeEnd: onDragEnd,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      CustomText(
                        text: _formatDuration(
                          Duration(milliseconds: value.round()),
                        ),
                        textColor: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                      CustomText(
                        text: _formatDuration(duration),
                        textColor: Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }
}
