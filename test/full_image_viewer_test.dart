import 'package:flash_chat_app/core/utils/full_image_viewer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Future<void> doubleTapAt(WidgetTester tester, Offset position) async {
  final gesture = await tester.startGesture(position);
  await gesture.up();
  await tester.pump(const Duration(milliseconds: 50));
  final gesture2 = await tester.startGesture(position);
  await gesture2.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('double tap toggles zoom in and out', (tester) async {
    await tester.binding.setSurfaceSize(const Size(800, 800));
    await tester.pumpWidget(
      MaterialApp(
        home: ScreenUtilInit(
          designSize: const Size(400, 800),
          minTextAdapt: true,
          splitScreenMode: true,
          builder: (context, child) => const FullImageViewer(
            imageUrl: 'https://example.com/nonexistent.png',
            heroTag: 'test',
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    InteractiveViewer? viewer() {
      final finder = find.byType(InteractiveViewer);
      return tester.widget<InteractiveViewer>(finder);
    }

    final Offset center = tester.getCenter(find.byType(InteractiveViewer));

    // First double tap -> zoom in
    await doubleTapAt(tester, center);
    await tester.pumpAndSettle();
    final scaleIn = viewer()!.transformationController!.value.getMaxScaleOnAxis();
    debugPrint('SCALE AFTER ZOOM IN: $scaleIn');

    // Second double tap -> zoom out
    await doubleTapAt(tester, center);
    await tester.pumpAndSettle();
    final scaleOut = viewer()!.transformationController!.value.getMaxScaleOnAxis();
    debugPrint('SCALE AFTER ZOOM OUT: $scaleOut');

    expect(scaleIn, greaterThan(1.05));
    expect(scaleOut, lessThanOrEqualTo(1.05));
  });
}
