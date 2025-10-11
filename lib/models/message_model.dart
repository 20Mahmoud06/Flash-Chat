import 'package:cloud_firestore/cloud_firestore.dart';

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
  final Map<String, String> reactions; // { userId: emoji }
  final Map<String, dynamic>? repliedTo;

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
    };
  }

  // edit message with copyWith
  MessageModel copyWith({
    String? text,
    String? senderName,
    bool? isEdited,
    bool? isDeleted,
    String? status,
    Map<String, String>? reactions,
    Map<String, dynamic>? repliedTo,
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
    );
  }
}