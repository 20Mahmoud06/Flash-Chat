import 'dart:convert';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class FcmV1Sender {
  static FcmV1Sender? _instance;

  static const String _workerUrl =
      'https://flashchat-notifications.mahmoudsafa220.workers.dev';

  FcmV1Sender._();

  static Future<FcmV1Sender> getInstance() async {
    _instance ??= FcmV1Sender._();
    return _instance!;
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

    final payload = {
      'token': token,
      'receiverId': receiverId,
      'data': dataPayload,
      'android': {
        'priority': 'HIGH',
      },
      'apns': {
        'payload': {
          'aps': {
            'content-available': 1,
            if (chatType != 'call') ...{
              'sound': 'alert.wav',
              'badge': 1,
              'alert': {
                'title': title,
                'body': body,
              },
            },
          },
        },
      },
    };

    try {
      final user = FirebaseAuth.instance.currentUser;

      if (user == null) {
        throw StateError(
          'Cannot send FCM notification: no authenticated Firebase user.',
        );
      }

      final idToken = await user.getIdToken();

      if (idToken == null || idToken.isEmpty) {
        throw StateError(
          'Cannot send FCM notification: failed to get Firebase ID token.',
        );
      }

      final response = await http.post(
        Uri.parse('$_workerUrl/send-test'),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken',
        },
        body: jsonEncode(payload),
      );

      if (response.statusCode == 200) {
        debugPrint('✅ FCM sent through Cloudflare Worker');
      } else {
        debugPrint(
          '❌ FCM Worker Error ${response.statusCode}: ${response.body}',
        );

        try {
          final responseBody = jsonDecode(response.body);
          final fcmResponse = responseBody['response'];

          if (response.statusCode == 502 &&
              fcmResponse is String &&
              fcmResponse.contains('UNREGISTERED')) {
            debugPrint(
              '⚠️ FCM token is no longer registered. '
              'The receiver will refresh its token on the next token update.',
            );
          }
        } catch (e) {
          debugPrint('Failed to parse FCM Worker response: $e');
        }
      }

      return response;
    } catch (e) {
      debugPrint('❌ Exception sending FCM through Worker: $e');
      rethrow;
    }
  }
}
