import 'dart:async';
import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
// ignore: implementation_imports
import 'package:flutter_local_notifications/src/platform_specifics/android/enums.dart' as notif_enums;
import '../block/block_service.dart';
import '../chat/active_chat.dart';
import '../deep_link_service.dart';
import '../hms/hms_native_channel.dart';
import '../mute/mute_service.dart';
import '../notifications/missed_notifications_service.dart';
import '../../core/utils/callkit_helper.dart';
import '../../core/utils/notification_ids.dart';
import '../../features/calls/services/call_service.dart';

class FcmService {
  final _fcm = FirebaseMessaging.instance;
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;
  static final _local = FlutterLocalNotificationsPlugin();

  static const String channelId = 'flash_chat_custom_v13';
  static const String channelName = 'Flash Chat Messages';

  static const AndroidNotificationChannel chatChannel =
  AndroidNotificationChannel(
    channelId,
    channelName,
    description: 'Notifications for chat messages',
    importance: notif_enums.Importance.max,
    playSound: true,
    enableVibration: true,
    sound: RawResourceAndroidNotificationSound('alert'),
  );

  // ---------------- INIT ----------------

  Future<void> initializeFCM() async {
    try {
      await _initLocal();

      // Always save the token — the server needs it regardless of whether
      // the local device shows notification banners. When the user later
      // enables notifications (onboarding or profile toggle) the token is
      // already in Firestore so pushes start arriving immediately.
      await _saveToken();

      // Listeners are always set up so taps, calls and deep links keep working
      // even when the notification permission was denied.
      await _setupListeners();

      // Re-register the token at every sign-in (and after a reinstall, where
      // the cold-start save above is skipped because nobody is logged in yet).
      // Without this, a fresh install / re-login leaves `users/{uid}.fcmTokens`
      // stale or empty, so the device silently stops receiving ALL pushes
      // (calls and chat alike) until the permission flow happens to re-save it.
      _auth.authStateChanges().listen((user) {
        if (user != null) _saveToken();
      });
    } catch (e) {
      debugPrint('⚠️ FCM init failed (non-fatal): $e');
    }
  }

  /// Requests notification permission (shows the system dialog on
  /// Android 13+ / iOS). Called from the permission onboarding screen and
  /// from the profile notification toggle — never on cold start.
  ///
  /// Returns `true` when the permission was granted.
  static Future<bool> requestNotificationPermission() async {
    // Android 13+ local-notifications permission. Requested first and
    // independently of FCM: on HMS-only devices (no Google Play services) the
    // FCM call below can throw, and if it gated this dialog the user would
    // never be prompted and notifications would stay blocked.
    var androidGranted = true;
    try {
      final androidPlugin = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      androidGranted = await androidPlugin?.requestNotificationsPermission() ??
          true;
    } catch (e) {
      debugPrint('⚠️ Android notification permission request failed: $e');
    }

    var granted = androidGranted;
    try {
      final settings = await FirebaseMessaging.instance.requestPermission(
        alert: true,
        badge: true,
        sound: true,
      );
      final fcmGranted =
          settings.authorizationStatus == AuthorizationStatus.authorized ||
              settings.authorizationStatus == AuthorizationStatus.provisional;
      granted = granted && fcmGranted;

      // Re-save token after permission change so the server can start
      // pushing immediately.
      if (granted) {
        await FcmService()._saveToken();
      }
    } catch (e) {
      debugPrint('⚠️ FCM permission request failed (HMS-only device?): $e');
    }
    return granted;
  }

  /// Whether notifications are currently enabled on this device.
  static Future<bool> areNotificationsEnabled() async {
    try {
      final androidPlugin = FlutterLocalNotificationsPlugin()
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      final enabled = await androidPlugin?.areNotificationsEnabled();
      return enabled ?? true; // iOS doesn't expose this; assume enabled.
    } catch (_) {
      return true;
    }
  }

  Future<void> _initLocal() async {
    const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
    const darwinInit = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidInit,
      iOS: darwinInit,
    );

    final androidPlugin = _local.resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();

    await _local.initialize(
      initSettings,
      onDidReceiveNotificationResponse: (response) async {
        if (response.payload != null) {
          DeepLinkService().handleNotificationTap(jsonDecode(response.payload!));
        }
      },
    );

