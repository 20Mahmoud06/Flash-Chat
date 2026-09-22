import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

/// Thin animated line painted ON TOP of the composer (over the text field)
/// while media — photos, videos or voice — is uploading, so the user always
/// sees that their message is loading and will be sent soon. The determinate
/// upload progress is smoothed with a tween while a soft highlight band
/// shimmers along the fill, tinted with the app's accent colour.
class MessageComposerUploadProgressLine extends StatefulWidget {
  final Color color;
  final double progress;

  const MessageComposerUploadProgressLine({
    super.key,
    required this.color,
    required this.progress,
  });

  @override
  State<MessageComposerUploadProgressLine> createState() =>
      _MessageComposerUploadProgressLineState();
}

class _MessageComposerUploadProgressLineState
    extends State<MessageComposerUploadProgressLine>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shimmer;
  late final Animation<Alignment> _shine;

  @override
  void initState() {
    super.initState();
    _shimmer = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1000),
    )..repeat();
    _shine = Tween<Alignment>(
      begin: const Alignment(-0.9, 0),
      end: const Alignment(0.9, 0),
    ).animate(CurvedAnimation(parent: _shimmer, curve: Curves.linear));
  }

  @override
  void dispose() {
    _shimmer.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = widget.color;
    final bright = Color.lerp(base, Colors.white, 0.35) ?? base;

    return IgnorePointer(
      child: SizedBox(
        height: 3.h,
        width: double.infinity,
        child: Stack(
          children: [
            DecoratedBox(
              decoration: BoxDecoration(
                color: base.withValues(alpha: 0.18),
              ),
            ),
            TweenAnimationBuilder<double>(
              tween: Tween<double>(
                begin: 0,
                end: widget.progress.clamp(0.0, 1.0).toDouble(),
              ),
              duration: const Duration(milliseconds: 250),
              curve: Curves.easeOut,
              builder: (context, fraction, _) {
                return AnimatedBuilder(
                  animation: _shine,
                  builder: (context, _) {
                    return Align(
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                        widthFactor: fraction,
                        child: ClipRect(
                          child: Stack(
                            fit: StackFit.expand,
                            children: [
                              DecoratedBox(
                                decoration: BoxDecoration(
                                  gradient: LinearGradient(
                                    colors: [base, bright, base],
                                  ),
                                ),
                              ),
                              Align(
                                alignment: _shine.value,
                                child: FractionallySizedBox(
                                  widthFactor: 0.3,
                                  child: DecoratedBox(
                                    decoration: BoxDecoration(
                                      gradient: LinearGradient(
                                        colors: [
                                          Colors.transparent,
                                          Colors.white
                                              .withValues(alpha: 0.85),
                                          Colors.transparent,
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    );
                  },
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}