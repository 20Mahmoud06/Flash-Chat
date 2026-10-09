import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/features/chat/widgets/reply_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('videoDurationAt', () {
    test('returns the per-index duration for a multi-video message', () {
      final message = MessageModel(
        id: 'm1',
        senderId: 'a',
        recipientId: 'b',
        text: '',
        timestamp: Timestamp.now(),
        messageType: MessageType.video,
        mediaUrls: const ['v0', 'v1', 'v2', 'v3'],
        videoDurations: const [10, 20, null, 40],
      );

      expect(message.videoDurationAt(0), 10);
      expect(message.videoDurationAt(1), 20);
      expect(message.videoDurationAt(3), 40);
    });

    test('falls back to the legacy single videoDuration for index 0', () {
      final message = MessageModel(
        id: 'm2',
        senderId: 'a',
        recipientId: 'b',
        text: '',
        timestamp: Timestamp.now(),
        messageType: MessageType.video,
        mediaUrls: const ['v0', 'v1'],
        videoDuration: 33,
      );

      expect(message.videoDurationAt(0), 33);
      expect(message.videoDurationAt(1), isNull);
    });

    test('returns null for out-of-range indexes', () {
      final message = MessageModel(
        id: 'm3',
        senderId: 'a',
        recipientId: 'b',
        text: '',
        timestamp: Timestamp.now(),
        messageType: MessageType.video,
        mediaUrls: const ['v0'],
        videoDurations: const [5],
      );

      expect(message.videoDurationAt(1), isNull);
      expect(message.videoDurationAt(-1), isNull);
    });
  });

  group('videoDurations persistence', () {
    test('writes the per-index durations, keeping null slots', () {
      final message = MessageModel(
        id: 'vid',
        senderId: 'a',
        recipientId: 'b',
        text: 'caption',
        timestamp: Timestamp.now(),
        messageType: MessageType.video,
        mediaUrls: const ['v0', 'v1'],
        videoDurations: const [12, null],
      );

      final data = message.toFirestore();

      expect(data['videoDurations'], [12, null]);
      expect(data['mediaUrls'], ['v0', 'v1']);
    });

    test('omits the field when no duration is known', () {
      final message = MessageModel(
        id: 'vid',
        senderId: 'a',
        recipientId: 'b',
        text: '',
        timestamp: Timestamp.now(),
        messageType: MessageType.video,
        mediaUrls: const ['v0'],
      );

      expect(message.toFirestore().containsKey('videoDurations'), isFalse);
    });

    test('copyWith keeps the durations', () {
      final message = MessageModel(
        id: 'vid',
        senderId: 'a',
        recipientId: 'b',
        text: '',
        timestamp: Timestamp.now(),
        messageType: MessageType.video,
        mediaUrls: const ['v0', 'v1'],
        videoDurations: const [1, 2],
      );

      final updated = message.copyWith(status: 'seen');

      expect(updated.videoDurations, [1, 2]);
      expect(updated.status, 'seen');
    });
  });

  group('replyPreviewString', () {
    MessageModel video(String text, List<String> urls) => MessageModel(
          id: 'r',
          senderId: 'a',
          recipientId: 'b',
          text: text,
          timestamp: Timestamp.now(),
          messageType: MessageType.video,
          mediaUrls: urls,
        );

    test('labels a whole video group', () {
      expect(
        replyPreviewString(video('', const ['v0', 'v1']), mediaCount: 2),
        '📹 2 videos',
      );
    });

    test('keeps the caption for a video group', () {
      expect(
        replyPreviewString(video('trip', const ['v0', 'v1']), mediaCount: 2),
        'trip',
      );
    });

    test('labels a single video', () {
      expect(
        replyPreviewString(video('', const ['v0']), mediaCount: 1),
        'Video',
      );
    });
  });
}
