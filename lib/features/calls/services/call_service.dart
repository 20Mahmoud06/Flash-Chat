import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/cupertino.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import '../../../models/group_model.dart';
import '../../../models/user_model.dart';
import '../../../models/message_model.dart';
import '../../../core/utils/callkit_helper.dart';
import '../../../services/block/block_service.dart';
import '../../../services/fcm/fcm_v1_sender.dart';
import '../../../services/hms/hms_v1_sender.dart';
import '../../../services/presence/presence_service.dart';
import '../../../core/routes/navigation_service.dart';
import '../../../core/routes/route_names.dart';
import '../../../core/utils/call_utils.dart';
import '../../../models/call_arguments.dart';
import '../cubit/call_cubit.dart';

class CallService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static StreamSubscription? _callSub;

  /// Call ids whose "accepted" flow already ran in this process, so the
  /// CallKit event handler and the Firestore recovery path can't both
  /// navigate to the same call.
  static final Set<String> _handledAcceptedCallIds = {};

  static bool claimAcceptedCall(String callId) {
    if (_handledAcceptedCallIds.contains(callId)) return false;
    _handledAcceptedCallIds.add(callId);
    return true;
  }

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

          /// 🚫 Never show a call from/to a blocked user (1-to-1)
          if (!isGroup && data['callerId'] is String) {
            final callerId = data['callerId'] as String;
            if (await BlockService.isBlockedPair(callerId, user.uid)) {
              debugPrint('Blocking call from blocked user: $callerId');
              continue;
            }
          }

          /// Group: only members see it
          if (isGroup) {
            try {
              final groupDoc = await _firestore
                  .collection('groups')
                  .doc(data['groupId'])
                  .get();

              if (!groupDoc.exists ||
                  !(groupDoc.data()?['memberUids'] as List)
                      .contains(user.uid)) {
                continue;
              }
            } catch (e) {
              // Permission denied for non-members (Firestore rules) or any
              // other failure — never ring for groups the user is not in.
              debugPrint('Group membership check failed for $user.uid: $e');
              continue;
            }
          }

          /// 🛑 Prevent duplicate ringing (VERY IMPORTANT)
          final activeCalls = await FlutterCallkitIncoming.activeCalls();
          if (activeCalls.any((c) => c['id'] == data['callId'])) {
            continue;
          }

          /// 😴 Already on a call? Don't stack a second ring — mark this
          /// incoming call as "busy" instead (1:1 ends it; group members are
          /// recorded as busy while the group call keeps going).
          if (await isUserBusy(excludingCallId: data['callId'])) {
            debugPrint('Busy — declining incoming call: ${data['callId']}');
            final peerUid = user.uid;
            if (isGroup) {
              await markGroupMemberOutcome(
                callId: data['callId'],
                uid: peerUid,
                outcome: 'busy',
              );
            } else {
              await _firestore
                  .collection('calls')
                  .doc(data['callId'])
                  .update({'status': 'busy'});
            }
            continue;
          }

          final extra = Map<String, dynamic>.from(data)..remove('createdAt');
          extra['type'] = 'call';

          /// 🔥 SHOW CALLKIT — only while the app is interactive. When the
          /// phone is locked or the app is backgrounded, the native FCM/HMS
          /// service already posts its own full-screen ring; presenting here
          /// too would double-ring AND register the call in the platform's
          /// active-calls list, which later blocks new calls ("busy").
          if (_appIsInteractive) {
            await showIncomingCall(
              callerName: data['callerName'] ?? 'Unknown',
              isVideo: data['isVideo'] == true,
              callId: data['callId'],
              extra: extra,
              avatar: data['callerAvatar']?.toString(),
            );
            setRingCleanupTimer(data['callId']);
          }

          addCallStatusListener(data['callId']);
        }
      });

      // Cold-boot recovery: if the app was terminated when the receiver
      // accepted the call on the lock screen, the CallKit accept event can be
      // dropped before the engine attaches. Detect the accepted call in
      // Firestore and resume it (join + open the call page).
      _resumeAcceptedCall(user.uid);
    });
  }

  /// Finds a call that was accepted in the last couple of minutes but whose
  /// accept event was never handled (app was killed). Joins and opens it.
  ///
  /// Uses a single-field query (auto-indexed) and filters in Dart to avoid
  /// requiring new composite indexes in the Firestore console.
  ///
  /// Retries over a short window: on a cold boot the native accept decision is
  /// persisted by [CallDecisionReceiver], which first waits for the restored
  /// FirebaseAuth session (slowest cold starts take ~10s). A single
  /// post-auth query can therefore run before the write lands, so we re-check
  /// for up to ~25s.
  static Future<void> _resumeAcceptedCall(String uid) async {
    final deadline = DateTime.now().add(const Duration(seconds: 25));
    var attempt = 0;
    while (DateTime.now().isBefore(deadline) && attempt < 10) {
      try {
        if (await _resumeAcceptedCallOnce(uid)) return;
      } catch (e) {
        debugPrint('Accepted-call recovery retry failed: $e');
      }
      attempt++;
      if (attempt >= 10 || DateTime.now().isAfter(deadline)) return;
      await Future.delayed(const Duration(milliseconds: 2500));
    }
  }

  static Future<bool> _resumeAcceptedCallOnce(String uid) async {
    try {
      final recent = DateTime.now().subtract(const Duration(minutes: 3));
      final recentMs = recent.millisecondsSinceEpoch;

      final snapshot = await _firestore
          .collection('calls')
          .where('status', isEqualTo: 'accepted')
          .limit(30)
          .get();

      for (final doc in snapshot.docs) {
        final data = doc.data();
        if (data['callerId'] == uid) continue;
        if (data['isGroup'] != true && data['receiverId'] != uid) continue;

        final createdAt = data['createdAt'];
        if (createdAt is! Timestamp ||
            createdAt.toDate().millisecondsSinceEpoch < recentMs) {
          continue;
        }

        if (data['isGroup'] == true &&
            !await _isGroupMember(data['groupId'], uid)) {
          continue;
        }

        final payload = Map<String, dynamic>.from(data);
        payload['callId'] = doc.id;
        if (await _navigateToAcceptedCall(payload, uid)) {
          return true;
        }
        // Already claimed/handled by the event channel — keep scanning (an
        // older accepted call must not stop us from picking up a newer one).
      }
    } catch (e) {
      debugPrint('Accepted-call recovery failed: $e');
    }
    return false;
  }

  static Future<bool> _isGroupMember(String? groupId, String uid) async {
    if (groupId == null) return false;
    try {
      final doc = await _firestore.collection('groups').doc(groupId).get();
      return doc.exists && (doc.data()?['memberUids'] as List).contains(uid);
    } catch (_) {
      return false;
    }
  }

  static Future<bool> _navigateToAcceptedCall(
    Map<String, dynamic> data,
    String uid,
  ) async {
    final callId = data['callId'];
    if (callId == null) return false;
    if (!claimAcceptedCall(callId)) return false;

    await joinCall(callId, uid);

    await _waitForNavigator();
    await applyCallerNickname(data);
    final args = CallArguments.fromMap(data);
    final routeName =
        args.isVideo ? RouteNames.videoCallPage : RouteNames.voiceCallPage;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      navigatorKey.currentState?.pushNamed(routeName, arguments: args);
    });
    debugPrint('Resumed accepted call: $callId');
    return true;
  }

  static Future<void> _waitForNavigator() async {
    int attempts = 0;
    while (navigatorKey.currentState == null && attempts < 200) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
    if (navigatorKey.currentState == null) {
      debugPrint('Navigator timed out for accepted-call recovery');
    }
  }

  static final Map<String, StreamSubscription> _activeCallListeners = {};

  /// True while the Flutter UI is on screen and interactive. When it is
  /// paused/hidden (phone locked, app backgrounded) incoming-call rings are
  /// owned by the native FCM/HMS full-screen-intent service.
  static bool get _appIsInteractive {
    try {
      return WidgetsBinding.instance.lifecycleState ==
          AppLifecycleState.resumed;
    } catch (_) {
      return true;
    }
  }

  /// Call statuses after which a presented incoming ring must be torn down
  /// in the native layer (stop the ringtone, clear the notification, drop the
  /// call from the platform active-calls list). Anything outside this set is
  /// an intermediate/active status (initiating / ringing / accepted).
  static const Set<String> _terminalCallStatuses = {
    'ended', 'cancelled',
    'declined', 'rejected',
    'busy',
    'timeout', 'no_answer',
    'unavailable', 'offline',
    'failed',
  };

  static void addCallStatusListener(String callId) {
    if (_activeCallListeners.containsKey(callId)) return;

    _activeCallListeners[callId] = _firestore
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) async {
      final data = snapshot.data();
      final status = data?['status'] as String?;
      // Tear the ring down on ANY terminal status, not just ended/cancelled:
      // a call that resolved to no_answer/timeout/busy/declined on the side of
      // the other participant used to leave its id in the platform
      // active-calls list forever, making every later incoming call be
      // declined as "busy" (the list "any other ring = busy" check).
      if (status != null && _terminalCallStatuses.contains(status)) {
        await FlutterCallkitIncoming.endCall(callId);
        _activeCallListeners[callId]?.cancel();
        _activeCallListeners.remove(callId);
        _ringCleanupTimers.remove(callId)?.cancel();
      }
    });
  }

  static void removeCallStatusListener(String callId) {
    _activeCallListeners[callId]?.cancel();
    _activeCallListeners.remove(callId);
  }

  /// Ring-timeout safety net for calls PRESENTED on this device. A ring that
  /// never resolves to a terminal status (orphaned doc, dropped platform
  /// timeout callback, killed caller) is force-dismissed after the ring window
  /// so the device never stays stuck "busy" for later calls.
  static final Map<String, Timer> _ringCleanupTimers = {};

  static void setRingCleanupTimer(String callId) {
    _ringCleanupTimers.remove(callId)?.cancel();
    _ringCleanupTimers[callId] =
        Timer(CallCubit.ringTimeout + const Duration(seconds: 15), () async {
      _ringCleanupTimers.remove(callId);
      try {
        final doc = await _firestore.collection('calls').doc(callId).get();
        final status = (doc.data()?['status'] as String?) ?? 'ended';
        if (status != 'accepted' &&
            !_terminalCallStatuses.contains(status)) {
          // Still ringing (or orphaned) after the ring window: dismiss it
          // locally so nothing lingers in the platform active-calls list.
          await FlutterCallkitIncoming.endCall(callId);
        }
      } catch (_) {
        await FlutterCallkitIncoming.endCall(callId);
      }
      removeCallStatusListener(callId);
    });
  }

  static void cancelRingCleanupTimer(String callId) {
    _ringCleanupTimers.remove(callId)?.cancel();
  }

  // ===============================
  // 📞 START CALL
  // ===============================

  static Future<String> startCall({
    required UserModel? receiver,
    required GroupModel? group,
    required bool isVideo,
    required String channelName,
  }) async {
    final caller = _auth.currentUser!;
    final isGroupCall = group != null;

    /// 🚫 Blocked users cannot be called (1-to-1 only).
    if (!isGroupCall && receiver != null) {
      // Check if the account is deleted
      if (receiver.isDeleted) {
        throw CallBlockedException(
            isVideo ? 'This user has deleted their account.' : 'This user has deleted their account.');
      }

      if (await BlockService.isBlockedPair(caller.uid, receiver.uid)) {
        throw CallBlockedException(
            isVideo ? 'You cannot video call this user.' : 'You cannot call this user.');
      }
    }

    final callDoc = _firestore.collection('calls').doc();
    final callId = callDoc.id;

    final callerDoc =
    await _firestore.collection('users').doc(caller.uid).get();

    final callerName = callerDoc.data() != null
        ? '${callerDoc['firstName']} ${callerDoc['lastName']}'
        : 'Unknown Caller';
    final callerAvatar = callerDoc.data()?['avatarEmoji'] ?? '👤';
    final receiverAvatar = receiver?.avatarEmoji ?? '👤';

    await callDoc.set({
      'callId': callId,
      'callerId': caller.uid,
      'callerName': callerName,
      'callerAvatar': callerAvatar,
      'isVideo': isVideo,
      'isGroup': isGroupCall,
      'channelName': channelName,
      'status': 'ringing',
      'createdAt': FieldValue.serverTimestamp(),
      'participants': [caller.uid],

      if (!isGroupCall) 'receiverId': receiver!.uid,
      if (!isGroupCall) 'receiverAvatar': receiverAvatar,
      if (isGroupCall) 'groupId': group.id,
      if (isGroupCall) 'groupName': group.name,
      if (isGroupCall) 'groupAvatar': group.avatarEmoji,
      if (isGroupCall) 'groupBio': group.bio,
    });

    if (!isGroupCall) {
      // 1-to-1 call: push to the receiver's FCM + HMS tokens. The call
      // document is already ringing in Firestore, so a failure on one
      // transport (dead/stale token, sender unconfigured) must never abort the
      // other — the native ring depends on whichever push actually lands.
      try {
        final fcmSender = await FcmV1Sender.getInstance();
        final receiverDoc =
        await _firestore.collection('users').doc(receiver!.uid).get();

        final List tokens =
        List.from(receiverDoc.data()?['fcmTokens'] ?? []);
        final List hmsTokens = List.from(receiverDoc.data()?['hmsTokens'] ?? []);

        for (final token in tokens) {
          try {
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
                'callerAvatar': callerAvatar,
                'isGroup': 'false',
                'receiverId': receiver.uid,
                'receiverAvatar': receiverAvatar,
              },
              receiverId: receiver.uid,
            );
          } catch (e) {
            debugPrint('FCM call push failed for a token: $e');
          }
        }

        // HMS devices (no GMS): HmsMessageService launches the native CallKit
        // incoming-call screen for call-type payloads.
        await HmsV1Sender.sendToTokens(
          tokens: hmsTokens.cast<String>(),
          title: isVideo ? 'Incoming Video Call' : 'Incoming Voice Call',
          body: '$callerName is calling you',
          chatType: 'call',
          targetId: callId,
          extraData: {
            'callId': callId,
            'isVideo': isVideo.toString(),
            'callerId': caller.uid,
            'callerName': callerName,
            'callerAvatar': callerAvatar,
            'isGroup': 'false',
            'receiverId': receiver.uid,
            'receiverAvatar': receiverAvatar,
          },
          receiverId: receiver.uid,
        );
      } catch (e) {
        debugPrint('1-to-1 call push loop failed: $e');
      }
    } else {
      // Group call FCM to all members except caller
      final groupDoc = await _firestore.collection('groups').doc(group.id).get();
      final memberUids = List<String>.from(groupDoc['memberUids'] ?? []);

      // Mark members who are currently offline as "offline" on the call doc so
      // the group call history can show how many members never saw the call.
      final offlineUids = await _offlineGroupMembers(memberUids, caller.uid);
      if (offlineUids.isNotEmpty) {
        final updates = <String, dynamic>{};
        for (final uid in offlineUids) {
          updates['participantStatus.$uid'] = 'offline';
        }
        try {
          await _firestore.collection('calls').doc(callId).update(updates);
        } catch (e) {
          debugPrint('Failed to mark offline group members: $e');
        }
      }

      // Write a WhatsApp-style "Join call" card into the group chat so any
      // member who opens the chat late sees the in-progress call and can tap
      // to join. Deleted when the call ends (see CallCubit.endCall).
      try {
        await _firestore.collection('groups').doc(group.id).collection('messages').add({
          'senderId': caller.uid,
          'senderName': callerName,
          'recipientId': '',
          'text': callId,
          'timestamp': FieldValue.serverTimestamp(),
          'status': 'sent',
          'reactions': {},
          'isDeleted': false,
          'isEdited': false,
          'messageType': MessageType.callActive.name,
          'callType': isVideo ? 'video' : 'voice',
          'callerId': caller.uid,
        });
      } catch (e) {
        debugPrint('Failed to write active call message: $e');
      }

      // Push notifications to members in the background: the call document
      // and Join-call card are already persisted above, so the caller must
      // navigate to the call page right away instead of waiting for every
      // member's FCM/HMS push to be delivered (which made starting a group
      // call feel slow). Failures are swallowed per member.
      unawaited(() async {
        final fcmSender = await FcmV1Sender.getInstance();
        for (final memberUid in memberUids) {
          if (memberUid == caller.uid) continue;

          try {
            final memberDoc = await _firestore.collection('users').doc(memberUid).get();
            final memberData = memberDoc.data();
            final tokens = List.from(memberData?['fcmTokens'] ?? []);
            final hmsTokens = List.from(memberData?['hmsTokens'] ?? []);

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

            await HmsV1Sender.sendToTokens(
              tokens: hmsTokens.cast<String>(),
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
          } catch (e) {
            debugPrint('Failed to notify group call member $memberUid: $e');
          }
        }
      }());
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

  /// Whether the current device is already in an active call, so a new
  /// incoming call should be declined as "busy" rather than stacked as a
  /// second ring.
  ///
  /// This only applies while the app is running (foreground or backgrounded
  /// with a live engine). When the app is killed there is no ongoing call, so
  /// the native service simply rings.
  static Future<bool> isUserBusy({String? excludingCallId}) async {
    if (CallCubit.instance.isCallActive) return true;

    // Fall back to platform-level active calls (e.g. recovered on cold start).
    // Only calls that were actually ACCEPTED (a real ongoing conversation)
    // make the device busy. Presented-but-unanswered rings — including ids
    // leftover from calls that ended while the app was in the background —
    // must never block a new call, or the receiver would be auto-declined as
    // "busy" for every future call.
    try {
      final active = await FlutterCallkitIncoming.activeCalls();
      return active.any((c) =>
          c['id'] != excludingCallId && c['isAccepted'] == true);
    } catch (_) {
      return false;
    }
  }

  /// Records a single group member's outcome on the `calls` doc without
  /// ending the group call for everyone else (the caller ends it explicitly).
  static Future<void> markGroupMemberOutcome({
    required String callId,
    required String uid,
    required String outcome,
  }) async {
    try {
      await _firestore.collection('calls').doc(callId).update({
        'participantStatus.$uid': outcome,
      });
    } catch (e) {
      debugPrint('markGroupMemberOutcome($outcome) for $uid failed: $e');
    }
  }

  /// Returns the subset of [memberUids] (excluding [callerUid]) that is
  /// currently offline, used to annotate group calls with who couldn't join.
  static Future<List<String>> _offlineGroupMembers(
    List<String> memberUids,
    String callerUid,
  ) async {
    final targets = memberUids.where((u) => u != callerUid).toList();
    final offline = <String>[];
    await Future.wait(targets.map((uid) async {
      try {
        if (await PresenceService.instance.isOffline(uid)) offline.add(uid);
      } catch (e) {
        debugPrint('Offline check for $uid failed: $e');
      }
    }));
    return offline;
  }

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
