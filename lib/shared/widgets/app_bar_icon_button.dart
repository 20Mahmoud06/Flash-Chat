import 'package:flutter/material.dart';

/// Compact AppBar action button used on chat screens. Sits flush beside its
/// siblings (no big default gaps) so call / profile actions look tight.
class AppBarIconButton extends StatelessWidget {
  final IconData icon;
  final VoidCallback? onPressed;
  final double iconSize;

  const AppBarIconButton({
    super.key,
    required this.icon,
    this.onPressed,
    this.iconSize = 24,
  });

  @override
  Widget build(BuildContext context) {
    return IconButton(
      onPressed: onPressed,
      icon: Icon(icon, color: Colors.white, size: iconSize),
      padding: EdgeInsets.zero,
      visualDensity: VisualDensity.compact,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
    );
  }
}