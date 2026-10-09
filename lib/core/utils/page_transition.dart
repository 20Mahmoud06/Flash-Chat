import 'package:flutter/material.dart';

class PageTransition {
  // 1. SLIDE FROM RIGHT - Standard navigation feel (like iOS)
  static Widget slideFromRight(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
      ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(1.0, 0.0),
        end: Offset.zero,
      ).animate(CurveTween(curve: Curves.easeInOut).animate(animation)),
      child: child,
    );
  }

  // 2. SLIDE FROM LEFT - Back navigation or drawer
  static Widget slideFromLeft(
      BuildContext context,
      Animation<double> animation,
      Animation<double> secondaryAnimation,
      Widget child,
      ) {
    return SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(-1.0, 0.0),
        end: Offset.zero,
      ).animate(CurveTween(curve: Curves.easeInOut).animate(animation)),
      child: child,
    );
  }
}
