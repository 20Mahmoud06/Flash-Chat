import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, video, voice, system, call, callActive }

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
  final int? voiceDuration; // seconds
  final int? videoDuration; // seconds
  final String? thumbnailUrl; // future use (video)

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
    this.voiceDuration,
    this.videoDuration,
    this.thumbnailUrl,
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
      voiceDuration: data['voiceDuration'],
      videoDuration: data['videoDuration'],
      thumbnailUrl: data['thumbnailUrl'],
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
      if (voiceDuration != null) 'voiceDuration': voiceDuration,
      if (videoDuration != null) 'videoDuration': videoDuration,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
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
    int? voiceDuration,
    int? videoDuration,
    String? thumbnailUrl,
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
      voiceDuration: voiceDuration ?? this.voiceDuration,
      videoDuration: videoDuration ?? this.videoDuration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
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
