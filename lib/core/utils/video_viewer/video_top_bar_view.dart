import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'video_glass_button.dart';

/// Top navigation row: back button, a small "VIDEO PLAYER" badge and the
/// playback-speed toggle.
class VideoTopBarView extends StatelessWidget {
  final bool visible;
  final bool isReady;
  final double playbackSpeed;
  final VoidCallback onChangeSpeed;
  final VoidCallback onClose;

  const VideoTopBarView({
    super.key,
    required this.visible,
    required this.isReady,
    required this.playbackSpeed,
    required this.onChangeSpeed,
    required this.onClose,
  });

  static const _accent = AppColors.sky;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: IgnorePointer(
        ignoring: !visible,
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
              child: Row(
                children: [
                  VideoGlassButton(
                    icon: Icons.arrow_back_rounded,
                    size: 20,
                    iconColor: Colors.white,
                    backgroundColor: Colors.black.withValues(alpha: 0.45),
                    borderColor: Colors.white.withValues(alpha: 0.2),
                    onTap: onClose,
                  ),
                  const SizedBox(width: 12),
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.45),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.15),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.videocam_rounded, color: _accent, size: 15),
                        SizedBox(width: 6),
                        CustomText(
                          text: 'VIDEO PLAYER',
                          textColor: Colors.white,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ],
                    ),
                  ),
                  const Spacer(),
                  if (isReady)
                    GestureDetector(
                      onTap: onChangeSpeed,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.45),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.2),
                          ),
                        ),
                        child: CustomText(
                          text: '${playbackSpeed}x',
                          textColor: Colors.white,
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
