import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Full-screen participant grid (shared by voice and video group calls) that
/// packs tiles from the *available box* so it can host any number of
/// participants without overflowing:
///
///  * The column count follows a count based default (1 participant fills the
///    surface, 2 stack, 3-4 use two columns, 5-9 three, 10-16 four, more up to
///    [maxColumns]) but is always clamped by the available width, so a tile is
///    never squeezed below [minTileWidth].
///  * Tiles fill the whole surface. When that would squash them below
///    [minTileHeight] (big crowds / short screens) the grid switches to a
///    scrollable layout where each tile keeps a readable size and a
///    [tileAspectRatio] shape, so 20+ participants still render properly.
///
/// Every tile is absolutely positioned, so when the grid re-packs on a
/// join/leave the surviving tiles glide to their new slot while the joining
/// tile fades/scales in and the leaving one fades out in place.
class AnimatedCallGrid extends StatefulWidget {
  const AnimatedCallGrid({
    super.key,
    required this.uids,
    required this.itemBuilder,
    this.spacing = 6,
    this.duration = const Duration(milliseconds: 320),
    this.minTileWidth = 96,
    this.minTileHeight = 108,
    this.tileAspectRatio = 1,
    this.maxColumns = 5,
  });

  /// Ordered participant uids; `0` is the local user.
  final List<int> uids;

  /// Builds one participant tile. Called with the same uid across rebuilds so
  /// the tile keeps its identity (and its position animation) across rebuilds.
  final Widget Function(BuildContext context, int uid) itemBuilder;

  /// Gap between tiles.
  final double spacing;

  /// Duration of the move / fade / scale animations.
  final Duration duration;

  /// Narrowest tile the grid will render before reducing the column count.
  final double minTileWidth;

  /// Shortest tile the grid will render before switching to a scrollable
  /// layout.
  final double minTileHeight;

  /// Width / height used for tiles in the scrollable (crowded) layout.
  final double tileAspectRatio;

  /// Upper bound of columns, regardless of how many participants join.
  final int maxColumns;

  @override
  State<AnimatedCallGrid> createState() => _AnimatedCallGridState();
}

class _AnimatedCallGridState extends State<AnimatedCallGrid> {
  /// Uids currently painted, including the ones still fading out after they
  /// left the call.
  final Set<int> _painted = <int>{};

  /// Last slot of every painted tile, so a leaving tile can fade out where it
  /// actually stood.
  final Map<int, Rect> _slots = <int, Rect>{};

  /// Last built tile of every painted uid, reused while the tile fades out.
  final Map<int, Widget> _built = <int, Widget>{};

  /// Columns that still keep every tile at least [AnimatedCallGrid.minTileWidth]
  /// wide (also capped by [AnimatedCallGrid.maxColumns]).
  int _columnsFor(int count, double width) {
    final double spacing = widget.spacing;
    final int affordable = math.max(
      1,
      ((width + spacing) / (widget.minTileWidth + spacing)).floor(),
    );
    final int cap = math.max(1, math.min(widget.maxColumns, affordable));
    final int preferred = switch (count) {
      <= 2 => 1,
      <= 4 => 2,
      <= 9 => 3,
      <= 16 => 4,
      _ => widget.maxColumns,
    };
    return math.min(preferred, cap).clamp(1, cap);
  }

  _GridLayout _layoutFor(Size area) {
    final double spacing = math.max(0, widget.spacing);
    final List<int> uids = widget.uids;
    final int count = uids.length;
    final int columns = _columnsFor(count, area.width);
    final int rows = (count / columns).ceil();

    final double tileWidth =
        (area.width - (columns - 1) * spacing) / columns;
    if (!tileWidth.isFinite || tileWidth <= 0) {
      // Degenerate width (e.g. mid-transition constraints): fall back to one
      // full width tile per row rather than producing an invalid layout.
      return _GridLayout(
        slots: _stackInSingleColumn(uids, area, spacing),
        contentHeight: area.height,
        scrollable: false,
      );
    }

    final double fittedHeight =
        (area.height - (rows - 1) * spacing) / rows;
    // Crowded call: keep tiles readable and let the user scroll instead of
    // shrinking them to slivers.
    final bool scrollable =
        rows > 1 && fittedHeight < widget.minTileHeight;
    final double tileHeight = scrollable
        ? math.max(widget.minTileHeight, tileWidth / widget.tileAspectRatio)
        : fittedHeight;
    if (!tileHeight.isFinite || tileHeight <= 0) {
      return _GridLayout(
        slots: _stackInSingleColumn(uids, area, spacing),
        contentHeight: area.height,
        scrollable: false,
      );
    }

    final Map<int, Rect> slots = <int, Rect>{};
    for (int i = 0; i < count; i++) {
      final int row = i ~/ columns;
      final int column = i % columns;
      slots[uids[i]] = Rect.fromLTWH(
        column * (tileWidth + spacing),
        row * (tileHeight + spacing),
        tileWidth,
        tileHeight,
      );
    }

    return _GridLayout(
      slots: slots,
      scrollable: scrollable,
      contentHeight: scrollable
          ? rows * tileHeight + (rows - 1) * spacing
          : area.height,
    );
  }

