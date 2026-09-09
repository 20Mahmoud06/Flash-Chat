import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

import '../../models/group_model.dart';
import '../../models/user_model.dart';

String buildOneOnOneChatId(String uid1, String uid2) {
  final ids = [uid1, uid2]..sort();
  return "chat_${ids.join('_')}";
}

String buildChannelName({
  required bool isGroup,
  GroupModel? group,
  String? groupId,
  UserModel? contact,
  String? otherUid,
}) {
  if (isGroup) {
    final id = group?.id ?? groupId;
    if (id == null) throw Exception("Group ID required for group call");
    return "group_$id";
  } else {
    final peerId = contact?.uid ?? otherUid;
    if (peerId == null) throw Exception("Peer ID required for 1-1 call");
    final currentUserId = FirebaseAuth.instance.currentUser!.uid;
    return buildOneOnOneChatId(currentUserId, peerId);
  }
}

int agoraUidFromFirebase(String firebaseUid) {
  return firebaseUid.hashCode & 0x7fffffff;
}

/// Applies my own nickname for the caller to an incoming-call payload so the
/// call screens (voice/video) show the nickname I set instead of the caller's
/// real name. No-op for group calls and when no nickname is set.
Future<void> applyCallerNickname(Map<String, dynamic> payload) async {
  final isGroup =
      payload['isGroup'] == true || payload['isGroup'] == 'true';
  if (isGroup) return;

  final myUid = FirebaseAuth.instance.currentUser?.uid;
  final callerId = (payload['callerId'] ?? payload['contactUid'])?.toString();
  if (myUid == null || callerId == null || callerId.isEmpty) return;
  if (callerId == myUid) return;

  try {
    final doc = await FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .get();
    final nicknames = doc.data()?['nicknames'];
    if (nicknames is Map) {
      final nick = nicknames[callerId]?.toString();
      if (nick != null && nick.isNotEmpty) {
        payload['callerName'] = nick;
      }
    }
  } catch (e) {
    debugPrint('Error resolving caller nickname: $e');
  }
}

