import 'package:flutter/material.dart';
import '../../../core/constants/app_colors.dart';

/// Center rewind / play-pause / forward controls. They fade in with the other
/// chrome and become non-tappable while the viewer is "ambient".
class VideoTransportOverlay extends StatelessWidget {
  final bool visible;
  final bool isPlaying;
  final bool handledEnded;
  final VoidCallback onPlayPause;
  final void Function(Duration offset) onSeek;

  const VideoTransportOverlay({
    super.key,
    required this.visible,
    required this.isPlaying,
    required this.handledEnded,
    required this.onPlayPause,
    required this.onSeek,
  });

  static const _accent = AppColors.sky;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Align(
        alignment: Alignment.center,
        child: IgnorePointer(
          ignoring: !visible,
          child: AnimatedOpacity(
            opacity: visible ? 1.0 : 0.0,
            duration: const Duration(milliseconds: 250),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  iconSize: 38,
                  icon: const Icon(
                    Icons.replay_5_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => onSeek(const Duration(seconds: -5)),
                ),
                const SizedBox(width: 28),
                GestureDetector(
                  onTap: onPlayPause,
                  child: Container(
                    width: 68,
                    height: 68,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: Colors.black.withValues(alpha: 0.55),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.35),
                        width: 1.5,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: _accent.withValues(alpha: 0.35),
                          blurRadius: 20,
                          spreadRadius: 2,
                        ),
                      ],
                    ),
                    child: Icon(
                      handledEnded
                          ? Icons.replay_rounded
                          : (isPlaying
                              ? Icons.pause_rounded
                              : Icons.play_arrow_rounded),
                      color: Colors.white,
                      size: 42,
                    ),
                  ),
                ),
                const SizedBox(width: 28),
                IconButton(
                  iconSize: 38,
                  icon: const Icon(
                    Icons.forward_5_rounded,
                    color: Colors.white,
                  ),
                  onPressed: () => onSeek(const Duration(seconds: 5)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}