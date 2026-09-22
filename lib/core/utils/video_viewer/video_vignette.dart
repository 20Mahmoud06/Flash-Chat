import 'package:flutter/material.dart';

/// Darkens the top and bottom of the screen behind the control bars while
/// they are visible, so the controls stay readable on bright footage.
class VideoVignette extends StatelessWidget {
  final bool visible;

  const VideoVignette({super.key, required this.visible});

  @override
  Widget build(BuildContext context) {
    return Positioned.fill(
      child: IgnorePointer(
        child: AnimatedOpacity(
          opacity: visible ? 1.0 : 0.0,
          duration: const Duration(milliseconds: 250),
          child: Container(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  Colors.black.withValues(alpha: 0.65),
                  Colors.transparent,
                  Colors.transparent,
                  Colors.black.withValues(alpha: 0.75),
                ],
                stops: const [0.0, 0.25, 0.7, 1.0],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
