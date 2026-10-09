import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType {
  text,
  image,
  video,
  voice,
  audio,
  file,
  system,
  call,
  callActive
}

/// Lifecycle of one photo / video inside a multi-item media message.
enum MediaItemState {
  /// Still uploading — the bubble shows a spinner tile.
  uploading,

  /// Uploaded and visible.
  done,

  /// The upload failed — the bubble shows a retry affordance.
  failed,
}

/// One photo or video of a media message.
///
/// Identity is [id], never the position in the list. That is what makes
/// per-item delete safe: every `repliedTo` payload and every media reaction
/// points at an id, so removing one item leaves its siblings' references
/// intact instead of shifting every index below it.
class MediaItem {
  const MediaItem({
    required this.id,
    this.url,
    this.durationSeconds,
    this.state = MediaItemState.done,
  });

  final String id;

  /// Cloudinary URL. Null while uploading and after a failure.
  final String? url;

  final int? durationSeconds;
  final MediaItemState state;

  bool get isDone => state == MediaItemState.done && url != null;
  bool get isUploading => state == MediaItemState.uploading;
  bool get isFailed => state == MediaItemState.failed;

  MediaItem copyWith({
    String? url,
    int? durationSeconds,
    MediaItemState? state,
  }) {
    return MediaItem(
      id: id,
      url: url ?? this.url,
      durationSeconds: durationSeconds ?? this.durationSeconds,
      state: state ?? this.state,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is MediaItem &&
          runtimeType == other.runtimeType &&
          id == other.id;

  @override
  int get hashCode => id.hashCode;

  Map<String, dynamic> toFirestore() => {
        'id': id,
        if (url != null) 'url': url,
        if (durationSeconds != null) 'duration': durationSeconds,
        'state': state.name,
      };

  static MediaItem fromFirestore(Object? raw, String fallbackId) {
    if (raw is! Map) {
      return MediaItem(id: fallbackId);
    }
    final data = Map<Object?, Object?>.from(raw);
    return MediaItem(
      id: (data['id'] ?? fallbackId).toString(),
      url: data['url'] as String?,
      durationSeconds:
          data['duration'] is num ? (data['duration'] as num).toInt() : null,
      state: MediaItemState.values.firstWhere(
        (s) => s.name == data['state'],
        orElse: () => MediaItemState.done,
      ),
    );
  }
}

class MessageModel {
  final String id;
  final String senderId;
  final String recipientId;

  final String text;
  final Timestamp timestamp;
  final String? senderName;
  final bool isEdited;
  final bool isDeleted;
  String status; // 'sent', 'delivered', 'seen'
  final Map<String, String> reactions;

  /// Per-photo reactions for multi-image messages. Key = media index
  /// (as a string, e.g. '0', '1'), value = (uid -> emoji).
  final Map<String, Map<String, String>> imageReactions;
  final Map<String, dynamic>? repliedTo;

  final MessageType messageType;
  final List<String>? mediaUrls; // images / videos

  /// Per-item view of a photo / video batch, each with its own stable id and
  /// upload state. Preferred over the legacy parallel arrays ([mediaUrls],
  /// [videoDurations], [mediaPending]); see [resolvedMediaItems].
  final List<MediaItem>? mediaItems;

  /// How many media slots of a multi-item send are still uploading.
  ///
  /// Legacy counterpart of [MediaItem.state]; only set on documents written
  /// before [mediaItems] existed.
  final int? mediaPending;

  final int? voiceDuration; // seconds
  final int? videoDuration; // seconds
  final List<int?>? videoDurations;
  final String? thumbnailUrl; // future use (video)

  /// Original name of a sent file / audio (MessageType.file / audio).
  final String? fileName;

  /// Size of the sent file in bytes (MessageType.file / audio).
  final int? fileSize;

  /// 'voice' | 'video' — only for [MessageType.call] messages.
  final String? callType;

  /// 'completed' | 'missed' | 'declined' | 'cancelled' | 'busy' — only for
  /// [MessageType.call] messages.
  final String? callOutcome;

  /// Call duration in seconds — only for completed [MessageType.call]s.
  final int? callDuration;

  /// Uid of the user who placed the call (needed so both participants see the
  /// correct "You"/caller name from a single shared call-history message).
  final String? callerId;

  /// For group call history: how many group members were offline at call time
  /// (so the summary can mention them). Null for 1:1 calls.
  final int? offlineCount;

  /// Uids of the users who starred (favorited) this message.
  final List<String> starredBy;

  /// Uids of the users who deleted this message only from their own chat
  /// ("delete for me"). Unlike [isDeleted] (which hides it for everyone), this
  /// keeps the message intact for the other side.
  final List<String> deletedForMe;

  /// Whether swipe / long-press reply is allowed. Call-history notices
  /// (missed / completed / declined), live call cards, and system notices are
  /// not chat bubbles — they must not be reply targets.
  bool get canReply =>
      !isDeleted &&
      messageType != MessageType.system &&
      messageType != MessageType.call &&
      messageType != MessageType.callActive;

  MessageModel({
    required this.id,
    required this.senderId,
    required this.recipientId,
    required this.text,
    required this.timestamp,
    this.senderName,
    this.isEdited = false,
    this.isDeleted = false,
    this.status = 'sent',
    this.reactions = const {},
    this.imageReactions = const {},
    this.repliedTo,
    this.messageType = MessageType.text,
    this.mediaUrls,
    this.mediaItems,
    this.mediaPending,
    this.voiceDuration,
    this.videoDuration,
    this.videoDurations,
    this.thumbnailUrl,
    this.fileName,
    this.fileSize,
    this.callType,
    this.callOutcome,
    this.callDuration,
    this.callerId,
    this.offlineCount,
    this.starredBy = const [],
    this.deletedForMe = const [],
  });

  /// Parses the stored per-photo reactions (`mediaIndex -> (uid -> emoji)`)
  /// defensively — older messages don't have the field at all.
  static Map<String, Map<String, String>> _parseImageReactions(dynamic raw) {
    if (raw is! Map<String, dynamic> || raw.isEmpty) return {};
    final result = <String, Map<String, String>>{};
    raw.forEach((key, value) {
      if (value is Map) {
        result[key] = value.map((k, v) => MapEntry(k.toString(), v.toString()));
      }
    });
    return result;
  }

  /// The media tiles this message renders, whatever shape it was stored in.
  ///
  /// Documents written by the current send pipeline carry [mediaItems].
  /// Older ones only have the parallel [mediaUrls] / [videoDurations] /
  /// [mediaPending] arrays, so those are projected into items here — with
  /// synthetic ids so per-item reactions and replies still resolve.
  List<MediaItem> get resolvedMediaItems {
    final stored = mediaItems;
    if (stored != null && stored.isNotEmpty) return stored;

    final urls = mediaUrls ?? const <String>[];
    if (urls.isEmpty) {
      // No URL at all: the batch was still in flight (or fully failed) and
      // only the pending count survived.
      final pendingCount = mediaPending ?? 0;
      return [
        for (var i = 0; i < pendingCount; i++)
          MediaItem(id: '$i', state: MediaItemState.uploading),
      ];
    }

    return [
      for (var i = 0; i < urls.length; i++)
        MediaItem(
          // The plain index is deliberately the id here: older documents key
          // their per-photo reactions by `imageReactions.<index>`, so reusing
          // the index keeps reactions on existing messages working.
          id: '$i',
          url: urls[i],
          durationSeconds: videoDurationAt(i),
        ),
    ];
  }

  /// Total number of tiles the media grid renders, including pending ones.
  int get mediaSlotCount => resolvedMediaItems.length;

  /// Resolved id of the tile at [index], used to key per-item reactions.
  String mediaItemIdAt(int index) {
    final items = resolvedMediaItems;
    if (index < 0 || index >= items.length) return '';
    return items[index].id;
  }

  /// The tile with [id], or null when this message has no such item.
  MediaItem? itemById(String id) {
    for (final item in resolvedMediaItems) {
      if (item.id == id) return item;
    }
    return null;
  }

  int? videoDurationAt(int index) {
    if (mediaItems != null && index >= 0 && index < mediaItems!.length) {
      final itemDuration = mediaItems![index].durationSeconds;
      if (itemDuration != null && itemDuration > 0) return itemDuration;
    }
    if (index >= 0 &&
        videoDurations != null &&
        index < videoDurations!.length &&
        videoDurations![index] != null) {
      return videoDurations![index];
    }
    return index == 0 ? videoDuration : null;
  }

  factory MessageModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return MessageModel(
      id: doc.id,
      senderId: data['senderId'] ?? '',
      recipientId: data['recipientId'] ?? '',
      text: data['text'] ?? '',
      timestamp: data['timestamp'] ?? Timestamp.now(),
      senderName: data['senderName'] as String?,
      isEdited: data['isEdited'] ?? false,
      isDeleted: data['isDeleted'] ?? false,
      status: data['status'] ?? 'sent',
      reactions: Map<String, String>.from(data['reactions'] ?? {}),
      imageReactions: _parseImageReactions(data['imageReactions']),
      repliedTo: data['repliedTo'],
      messageType: MessageType.values.byName(
        data['messageType'] ?? 'text',
      ),
      mediaUrls: data['mediaUrls'] != null
          ? List<String>.from(data['mediaUrls'])
          : null,
      mediaItems: data['mediaItems'] is List
          ? (data['mediaItems'] as List)
              .asMap()
              .entries
              .map((e) => MediaItem.fromFirestore(e.value, 'slot_${e.key}'))
              .toList()
          : null,
      mediaPending: data['mediaPending'] is num
          ? (data['mediaPending'] as num).toInt()
          : null,
      voiceDuration: data['voiceDuration'],
      videoDuration: data['videoDuration'],
      videoDurations: data['videoDurations'] is List
          ? (data['videoDurations'] as List)
              .map((value) => value is num ? value.toInt() : null)
              .toList()
          : null,
      thumbnailUrl: data['thumbnailUrl'],
      fileName: data['fileName'],
      fileSize: data['fileSize'],
      callType: data['callType'],
      callOutcome: data['callOutcome'],
      callDuration: data['callDuration'],
      callerId: data['callerId'],
      offlineCount: data['offlineCount'],
      starredBy: List<String>.from(data['starredBy'] ?? const []),
      deletedForMe: List<String>.from(data['deletedForMe'] ?? const []),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'senderId': senderId,
      'recipientId': recipientId,
      'text': text,
      'timestamp': timestamp,
      'senderName': senderName,
      'isEdited': isEdited,
      'isDeleted': isDeleted,
      'status': status,
      'reactions': reactions,
      'imageReactions': imageReactions,
      if (repliedTo != null) 'repliedTo': repliedTo,
      'messageType': messageType.name,
      if (mediaUrls != null) 'mediaUrls': mediaUrls,
      if (mediaItems != null)
        'mediaItems': [
          for (final item in mediaItems!) item.toFirestore(),
        ],
      if (mediaPending != null && mediaPending! > 0)
        'mediaPending': mediaPending,
      if (voiceDuration != null) 'voiceDuration': voiceDuration,
      if (videoDuration != null) 'videoDuration': videoDuration,
      if (videoDurations != null) 'videoDurations': videoDurations,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
      if (fileName != null) 'fileName': fileName,
      if (fileSize != null) 'fileSize': fileSize,
      if (callType != null) 'callType': callType,
      if (callOutcome != null) 'callOutcome': callOutcome,
      if (callDuration != null) 'callDuration': callDuration,
      if (callerId != null) 'callerId': callerId,
      if (offlineCount != null) 'offlineCount': offlineCount,
      'starredBy': starredBy,
      'deletedForMe': deletedForMe,
    };
  }

  MessageModel copyWith({
    String? text,
    String? senderName,
    bool? isEdited,
    bool? isDeleted,
    String? status,
    Map<String, String>? reactions,
    Map<String, Map<String, String>>? imageReactions,
    Map<String, dynamic>? repliedTo,
    MessageType? messageType,
    List<String>? mediaUrls,
    List<MediaItem>? mediaItems,
    int? mediaPending,
    int? voiceDuration,
    int? videoDuration,
    List<int?>? videoDurations,
    String? thumbnailUrl,
    String? fileName,
    int? fileSize,
    String? callType,
    String? callOutcome,
    int? callDuration,
    String? callerId,
    int? offlineCount,
    List<String>? starredBy,
    List<String>? deletedForMe,
  }) {
    return MessageModel(
      id: id,
      senderId: senderId,
      recipientId: recipientId,
      text: text ?? this.text,
      timestamp: timestamp,
      senderName: senderName ?? this.senderName,
      isEdited: isEdited ?? this.isEdited,
      isDeleted: isDeleted ?? this.isDeleted,
      status: status ?? this.status,
      reactions: reactions ?? this.reactions,
      imageReactions: imageReactions ?? this.imageReactions,
      repliedTo: repliedTo ?? this.repliedTo,
      messageType: messageType ?? this.messageType,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      mediaItems: mediaItems ?? this.mediaItems,
      mediaPending: mediaPending ?? this.mediaPending,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      videoDuration: videoDuration ?? this.videoDuration,
      videoDurations: videoDurations ?? this.videoDurations,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
      fileName: fileName ?? this.fileName,
      fileSize: fileSize ?? this.fileSize,
      callType: callType ?? this.callType,
      callOutcome: callOutcome ?? this.callOutcome,
      callDuration: callDuration ?? this.callDuration,
      callerId: callerId ?? this.callerId,
      offlineCount: offlineCount ?? this.offlineCount,
      starredBy: starredBy ?? this.starredBy,
      deletedForMe: deletedForMe ?? this.deletedForMe,
    );
  }
}
