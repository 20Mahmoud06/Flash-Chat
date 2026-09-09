import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'config/firebase_options.dart';
import 'features/calls/cubit/call_cubit.dart';
import 'features/calls/services/call_notif.dart';
import 'services/calls/callkit_event_handler.dart';
import 'services/connectivity/connectivity_service.dart';
import 'services/fcm/fcm_service.dart';
import 'services/hms/hms_push_service.dart';
import 'services/notifications/missed_notifications_service.dart';
import 'services/presence/presence_service.dart';
import 'shared/widgets/call_in_progress_pill.dart';

/// Background message handler
///
/// NOTE: incoming CALL rings are now rendered natively (FlashChatFirebaseMessagingService
/// for GMS, HmsMessageService for HMS) so they work reliably when the app is
/// killed or backgrounded. Rendering them here too would cause a double ring,
/// so call pushes are deliberately ignored on this path — the native service
/// (and the callkit accept/decline event handler on cold start) covers them.
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final data = message.data;
  // Calls are handled natively (see above). Chat/group pushes don't reach this
  // path either (they're rendered natively); nothing else needs doing here.
  if (data['type'] == 'call') {
    return;
  }
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Configure Firestore settings
  if (!kIsWeb) {
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: true,
      cacheSizeBytes: 25 * 1024 * 1024,
    );
  }

  // Setup background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Subscribe to CallKit events before runApp so no accept/decline event from
  // a terminated app (lock-screen answer) can be missed.
  initCallKitEventHandler();

  // Sticky voice-call notification actions (native -> Dart): drive the same
  // app-wide call cubit the call page uses, so the actions work even after
  // the call page was popped (call minimized).
  CallNotifBridge.instance.onAction = (action, callId) {
    final cubit = CallCubit.instance;
    switch (action) {
      case CallNotifAction.mute:
        cubit.toggleMute();
        break;
      case CallNotifAction.end:
        if (callId.isNotEmpty) cubit.endCall(callId);
        break;
      case CallNotifAction.open:
        CallInProgressPill.openActiveCall();
        break;
    }
  };

  // Clear any sticky ongoing-call notification a previous process may have left
  // behind (a call cannot survive a process restart, so it is always stale).
  unawaited(CallNotifBridge.instance.reconcileOnStartup());

  // Setup system UI
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Lock orientation to portrait
  await SystemChrome.setPreferredOrientations([
    DeviceOrientation.portraitUp,
    DeviceOrientation.portraitDown,
  ]);

  // Initialize FCM
  unawaited(FcmService().initializeFCM());

  // Reliable missed-notification backfill: show notifications for messages
  // that arrived while the app was offline / killed once we reconnect.
  unawaited(MissedNotificationsService.instance.initialize());

  // Initialize HMS Push Kit bridge (no-op on GMS-only devices) before runApp
  // so cold-start notification taps are not missed.
  unawaited(HmsPushService.init());

  // Initialize connectivity monitoring (used for offline banners & auto-resend)
  await ConnectivityService.instance.initialize();

  // Start tracking the user's online presence (writes `presence/{uid}`).
  PresenceService.instance.start();

  // Run app
  runApp(const MyApp());
}
