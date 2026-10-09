import 'package:flutter/material.dart';
import '../../../core/theme/app_theme.dart';

/// Floating jump-to-bottom button shown once the user has scrolled up.
class ChatScrollDownButton extends StatelessWidget {
  final bool visible;
  final VoidCallback onTap;

  const ChatScrollDownButton({
    super.key,
    required this.visible,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    if (!visible) return const SizedBox.shrink();
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface,
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.arrow_downward, color: Colors.lightBlueAccent),
      ),
    );
  }
}
