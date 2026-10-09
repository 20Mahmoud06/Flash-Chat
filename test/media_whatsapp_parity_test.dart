import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/core/utils/message_preview.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/features/chat/widgets/reply_preview.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('MediaItem model & equality', () {
    test('equality and hashCode are based on id', () {
      const item1 = MediaItem(id: 'm1_0', url: 'http://img1.jpg');
      const item2 = MediaItem(id: 'm1_0', url: 'http://img1_diff.jpg');
      const item3 = MediaItem(id: 'm1_1', url: 'http://img1.jpg');

      expect(item1 == item2, isTrue);
      expect(item1.hashCode, item2.hashCode);
      expect(item1 == item3, isFalse);
    });

    test('mediaItemIdAt returns stable id and empty string for out-of-range', () {
      final message = MessageModel(
        id: 'msg123',
        senderId: 'u1',
        recipientId: 'u2',
        text: '',
        timestamp: Timestamp.now(),
        mediaItems: const [
          MediaItem(id: 'msg123_0', url: 'u0'),
          MediaItem(id: 'msg123_1', url: 'u1'),
        ],
      );

      expect(message.mediaItemIdAt(0), 'msg123_0');
      expect(message.mediaItemIdAt(1), 'msg123_1');
      expect(message.mediaItemIdAt(2), '');
      expect(message.mediaItemIdAt(-1), '');
    });

    test('videoDurationAt prioritizes MediaItem.durationSeconds', () {
      final message = MessageModel(
        id: 'msg123',
        senderId: 'u1',
        recipientId: 'u2',
        text: '',
        timestamp: Timestamp.now(),
        messageType: MessageType.video,
        mediaItems: const [
          MediaItem(id: 'msg123_0', url: 'v0', durationSeconds: 45),
          MediaItem(id: 'msg123_1', url: 'v1', durationSeconds: 60),
        ],
        videoDurations: const [10, 20],
      );

      expect(message.videoDurationAt(0), 45);
      expect(message.videoDurationAt(1), 60);
    });
  });

  group('Batch previews during in-flight send', () {
    test('messagePreviewText reports plural for in-flight mediaItems batch', () {
      final map = {
        'messageType': 'image',
        'mediaUrls': <String>[],
        'mediaItems': [
          {'id': 'm_0', 'state': 'uploading'},
          {'id': 'm_1', 'state': 'uploading'},
          {'id': 'm_2', 'state': 'uploading'},
        ],
      };

      expect(messagePreviewText(map), '📷 3 photos');
    });

    test('messagePreviewText reports count for 9 photos and 3 videos', () {
      final photos9 = {
        'messageType': 'image',
        'mediaUrls': List.generate(9, (i) => 'img_$i'),
      };
      expect(messagePreviewText(photos9), '📷 9 photos');

      final videos3 = {
        'messageType': 'video',
        'mediaUrls': List.generate(3, (i) => 'vid_$i'),
      };
      expect(messagePreviewText(videos3), '📹 3 videos');

      final singlePhoto = {
        'messageType': 'image',
        'mediaUrls': ['img_0'],
      };
      expect(messagePreviewText(singlePhoto), '📷 Photo');

      final singleVideo = {
        'messageType': 'video',
        'mediaUrls': ['vid_0'],
      };
      expect(messagePreviewText(singleVideo), '📹 Video');
    });

    test('replyPreviewString uses mediaSlotCount when mediaUrls is empty or partial', () {
      final message = MessageModel(
        id: 'msg_batch',
        senderId: 'u1',
        recipientId: 'u2',
        text: '',
        timestamp: Timestamp.now(),
        messageType: MessageType.image,
        mediaUrls: const ['u0'], // only 1 done so far
        mediaItems: const [
          MediaItem(id: 'msg_batch_0', url: 'u0'),
          MediaItem(id: 'msg_batch_1', state: MediaItemState.uploading),
          MediaItem(id: 'msg_batch_2', state: MediaItemState.uploading),
        ],
      );

      expect(replyPreviewString(message), '📷 3 photos');
    });
  });
}
