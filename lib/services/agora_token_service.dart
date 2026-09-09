import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:flutter/foundation.dart';

import '../config/agora_config.dart';

/// Client-side Agora token generator.
///
/// ⚠️ SECURITY WARNING: This uses the App Certificate on the client.
/// For production, migrate to a Firebase Cloud Function that keeps the
/// certificate server-side and returns tokens via an HTTPS endpoint.
///
/// This is the recommended temporary solution to unblock calls while the
/// server-side token infrastructure is being built.
class AgoraTokenService {
  AgoraTokenService._();
  static final AgoraTokenService instance = AgoraTokenService._();

  /// Generate an RTC (media) token for joining a channel.
  ///
  /// [channelName] — the Agora channel name (must match on both sides).
  /// [uid] — the integer Agora UID of the local user.
  /// [tokenExpirationSeconds] — how long the token is valid (default 1 hour).
  String generateRtcToken({
    required String channelName,
    required int uid,
    int tokenExpirationSeconds = 3600,
  }) {
    try {
      final token = RtcTokenBuilder.buildTokenWithUid(
        appId: AgoraConfig.appId,
        appCertificate: AgoraConfig.appCertificate,
        channelName: channelName,
        uid: uid,
        tokenExpireSeconds: tokenExpirationSeconds,
      );
      debugPrint(
        '🔑 Token generated — channel=$channelName uid=$uid',
      );
      return token;
    } catch (e, st) {
      debugPrint('❌ Token generation failed: $e\n$st');
      // Return empty string as fallback — Agora will reject it but won't crash.
      return '';
    }
  }
}

