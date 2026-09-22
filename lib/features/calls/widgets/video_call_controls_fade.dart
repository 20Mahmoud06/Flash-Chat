import 'package:flutter/material.dart';

/// Wraps a call-controls layer so hidden controls never swallow taps (let
/// them pass through to the GestureDetector that toggles them) and they
/// fade in/out with the shared controls animation.
class CallControlsFade extends StatelessWidget {
  final Animation<double> animation;
  final bool show;
  final Widget child;

  const CallControlsFade({
    super.key,
    required this.animation,
    required this.show,
    required this.child,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: animation,
      child: child,
      builder: (context, child) => IgnorePointer(
        ignoring: !show,
        child: Opacity(opacity: animation.value, child: child),
      ),
    );
  }
}
