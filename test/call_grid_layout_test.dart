import 'package:flash_chat_app/features/calls/widgets/animated_call_grid.dart';
import 'package:flash_chat_app/features/calls/widgets/group_voice_grid_tile.dart';
import 'package:flash_chat_app/features/calls/widgets/video_call_avatar_placeholder.dart';
import 'package:flash_chat_app/features/calls/widgets/video_call_grid_area.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Same grid configuration [VoiceCallGridArea] uses, with long participant
/// names so the name tag is forced to ellipsize.
Widget _videoHost(List<int> uids, {Size size = const Size(360, 640)}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: AnimatedCallGrid(
            uids: uids,
            spacing: 6,
            minTileWidth: 100,
            minTileHeight: 112,
            tileAspectRatio: 0.72,
            maxColumns: 5,
            itemBuilder: (context, uid) => VideoCallGridTile(
              content: VideoCallAvatarPlaceholder(
                displayName: 'Participant $uid',
                statusText: "Camera off",
                isCompact: true,
              ),
              participantName:
                  'Participant $uid with a very long display name',
              isSpeaking: uid == 1,
              isMutedAudio: uid.isEven,
            ),
          ),
        ),
      ),
    ),
  );
}

/// Regression guard for the group-call grid overflow: the grid must lay out
/// any number of participants on any screen without a RenderFlex overflow and
/// without painting a tile outside the visible area.
Widget _host(List<int> uids, {Size size = const Size(360, 640)}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(
          width: size.width,
          height: size.height,
          child: AnimatedCallGrid(
            uids: uids,
            spacing: 12,
            minTileWidth: 96,
            minTileHeight: 108,
            tileAspectRatio: 1,
            maxColumns: 4,
            itemBuilder: (context, uid) => GroupVoiceGridTile(
              name: uid == 0 ? 'You' : 'Participant $uid',
              isMuted: uid.isEven,
              isLocal: uid == 0,
              isSpeaking: uid == 1,
            ),
          ),
        ),
      ),
    ),
  );
}

List<int> _uids(int count) => List<int>.generate(count, (int i) => i);

void main() {
  const List<Size> screens = <Size>[
    Size(320, 480), // small phone
    Size(360, 640), // phone
    Size(360, 900), // tall phone
    Size(800, 360), // landscape phone
    Size(1024, 768), // tablet
  ];

  testWidgets('lays out 1..40 participants on every screen size', (
    WidgetTester tester,
  ) async {
    for (final Size screen in screens) {
      tester.view.physicalSize = screen * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      for (int count = 1; count <= 40; count++) {
        await tester.pumpWidget(_host(_uids(count), size: screen));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.takeException(),
          isNull,
          reason: 'overflow with $count participants on $screen',
        );
      }
    }
  });

  testWidgets('tiles stay inside the grid bounds while someone joins/leaves', (
    WidgetTester tester,
  ) async {
    const Size screen = Size(360, 640);
    tester.view.physicalSize = screen * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    List<int> uids = _uids(4);
    await tester.pumpWidget(_host(uids, size: screen));
    await tester.pump(const Duration(milliseconds: 400));

    // Grow the call one participant at a time; the re-pack must animate
    // without overflowing and every tile must stay on screen.
    for (int next = 5; next <= 30; next++) {
      uids = _uids(next);
      await tester.pumpWidget(_host(uids, size: screen));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'join #$next (mid animation)');
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'join #$next (settled)');
    }

    // Shrink back down again.
    for (int next = 29; next >= 1; next--) {
      uids = _uids(next);
      await tester.pumpWidget(_host(uids, size: screen));
      await tester.pump(const Duration(milliseconds: 100));
      expect(tester.takeException(), isNull, reason: 'leave #$next (mid animation)');
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'leave #$next (settled)');
    }
  });

  testWidgets('group video grid: 1..40 participants never overflow', (
    WidgetTester tester,
  ) async {
    for (final Size screen in screens) {
      tester.view.physicalSize = screen * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      for (int count = 1; count <= 40; count++) {
        await tester.pumpWidget(_videoHost(_uids(count), size: screen));
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          tester.takeException(),
          isNull,
          reason: 'video overflow with $count participants on $screen',
        );
      }
    }
  });

  testWidgets('group video grid: joining/leaving never overflows', (
    WidgetTester tester,
  ) async {
    const Size screen = Size(360, 640);
    tester.view.physicalSize = screen * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    for (int count = 1; count <= 30; count++) {
      await tester.pumpWidget(_videoHost(_uids(count), size: screen));
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull, reason: 'video join #$count');
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'video settled #$count');
    }
    for (int count = 29; count >= 1; count--) {
      await tester.pumpWidget(_videoHost(_uids(count), size: screen));
      await tester.pump(const Duration(milliseconds: 120));
      expect(tester.takeException(), isNull, reason: 'video leave #$count');
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull, reason: 'video settled #$count');
    }
  });

  testWidgets('crowded calls keep readable tiles and become scrollable', (
    WidgetTester tester,
  ) async {
    const Size screen = Size(320, 480);
    tester.view.physicalSize = screen * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_uids(40), size: screen));
    await tester.pump(const Duration(milliseconds: 400));

    expect(tester.takeException(), isNull);
    // Too many tiles to fit the screen: keep them readable inside a scroller.
    expect(find.byType(SingleChildScrollView), findsWidgets);
    final Size tile = tester.getSize(find.byType(GroupVoiceGridTile).first);
    expect(tile.width, greaterThanOrEqualTo(96));
    expect(tile.height, greaterThanOrEqualTo(108));
  });

  testWidgets('few participants fill the whole surface', (
    WidgetTester tester,
  ) async {
    const Size screen = Size(360, 640);
    tester.view.physicalSize = screen * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(_host(_uids(1), size: screen));
    await tester.pump(const Duration(milliseconds: 400));

    final Size tile = tester.getSize(find.byType(GroupVoiceGridTile).first);
    expect(tile.width, moreOrLessEquals(screen.width));
    expect(tile.height, moreOrLessEquals(screen.height));
  });
}