  Map<int, Rect> _stackInSingleColumn(
    List<int> uids,
    Size area,
    double spacing,
  ) {
    final int rows = math.max(1, uids.length);
    final double tileHeight =
        math.max(1.0, (area.height - (rows - 1) * spacing) / rows);
    final Map<int, Rect> slots = <int, Rect>{};
    for (int i = 0; i < uids.length; i++) {
      slots[uids[i]] = Rect.fromLTWH(0, i * (tileHeight + spacing),
          math.max(1.0, area.width), tileHeight);
    }
    return slots;
  }

  Size _resolveArea(BoxConstraints constraints) {
    final Size mediaSize = MediaQuery.sizeOf(context);
    final double width =
        constraints.hasBoundedWidth ? constraints.maxWidth : mediaSize.width;
    final double height = constraints.hasBoundedHeight
        ? constraints.maxHeight
        : mediaSize.height;
    return Size(math.max(0, width), math.max(0, height));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.uids.isEmpty) return const SizedBox.shrink();

    return LayoutBuilder(
      builder: (context, constraints) {
        final Size area = _resolveArea(constraints);
        if (area.width <= 0 || area.height <= 0) return const SizedBox.shrink();

        final _GridLayout layout = _layoutFor(area);
        final Set<int> joined = widget.uids.toSet();
        final List<int> leaving = _painted
            .where((int uid) => !joined.contains(uid))
            .toList(growable: false);

        final List<Widget> tiles = <Widget>[];
        for (final int uid in widget.uids) {
          final Rect slot = layout.slots[uid]!;
          final Widget content = widget.itemBuilder(context, uid);
          _slots[uid] = slot;
          _painted.add(uid);
          _built[uid] = content;
          tiles.add(
            _SlotTransition(
              key: ValueKey<int>(uid),
              rect: slot,
              duration: widget.duration,
              entering: true,
              child: SizedBox.expand(child: content),
            ),
          );
        }
        for (final int uid in leaving) {
          final Rect? slot = _slots[uid];
          // Reuse the last built tile: a participant that already left the
          // channel must not be resolved / rendered again.
          final Widget? content = _built[uid];
          if (slot == null || content == null) continue;
          tiles.add(
            _SlotTransition(
              key: ValueKey<int>(uid),
              rect: slot,
              duration: widget.duration,
              entering: false,
              onRemoved: () {
                if (!mounted) return;
                setState(() {
                  _painted.remove(uid);
                  _slots.remove(uid);
                  _built.remove(uid);
                });
              },
              child: SizedBox.expand(child: content),
            ),
          );
        }

        final Widget grid = Stack(
          clipBehavior: Clip.hardEdge,
          children: tiles,
        );

        if (!layout.scrollable) {
          return SizedBox(width: area.width, height: area.height, child: grid);
        }
        // Too many participants to fit: keep tile sizes and scroll the grid.
        return SingleChildScrollView(
          physics: const ClampingScrollPhysics(),
          child: SizedBox(
            width: area.width,
            height: layout.contentHeight,
            child: grid,
          ),
        );
      },
    );
  }
}

/// Slot of every tile plus the metrics needed to render the container.
class _GridLayout {
  const _GridLayout({
    required this.slots,
    required this.contentHeight,
    required this.scrollable,
  });

  final Map<int, Rect> slots;
  final double contentHeight;
  final bool scrollable;
}

/// Positions a tile in its slot (animating the move when the grid re-packs)
/// and fades/scales it in when it joins or out when it leaves.
class _SlotTransition extends StatefulWidget {
  const _SlotTransition({
    super.key,
    required this.rect,
    required this.duration,
    required this.entering,
    required this.child,
    this.onRemoved,
  });

  final Rect rect;
  final Duration duration;
  final bool entering;
  final Widget child;
  final VoidCallback? onRemoved;

  @override
  State<_SlotTransition> createState() => _SlotTransitionState();
}

class _SlotTransitionState extends State<_SlotTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: widget.duration,
  );
  CurvedAnimation? _curve;
  late Animation<double> _opacity;
  late Animation<double> _scale;

  @override
  void initState() {
    super.initState();
    _buildAnimations();
    if (widget.entering) {
      _controller.forward(from: 0);
    } else {
      _controller.value = 1;
      _playOut();
    }
  }

  @override
  void didUpdateWidget(covariant _SlotTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.duration != oldWidget.duration) {
      _controller.duration = widget.duration;
    }
    if (widget.entering != oldWidget.entering) {
      _buildAnimations();
      if (widget.entering) {
        _controller.forward(from: 0);
      } else {
        _controller.value = 1;
        _playOut();
      }
    }
  }

  void _buildAnimations() {
    _curve?.dispose();
    final CurvedAnimation curve = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _curve = curve;
    _opacity = widget.entering
        ? Tween<double>(begin: 0, end: 1).animate(curve)
        : Tween<double>(begin: 1, end: 0).animate(curve);
    _scale = widget.entering
        ? Tween<double>(begin: 0.86, end: 1).animate(curve)
        : Tween<double>(begin: 1, end: 0.86).animate(curve);
  }

  void _playOut() {
    _controller.reverse().whenCompleteOrCancel(() {
      if (!mounted) return;
      widget.onRemoved?.call();
    });
  }

  @override
  void dispose() {
    _curve?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedPositioned(
      duration: widget.duration,
      curve: Curves.easeOutCubic,
      left: widget.rect.left,
      top: widget.rect.top,
      width: widget.rect.width,
      height: widget.rect.height,
      child: FadeTransition(
        opacity: _opacity,
        child: ScaleTransition(
          scale: _scale,
          alignment: Alignment.center,
          child: widget.child,
        ),
      ),
    );
  }
}