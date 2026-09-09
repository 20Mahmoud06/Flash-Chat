import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/services.dart';
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class FcmV1Sender {
  static FcmV1Sender? _instance;
  auth.AuthClient? _authClient;
  String? _projectId;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  FcmV1Sender._();

  static Future<FcmV1Sender> getInstance() async {
    if (_instance != null && _instance!._authClient != null) return _instance!;
    _instance = FcmV1Sender._();
    await _instance!._init();
    return _instance!;
  }

  Future<void> _init() async {
    if (_authClient != null) return;

    try {
      final jsonStr = await rootBundle.loadString('assets/service_account.json');
      final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);

      _projectId = jsonMap['project_id'] as String?;

      final credentials = ServiceAccountCredentials.fromJson(jsonMap);

      final scopes = <String>[
        'https://www.googleapis.com/auth/firebase.messaging',
      ];

      _authClient = await clientViaServiceAccount(credentials, scopes);
    } catch (e) {
      debugPrint("Error initializing FCM Sender: $e");
    }
  }

  Future<http.Response> sendMessageToToken({
    required String token,
    required String title,
    required String body,
    required String chatType,
    required String targetId,
    Map<String, String>? extraData,
    String? receiverId,
  }) async {
    if (_authClient == null) await _init();
    if (_projectId == null) throw Exception('project_id not found in service_account.json');

    final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$_projectId/messages:send');

    final Map<String, String> dataPayload = {
      'type': chatType,
      'click_action': 'FLUTTER_NOTIFICATION_CLICK',
      'title': title,
      'body': body,
    };

    if (chatType == 'chat') {
      dataPayload['senderId'] = targetId;
    } else if (chatType == 'group_chat') {
      dataPayload['groupId'] = targetId;
    }

    if (extraData != null) {
      dataPayload.addAll(extraData);
    }

    // Chat pushes are sent DATA-ONLY on Android: the plugin's manifest
    // FlutterFirebaseMessagingService shadows the FCM SDK's rendering service
    // (its onMessageReceived is a no-op), so the system never displays the
    // `notification` block when the app is closed. A custom native service
    // (FlashChatFirebaseMessagingService) renders instead. On iOS the system
    // renders the alert from `aps` even when the app is terminated, so the
    // alert (plus sound/badge/content-available) is delivered through APNs.
    final payload = {
      "message": {
        "token": token,
        "android": {
          "priority": "HIGH"
        },
        "apns": {
          "payload": {
            "aps": {
              "content-available": 1,
              if (chatType != 'call') ...{
                "sound": "alert.wav",
                "badge": 1,
                // On iOS the system renders this alert even when the app is
                // terminated, so chat notifications always reach the lock
                // screen without relying on a background launch.
                "alert": {
                  "title": title,
                  "body": body,
                }
              }
            }
          }
        },
        "data": dataPayload,
      }
    };

    try {
      final resp = await _authClient!.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode(payload),
      );

      if (resp.statusCode == 200) {
        debugPrint('✅ FCM sent successfully');
      } else {
        debugPrint('❌ FCM Error ${resp.statusCode}: ${resp.body}');

        final responseBody = jsonDecode(resp.body);
        if (resp.statusCode == 404 &&
            responseBody['error']['details']?[0]['errorCode'] == 'UNREGISTERED') {
          if (receiverId != null) {
            _firestore.collection('users').doc(receiverId).update({
              'fcmTokens': FieldValue.arrayRemove([token])
            }).catchError((e) => debugPrint("Failed to remove token: $e"));
          }
        }
      }
      return resp;
    } catch (e) {
      debugPrint("❌ Exception sending FCM: $e");
      rethrow;
    }
  }
}