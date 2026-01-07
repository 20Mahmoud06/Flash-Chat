import 'package:cloud_firestore/cloud_firestore.dart';

enum MessageType { text, image, video, voice }

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
  final Map<String, dynamic>? repliedTo;

  final MessageType messageType;
  final List<String>? mediaUrls; // images / videos
  final int? voiceDuration; // seconds
  final String? thumbnailUrl; // future use (video)

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
    this.repliedTo,

    this.messageType = MessageType.text,
    this.mediaUrls,
    this.voiceDuration,
    this.thumbnailUrl,
  });

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
      repliedTo: data['repliedTo'],

      messageType: MessageType.values.byName(
        data['messageType'] ?? 'text',
      ),
      mediaUrls: data['mediaUrls'] != null
          ? List<String>.from(data['mediaUrls'])
          : null,
      voiceDuration: data['voiceDuration'],
      thumbnailUrl: data['thumbnailUrl'],
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
      if (repliedTo != null) 'repliedTo': repliedTo,

      'messageType': messageType.name,
      if (mediaUrls != null) 'mediaUrls': mediaUrls,
      if (voiceDuration != null) 'voiceDuration': voiceDuration,
      if (thumbnailUrl != null) 'thumbnailUrl': thumbnailUrl,
    };
  }

  MessageModel copyWith({
    String? text,
    String? senderName,
    bool? isEdited,
    bool? isDeleted,
    String? status,
    Map<String, String>? reactions,
    Map<String, dynamic>? repliedTo,

    MessageType? messageType,
    List<String>? mediaUrls,
    int? voiceDuration,
    String? thumbnailUrl,
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
      repliedTo: repliedTo ?? this.repliedTo,

      messageType: messageType ?? this.messageType,
      mediaUrls: mediaUrls ?? this.mediaUrls,
      voiceDuration: voiceDuration ?? this.voiceDuration,
      thumbnailUrl: thumbnailUrl ?? this.thumbnailUrl,
    );
  }
}
