import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Thin wrapper around the native HMS Push Kit bridge
/// (android/.../hms/HmsPushBridge.kt).
///
/// All calls are safe on GMS-only devices: they fail fast with null/defaults.
class HmsNativeChannel {
  static const _method = MethodChannel('flash_chat/hms');
  static const _events = EventChannel('flash_chat/hms_push_events');

  /// Whether HMS Core + Push Kit is usable on this device.
  static Future<bool> isHmsAvailable() async {
    try {
      return await _method.invokeMethod<bool>('isHmsAvailable') ?? false;
    } catch (e) {
      return false;
    }
  }

  /// The cached HMS push token, or null when not registered yet.
  static Future<String?> getHmsToken() async {
    try {
      return await _method.invokeMethod<String?>('getHmsToken');
    } catch (e) {
      return null;
    }
  }

  /// One-shot payload of a notification tap that happened before Dart was
  /// ready (cold start from a killed state). Cleared after the first read.
  static Future<Map<String, dynamic>?> getNotificationPayload() async {
    try {
      final payload =
          await _method.invokeMethod<String?>('getNotificationPayload');
      if (payload == null || payload.isEmpty) return null;
      return decodePayload(payload);
    } on MissingPluginException {
      rethrow;
    } catch (e) {
      return null;
    }
  }

  /// Cancels a notification rendered natively by HmsMessageService.
  static Future<void> cancelNotification(int id) async {
    try {
      await _method.invokeMethod<void>('cancelNotification', id);
    } catch (e) {
      debugPrint('HMS cancelNotification failed: $e');
    }
  }

  /// Stream of incoming HMS push events:
  /// `{"event": "message", "data": {payload}}`.
  ///
  /// Fires when a data message arrives while the app is in the foreground and
  /// when a notification is tapped while the app is already running.
  static Stream<Map<String, dynamic>> get events {
    return _events.receiveBroadcastStream().where((e) => e is Map).map((e) {
      final map = Map<String, dynamic>.from(e as Map);
      final data = map['data'];
      if (data is String) return decodePayload(data);
      if (data is Map) return Map<String, dynamic>.from(data);
      return const <String, dynamic>{};
    }).where((data) => data['type'] != null);
  }

  static Map<String, dynamic> decodePayload(String json) {
    try {
      final decoded =
          Map<String, dynamic>.from(jsonDecode(json) as Map? ?? const {});
      // The v1 push API may nest the payload under a "data" key.
      if (decoded['type'] == null && decoded['data'] is String) {
        return decodePayload(decoded['data'] as String);
      }
      return decoded;
    } catch (_) {
      return const <String, dynamic>{};
    }
  }
}
