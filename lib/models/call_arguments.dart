import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/user_model.dart';

class CallArguments {
  final bool isGroup;
  final GroupModel? group;
  final UserModel? contact;
  final String callId;
  final bool isVideo;
  final String? callerId;
  final String? callerName;
  final String? groupName;

  CallArguments({
    required this.isGroup,
    this.group,
    this.contact,
    required this.callId,
    required this.isVideo,
    this.callerId,
    this.callerName,
    this.groupName,
  }) : assert(isGroup ? group != null || groupName != null : contact != null,
  'Must provide group or contact info');

  factory CallArguments.fromMap(Map<String, dynamic> map) {
    final isGroup = map['isGroup'] == true || map['isGroup'] == 'true';

    return CallArguments(
      isGroup: isGroup,
      group: isGroup && map['groupId'] != null
          ? GroupModel(
        id: map['groupId'],
        name: map['groupName'] ?? 'Group Call',
        avatarEmoji: map['groupAvatar'] ?? '👥',
        memberUids: [],
        adminUids: [],
        createdBy: '',
        createdAt: Timestamp.now(),
        bio: map['groupBio'],
      )
          : null,
      contact: !isGroup && (map['contactUid'] != null || map['callerId'] != null)
          ? UserModel(
        uid: map['contactUid'] ?? map['callerId'] ?? '',
        email: '',
        firstName: map['callerName']?.split(' ').first ?? '',
        lastName: map['callerName']?.split(' ').skip(1).join(' ') ?? '',
        phoneNumber: '',
        avatarEmoji: '👤',
      )
          : null,
      callId: map['callId'] ?? '',
      isVideo: map['isVideo'] == true || map['isVideo'] == 'true',
      callerId: map['callerId'],
      callerName: map['callerName'],
      groupName: map['groupName'],
    );
  }
}
