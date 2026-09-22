import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:video_player/video_player.dart';

/// The black video stage: renders the fitted [VideoPlayer], a spinning
/// "Loading video..." state while initializing, or an error + retry state
/// once every playback-URL attempt failed. A small buffering spinner is
/// drawn on top of the playing video while the player catches up — hidden at
/// the end, where the player can briefly report buffering behind the rewatch
/// button.
class VideoStageView extends StatelessWidget {
  final VideoPlayerController? controller;
  final bool isReady;
  final bool isBuffering;
  final bool initFailed;
  final bool handledEnded;
  final VoidCallback onRetry;

  const VideoStageView({
    super.key,
    required this.controller,
    required this.isReady,
    required this.isBuffering,
    required this.initFailed,
    required this.handledEnded,
    required this.onRetry,
  });

  static const _accent = AppColors.sky;

  bool get _showBuffering =>
      !initFailed && isReady && !handledEnded && isBuffering;

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: Container(
        color: Colors.black,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (initFailed)
              _buildFailed()
            else if (!isReady)
              _buildLoading()
            else
              Center(
                child: AspectRatio(
                  aspectRatio: controller!.value.aspectRatio,
                  child: VideoPlayer(controller!),
                ),
              ),
            if (_showBuffering) _buildBuffering(),
          ],
        ),
      ),
    );
  }

  Widget _buildFailed() {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.error_outline, color: Colors.white54, size: 44),
          const SizedBox(height: 12),
          TextButton.icon(
            onPressed: onRetry,
            icon: const Icon(Icons.refresh, color: _accent, size: 20),
            label: const CustomText(
              text: 'Video failed to load. Tap to retry',
              textColor: Colors.white70,
              fontSize: 14,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: 44,
            height: 44,
            child: CircularProgressIndicator(
              strokeWidth: 3,
              color: _accent,
            ),
          ),
          SizedBox(height: 14),
          CustomText(
            text: 'Loading video...',
            textColor: Colors.white60,
            fontSize: 13,
            letterSpacing: 0.5,
          ),
        ],
      ),
    );
  }

  Widget _buildBuffering() {
    return Center(
      child: Container(
        width: 50,
        height: 50,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: Colors.black.withValues(alpha: 0.6),
        ),
        child: const Padding(
          padding: EdgeInsets.all(12),
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: _accent,
          ),
        ),
      ),
    );
  }
}
