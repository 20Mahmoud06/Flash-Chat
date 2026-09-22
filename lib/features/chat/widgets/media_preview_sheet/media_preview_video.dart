import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:video_player/video_player.dart';

import '../../../../core/constants/app_colors.dart';
import '../../../../core/theme/app_theme.dart';
import '../../../../shared/widgets/custom_text.dart';
import 'media_circle_button.dart';

String formatVideoDuration(Duration d) {
  final hours = d.inHours;
  final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
  return hours > 0 ? '$hours:$minutes:$seconds' : '$minutes:$seconds';
}

/// Full-screen preview of the selected video with play/pause, ±5s seek,
/// scrubber, and a VIDEO chip. The owning sheet keeps the controller and
/// playback state; this widget is purely presentational and pushes every
/// interaction back through the callbacks.
class MediaPreviewVideoPlayer extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool isInitialized;
  final bool initFailed;
  final bool isPlaying;
  final bool showControls;
  final double? dragSliderValue;
  final VoidCallback onToggleControls;
  final VoidCallback onPlayPause;
  final void Function(int seconds) onSkip;
  final ValueChanged<double> onSliderChanged;
  final Future<void> Function(Duration target) onSeek;

  const MediaPreviewVideoPlayer({
    super.key,
    required this.controller,
    required this.isInitialized,
    required this.initFailed,
    required this.isPlaying,
    required this.showControls,
    required this.dragSliderValue,
    required this.onToggleControls,
    required this.onPlayPause,
    required this.onSkip,
    required this.onSliderChanged,
    required this.onSeek,
  });

  @override
  Widget build(BuildContext context) {
    if (initFailed) {
      return const _MediaPreviewVideoFallback();
    }

    final controller = this.controller;
    if (controller == null || !isInitialized) {
      return Container(
        width: double.infinity,
        height: double.infinity,
        decoration: BoxDecoration(
          color: FcAppColors.of(context).surfaceMuted,
          borderRadius: BorderRadius.circular(20.r),
        ),
        child: const Center(
          child: CircularProgressIndicator(color: AppColors.primaryDark),
        ),
      );
    }

    final duration = controller.value.duration;
    final position = controller.value.position;

    return ClipRRect(
      borderRadius: BorderRadius.circular(20.r),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onToggleControls,
        child: Container(
          width: double.infinity,
          height: double.infinity,
          color: Colors.black,
          child: Stack(
            fit: StackFit.expand,
            alignment: Alignment.center,
            children: [
              // Video keeps its native aspect ratio (landscape or portrait):
              // centered, never cropped or stretched, with a rounded frame.
              Padding(
                padding: EdgeInsets.symmetric(horizontal: 12.w, vertical: 4.h),
                child: Center(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12.r),
                    child: AspectRatio(
                      aspectRatio: controller.value.aspectRatio,
                      child: VideoPlayer(controller),
                    ),
                  ),
                ),
              ),
              // Buffering indicator while loading during playback, never at EOF.
              if (controller.value.isBuffering &&
                  !(duration > Duration.zero && position >= duration))
                const Center(
                  child: SizedBox(
                    width: 38,
                    height: 38,
                    child: CircularProgressIndicator(
                      strokeWidth: 3,
                      color: AppColors.sky,
                    ),
                  ),
                ),
              // Decorative gradient overlay for visibility
              IgnorePointer(
                child: Container(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withValues(alpha: 0.25),
                        Colors.transparent,
                        Colors.transparent,
                        Colors.black.withValues(alpha: 0.4),
                      ],
                    ),
                  ),
                ),
              ),
              // Play / Pause
              if (showControls) ...[
                Center(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      MediaCircleButton(
                        size: 48,
                        icon: Icons.replay_5_rounded,
                        iconSize: 26,
                        iconColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        onTap: () => onSkip(-5),
                      ),
                      SizedBox(width: 18.w),
                      MediaCircleButton(
                        size: 62,
                        icon: isPlaying
                            ? Icons.pause_rounded
                            : Icons.play_arrow_rounded,
                        iconSize: 34,
                        iconColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        onTap: onPlayPause,
                      ),
                      SizedBox(width: 18.w),
                      MediaCircleButton(
                        size: 48,
                        icon: Icons.forward_5_rounded,
                        iconSize: 26,
                        iconColor: Colors.white,
                        backgroundColor: Colors.black.withValues(alpha: 0.5),
                        onTap: () => onSkip(5),
                      ),
                    ],
                  ),
                ),
                // Top: video chip
                Positioned(
                  top: 12,
                  left: 12,
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(
                          Icons.videocam_rounded,
                          color: Colors.white,
                          size: 14,
                        ),
                        const SizedBox(width: 6),
                        CustomText(
                          text: 'VIDEO',
                          textColor: Colors.white,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                          letterSpacing: 1.2,
                        ),
                      ],
                    ),
                  ),
                ),
                // Bottom row: time + progress
                Positioned(
                  left: 16,
                  right: 16,
                  bottom: 10,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          CustomText(
                            text: formatVideoDuration(
                              dragSliderValue != null
                                  ? Duration(
                                      milliseconds: dragSliderValue!.round())
                                  : position,
                            ),
                            textColor: Colors.white,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                          ),
                          CustomText(
                            text: formatVideoDuration(duration),
                            textColor: Colors.white54,
                            fontSize: 11.sp,
                            fontWeight: FontWeight.w600,
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      _MediaPreviewVideoSlider(
                        controller: controller,
                        dragValue: dragSliderValue,
                        onChanged: onSliderChanged,
                        onSeek: onSeek,
                      ),
                    ],
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Shown when the video could not be initialized (unsupported codec etc.) —
/// the user can still send it.
class _MediaPreviewVideoFallback extends StatelessWidget {
  const _MediaPreviewVideoFallback();

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      width: double.infinity,
      height: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 24.w),
      decoration: BoxDecoration(
        color: Colors.black,
        borderRadius: BorderRadius.circular(20.r),
      ),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(
              Icons.movie_outlined,
              color: Colors.white70,
              size: 52,
            ),
            SizedBox(height: 12.h),
            CustomText(
              text: 'Preview unavailable on this phone',
              textColor: Colors.white,
              fontSize: 15.sp,
              fontWeight: FontWeight.w700,
              textAlign: TextAlign.center,
            ),
            SizedBox(height: 6.h),
            CustomText(
              text:
                  'You can still send it. The chat video will be converted for playback.',
              textColor: colors.textWeak,
              fontSize: 12.sp,
              height: 1.3,
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}

/// Scrubber bar: while dragging it pauses playback and shows the dragged
/// position; it resumes if the video was playing before the drag.
class _MediaPreviewVideoSlider extends StatefulWidget {
  final VideoPlayerController controller;
  final double? dragValue;
  final ValueChanged<double> onChanged;
  final Future<void> Function(Duration target) onSeek;

  const _MediaPreviewVideoSlider({
    required this.controller,
    required this.dragValue,
    required this.onChanged,
    required this.onSeek,
  });

  @override
  State<_MediaPreviewVideoSlider> createState() =>
      _MediaPreviewVideoSliderState();
}

class _MediaPreviewVideoSliderState extends State<_MediaPreviewVideoSlider> {
  bool _wasPlayingBeforeSeek = false;

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final durationMs = controller.value.duration.inMilliseconds;
    if (durationMs <= 0) {
      return const SizedBox(height: 24);
    }

    final positionMs =
        controller.value.position.inMilliseconds.clamp(0, durationMs);
    final valueMs = widget.dragValue ?? positionMs.toDouble();

    return SliderTheme(
      data: SliderTheme.of(context).copyWith(
        trackHeight: 3,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
        overlayShape: const RoundSliderOverlayShape(overlayRadius: 14),
        activeTrackColor: AppColors.sky,
        inactiveTrackColor: Colors.white24,
        thumbColor: Colors.white,
        overlayColor: AppColors.sky.withValues(alpha: 0.25),
        tickMarkShape: const RoundSliderTickMarkShape(),
        activeTickMarkColor: Colors.transparent,
        inactiveTickMarkColor: Colors.transparent,
      ),
      child: Slider(
        value: valueMs.clamp(0, durationMs.toDouble()),
        max: durationMs.toDouble(),
        onChangeStart: (_) {
          _wasPlayingBeforeSeek = controller.value.isPlaying;
          controller.pause();
        },
        onChanged: widget.onChanged,
        onChangeEnd: (value) async {
          final target = Duration(milliseconds: value.round());
          await widget.onSeek(target);
          if (mounted &&
              _wasPlayingBeforeSeek &&
              widget.controller.value.position <
                  widget.controller.value.duration) {
            widget.controller.play();
          }
        },
      ),
    );
  }
}