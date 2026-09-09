import 'package:flutter/material.dart';
import 'features/calls/services/call_service.dart';
import 'features/calls/services/group_call_tracker.dart';

/// Keeps the incoming-call Firestore listener alive for the whole app
/// lifetime, and watches active group calls so members can join mid-call.
/// CallKit events themselves are handled by [initCallKitEventHandler]
/// (subscribed in `main` before `runApp` so no lock-screen accept/decline
/// event can be missed).
class AppCallListener extends StatefulWidget {
  final Widget child;
  const AppCallListener({super.key, required this.child});

  @override
  State<AppCallListener> createState() => _AppCallListenerState();
}

class _AppCallListenerState extends State<AppCallListener> {
  @override
  void initState() {
    super.initState();
    CallService.listenForIncomingCalls();
    GroupCallTracker.instance.start();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
