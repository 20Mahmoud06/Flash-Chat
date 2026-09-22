import 'package:flutter/material.dart';

/// Small circular icon button used across the media preview sheet (header back
/// button, video seek/play controls).
class MediaCircleButton extends StatelessWidget {
  final double size;
  final IconData icon;
  final double iconSize;
  final Color iconColor;
  final Color backgroundColor;
  final VoidCallback onTap;

  const MediaCircleButton({
    super.key,
    required this.size,
    required this.icon,
    this.iconSize = 18,
    required this.iconColor,
    required this.backgroundColor,
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
          color: backgroundColor,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.black.withValues(alpha: 0.08)),
        ),
        child: Icon(icon, color: iconColor, size: iconSize),
      ),
    );
  }
}