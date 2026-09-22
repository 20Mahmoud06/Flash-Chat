import 'package:flash_chat_app/core/utils/video_duration.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('effectiveVideoDuration', () {
    const stored = Duration(seconds: 36);

    test('prefers the controller duration when it is known', () {
      const controllerDuration = Duration(minutes: 1, seconds: 5);
      expect(
        effectiveVideoDuration(controllerDuration, stored),
        controllerDuration,
      );
    });

    test('falls back to the stored length while the controller reports zero',
        () {
      expect(effectiveVideoDuration(Duration.zero, stored), stored);
    });

    test('returns zero when both the controller and stored length are unknown',
        () {
      expect(effectiveVideoDuration(Duration.zero, null), Duration.zero);
    });

    test('ignores the stored length as soon as the controller duration is real',
        () {
      const controllerDuration = Duration(seconds: 9);
      expect(
        effectiveVideoDuration(controllerDuration, stored),
        const Duration(seconds: 9),
      );
    });
  });
}