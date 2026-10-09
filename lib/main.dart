import 'dart:async';
import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart' show kReleaseMode;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'app.dart';
import 'config/firebase_options.dart';
import 'features/calls/bloc/call_bloc.dart';
import 'features/calls/services/call_notif.dart';
import 'features/calls/services/callkit_event_handler.dart';
import 'services/connectivity/connectivity_service.dart';
import 'services/fcm/fcm_service.dart';
import 'services/hms/hms_push_service.dart';
import 'services/notifications/missed_notifications_service.dart';
import 'services/presence/presence_service.dart';
import 'features/calls/widgets/call_in_progress_pill.dart';

/// Activates Firebase App Check.
///
/// Release builds use strong attestation (Play Integrity on Android, App Attest
/// with DeviceCheck fallback on iOS/macOS). Debug and profile builds use the
/// debug provider so `flutter run` keeps working — the corresponding debug
/// token (logged to the device console) must be registered in the Firebase
/// console > App Check > Apps > (your app) > DEBUG TOKENS.
///
/// This is intentionally non-fatal: if App Check can't be activated (e.g. an
/// unsupported platform), the rest of the app still boots. App Check only
/// starts blocking traffic once each service is set to Enforce in the console.
Future<void> _initializeFirebaseAppCheck() async {
  try {
    await FirebaseAppCheck.instance.activate(
      androidProvider:
          kReleaseMode ? AndroidProvider.playIntegrity : AndroidProvider.debug,
      appleProvider: kReleaseMode
          ? AppleProvider.appAttestWithDeviceCheckFallback
          : AppleProvider.debug,
    );
    // Note: refreshing is on by default; kept explicit for clarity.
    FirebaseAppCheck.instance.setTokenAutoRefreshEnabled(true);
  } catch (e) {
    debugPrint('Firebase App Check activation skipped: $e');
  }
}

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

  // Attest that this is a genuine build of our app (Play Integrity / App Attest).
  await _initializeFirebaseAppCheck();

  // Setup background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Subscribe to CallKit events before runApp so no accept/decline event from
  // a terminated app (lock-screen answer) can be missed.
  initCallKitEventHandler();

  // Sticky voice-call notification actions (native -> Dart): drive the same
  // app-wide call bloc the call page uses, so the actions work even after
  // the call page was popped (call minimized).
  CallNotifBridge.instance.onAction = (action, callId) {
    final cubit = CallBloc.instance;
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