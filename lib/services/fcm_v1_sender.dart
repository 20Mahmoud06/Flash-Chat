import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:googleapis_auth/auth_io.dart';
import 'package:googleapis_auth/googleapis_auth.dart' as auth;
import 'package:http/http.dart' as http;
import 'package:flutter/foundation.dart';

class FcmV1Sender {
  static FcmV1Sender? _instance;
  auth.AuthClient? _authClient;
  String? _projectId;

  FcmV1Sender._();

  static Future<FcmV1Sender> getInstance() async {
    if (_instance != null && _instance!._authClient != null) return _instance!;
    _instance = FcmV1Sender._();
    await _instance!._init();
    return _instance!;
  }

  Future<void> _init() async {
    if (_authClient != null) return;

    final jsonStr = await rootBundle.loadString('assets/service_account.json');
    final Map<String, dynamic> jsonMap = jsonDecode(jsonStr);

    _projectId = jsonMap['project_id'] as String?;

    final credentials = ServiceAccountCredentials.fromJson(jsonMap);

    final scopes = <String>[
      'https://www.googleapis.com/auth/firebase.messaging',
    ];

    _authClient = await clientViaServiceAccount(credentials, scopes);
  }

  Future<http.Response> sendMessageToToken({
    required String token,
    required String title,
    required String body,
    Map<String, String>? data,
  }) async {
    if (_authClient == null) await _init();
    if (_projectId == null) throw Exception('project_id not found in service_account.json');

    final url = Uri.parse('https://fcm.googleapis.com/v1/projects/$_projectId/messages:send');

    final payload = {
      "message": {
        "token": token,
        "notification": {"title": title, "body": body},
        "data": data ?? {},
      }
    };

    final resp = await _authClient!.post(
      url,
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(payload),
    );

    if (resp.statusCode == 200) {
      debugPrint('✅ FCM v1 sent (token): ${token.substring(0, token.length < 8 ? token.length : 8)}...');
    } else {
      debugPrint('❌ FCM v1 error ${resp.statusCode}: ${resp.body}');
    }

    return resp;
  }

  void close() {
    _authClient?.close();
    _authClient = null;
  }
}
