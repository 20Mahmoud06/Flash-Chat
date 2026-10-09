import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:swipe_to/swipe_to.dart';

/// Regression coverage for swipe-to-reply on multi-photo message bubbles:
/// the `swipe_to` gestural layer must fire even when the child is a full
/// bubble with a tappable / long-pressable photo grid placed inside a
/// reversed [ListView], mirroring how ChatMessagesBody lays out bubbles.
void main() {
  Widget fourPhotoGrid(Key key) {
    return Container(
      key: key,
      width: 200,
      height: 200,
      color: Colors.white,
      child: GridView.builder(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: 2,
          childAspectRatio: 1,
        ),
        itemCount: 4,
        itemBuilder: (_, i) => GestureDetector(
          onTap: () {},
          onLongPress: () {},
          child: Container(
            color: Colors.amber,
            child: const Center(child: Icon(Icons.photo)),
          ),
        ),
      ),
    );
  }

  Future<void> dragRight(WidgetTester tester, Key target,
      {int pointer = 1}) async {
    final center = tester.getCenter(find.byKey(target));
    final gesture = await tester.startGesture(
        center, pointer: pointer, kind: PointerDeviceKind.touch);
    await gesture.moveBy(const Offset(40, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.moveBy(const Offset(60, 0));
    await tester.pump(const Duration(milliseconds: 16));
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('SwipeTo fires over a simple text child', (tester) async {
    var fired = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 600,
            child: SwipeTo(
              onRightSwipe: (_) => fired = true,
              child: const ColoredBox(
                key: Key('plain'),
                color: Colors.blueAccent,
                child: SizedBox(width: 200, height: 80),
              ),
            ),
          ),
        ),
      ),
    ));

    await dragRight(tester, const Key('plain'));
    expect(fired, isTrue, reason: 'plain child should accept right swipe');
  });

  testWidgets('SwipeTo over a multi-photo GridView bubble', (tester) async {
    var fired = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 600,
            child: SwipeTo(
              onRightSwipe: (_) => fired = true,
              child: fourPhotoGrid(const Key('grid')),
            ),
          ),
        ),
      ),
    ));

    await dragRight(tester, const Key('grid'), pointer: 2);
    expect(fired, isTrue,
        reason: 'swipe over grid child should still fire onRightSwipe');
  });

  testWidgets('SwipeTo over grid inside a reversed ListView', (tester) async {
    final fired = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          reverse: true,
          children: [
            SwipeTo(
              onLeftSwipe: (_) => fired.add('bubbleA-left'),
              onRightSwipe: (_) => fired.add('bubbleA-right'),
              child: fourPhotoGrid(const Key('bubbleA')),
            ),
            SwipeTo(
              onLeftSwipe: (_) => fired.add('bubbleB-left'),
              onRightSwipe: (_) => fired.add('bubbleB-right'),
              child: Container(
                key: const Key('bubbleB'),
                width: 160,
                height: 60,
                color: Colors.green,
              ),
            ),
          ],
        ),
      ),
    ));

    await dragRight(tester, const Key('bubbleA'), pointer: 3);
    expect(
      fired,
      equals(const ['bubbleA-right']),
      reason: 'grid bubble inside ListView should fire right swipe only',
    );
  });

  testWidgets(
      'bare GestureDetector.onPanUpdate fires over a GridView', (tester) async {
    var fired = false;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 300,
            height: 600,
            child: GestureDetector(
              onPanUpdate: (_) => fired = true,
              child: fourPhotoGrid(const Key('grid')),
            ),
          ),
        ),
      ),
    ));

    await dragRight(tester, const Key('grid'), pointer: 4);
    expect(fired, isTrue,
        reason: 'pan recognizer must win the arena over the grid cells');
  });
}