import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import '../deep_link_service.dart';
import '../fcm/fcm_service.dart';
import 'hms_native_channel.dart';

/// Bridges HMS Push Kit events from native Android into the same handling
/// pipeline as FCM (see FcmService.handleIncomingPushData) and keeps the
/// device's HMS push token registered in Firestore.
class HmsPushService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  static bool _initialized = false;
  static Timer? _tokenRetryTimer;
  static int _tokenRetryAttempts = 0;
  static Timer? _tapDrainTimer;
  static int _tapDrainAttempts = 0;

  /// Polls for a notification tap that happened before the Flutter engine was
  /// ready. The native method channel is only registered after runApp, so an
  /// early read throws MissingPluginException; retry until it answers.
  static void _drainPendingNotificationTap() {
    if (_tapDrainTimer != null) return;
    _tapDrainAttempts = 0;
    _tapDrainRemaining();
  }

  static void _tapDrainRemaining() async {
    try {
      // A returned value (null or a payload) proves the channel is live.
      final pending = await HmsNativeChannel.getNotificationPayload();
      if (pending != null) {
        debugPrint('HMS pending notification tap: $pending');
        DeepLinkService().handleNotificationTap(pending);
      }
      _tapDrainTimer?.cancel();
      _tapDrainTimer = null;
    } catch (_) {
      // Channel not registered yet — retry until the engine is up.
      _tapDrainAttempts++;
      if (_tapDrainAttempts > 100) {
        _tapDrainTimer?.cancel();
        _tapDrainTimer = null;
        return;
      }
      _tapDrainTimer = Timer(const Duration(milliseconds: 100), _tapDrainRemaining);
    }
  }

  /// Must be called once from main() (before runApp) so cold-start taps and
  /// foreground data messages are not missed.
  static Future<void> init() async {
    if (_initialized) return;
    _initialized = true;

    try {
      final available = await HmsNativeChannel.isHmsAvailable();
      debugPrint('HMS Push available: $available');
    } catch (e) {
      debugPrint('HMS availability check failed: $e');
    }

    // Deliver taps that happened while the app was killed. The native side
    // buffers the payload until Dart reads it, but the method channel is only
    // registered once the Flutter engine starts (configureFlutterEngine) —
    // which happens after runApp. So keep polling until the native handler is
    // live, then drain the buffered payload exactly once.
    _drainPendingNotificationTap();

    // Live events: foreground data messages and taps while the app is running.
    HmsNativeChannel.events.listen((data) {
      debugPrint('HMS push event: $data');
      _route(data);
    });

    // Keep the Firestore HMS token list fresh on every sign-in.
    _auth.authStateChanges().listen((user) {
      if (user != null) {
        _syncToken(user.uid);
      } else {
        _stopTokenRetry();
      }
    });
  }

  static Future<void> _route(Map<String, dynamic> data) async {
    // Chat/group messages respect the active-chat suppression inside the
    // handler; call messages go through CallKit (CallService may be needed).
    await FcmService().handleIncomingPushData(data);
  }

  /// Uploads the native HMS token (once it exists) into `users/{uid}.hmsTokens`
  /// so the server can reach this device through the Huawei Push API.
  static Future<void> _syncToken(String uid) async {
    _stopTokenRetry();
    _tokenRetryAttempts = 0;

    Future<bool> attempt() async {
      try {
        final token = await HmsNativeChannel.getHmsToken();
        if (token != null && token.isNotEmpty) {
          await _firestore.collection('users').doc(uid).set({
            'hmsTokens': FieldValue.arrayUnion([token]),
          }, SetOptions(merge: true));
          debugPrint('HMS token registered');
          _stopTokenRetry();
          return true;
        }
      } catch (e) {
        debugPrint('HMS token sync failed: $e');
      }
      return false;
    }

    if (await attempt()) return;

    // The token may arrive a few seconds after first app launch (HMS Core
    // registration). Retry briefly so first-run devices still register.
    _tokenRetryTimer = Timer.periodic(const Duration(seconds: 10), (timer) async {
      _tokenRetryAttempts++;
      if (_tokenRetryAttempts >= 12) {
        _stopTokenRetry();
        return;
      }
      if (await attempt()) {
        _stopTokenRetry();
      }
    });
  }

  static void _stopTokenRetry() {
    _tokenRetryTimer?.cancel();
    _tokenRetryTimer = null;
  }
}
