import 'dart:async';
import 'dart:convert';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;

/// Sends push messages to HMS (Huawei/Honor devices without GMS) through the
/// Huawei Push Kit v1 API, mirroring FcmV1Sender's payload structure.
///
/// Credentials live in `assets/hms_credentials.json` (appId, clientId,
/// clientSecret from AppGallery Connect). When the file is absent the sender
/// reports itself as unconfigured and every call is a no-op, so GMS-only
/// builds keep working.
class HmsV1Sender {
  static HmsV1Sender? _instance;
  static bool _configured = false;

  final String? _appId;
  final String? _clientId;
  final String? _clientSecret;
  String? _accessToken;
  DateTime? _tokenExpiry;

  HmsV1Sender._(this._appId, this._clientId, this._clientSecret);

  static Future<HmsV1Sender?> getInstance() async {
    if (_instance != null) return _instance;
    if (_configured) return null;

    try {
      final jsonStr = await rootBundle.loadString('assets/hms_credentials.json');
      final map = Map<String, dynamic>.from(jsonDecode(jsonStr));
      final appId = map['appId'] as String?;
      final clientId = map['clientId'] as String?;
      final clientSecret = map['clientSecret'] as String?;
      if (appId == null || clientId == null || clientSecret == null) {
        _configured = true;
        return null;
      }
      _instance = HmsV1Sender._(appId, clientId, clientSecret);
      return _instance;
    } catch (e) {
      _configured = true;
      debugPrint('HMS sender not configured (missing hms_credentials.json): $e');
      return null;
    }
  }

  /// OAuth 2.0 app-level access token for the Huawei Push API.
  Future<String> _ensureAccessToken() async {
    final now = DateTime.now();
    if (_accessToken != null &&
        _tokenExpiry != null &&
        _tokenExpiry!.isAfter(now.add(const Duration(minutes: 1)))) {
      return _accessToken!;
    }

    final resp = await http.post(
      Uri.parse('https://oauth-login.cloud.huawei.com/oauth2/v3/token'),
      headers: {
        'Content-Type': 'application/x-www-form-urlencoded',
        'Accept': 'application/json',
      },
      body: {
        'grant_type': 'client_credentials',
        'client_id': _clientId!,
        'client_secret': _clientSecret!,
      },
    );

    if (resp.statusCode != 200) {
      throw Exception('HMS OAuth failed (${resp.statusCode}): ${resp.body}');
    }

    final json = jsonDecode(resp.body) as Map<String, dynamic>;
    _accessToken = json['access_token'] as String;
    final expiresIn = (json['expires_in'] as num?)?.toInt() ?? 3600;
    _tokenExpiry = DateTime.now().add(Duration(seconds: expiresIn));
    return _accessToken!;
  }

  /// Sends a data-only push so HmsMessageService (always running on HMS
  /// devices) renders the notification with the REPLY action and full CallKit
  /// UI, even when the app is in the background.
  Future<http.Response> sendMessageToToken({
    required String token,
    required String title,
    required String body,
    required String chatType,
    required String targetId,
    Map<String, String>? extraData,
    String? receiverId,
  }) async {
    final accessToken = await _ensureAccessToken();

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

    final requestBody = jsonEncode({
      'message': {
        'token': [token],
        'data': jsonEncode(dataPayload),
        'android': {
          'urgency': 'HIGH',
          if (chatType == 'call') 'category': 'PLAY_VOICE',
        },
      },
    });

    // The v1 API requires the request body to be HMAC-SHA256 signed with the
    // client secret (base64-encoded digest).
    final hmac = Hmac(sha256, utf8.encode(_clientSecret!));
    final digest = hmac.convert(utf8.encode(requestBody));
    final sign = base64Encode(digest.bytes);

    final resp = await http.post(
      Uri.parse('https://push-api.cloud.huawei.com/v1/$_appId/messages:send'),
      headers: {
        'Content-Type': 'application/json;charset=utf-8',
        'Authorization': 'Bearer $accessToken',
        'sign': sign,
      },
      body: requestBody,
    );

    if (resp.statusCode == 200) {
      debugPrint('HMS sent successfully');
    } else {
      debugPrint('HMS error ${resp.statusCode}: ${resp.body}');
    }
    return resp;
  }

  /// Sends to every HMS token of a recipient, skipping silently when the
  /// credentials file is not configured (GMS-only deployments).
  static Future<void> sendToTokens({
    required List<String> tokens,
    required String title,
    required String body,
    required String chatType,
    required String targetId,
    Map<String, String>? extraData,
    String? receiverId,
  }) async {
    if (tokens.isEmpty) return;
    final sender = await getInstance();
    if (sender == null) return;

    for (final token in tokens) {
      try {
        await sender.sendMessageToToken(
          token: token,
          title: title,
          body: body,
          chatType: chatType,
          targetId: targetId,
          extraData: extraData,
          receiverId: receiverId,
        );
      } catch (e) {
        debugPrint('HMS send failed for a token: $e');
      }
    }
  }
}
