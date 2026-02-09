import 'dart:async';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import 'app.dart';
import 'config/firebase_options.dart';
import 'core/utils/callkit_helper.dart';
import 'services/fcm/fcm_service.dart';

/// Background message handler
@pragma('vm:entry-point')
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final data = message.data;
  if (data['type'] == 'call') {
    await _handleIncomingCall(data);
  }
}

Future<void> _handleIncomingCall(Map<String, dynamic> data) async {
  final callId = data['callId'];
  if (callId == null) return;

  final activeCalls = await FlutterCallkitIncoming.activeCalls();
  if (activeCalls.any((c) => c['id'] == callId)) return;

  final extra = <String, dynamic>{
    'type': 'call',
    'callId': callId,
    'isVideo': data['isVideo'] == 'true',
    'callerId': data['callerId'],
    'callerName': data['callerName'],
    'isGroup': data['isGroup'] == 'true',
    if (data.containsKey('groupId')) 'groupId': data['groupId'],
    if (data.containsKey('groupName')) 'groupName': data['groupName'],
    if (data.containsKey('receiverId')) 'receiverId': data['receiverId'],
  };

  await showIncomingCall(
    callerName: data['callerName'] ?? 'Unknown',
    isVideo: data['isVideo'] == 'true',
    callId: callId,
    extra: extra,
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Initialize Firebase
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // Setup background message handler
  FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);

  // Setup system UI
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);

  // Initialize FCM
  unawaited(FcmService().initializeFCM());

  // Run app
  runApp(const MyApp());
}