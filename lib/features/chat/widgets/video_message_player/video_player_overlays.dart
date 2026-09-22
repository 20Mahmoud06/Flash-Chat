import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Semi-transparent overlay with a spinner shown while the video is being
/// fetched / initialized.
class VideoPlayerLoadingOverlay extends StatelessWidget {
  final Color accent;

  const VideoPlayerLoadingOverlay({super.key, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black38,
      child: Center(
        child: SizedBox(
          width: 40,
          height: 40,
          child: CircularProgressIndicator(
            strokeWidth: 3,
            color: accent,
          ),
        ),
      ),
    );
  }
}

/// Bottom fade-to-black gradient behind the controls, for legibility.
class VideoPlayerBottomGradient extends StatelessWidget {
  const VideoPlayerBottomGradient({super.key});

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.bottomCenter,
            end: Alignment.topCenter,
            colors: [
              Colors.black.withValues(alpha: 0.65),
              Colors.transparent,
            ],
            stops: const [0.0, 0.55],
          ),
        ),
      ),
    );
  }
}

/// Full-screen error state shown when every playback URL attempt failed,
/// with a "Tap to retry" action.
class VideoPlayerErrorOverlay extends StatelessWidget {
  final VoidCallback onRetry;

  const VideoPlayerErrorOverlay({super.key, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: Colors.black87,
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.error_outline, color: Colors.white54, size: 34),
            SizedBox(height: 8.h),
            TextButton.icon(
              onPressed: onRetry,
              icon: const Icon(Icons.refresh, color: Colors.white, size: 18),
              label: const CustomText(
                text: 'Video failed to load. Tap to retry',
                textColor: Colors.white,
                fontSize: 12,
              ),
            ),
          ],
        ),
      ),
    );
  }
}