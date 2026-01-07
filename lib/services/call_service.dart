import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../models/group_model.dart';
import '../models/user_model.dart';
import '../utils/callkit_helper.dart';
import 'fcm_v1_sender.dart';

class CallService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static StreamSubscription? _callSub;
  static final Map<String, StreamSubscription> _callStatusSubs = {};

  // ===============================
  // 🔔 INCOMING CALL LISTENER
  // ===============================
  static void listenForIncomingCalls() {

    _auth.authStateChanges().listen((user) {
      if (user == null) return;

      _callSub?.cancel();

      _callSub = _firestore
          .collection('calls')
          .where('status', isEqualTo: 'ringing')
          .snapshots()
          .listen((snapshot) async {

        for (final change in snapshot.docChanges) {
          if (change.type != DocumentChangeType.added) continue;

          final data = change.doc.data();
          if (data == null) continue;

          /// ❌ NEVER show CallKit for your own call
          if (data['callerId'] == user.uid) continue;

          final isGroup = data['isGroup'] == true;

          /// 1-to-1: only receiver sees it
          if (!isGroup && data['receiverId'] != user.uid) continue;

          /// Group: only members see it
          if (isGroup) {
            final groupDoc = await _firestore
                .collection('groups')
                .doc(data['groupId'])
                .get();

            if (!groupDoc.exists ||
                !(groupDoc.data()?['memberUids'] as List)
                    .contains(user.uid)) {
              continue;
            }
          }

          /// 🛑 Prevent duplicate ringing (VERY IMPORTANT)
          final activeCalls = await FlutterCallkitIncoming.activeCalls();
          if (activeCalls.any((c) => c['id'] == data['callId'])) {
            continue;
          }

          final extra = Map<String, dynamic>.from(data)..remove('createdAt');
          extra['type'] = 'call';

          /// 🔥 SHOW CALLKIT (ONLY HERE)
          await showIncomingCall(
            callerName: data['callerName'] ?? 'Unknown',
            isVideo: data['isVideo'] == true,
            callId: data['callId'],
            extra: extra,
          );

          addCallStatusListener(data['callId']);
        }
      });
    });
  }

  static final Map<String, StreamSubscription> _activeCallListeners = {};

  static void addCallStatusListener(String callId) {
    if (_activeCallListeners.containsKey(callId)) return;

    _activeCallListeners[callId] = _firestore
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) async {
      final data = snapshot.data();
      if (data != null && data['status'] == 'ended') {
        await FlutterCallkitIncoming.endCall(callId);
        _activeCallListeners[callId]?.cancel();
        _activeCallListeners.remove(callId);
      }
    });
  }

  static void removeCallStatusListener(String callId) {
    _activeCallListeners[callId]?.cancel();
    _activeCallListeners.remove(callId);
  }

  // ===============================
  // 📞 START CALL (THIS WAS MISSING)
  // ===============================

  static Future<String> startCall({
    required UserModel? receiver,
    required GroupModel? group,
    required bool isVideo,
    required String channelName,
  }) async {
    final caller = _auth.currentUser!;
    final isGroupCall = group != null;

    final callDoc = _firestore.collection('calls').doc();
    final callId = callDoc.id;

    final callerDoc =
    await _firestore.collection('users').doc(caller.uid).get();

    final callerName = callerDoc.data() != null
        ? '${callerDoc['firstName']} ${callerDoc['lastName']}'
        : 'Unknown Caller';

    await callDoc.set({
      'callId': callId,
      'callerId': caller.uid,
      'callerName': callerName,
      'isVideo': isVideo,
      'isGroup': isGroupCall,
      'channelName': channelName,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
      'participants': [caller.uid],

      if (!isGroupCall) 'receiverId': receiver!.uid,
      if (isGroupCall) 'groupId': group!.id,
      if (isGroupCall) 'groupName': group.name,
      if (isGroupCall) 'groupAvatar': group.avatarEmoji,
      if (isGroupCall) 'groupBio': group.bio,
    });

    final fcmSender = await FcmV1Sender.getInstance();

    if (!isGroupCall) {
      // 1-to-1 call FCM
      final receiverDoc =
      await _firestore.collection('users').doc(receiver!.uid).get();

      final List tokens =
      List.from(receiverDoc.data()?['fcmTokens'] ?? []);

      for (final token in tokens) {
        await fcmSender.sendMessageToToken(
          token: token,
          title: isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
          body: '$callerName is calling you',
          chatType: 'call',
          targetId: callId,
          extraData: {
            'callId': callId,
            'isVideo': isVideo.toString(),
            'callerId': caller.uid,
            'callerName': callerName,
            'isGroup': 'false',
            'receiverId': receiver.uid,
          },
          receiverId: receiver.uid,
        );
      }
    } else {
      // Group call FCM to all members except caller
      final groupDoc = await _firestore.collection('groups').doc(group!.id).get();
      final memberUids = List<String>.from(groupDoc['memberUids'] ?? []);

      for (final memberUid in memberUids) {
        if (memberUid == caller.uid) continue;

        final memberDoc = await _firestore.collection('users').doc(memberUid).get();
        final tokens = List<String>.from(memberDoc['fcmTokens'] ?? []);

        for (final token in tokens) {
          await fcmSender.sendMessageToToken(
            token: token,
            title: isVideo ? 'Incoming Group Video Call' : 'Incoming Group Voice Call',
            body: '$callerName started a call in ${group.name}',
            chatType: 'call',
            targetId: callId,
            extraData: {
              'callId': callId,
              'isVideo': isVideo.toString(),
              'callerId': caller.uid,
              'callerName': callerName,
              'isGroup': 'true',
              'groupId': group.id,
              'groupName': group.name,
            },
            receiverId: memberUid,
          );
        }
      }
    }

    return callId;
  }

  static Future<String?> getActiveCallId(String channelName, bool isVideo) async {
    final query = _firestore.collection('calls')
        .where('channelName', isEqualTo: channelName)
        .where('isVideo', isEqualTo: isVideo)
        .where('status', whereIn: ['ringing', 'accepted'])
        .orderBy('createdAt', descending: true)
        .limit(1);

    final snap = await query.get();
    if (snap.docs.isNotEmpty) {
      debugPrint('Existing call found: ${snap.docs.first.id}');
      return snap.docs.first.id;
    }
    return null;
  }

  // ===============================
  // 🔄 CALL STATE
  // ===============================
  static Future<void> updateCallStatus(
      String callId,
      String status,
      ) async {
    await _firestore.collection('calls').doc(callId).update({
      'status': status,
    });

    if (status == 'ended') {
      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls.any((c) => c['id'] == callId)) {
        await FlutterCallkitIncoming.endCall(callId);
      }
    }

  }

  static Future<void> joinCall(String callId, String userId) async {
    await _firestore.collection('calls').doc(callId).update({
      'participants': FieldValue.arrayUnion([userId]),
    });
    debugPrint('Joined call: $callId as $userId');
  }

}