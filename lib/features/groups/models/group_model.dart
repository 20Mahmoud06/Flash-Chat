import 'package:cloud_firestore/cloud_firestore.dart';

class GroupModel {
  final String id;
  final String name;
  final String avatarEmoji;
  final List<String> memberUids;
  final List<String> adminUids;
  final String createdBy;
  final Timestamp createdAt;
  final String? bio;

  /// True once the creator deletes the whole group. The group and its
  /// messages stay in place so every member keeps read access to the history,
  /// but the chat becomes read-only: no sending, calling, or reacting.
  final bool isDeleted;
  final Map<String, Timestamp> memberJoinTimestamps;

  /// uid -> timestamp when the member left the group or was removed by an
  /// admin. Kept even after removal so a removed/left member can still read
  /// the messages that were sent during their membership, but nothing newer.
  final Map<String, Timestamp> memberLeaveTimestamps;

  GroupModel({
    required this.id,
    required this.name,
    required this.avatarEmoji,
    required this.memberUids,
    required this.adminUids,
    required this.createdBy,
    required this.createdAt,
    this.bio,
    this.isDeleted = false,
    Map<String, Timestamp>? memberJoinTimestamps,
    Map<String, Timestamp>? memberLeaveTimestamps,
  })  : memberJoinTimestamps = memberJoinTimestamps ?? {},
        memberLeaveTimestamps = memberLeaveTimestamps ?? {};

  factory GroupModel.fromFirestore(DocumentSnapshot doc) {
    Map<String, dynamic> data = doc.data() as Map<String, dynamic>;
    return GroupModel(
      id: doc.id,
      name: data['name'] ?? 'New Group',
      avatarEmoji: data['avatarEmoji'] ?? '👥',
      memberUids: List<String>.from(data['memberUids'] ?? []),
      adminUids: List<String>.from(data['adminUids'] ?? []),
      createdBy: data['createdBy'] ?? '',
      createdAt: data['createdAt'] ?? Timestamp.now(),
      bio: data['bio'],
      isDeleted: data['isDeleted'] == true,
      memberJoinTimestamps: data['memberJoinTimestamps'] != null
          ? Map<String, Timestamp>.from(data['memberJoinTimestamps'])
          : {},
      memberLeaveTimestamps: data['memberLeaveTimestamps'] != null
          ? Map<String, Timestamp>.from(data['memberLeaveTimestamps'])
          : {},
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'name': name,
      'avatarEmoji': avatarEmoji,
      'memberUids': memberUids,
      'adminUids': adminUids,
      'createdBy': createdBy,
      'createdAt': createdAt,
      if (bio != null) 'bio': bio,
      'isDeleted': isDeleted,
      'memberJoinTimestamps': memberJoinTimestamps,
      'memberLeaveTimestamps': memberLeaveTimestamps,
    };
  }

  GroupModel copyWith({
    String? id,
    String? name,
    String? avatarEmoji,
    List<String>? memberUids,
    List<String>? adminUids,
    String? createdBy,
    Timestamp? createdAt,
    String? bio,
    bool? isDeleted,
    Map<String, Timestamp>? memberJoinTimestamps,
    Map<String, Timestamp>? memberLeaveTimestamps,
  }) {
    return GroupModel(
      id: id ?? this.id,
      name: name ?? this.name,
      avatarEmoji: avatarEmoji ?? this.avatarEmoji,
      memberUids: memberUids ?? this.memberUids,
      adminUids: adminUids ?? this.adminUids,
      createdBy: createdBy ?? this.createdBy,
      createdAt: createdAt ?? this.createdAt,
      bio: bio ?? this.bio,
      isDeleted: isDeleted ?? this.isDeleted,
      memberJoinTimestamps: memberJoinTimestamps ?? this.memberJoinTimestamps,
      memberLeaveTimestamps: memberLeaveTimestamps ?? this.memberLeaveTimestamps,
    );
  }
}