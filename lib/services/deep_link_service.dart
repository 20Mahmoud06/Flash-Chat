import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import '../core/routes/navigation_service.dart';
import '../core/routes/route_names.dart';
import '../models/call_arguments.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';

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
        final args = CallArguments.fromMap(data);
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
          final doc = await FirebaseFirestore.instance.collection('users').doc(senderId).get();
          if (doc.exists) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              navigatorKey.currentState?.pushNamed(
                RouteNames.chatPage,
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
          final doc = await FirebaseFirestore.instance.collection('groups').doc(groupId).get();
          if (doc.exists) {
            SchedulerBinding.instance.addPostFrameCallback((_) {
              navigatorKey.currentState?.pushNamed(
                RouteNames.chatPage,
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