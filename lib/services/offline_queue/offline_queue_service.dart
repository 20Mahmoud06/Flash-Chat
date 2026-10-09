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
  final List<int?>? videoDurations;
  final String? fileName;
  final int? fileSize;
  final int createdAt;
  final int retryCount;

  /// Local copies of the media items of an already-sent message that failed to
  /// upload, keyed by the item's stable id (`mediaItems[].id`).
  ///
  /// A batch is reported as sent as soon as *one* item lands, so the queue
  /// entry would normally be dropped (and its files deleted) at that point.
  /// When some items failed, their files are parked here instead: the message
  /// stays on screen with a retry tile, and the file survives until the user
  /// retries or deletes that item, even across app restarts.
  final Map<String, String> failedMediaItems;

  /// Set once the message reached Firestore with at least one failed item, so
  /// the queue no longer re-runs the whole send — only the failed item is left
  /// to retry on demand.
  final bool hasFailedItems;

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
    this.videoDurations,
    this.fileName,
    this.fileSize,
    required this.createdAt,
    this.retryCount = 0,
    this.failedMediaItems = const {},
    this.hasFailedItems = false,
  });

  bool get canRetry => retryCount < maxRetries;

  /// Exponential backoff: 2s, 4s, 8s, 16s, 32s.
  Duration get backoffDelay => Duration(seconds: 1 << (retryCount + 1));

  PendingMessage copyWith({
    int? retryCount,
    List<String>? mediaPaths,
    Map<String, String>? failedMediaItems,
    bool? hasFailedItems,
  }) =>
      PendingMessage(
        localId: localId,
        chatId: chatId,
        isGroup: isGroup,
        recipientId: recipientId,
        messageType: messageType,
        text: text,
        sender: sender,
        repliedTo: repliedTo,
        mediaPaths: mediaPaths ?? this.mediaPaths,
        voiceDuration: voiceDuration,
        videoDuration: videoDuration,
        videoDurations: videoDurations,
        fileName: fileName,
        fileSize: fileSize,
        createdAt: createdAt,
        retryCount: retryCount ?? this.retryCount,
        failedMediaItems: failedMediaItems ?? this.failedMediaItems,
        hasFailedItems: hasFailedItems ?? this.hasFailedItems,
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
        'videoDurations': videoDurations,
        'fileName': fileName,
        'fileSize': fileSize,
        'createdAt': createdAt,
        'retryCount': retryCount,
        'failedMediaItems': failedMediaItems,
        'hasFailedItems': hasFailedItems,
      };

  factory PendingMessage.fromJson(Map<String, dynamic> json) => PendingMessage(
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
        videoDurations: json['videoDurations'] != null
            ? (json['videoDurations'] as List)
                .map((value) => value is num ? value.toInt() : null)
                .toList()
            : null,
        fileName: json['fileName'] as String?,
        fileSize: json['fileSize'] as int?,
        createdAt: json['createdAt'] as int? ?? 0,
        retryCount: json['retryCount'] as int? ?? 0,
        failedMediaItems: json['failedMediaItems'] != null
            ? Map<String, String>.from(json['failedMediaItems'] as Map)
            : const {},
        hasFailedItems: json['hasFailedItems'] as bool? ?? false,
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

  /// Copies [file] into the persistent store under a name derived from
  /// [itemId], so persisting the same item again (a later send attempt) simply
  /// overwrites the copy instead of piling up duplicates.
  Future<String> persistFailedItem(
      File file, String docId, String itemId) async {
    final dir = await _queueDir;
    final mediaDir = Directory('${dir.path}/$docId');
    await mediaDir.create(recursive: true);
    final ext = file.path.split('.').last;
    final safeId = itemId.replaceAll(RegExp(r'[^A-Za-z0-9_-]'), '_');
    final dest = File('${mediaDir.path}/$safeId.$ext');
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
  Future<void> updateRetry(
      String chatId, String localId, int retryCount) async {
    final queue = await loadQueue(chatId);
    final idx = queue.indexWhere((m) => m.localId == localId);
    if (idx == -1) return;
    queue[idx] = queue[idx].copyWith(retryCount: retryCount);
    await _saveQueue(chatId, queue);
  }

  /// Records the failed media items of an already-sent message so their
  /// retry tiles keep working after an app restart.
  ///
  /// [message] supplies the descriptive fields only when the entry has to be
  /// created (the online path never enqueues a replayable message). The entry
  /// is flagged [PendingMessage.hasFailedItems], so the replay logic leaves it
  /// alone and only the manual retry consumes it.
  Future<void> retainFailedItems(
      PendingMessage message, Map<String, String> items) async {
    if (items.isEmpty) return;
    final queue = await loadQueue(message.chatId);
    final idx = queue.indexWhere((m) => m.localId == message.localId);
    final base = idx == -1 ? message : queue[idx];
    final entry = base.copyWith(
      failedMediaItems: {...base.failedMediaItems, ...items},
      hasFailedItems: true,
      // No longer replayable: the message is already on Firestore.
      mediaPaths: const [],
    );
    if (idx == -1) {
      queue.add(entry);
    } else {
      queue[idx] = entry;
    }
    await _saveQueue(message.chatId, queue);
  }

  /// Drops [itemId] from the failed-items entry and deletes the copied file.
  /// Removes the whole entry once nothing is left to retry.
  Future<void> releaseFailedItem(
      String chatId, String localId, String itemId) async {
    final queue = await loadQueue(chatId);
    final idx = queue.indexWhere((m) => m.localId == localId);
    if (idx == -1) return;
    final entry = queue[idx];
    final remaining = Map<String, String>.from(entry.failedMediaItems)
      ..remove(itemId);
    if (remaining.isEmpty) {
      queue.removeAt(idx);
      await _saveQueue(chatId, queue);
      await cleanupFiles(localId);
      return;
    }
    queue[idx] = entry.copyWith(
      failedMediaItems: remaining,
      hasFailedItems: true,
    );
    await _saveQueue(chatId, queue);
  }

  /// The message reached Firestore, so the replayable queue entry is dropped.
  ///
  /// [keep] holds the items whose upload failed: their files must survive for
  /// the retry tile, so the entry is kept (flagged, non-replayable) instead of
  /// being deleted along with the copies.
  Future<void> settleAfterSend(
      String chatId, String localId, Map<String, String> keep) async {
    if (keep.isEmpty) {
      await remove(chatId, localId);
      return;
    }
    final queue = await loadQueue(chatId);
    final idx = queue.indexWhere((m) => m.localId == localId);
    if (idx == -1) return;
    queue[idx] = queue[idx].copyWith(
      failedMediaItems: keep,
      hasFailedItems: true,
      mediaPaths: const [],
    );
    await _saveQueue(chatId, queue);
  }

  /// Local copy of a failed media item, or null when it is gone (already
  /// retried, deleted, or cleaned up). Survives app restarts.
  Future<File?> failedItemFile(String chatId, String itemId) async {
    final queue = await loadQueue(chatId);
    for (final message in queue) {
      final path = message.failedMediaItems[itemId];
      if (path == null) continue;
      final file = File(path);
      if (await file.exists()) return file;
    }
    return null;
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
