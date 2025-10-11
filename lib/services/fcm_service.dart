import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flash_chat_app/core/routes/navigation_service.dart';
import 'package:flash_chat_app/core/routes/route_names.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:googleapis_auth/auth_io.dart' as auth;

@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  debugPrint("Handling a background message: ${message.messageId}");
}

class FcmService {
  final _fcm = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  final _local = FlutterLocalNotificationsPlugin();

  Future<void> initializeFCM() async {
    // 1. Permissions
    NotificationSettings settings = await _fcm.requestPermission(
      alert: true,
      badge: true,
      sound: true,
    );
    if (settings.authorizationStatus == AuthorizationStatus.authorized) {
      debugPrint('✅ User granted notification permission');
    }

    // 2. Background handler
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

    // 3. Get token + save to Firestore
    await _getTokenAndSave();

    // 4. Local notifications init
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const initSettings = InitializationSettings(android: androidInit);
    await _local.initialize(initSettings,
        onDidReceiveNotificationResponse: (resp) {
          if (resp.payload != null) {
            final data = jsonDecode(resp.payload!);
            _handleNotificationTap(data);
          }
        });

    _setupInteractions();
  }

  Future<void> _getTokenAndSave() async {
    final token = await _fcm.getToken();
    debugPrint("📲 FCM Token: $token");
    final uid = _auth.currentUser?.uid;
    if (token != null && uid != null) {
      final userRef = _firestore.collection('users').doc(uid);
      await userRef.set({
        'fcmTokens': FieldValue.arrayUnion([token])
      }, SetOptions(merge: true));
    }
  }

  void _setupInteractions() {
    // Foreground
    FirebaseMessaging.onMessage.listen((RemoteMessage message) {
      debugPrint('📩 Foreground message: ${message.data}');
      _showNotification(message);
    });

    // Background
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      debugPrint('📩 App opened from background: ${message.data}');
      _handleNotificationTap(message.data);
    });

    // Terminated
    _fcm.getInitialMessage().then((RemoteMessage? message) {
      if (message != null) {
        debugPrint('📩 App opened from terminated: ${message.data}');
        _handleNotificationTap(message.data);
      }
    });
  }

  void _showNotification(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;

    const details = NotificationDetails(
      android: AndroidNotificationDetails(
        'chat_channel',
        'Chat Messages',
        importance: Importance.max,
        priority: Priority.high,
      ),
    );

    await _local.show(
      notification.hashCode,
      notification.title,
      notification.body,
      details,
      payload: jsonEncode(message.data),
    );
  }

  void _handleNotificationTap(Map<String, dynamic> data) async {
    final type = data['type'] as String?;
    if (_auth.currentUser == null) return;

    try {
      if (type == 'chat' && data['senderId'] != null) {
        final senderId = data['senderId'] as String;
        final doc = await _firestore.collection('users').doc(senderId).get();
        if (doc.exists) {
          final sender = UserModel.fromFirestore(doc);
          navigatorKey.currentState
              ?.pushNamed(RouteNames.chatPage, arguments: sender);
        }
      } else if (type == 'group_chat' && data['groupId'] != null) {
        final groupId = data['groupId'] as String;
        final doc = await _firestore.collection('groups').doc(groupId).get();
        if (doc.exists) {
          final group = GroupModel.fromFirestore(doc);
          navigatorKey.currentState
              ?.pushNamed(RouteNames.chatPage, arguments: group);
        }
      }
    } catch (e) {
      debugPrint('❌ Deep link error: $e');
    }
  }

  Future<void> sendPushMessageV1({
    required String token,
    required String title,
    required String body,
    required Map<String, dynamic> data,
  }) async {
    try {
      final jsonStr =
      await rootBundle.loadString('assets/service_account.json');
      final jsonMap = jsonDecode(jsonStr);

      final accountCredentials =
      auth.ServiceAccountCredentials.fromJson(jsonMap);
      final scopes = ['https://www.googleapis.com/auth/firebase.messaging'];

      final client =
      await auth.clientViaServiceAccount(accountCredentials, scopes);
      final projectId = jsonMap['project_id'];
      final url =
          'https://fcm.googleapis.com/v1/projects/$projectId/messages:send';
      String trimmedBody =
      body.length > 40 ? "${body.substring(0, 40)}..." : body;

      final response = await client.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          "message": {
            "token": token,
            "notification": {"title": title, "body": trimmedBody},
            "android": {
              "notification": {"icon": "ic_launcher", "color": "#34A853"}
            },
            "apns": {
              "payload": {
                "aps": {"badge": 1, "sound": "default"}
              }
            },
            "data": data,
          }
        }),
      );

      debugPrint('✅ v1 Push response: ${response.statusCode} ${response.body}');
      client.close();
    } catch (e) {
      debugPrint('❌ Error sending push via v1 API: $e');
    }
  }
}

