import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';

/// Represents a single message queued for send while offline.
/// Persisted to disk so it survives app restarts.
class PendingMessage {
  final String localId;
  final String chatId;
  final bool isGroup;
  final String recipientId;
  final String messageType;
  final String text;
  final Map<String, dynamic> sender;
  final Map<String, dynamic>? repliedTo;
  final List<String> mediaPaths;
  final int? voiceDuration;
  final int? videoDuration;
  final int createdAt;
  final int retryCount;
  static const int maxRetries = 5;

  const PendingMessage({
    required this.localId,
    required this.chatId,
    required this.isGroup,
    required this.recipientId,
    required this.messageType,
    required this.text,
    required this.sender,
    this.repliedTo,
    this.mediaPaths = const [],
    this.voiceDuration,
    this.videoDuration,
    required this.createdAt,
    this.retryCount = 0,
  });

  bool get canRetry => retryCount < maxRetries;

  /// Exponential backoff: 2s, 4s, 8s, 16s, 32s.
  Duration get backoffDelay =>
      Duration(seconds: 1 << (retryCount + 1));

  PendingMessage copyWith({int? retryCount}) => PendingMessage(
        localId: localId,
        chatId: chatId,
        isGroup: isGroup,
        recipientId: recipientId,
        messageType: messageType,
        text: text,
        sender: sender,
        repliedTo: repliedTo,
        mediaPaths: mediaPaths,
        voiceDuration: voiceDuration,
        videoDuration: videoDuration,
        createdAt: createdAt,
        retryCount: retryCount ?? this.retryCount,
      );

  Map<String, dynamic> toJson() => {
        'localId': localId,
        'chatId': chatId,
        'isGroup': isGroup,
        'recipientId': recipientId,
        'messageType': messageType,
        'text': text,
        'sender': sender,
        'repliedTo': repliedTo,
        'mediaPaths': mediaPaths,
        'voiceDuration': voiceDuration,
        'videoDuration': videoDuration,
        'createdAt': createdAt,
        'retryCount': retryCount,
      };

  factory PendingMessage.fromJson(Map<String, dynamic> json) =>
      PendingMessage(
        localId: json['localId'] as String,
        chatId: json['chatId'] as String,
        isGroup: json['isGroup'] as bool? ?? false,
        recipientId: json['recipientId'] as String? ?? '',
        messageType: json['messageType'] as String? ?? 'text',
        text: json['text'] as String? ?? '',
        sender: json['sender'] as Map<String, dynamic>,
        repliedTo: json['repliedTo'] as Map<String, dynamic>?,
        mediaPaths: json['mediaPaths'] != null
            ? List<String>.from(json['mediaPaths'] as List)
            : const [],
        voiceDuration: json['voiceDuration'] as int?,
        videoDuration: json['videoDuration'] as int?,
        createdAt: json['createdAt'] as int? ?? 0,
        retryCount: json['retryCount'] as int? ?? 0,
      );
}

/// Production-grade offline message queue.
///
/// Persists queued messages to a JSON file per chat and copies media files
/// (images, videos, voice recordings) to a dedicated directory so they
/// survive app restarts. On reconnect, the bloc loads the queue and
/// replays each send action.
class OfflineQueueService {
  OfflineQueueService._();
  static final OfflineQueueService instance = OfflineQueueService._();

  Directory? _baseDir;

  Future<Directory> get _queueDir async {
    if (_baseDir != null) return _baseDir!;
    final appDir = await getApplicationDocumentsDirectory();
    _baseDir = Directory('${appDir.path}/offline_queue');
    await _baseDir!.create(recursive: true);
    return _baseDir!;
  }

  Future<File> _queueFile(String chatId) async {
    final dir = await _queueDir;
    return File('${dir.path}/$chatId.json');
  }

  // ── Media file persistence ──────────────────────────────────────────

  /// Copies [file] into the persistent offline-media directory and returns
  /// the new absolute path. The copy survives temp-dir purges and app
  /// restarts.
  Future<String> persistFile(File file, String localId, {int index = 0}) async {
    final dir = await _queueDir;
    final mediaDir = Directory('${dir.path}/$localId');
    await mediaDir.create(recursive: true);
    final ext = file.path.split('.').last;
    final dest = File('${mediaDir.path}/$index.$ext');
    await file.copy(dest.path);
    return dest.path;
  }

  Future<void> cleanupFiles(String localId) async {
    try {
      final dir = await _queueDir;
      final mediaDir = Directory('${dir.path}/$localId');
      if (await mediaDir.exists()) {
        await mediaDir.delete(recursive: true);
      }
    } catch (e) {
      debugPrint('OfflineQueue: failed to cleanup $localId: $e');
    }
  }

  // ── Queue persistence ───────────────────────────────────────────────

  Future<List<PendingMessage>> loadQueue(String chatId) async {
    try {
      final file = await _queueFile(chatId);
      if (!await file.exists()) return [];
      final content = await file.readAsString();
      if (content.isEmpty) return [];
      final list = jsonDecode(content) as List;
      return list
          .map((e) => PendingMessage.fromJson(e as Map<String, dynamic>))
          .toList();
    } catch (e) {
      debugPrint('OfflineQueue: failed to load queue for $chatId: $e');
      return [];
    }
  }

  Future<void> _saveQueue(String chatId, List<PendingMessage> queue) async {
    try {
      final file = await _queueFile(chatId);
      final json = queue.map((m) => m.toJson()).toList();
      await file.writeAsString(jsonEncode(json));
    } catch (e) {
      debugPrint('OfflineQueue: failed to save queue for $chatId: $e');
    }
  }

  Future<void> enqueue(PendingMessage message) async {
    final queue = await loadQueue(message.chatId);
    queue.add(message);
    await _saveQueue(message.chatId, queue);
  }

  Future<void> remove(String chatId, String localId) async {
    final queue = await loadQueue(chatId);
    queue.removeWhere((m) => m.localId == localId);
    await _saveQueue(chatId, queue);
    await cleanupFiles(localId);
  }

  /// Updates the retry count for a queued message on disk.
  Future<void> updateRetry(String chatId, String localId, int retryCount) async {
    final queue = await loadQueue(chatId);
    final idx = queue.indexWhere((m) => m.localId == localId);
    if (idx == -1) return;
    queue[idx] = queue[idx].copyWith(retryCount: retryCount);
    await _saveQueue(chatId, queue);
  }

  Future<void> clearQueue(String chatId) async {
    final queue = await loadQueue(chatId);
    for (final msg in queue) {
      await cleanupFiles(msg.localId);
    }
    final file = await _queueFile(chatId);
    if (await file.exists()) await file.delete();
  }
}
