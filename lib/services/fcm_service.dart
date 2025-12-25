import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart'; // Add this import for addPostFrameCallback
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications/src/platform_specifics/android/enums.dart' as notifEnums; // New import for alias
import '../core/routes/navigation_service.dart';
import '../core/routes/route_names.dart';
import '../models/user_model.dart';
import '../models/group_model.dart';
import 'active_chat.dart';

class FcmService {
  final _fcm = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _local = FlutterLocalNotificationsPlugin();

  static const String channelId = 'flash_chat_custom_v1';
  static const String channelName = 'Flash Chat Messages';
  static const String soundFileName = 'alert';

  static const AndroidNotificationChannel chatChannel =
  AndroidNotificationChannel(
    channelId,
    channelName,
    importance: notifEnums.Importance.max, // Use alias
    playSound: true,
  );

  // ---------------- INIT ----------------

  Future<void> initializeFCM() async {
    final settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );

    if (settings.authorizationStatus != AuthorizationStatus.authorized) return;

    await _initLocal();
    await _saveToken();
    await _setupListeners();
  }

  Future<void> _initLocal() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings();
    const initSettings =
    InitializationSettings(android: androidInit, iOS: darwinInit);

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        if (response.actionId == 'REPLY') {
          final text = response.input;
          if (text != null &&
              text.isNotEmpty &&
              response.payload != null) {
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

    final androidPlugin =
    _local.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();

    await androidPlugin?.createNotificationChannel(chatChannel);
  }

  Future<void> _saveToken() async {
    final token = await _fcm.getToken();
    final uid = _auth.currentUser?.uid;
    if (token != null && uid != null) {
      await _firestore.collection('users').doc(uid).set({
        'fcmTokens': FieldValue.arrayUnion([token])
      }, SetOptions(merge: true));
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

    FirebaseMessaging.onMessage.listen((message) {
      final data = message.data;
      if (data['type'] == 'chat' &&
          data['senderId'] == activeChatUserId) return;
      if (data['type'] == 'group_chat' &&
          data['groupId'] == activeGroupId) return;
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
      importance: notifEnums.Importance.max, // Use alias
      priority: notifEnums.Priority.high, // Use alias
      icon: '@drawable/ic_notification',

      // 🚨 DO NOT use BigTextStyle on MIUI
      styleInformation: DefaultStyleInformation(true, true),
    );

    await _local.show(
      DateTime.now().millisecondsSinceEpoch ~/ 1000,
      title,
      body,
      NotificationDetails(android: androidDetails),
      payload: jsonEncode(data),
    );
  }

  // ---------------- TAP HANDLING ----------------

  Future<void> _handleTap(Map<String, dynamic> data) async {
    await _waitForNavigator();

    if (_auth.currentUser == null) return;

    try {
      // Fetch doc asynchronously, then navigate in post-frame callback
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
    while (navigatorKey.currentState == null && attempts < 50) {
      await Future.delayed(const Duration(milliseconds: 100));
      attempts++;
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