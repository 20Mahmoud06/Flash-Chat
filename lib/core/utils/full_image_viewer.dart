import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'save_media_to_gallery.dart';

/// Full-screen gallery-style image viewer:
/// - fully opaque black background (the chat is never visible behind it)
/// - tap anywhere to close; X and download buttons on the top-right
/// - pinch to zoom (1x - 4x) and pan while zoomed
/// - double-tap smoothly zooms in at the tapped point and zooms back out on
///   a second double-tap. If the tap lands on a letterboxed black band the
///   anchor snaps onto the nearest visible photo area, and the zoomed photo
///   is clamped so it can never be pushed off-screen leaving black gaps.
class FullImageViewer extends StatefulWidget {
  final String imageUrl;
  final String heroTag;

  const FullImageViewer({
    super.key,
    required this.imageUrl,
    required this.heroTag,
  });

  @override
  State<FullImageViewer> createState() => _FullImageViewerState();
}

class _FullImageViewerState extends State<FullImageViewer>
    with TickerProviderStateMixin {
  final TransformationController _controller = TransformationController();
  TapDownDetails? _doubleTapDetails;

  /// Decoded dimensions of the photo, used to compute where the photo is
  /// actually drawn inside the viewport (BoxFit.contain letterboxes it).
  Size? _imageSize;
  Size _viewport = Size.zero;
  bool _isZoomed = false;
  AnimationController? _zoomAnimation;

  static const double _doubleTapScale = 2.5;
  static const double _maxScale = 4;

  @override
  void initState() {
    super.initState();
    // Only this viewer may rotate (landscape photos / videos): the rest of
    // the app stays locked to portrait.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
      DeviceOrientation.landscapeLeft,
      DeviceOrientation.landscapeRight,
    ]);
    _controller.addListener(_onTransformChanged);
    _resolveImageSize();
  }

  @override
  void dispose() {
    _zoomAnimation?.dispose();
    _controller.removeListener(_onTransformChanged);
    _controller.dispose();
    // Restore the portrait-only lock for the rest of the app.
    SystemChrome.setPreferredOrientations([
      DeviceOrientation.portraitUp,
      DeviceOrientation.portraitDown,
    ]);
    super.dispose();
  }

  void _onTransformChanged() {
    final zoomed = _controller.value.getMaxScaleOnAxis() > 1.05;
    if (zoomed != _isZoomed) _isZoomed = zoomed;
  }

  /// Reads the decoded image dimensions through the shared NetworkImage
  /// cache so the zoom anchor can be clamped to the actual photo instead of
  /// the letterboxed black bars.
  void _resolveImageSize() {
    final stream =
        NetworkImage(widget.imageUrl).resolve(ImageConfiguration.empty);
    late final ImageStreamListener listener;
    listener = ImageStreamListener(
      (info, _) {
        if (mounted) {
          setState(() {
            _imageSize = Size(
              info.image.width.toDouble(),
              info.image.height.toDouble(),
            );
          });
        }
        stream.removeListener(listener);
      },
      onError: (error, stackTrace) => stream.removeListener(listener),
    );
    stream.addListener(listener);
  }

  /// The rectangle (in viewport coordinates) actually occupied by the photo
  /// when it is drawn with BoxFit.contain. Falls back to the whole viewport
  /// while the image dimensions are still unknown.
  Rect _fittedRect() {
    final image = _imageSize;
    if (image == null || image.width <= 0 || image.height <= 0) {
      return Offset.zero & _viewport;
    }
    final scale = math.min(
      _viewport.width / image.width,
      _viewport.height / image.height,
    );
    final size = Size(image.width * scale, image.height * scale);
    return Rect.fromCenter(
      center: _viewport.center(Offset.zero),
      width: size.width,
      height: size.height,
    );
  }

  /// Builds a matrix that scales by [scale] while keeping [anchor] fixed,
  /// then clamps the translation: axes the zoomed photo still doesn't cover
  /// are re-centered, and axes it does cover can't be panned off-screen.
  Matrix4 _zoomMatrix({required double scale, required Offset anchor}) {
    final fitted = _fittedRect();
    var tx = anchor.dx - scale * anchor.dx;
    var ty = anchor.dy - scale * anchor.dy;

    double clampAxis(
        double t, double scaledLen, double fittedStart, double viewportLen) {
      if (scaledLen >= viewportLen) {
        final minT = viewportLen - scaledLen - scale * fittedStart;
        final maxT = -scale * fittedStart;
        return t.clamp(minT, maxT).toDouble();
      }
      return (viewportLen - scaledLen) / 2 - scale * fittedStart;
    }

    tx = clampAxis(tx, fitted.width * scale, fitted.left, _viewport.width);
    ty = clampAxis(ty, fitted.height * scale, fitted.top, _viewport.height);

    return Matrix4.identity()
      ..translateByDouble(tx, ty, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1);
  }

  void _handleDoubleTap() {
    if (_viewport.isEmpty) return;

    // Already zoomed (or still animating): zoom back out.
    if (_isZoomed || _zoomAnimation != null) {
      _animateTo(Matrix4.identity());
      return;
    }

    final fitted = _fittedRect();
    final tapPoint = _doubleTapDetails?.localPosition ?? fitted.center;

    // If the double-tap landed on a black letterbox band, zoom toward the
    // nearest point of the actual photo instead of into nothing.
    final anchor = Offset(
      tapPoint.dx.clamp(fitted.left, fitted.right).toDouble(),
      tapPoint.dy.clamp(fitted.top, fitted.bottom).toDouble(),
    );

    _animateTo(_zoomMatrix(scale: _doubleTapScale, anchor: anchor));
  }

  void _animateTo(
    Matrix4 target, {
    Duration duration = const Duration(milliseconds: 220),
  }) {
    _zoomAnimation?.dispose();
    final begin = _controller.value;
    final animation = AnimationController(vsync: this, duration: duration);
    _zoomAnimation = animation;
    final curved =
        CurvedAnimation(parent: animation, curve: Curves.easeOutCubic);
    final tween = Matrix4Tween(begin: begin, end: target);
    animation.addListener(() {
      _controller.value = tween.evaluate(curved);
    });
    animation.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        animation.dispose();
        if (_zoomAnimation == animation) _zoomAnimation = null;
      }
    });
    animation.forward();
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        GestureDetector(
          onTap: () => Navigator.pop(context),
          onDoubleTapDown: (details) => _doubleTapDetails = details,
          onDoubleTap: _handleDoubleTap,
          child: Container(
            color: Colors.black,
            child: LayoutBuilder(
              builder: (context, constraints) {
                _viewport =
                    Size(constraints.maxWidth, constraints.maxHeight);
                return Center(
                  child: Hero(
                    tag: widget.heroTag,
                    child: InteractiveViewer(
                      transformationController: _controller,
                      minScale: 1,
                      maxScale: _maxScale,
                      panEnabled: true,
                      scaleEnabled: true,
                      // Let the user grab the photo immediately, even in the
                      // middle of a double-tap zoom animation.
                      onInteractionStart: (_) => _zoomAnimation?.stop(),
                      child: Image.network(
                        widget.imageUrl,
                        fit: BoxFit.contain,
                        loadingBuilder: (context, child, progress) {
                          if (progress == null) return child;
                          return const CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          );
                        },
                        errorBuilder: (_, __, ___) => const Icon(
                          Icons.broken_image,
                          color: Colors.white,
                          size: 60,
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
        ),

        // Top-right actions: download + close
        Positioned(
          top: 0,
          right: 0,
          child: SafeArea(
            child: Row(
              children: [
                IconButton(
                  onPressed: () => saveImageToGallery(context, widget.imageUrl),
                  icon: const Icon(Icons.download_rounded,
                      color: Colors.white, size: 24),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    padding: EdgeInsets.all(10.w),
                  ),
                  tooltip: 'Save to gallery',
                ),
                IconButton(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.close, color: Colors.white, size: 26),
                  style: IconButton.styleFrom(
                    backgroundColor: Colors.black.withValues(alpha: 0.35),
                    padding: EdgeInsets.all(10.w),
                  ),
                  tooltip: 'Close',
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
