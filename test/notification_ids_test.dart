import 'package:flash_chat_app/core/utils/notification_ids.dart';
import 'package:flutter_test/flutter_test.dart';

/// Contract tests for the notification ids / watermark keys shared between the
/// Dart backfill and the native FCM/HMS services. The Android side
/// (MissedNotifPrefs.kt) must mirror these EXACTLY (with a `flutter.` prefix in
/// the `FlutterSharedPreferences` XML), so any drift here would silently
/// re-notify already-delivered messages.
void main() {
  group('conversationNotificationId', () {
    test('is deterministic', () {
      expect(conversationNotificationId('abc', isGroup: false),
          conversationNotificationId('abc', isGroup: false));
      expect(conversationNotificationId('g1', isGroup: true),
          conversationNotificationId('g1', isGroup: true));
    });

    test('keeps group ids in a separate bucket from 1-to-1 ids', () {
      final oneOnOne = conversationNotificationId('peer', isGroup: false);
      final group = conversationNotificationId('peer', isGroup: true);
      expect(oneOnOne, lessThan(2000000));
      expect(group, greaterThanOrEqualTo(2000000));
      expect(group, lessThan(3000000));
    });

    test('different peers produce different ids', () {
      expect(
        conversationNotificationId('peerA', isGroup: false),
        isNot(conversationNotificationId('peerB', isGroup: false)),
      );
    });
  });

  group('missedNotificationPrefKey', () {
    test('builds the 1-to-1 key under the missed_notif_ts prefix', () {
      expect(
        missedNotificationPrefKey('peer123', isGroup: false),
        'missed_notif_ts:chat:peer123',
      );
    });

    test('builds the group key under the missed_notif_ts prefix', () {
      expect(
        missedNotificationPrefKey('grp456', isGroup: true),
        'missed_notif_ts:group:grp456',
      );
    });

    test('round-trips through the backfill prefix parser', () {
      // MissedNotificationsService trims '<prefix>:' before caching the value;
      // the native format must always survive that trim.
      const prefix = missedNotificationsPrefsPrefix;
      for (final key in [
        missedNotificationPrefKey('peer123', isGroup: false),
        missedNotificationPrefKey('grp456', isGroup: true),
      ]) {
        expect(key.startsWith(prefix), isTrue);
        final rest = key.substring(prefix.length + 1);
        expect(rest, isNotEmpty);
        expect(rest.contains(prefix), isFalse);
      }
    });

    test('chat and group keys for the same peer never collide', () {
      expect(
        missedNotificationPrefKey('peer', isGroup: false),
        isNot(missedNotificationPrefKey('peer', isGroup: true)),
      );
    });
  });
}