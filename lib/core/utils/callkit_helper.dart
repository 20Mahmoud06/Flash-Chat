import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

Future<void> showIncomingCall({
  required String callerName,
  required bool isVideo,
  required String callId,
  required Map<String, dynamic> extra,
  String? avatar,
}) async {
  final params = CallKitParams(
    id: callId,
    nameCaller: callerName,
    handle: 'Flash Chat',
    type: isVideo ? 1 : 0,
    duration: 30000,
    avatar: avatar,
    textAccept: 'Accept',
    textDecline: 'Decline',
    extra: extra,

    android: const AndroidParams(
      isCustomNotification: true,
      isShowFullLockedScreen: true,
      // The app's own incoming-call ringtone (bundled in
      // android/app/src/main/res/raw/ringtone.wav). The native
      // CallkitSoundPlayerManager resolves this to a raw resource and loops it
      // on the RING stream; it stops automatically when the call is accepted,
      // declined, cancelled, timed out or ended.
      ringtonePath: 'ringtone',
      backgroundColor: '#000000',
      actionColor: '#4CAF50',
    ),

    ios: const IOSParams(
      handleType: 'generic',
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}
