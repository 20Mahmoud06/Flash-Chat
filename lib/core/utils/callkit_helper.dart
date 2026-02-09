import 'package:flutter_callkit_incoming/entities/android_params.dart';
import 'package:flutter_callkit_incoming/entities/call_kit_params.dart';
import 'package:flutter_callkit_incoming/entities/ios_params.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

Future<void> showIncomingCall({
  required String callerName,
  required bool isVideo,
  required String callId,
  required Map<String, dynamic> extra,
}) async {
  final params = CallKitParams(
    id: callId,
    nameCaller: callerName,
    handle: 'Flash Chat',
    type: isVideo ? 1 : 0,
    duration: 30000,
    textAccept: 'Accept',
    textDecline: 'Decline',
    extra: extra,

    android: const AndroidParams(
      isCustomNotification: true,
      isShowFullLockedScreen: true,
      ringtonePath: 'system_ringtone_default',
      backgroundColor: '#000000',
      actionColor: '#4CAF50',
    ),

    ios: const IOSParams(
      handleType: 'generic',
    ),
  );

  await FlutterCallkitIncoming.showCallkitIncoming(params);
}