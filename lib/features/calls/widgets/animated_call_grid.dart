import 'package:flutter/material.dart';

/// Full-screen participant grid (shared by voice and video group calls) that
/// animates smoothly when the participant set changes:
///
///  * [AnimatedSize] per cell makes every tile glide to its new size when the
///    grid re-packs (someone joins/leaves changes the number of columns).
///  * [AnimatedSwitcher] keyed by participant uid fades/scales a joining tile
///    in (and animates a departing tile out in its cell).
///
/// Layout fills the whole available surface: 2 participants stack as two big
/// full-width tiles, 3-4 use a 2-column grid, 5-9 a 3-column grid, more a
/// 4-column grid.
class AnimatedCallGrid extends StatelessWidget {
  const AnimatedCallGrid({
    super.key,
    required this.uids,
    required this.itemBuilder,
    this.spacing = 6,
    this.duration = const Duration(milliseconds: 320),
  });

  /// Ordered participant uids; `0` is the local user.
  final List<int> uids;

  /// Builds one participant tile. Called with the same uid across rebuilds so
  /// the [AnimatedSwitcher] can keep stable element identity.
  final Widget Function(BuildContext context, int uid) itemBuilder;

  /// Gap between tiles.
  final double spacing;

  /// Duration of the size / fade / scale animations.
  final Duration duration;

  int get _crossCount {
    final count = uids.length;
    if (count <= 2) return 1;
    if (count <= 4) return 2;
    if (count <= 9) return 3;
    return 4;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final count = uids.length;
        if (count == 0) return const SizedBox.shrink();

        final crossCount = _crossCount;
        final rows = <List<int>>[];
        for (var i = 0; i < count; i += crossCount) {
          final end = i + crossCount < count ? i + crossCount : count;
          rows.add(uids.sublist(i, end));
        }

        final tileWidth =
            (constraints.maxWidth - (crossCount - 1) * spacing) / crossCount;
        final tileHeight =
            (constraints.maxHeight - (rows.length - 1) * spacing) / rows.length;

        Widget tileAt(int row, int col, int uid) {
          return KeyedSubtree(
            key: ValueKey('$row-$col'),
            child: AnimatedSize(
              duration: duration,
              curve: Curves.easeInOut,
              alignment: Alignment.center,
              child: AnimatedSwitcher(
                duration: duration,
                switchInCurve: Curves.easeOutBack,
                switchOutCurve: Curves.easeIn,
                transitionBuilder: (child, animation) => FadeTransition(
                  opacity: animation,
                  child: ScaleTransition(
                    scale: animation,
                    alignment: Alignment.center,
                    child: child,
                  ),
                ),
                child: SizedBox(
                  key: ValueKey(uid),
                  width: tileWidth,
                  height: tileHeight,
                  child: itemBuilder(context, uid),
                ),
              ),
            ),
          );
        }

        return Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var r = 0; r < rows.length; r++)
                Padding(
                  padding: EdgeInsets.only(
                    bottom: r == rows.length - 1 ? 0 : spacing,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      for (var c = 0; c < rows[r].length; c++)
                        Padding(
                          padding: EdgeInsets.only(
                            right:
                                c == rows[r].length - 1 ? 0 : spacing,
                          ),
                          child: tileAt(r, c, rows[r][c]),
                        ),
                    ],
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}