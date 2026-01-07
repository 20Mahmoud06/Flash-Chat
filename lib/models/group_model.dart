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

  GroupModel({
    required this.id,
    required this.name,
    required this.avatarEmoji,
    required this.memberUids,
    required this.adminUids,
    required this.createdBy,
    required this.createdAt,
    this.bio,
  });

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
    );
  }
}