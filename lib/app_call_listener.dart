import 'dart:async';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'services/call_service.dart';
import 'services/deep_link_service.dart';

class AppCallListener extends StatefulWidget {
  final Widget child;
  const AppCallListener({super.key, required this.child});

  @override
  State<AppCallListener> createState() => _AppCallListenerState();
}

class _AppCallListenerState extends State<AppCallListener> {
  StreamSubscription<CallEvent?>? _callKitSub;

  @override
  void initState() {
    super.initState();
    CallService.listenForIncomingCalls();
    _callKitSub =
        FlutterCallkitIncoming.onEvent.listen(_handleCallKitEvent);
  }

  @override
  void dispose() {
    _callKitSub?.cancel();
    super.dispose();
  }

  void _handleCallKitEvent(CallEvent? event) {
    if (event == null) return;

    final name = event.event;
    final body = event.body ?? {};
    final callId = body['id'];
    final extra = body['extra'];

    debugPrint('CallKit Event: $name, Call ID: $callId');

    if (name == Event.actionCallAccept && callId != null && extra != null) {
      try {
        CallService.updateCallStatus(callId, 'accepted');

        CallService.joinCall(
          callId,
          FirebaseAuth.instance.currentUser!.uid,
        );

        DeepLinkService().handleNotificationTap(Map<String, dynamic>.from(extra));
        debugPrint('Accepted call: $callId');
      } catch (e) {
        debugPrint('Error handling accept: $e');
      }
    }

    if (name == Event.actionCallDecline ||
        name == Event.actionCallEnded ||
        name == Event.actionCallTimeout) {
      if (callId != null) {
        CallService.updateCallStatus(callId, 'ended');
        FlutterCallkitIncoming.endCall(callId);
        debugPrint('Ended call: $callId');
      }
    }
  }

  @override
  Widget build(BuildContext context) => widget.child;
}