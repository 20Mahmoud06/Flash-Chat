import 'package:flash_chat_app/features/home/widgets/home_chat_tile_view.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _wrap(Widget child) {
  return ScreenUtilInit(
    designSize: const Size(375, 812),
    builder: (context, _) => MaterialApp(
      home: Scaffold(
        body: child,
      ),
    ),
  );
}

void main() {
  testWidgets('HomeChatTileView places time on top right and last message below',
      (tester) async {
    bool tapped = false;

    await tester.pumpWidget(
      _wrap(
        HomeChatTileView(
          avatar: '👤',
          title: 'Mahmoud Safa',
          isPinned: false,
          isDeleted: false,
          isBlocked: false,
          isNewHighlight: false,
          isUnread: false,
          badgeCount: 0,
          prefix: 'Mahmoud Safa: ',
          lastMessage: '📞 Voice message (0:15)',
          time: '4/10/2026',
          onTap: () {
            tapped = true;
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final titleFinder = find.text('Mahmoud Safa');
    final timeFinder = find.text('4/10/2026');
    final lastMessageFinder = find.text('📞 Voice message (0:15)');

    expect(titleFinder, findsOneWidget);
    expect(timeFinder, findsOneWidget);
    expect(lastMessageFinder, findsOneWidget);

    final titleTopLeft = tester.getTopLeft(titleFinder);
    final timeTopRight = tester.getTopRight(timeFinder);
    final lastMessageTopLeft = tester.getTopLeft(lastMessageFinder);

    // Time is to the right of title
    expect(timeTopRight.dx, greaterThan(titleTopLeft.dx));
    // Title and time are roughly on the same top line
    expect((timeTopRight.dy - titleTopLeft.dy).abs(), lessThan(10.0));
    // Last message is positioned below the title line
    expect(lastMessageTopLeft.dy, greaterThan(titleTopLeft.dy));

    // Verify tap works
    await tester.tap(titleFinder);
    expect(tapped, isTrue);
  });
}