    await androidPlugin?.createNotificationChannel(chatChannel);
  }

  Future<void> _saveToken({String? token}) async {
    for (int i = 0; i < 3; i++) {
      try {
        final resolved = token ?? await _fcm.getToken();
        final uid = _auth.currentUser?.uid;

        if (resolved != null && uid != null) {
          await _firestore.collection('users').doc(uid).set({
            'fcmTokens': FieldValue.arrayUnion([resolved])
          }, SetOptions(merge: true));
        }
        break;
      }
      catch (e) {
        debugPrint('⚠️ FCM token not available yet: $e');
        await Future.delayed(const Duration(seconds: 2));
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

    // Keep the Firestore token list fresh when Firebase rotates the token
    // (reinstall, expiry, registration changes).
    _fcm.onTokenRefresh.listen((token) {
      _saveToken(token: token);
    });

    FirebaseMessaging.onMessage.listen((message) {
      handleIncomingPushData(message.data);
    });

    FirebaseMessaging.onMessageOpenedApp.listen((message) {
      DeepLinkService().handleNotificationTap(message.data);
    });

    _fcm.getInitialMessage().then((message) {
      if (message != null) {
        DeepLinkService().handleNotificationTap(message.data);
      }
    });
  }

  /// Handles an incoming push payload the same way regardless of transport
  /// (FCM messages, FCM taps and HMS Push Kit messages/taps all funnel here).
  Future<void> handleIncomingPushData(Map<String, dynamic> data) async {
    if (data['type'] == 'call') {
      final callId = data['callId'];
      if (callId == null) return;

      // 🔕 Defensive: never treat our own call as an incoming one (the caller
      // must never mark its own call as "busy" from its own device).
      if (data['callerId']?.toString() == _auth.currentUser?.uid) return;

      final activeCalls = await FlutterCallkitIncoming.activeCalls();
      if (activeCalls.any((c) => c['id'] == callId)) return;

      // 😴 Already on a call? Decline this one as "busy" instead of stacking.
      final isBusy = await CallService.isUserBusy(excludingCallId: callId);
      final isGroup = data['isGroup'] == 'true';
      if (isBusy) {
        debugPrint('Busy — ignoring incoming call push: $callId');
        final me = _auth.currentUser?.uid;
        if (isGroup && me != null) {
          await CallService.markGroupMemberOutcome(
            callId: callId,
            uid: me,
            outcome: 'busy',
          );
        } else {
          await CallService.updateCallStatus(callId, 'busy');
        }
        return;
      }

      // 🚫 Never ring for calls to/from a blocked user (1-to-1 only).
      if (data['isGroup'] != 'true' &&
          data['callerId'] is String &&
          _auth.currentUser != null) {
        try {
          if (await BlockService.isBlockedPair(
              data['callerId'] as String, _auth.currentUser!.uid)) {
            debugPrint('Blocking FCM call from blocked user: ${data['callerId']}');
            return;
          }
        } catch (e) {
          debugPrint('Block check failed for incoming call: $e');
        }
      }

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
        if (data.containsKey('callerAvatar'))
          'callerAvatar': data['callerAvatar'],
        if (data.containsKey('groupAvatar'))
          'groupAvatar': data['groupAvatar'],
      };
      await showIncomingCall(
        callerName: data['callerName'] ?? 'Unknown',
        isVideo: data['isVideo'] == 'true',
        callId: callId,
        extra: extra,
        avatar: data.containsKey('callerAvatar')
            ? data['callerAvatar']?.toString()
            : null,
      );
      CallService.setRingCleanupTimer(callId);
      CallService.addCallStatusListener(callId);
      return;
    }

    // 🔕 Ignore chat if already open (existing code)
    if (data['type'] == 'chat' && data['senderId'] == activeChatUserId) {
      return;
    }
    // 🔕 Ignore self-messages (I sent a message to myself): the server pushes
    // to the sender's own token, so without this guard I'd be notified about
    // my own message.
    if (data['type'] == 'chat' &&
        data['senderId']?.toString() == _auth.currentUser?.uid) {
      return;
    }
    // 🔕 Ignore group chat if already open
    if (data['type'] == 'group_chat' && data['groupId'] == activeGroupId) {
      return;
    }
    // 🔕 Ignore messages from contacts I muted (sender-side check already
    // prevents the push; this is the backup for older senders / HMS).
    if (data['type'] == 'chat' &&
        await MuteService.isMuted(data['senderId']?.toString() ?? '')) {
      return;
    }

    // ✅ Only normal messages reach here
    final showed = await showNotificationForData(data);

    // Keep the backfill in sync: whenever a foreground chat message is shown,
    // advance its per-conversation "last handled" timestamp so the offline
    // backfill never re-notifies it later.
    if (showed) {
      final peerKey = data['type'] == 'group_chat'
          ? data['groupId']?.toString()
          : data['senderId']?.toString();
      final isGroup = data['type'] == 'group_chat';
      if (peerKey != null && peerKey.isNotEmpty) {
        await MissedNotificationsService.instance
            .recordHandled(peerKey, isGroup: isGroup);
      }
    }
  }

  // ---------------- NOTIFICATION UI ----------------

  /// Deterministic id per conversation so a new message replaces the previous
  /// one for the same chat and open chats can cancel their own notifications.
  static int notificationIdFor(Map<String, dynamic> data) {
    final type = data['type'];
    if (type == 'chat') {
      return conversationNotificationId(
        data['senderId']?.toString() ?? '',
        isGroup: false,
      );
    }
    if (type == 'group_chat') {
      return conversationNotificationId(
        data['groupId']?.toString() ?? '',
        isGroup: true,
      );
    }
    return DateTime.now().millisecondsSinceEpoch ~/ 1000;
  }

  /// Cancels the notifications for a conversation. `peerId` is the contact
  /// uid for 1-to-1 chats and the group id for group chats. Cancels both the
  /// Flutter-rendered notification and the native HMS-rendered one.
  static Future<void> clearChatNotifications(
    String peerId, {
    required bool isGroup,
  }) async {
    final id = conversationNotificationId(peerId, isGroup: isGroup);
    try {
      await _local.cancel(id);
    } catch (e) {
      debugPrint('Failed to clear notifications: $e');
    }
    await HmsNativeChannel.cancelNotification(id);
  }

  /// Whether the device currently shows a live notification with [id] — e.g.
  /// one the native FCM/HMS service rendered while the app was closed. Used by
  /// the offline backfill so it never re-notifies (and re-sounds) a pile of
  /// conversations the user already sees in the shade on app open.
  static Future<bool> hasActiveNotification(int id) async {
    try {
      final active = await _local.getActiveNotifications();
      return active.any((n) => n.id == id);
    } catch (e) {
      debugPrint('Failed to read active notifications: $e');
      return false;
    }
  }

  /// Builds a notification for a chat message and shows it on the device.
  /// Returns `true` when a notification was actually displayed (permission
  /// granted), `false` otherwise (e.g. permission revoked). Reused by the
  /// foreground FCM listener, the offline backfill and the tap/QQ handlers.
  static Future<bool> showNotificationFor({
    required String title,
    required String body,
    required String type,
    required String senderId,
    required String groupId,
  }) async {
    final data = <String, dynamic>{
      'type': type,
      'title': title,
      'body': body,
      if (type == 'group_chat') 'groupId': groupId else 'senderId': senderId,
    };
    return FcmService().showNotificationForData(data);
  }

  /// Whether a notification can be shown given the current permission state.
  static Future<bool> _canShowNotification() async {
    final androidPlugin = _local
        .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>();
    try {
      final enabled = await androidPlugin?.areNotificationsEnabled();
      if (enabled == false) return false;
    } catch (_) {
      // Permission check unavailable; fall through and let show() decide.
    }
    return true;
  }

  /// Determines the notification id for a payload. Always uses the
  /// per-conversation id so repeated messages from the same chat replace the
  /// previous notification (one latest-message notification per chat).
  static int _notificationIdForPayload(Map<String, dynamic> data) {
    return notificationIdFor(data);
  }

  Future<bool> showNotificationForData(Map<String, dynamic> data) async {
    final title = data['title'] ?? 'New message';
    final body = data['body'] ?? '';

    // Don't attempt to show if the user revoked notification permission.
    if (!await _canShowNotification()) return false;

    final androidDetails = AndroidNotificationDetails(
      chatChannel.id,
      chatChannel.name,
      channelDescription: chatChannel.description,
      importance: notif_enums.Importance.max,
      priority: notif_enums.Priority.high,
      icon: '@drawable/ic_notification',
      largeIcon: const DrawableResourceAndroidBitmap('mipmap/ic_launcher'),
      playSound: true,
      enableVibration: true,
      sound: const RawResourceAndroidNotificationSound('alert'),
      styleInformation: const DefaultStyleInformation(true, true),
    );

    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
      sound: 'alert.wav',
    );

    final notificationId = _notificationIdForPayload(data);
    try {
      await _local.show(
        notificationId,
        title,
        body,
        NotificationDetails(
          android: androidDetails,
          iOS: iosDetails,
        ),
        payload: jsonEncode(data),
      );
      return true;
    } catch (e) {
      debugPrint('Failed to show local notification: $e');
      return false;
    }
  }
}
