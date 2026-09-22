import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/routes/navigation_service.dart';
import '../core/routes/route_names.dart';
import '../core/utils/call_utils.dart';
import '../features/calls/models/call_arguments.dart';
import '../features/calls/services/call_service.dart';
import '../features/profile/models/user_model.dart';
import '../features/groups/models/group_model.dart';

class DeepLinkService {
  static final DeepLinkService _instance = DeepLinkService._internal();
  factory DeepLinkService() => _instance;
  DeepLinkService._internal();

  Map<String, dynamic>? _pendingData;
  bool _isNavReady = false;
  bool _isAuthReady = false;

  void setNavReady() {
    _isNavReady = true;
    _processPendingDeepLink();
  }

  void setAuthReady() {
    _isAuthReady = true;
    _processPendingDeepLink();
  }

  /// Clears any pending deep link and marks auth as not ready (user signed
  /// out or the session could not be restored), so a stale notification tap
  /// never navigates without a logged-in user.
  void setLoggedOut() {
    _pendingData = null;
    _isAuthReady = false;
    _isNavReady = false;
  }

  void handleNotificationTap(Map<String, dynamic> data) {
    debugPrint('🔗 Deep link received: $data');
    _pendingData = data;
    _processPendingDeepLink();
  }

  Future<void> _waitForNavigator() async {
    int attempts = 0;
    while (navigatorKey.currentState == null && attempts < 200) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
    }
    if (navigatorKey.currentState == null) {
      debugPrint('Navigator timed out for deep link');
    }
  }

  /// Reads a document from the server first so a notification tap always
  /// opens with the freshest data (e.g. a group I was just added to). Falls
  /// back to the on-device cache when offline so the tap still opens.
  Future<DocumentSnapshot<Map<String, dynamic>>> _freshServerDoc(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      return await ref.get(const GetOptions(source: Source.server));
    } catch (e) {
      debugPrint('🔗 Server read failed, falling back to cache: $e');
      return ref.get(const GetOptions(source: Source.cache));
    }
  }

  void _processPendingDeepLink() async {
    if (!_isNavReady || !_isAuthReady || _pendingData == null) {
      debugPrint('⏳ Waiting for dependencies: Nav: $_isNavReady, Auth: $_isAuthReady');
      return;
    }

    final data = _pendingData!;
    _pendingData = null;

    await _waitForNavigator();

    try {
      // 1. Handle Calls
      if (data['type'] == 'call') {
        await applyCallerNickname(data);
        final args = CallArguments.fromMap(data);
        // Register as a participant BEFORE navigating (the group "Join call"
        // card path already does this). A tap on a ring/notification that only
        // opens the call page — without joinCall — left the caller seeing an
        // unanswered ring and this device never appearing as in-call, so the
        // user had to fall back to opening the chat and tapping "Join call".
        final myUid = FirebaseAuth.instance.currentUser?.uid;
        if (myUid != null && data['callerId']?.toString() != myUid) {
          await CallService.joinCall(args.callId, myUid);
        }
        SchedulerBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushNamed(
            args.isVideo ? RouteNames.videoCallPage : RouteNames.voiceCallPage,
            arguments: args,
          );
        });
        return;
      }

      // 2. Handle Chats
      if (data['type'] == 'chat') {
        final senderId = data['senderId'];
        if (senderId != null) {
          final doc = await _freshServerDoc(
            FirebaseFirestore.instance.collection('users').doc(senderId),
          );
          if (doc.exists && doc.data() != null) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              navigatorKey.currentState?.pushNamedAndRemoveUntil(
                RouteNames.chatPage,
                (route) => route.isFirst,
                arguments: UserModel.fromFirestore(doc),
              );
            });
          }
        }
      }

      // 3. Handle Group Chats
      if (data['type'] == 'group_chat') {
        final groupId = data['groupId'];
        if (groupId != null) {
          final doc = await _freshServerDoc(
            FirebaseFirestore.instance.collection('groups').doc(groupId),
          );
          if (doc.exists && doc.data() != null) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              navigatorKey.currentState?.pushNamedAndRemoveUntil(
                RouteNames.chatPage,
                (route) => route.isFirst,
                arguments: GroupModel.fromFirestore(doc),
              );
            });
          }
        }
      }
    } catch (e) {
      debugPrint('❌ Navigation error: $e');
    }
  }
}