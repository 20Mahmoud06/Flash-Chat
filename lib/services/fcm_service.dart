import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications/src/platform_specifics/android/enums.dart' as notifEnums;
import '../core/routes/navigation_service.dart';
import '../core/routes/route_names.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import 'active_chat.dart';
import '../utils/callkit_helper.dart';
import 'call_service.dart';
import 'deep_link_service.dart';

class FcmService {
  final _fcm = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _local = FlutterLocalNotificationsPlugin();

  static const String channelId = 'flash_chat_custom_v10';
  static const String channelName = 'Flash Chat Messages';

  static const AndroidNotificationChannel chatChannel =
  AndroidNotificationChannel(
    channelId,
    channelName,
    description: 'Notifications for chat messages',
    importance: notifEnums.Importance.max,
    playSound: true,
    enableVibration: true,
  );

  // ---------------- INIT ----------------

  Future<void> initializeFCM() async {
    try {
      final settings = await _fcm.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );

      if (settings.authorizationStatus != AuthorizationStatus.authorized) return;

      await _initLocal();
      await _saveToken();
      await _setupListeners();
    } catch (e) {
      debugPrint('⚠️ FCM init failed (non-fatal): $e');
    }
  }

  Future<void> _initLocal() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: true,
      requestBadgePermission: true,
      requestSoundPermission: true,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );

    final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.requestNotificationsPermission();

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        if (response.actionId == 'REPLY') {
          final text = response.input;
          if (text != null && text.isNotEmpty && response.payload != null) {
            await _handleInlineReply(
              jsonDecode(response.payload!),
              text,
            );
          }
        } else if (response.payload != null) {
          _handleTap(jsonDecode(response.payload!));
        }
      },
    );

    const channel = AndroidNotificationChannel(
      channelId,
      channelName,
      description: 'Notifications for chat messages',
      importance: notifEnums.Importance.max,
      playSound: true,
      enableVibration: true,
    );

    await androidPlugin?.createNotificationChannel(channel);
  }

  Future<void> _saveToken() async {
    for (int i = 0; i < 3; i++) {
      try {
        final token = await _fcm.getToken();
        final uid = _auth.currentUser?.uid;

        if (token != null && uid != null) {
          await _firestore.collection('users').doc(uid).set({
            'fcmTokens': FieldValue.arrayUnion([token])
          }, SetOptions(merge: true));
        }
        break;
      }
      catch (e) {
        debugPrint('⚠️ FCM token not available yet: $e');
        await Future.delayed(Duration(seconds: 2));
      }
    }
  }


  // ---------------- LISTENERS ----------------

  Future<void> _setupListeners() async {
    await FirebaseMessaging.instance
        .setForegroundNotificationPresentationOptions(
      alert: false,
      badge: false,
      sound: false,
    );

    FirebaseMessaging.onMessage.listen((message) async {
      final data = message.data;

      if (data['type'] == 'call') {
        final callId = data['callId'];
        if (callId == null) return;

        final activeCalls = await FlutterCallkitIncoming.activeCalls();
        if (activeCalls.any((c) => c['id'] == callId)) return;

        final extra = <String, dynamic>{
          'callId': callId,
          'isVideo': data['isVideo'] == 'true',
          'callerId': data['callerId'],
          'callerName': data['callerName'],
          'isGroup': data['isGroup'] == 'true',
          if (data.containsKey('groupId')) 'groupId': data['groupId'],
          if (data.containsKey('groupName')) 'groupName': data['groupName'],
          if (data.containsKey('receiverId')) 'receiverId': data['receiverId'],
          if (data.containsKey('contactUid')) 'contactUid': data['contactUid'],
          if (data.containsKey('groupBio')) 'groupBio': data['groupBio'],
        };
        await showIncomingCall(
          callerName: data['callerName'] ?? 'Unknown',
          isVideo: data['isVideo'] == 'true',
          callId: callId,
          extra: extra,
        );
        CallService.addCallStatusListener(callId);
        return;
      }

      // 🔕 Ignore chat if already open (existing code)
      if (data['type'] == 'chat' && data['senderId'] == activeChatUserId) {
        return;
      }
      // 🔕 Ignore group chat if already open
      if (data['type'] == 'group_chat' && data['groupId'] == activeGroupId) {
        return;
      }

      // ✅ Only normal messages reach here
      _showNotification(message);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      _handleTap(message.data);
    });

    _fcm.getInitialMessage().then((message) {
      if (message != null) {
        _handleTap(message.data);
      }
    });
  }

  // ---------------- NOTIFICATION UI ----------------

  Future<void> _showNotification(RemoteMessage message) async {
    final data = message.data;

    final title = data['title'] ?? 'New message';
    final body = data['body'] ?? '';

    final androidDetails = AndroidNotificationDetails(
      chatChannel.id,
      chatChannel.name,
      channelDescription: chatChannel.description,
      importance: notifEnums.Importance.max,
      priority: notifEnums.Priority.high,
      icon: '@drawable/ic_notification',
      playSound: true,
      enableVibration: true,
      styleInformation: const DefaultStyleInformation(true, true),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(
        android: androidDetails,
        iOS: iosDetails,
      ),
      payload: jsonEncode(data),
    );
  }

  // ---------------- TAP HANDLING ----------------

  Future<void> _handleTap(Map<String, dynamic> data) async {
    debugPrint('📲 Notification tapped: ${data['type']}');

    if (_auth.currentUser == null) {
      debugPrint('❌ No user logged in');
      return;
    }

    if (data['type'] == 'call') {
      DeepLinkService().handleNotificationTap(data);
      return;
    }

    await _waitForNavigator();

    try {
      if (data['type'] == 'chat') {
        final senderId = data['senderId'];
        if (senderId == null) return;

        final doc = await _firestore.collection('users').doc(senderId).get();
        if (!doc.exists) return;

        SchedulerBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushNamedAndRemoveUntil(
            RouteNames.chatPage,
                (route) => route.isFirst,
            arguments: UserModel.fromFirestore(doc),
          );
        });
      }

      if (data['type'] == 'group_chat') {
        final groupId = data['groupId'];
        if (groupId == null) return;

        final doc = await _firestore.collection('groups').doc(groupId).get();
        if (!doc.exists) return;

        SchedulerBinding.instance.addPostFrameCallback((_) {
          navigatorKey.currentState?.pushNamedAndRemoveUntil(
            RouteNames.chatPage,
                (route) => route.isFirst,
            arguments: GroupModel.fromFirestore(doc),
          );
        });
      }
    } catch (e) {
      debugPrint('Navigation error: $e');
    }
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

  // ---------------- INLINE REPLY ----------------

  Future<void> _handleInlineReply(
      Map<String, dynamic> data,
      String text,
      ) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    if (data['type'] != 'chat') return;

    final senderId = data['senderId'];
    if (senderId == null) return;

    final chatId = _buildChatId(uid, senderId);

    await _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .add({
      'text': text,
      'senderId': uid,
      'recipientId': senderId,
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
    });
  }

  String _buildChatId(String a, String b) {
    final ids = [a, b]..sort();
    return ids.join('_');
  }
}