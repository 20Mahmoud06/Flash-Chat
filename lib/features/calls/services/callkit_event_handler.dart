import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_callkit_incoming/entities/call_event.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';

import '../../../core/routes/navigation_service.dart';
import '../../../core/routes/route_names.dart';
import '../../../core/utils/call_utils.dart';
import '../models/call_arguments.dart';
import 'call_service.dart';

/// Subscribes to CallKit events as early as possible (before `runApp`).
///
/// The plugin's Android side uses a plain `EventChannel`: events emitted
/// before a Dart listener attaches are dropped. When the app is terminated and
/// the user answers a call from the lock screen, the accept event can arrive
/// while the engine is still booting, so the subscription must exist the
/// moment the Dart isolate starts.
void initCallKitEventHandler() {
  FlutterCallkitIncoming.onEvent.listen(_handleCallKitEvent);
  unawaited(checkInitialCallAccept());
}

/// Cold-boot check: inspects native active calls to see if an incoming call
/// was accepted while the Flutter isolate was being started.
Future<void> checkInitialCallAccept() async {
  try {
    final calls = await FlutterCallkitIncoming.activeCalls();
    if (calls is List && calls.isNotEmpty) {
      for (final call in calls) {
        if (call is Map) {
          final isAccepted =
              call['isAccepted'] == true || call['accepted'] == true;
          if (isAccepted) {
            final callId = call['id']?.toString();
            if (callId != null && callId.isNotEmpty) {
              debugPrint('checkInitialCallAccept found accepted call: $callId');
              final event = CallEvent(
                call,
                Event.actionCallAccept,
              );
              await _handleCallKitEvent(event);
              break;
            }
          }
        }
      }
    }
  } catch (e) {
    debugPrint('checkInitialCallAccept error: $e');
  }
}

Future<void> _handleCallKitEvent(CallEvent? event) async {
  if (event == null) return;

  final name = event.event;
  final body = event.body ?? {};
  final callId = body['id']?.toString();
  final extra = body['extra'];

  debugPrint('CallKit Event: $name, Call ID: $callId');

  if (name == Event.actionCallAccept && callId != null) {
    try {
      await CallService.updateCallStatus(callId, 'accepted');

      final currentUser = await _waitForAuth();
      if (currentUser == null) {
        debugPrint('Call accepted but no user is logged in');
        return;
      }

      // Prevent the Firestore accepted-call recovery from also opening the
      // same call (e.g. on a cold start where both paths can fire).
      if (!CallService.claimAcceptedCall(callId)) {
        debugPrint('Accepted call already handled elsewhere: $callId');
        return;
      }
      CallService.cancelRingCleanupTimer(callId);

      await CallService.joinCall(callId, currentUser.uid);

      Map<String, dynamic> callPayload;
      if (extra is Map) {
        callPayload = Map<String, dynamic>.from(extra);
      } else {
        // Fallback: query Firestore document directly if extra wasn't passed
        final doc = await FirebaseFirestore.instance
            .collection('calls')
            .doc(callId)
            .get();
        callPayload = Map<String, dynamic>.from(doc.data() ?? {});
      }
      callPayload['type'] = 'call';
      callPayload['callId'] = callId;

      await _waitForNavigator();
      await applyCallerNickname(callPayload);
      final args = CallArguments.fromMap(callPayload);
      final routeName = args.isVideo
          ? RouteNames.videoCallPage
          : RouteNames.voiceCallPage;
      SchedulerBinding.instance.addPostFrameCallback((_) {
        navigatorKey.currentState?.pushNamed(routeName, arguments: args);
      });

      debugPrint('Accepted call: $callId');
    } catch (e) {
      debugPrint('Error handling accept: $e');
    }
  }

  if (name == Event.actionCallDecline) {
    // Receiver explicitly declined → caller sees "Call Declined".
    // For group calls the decline is member-only: the group call keeps going
    // for everyone else, so we record this member's outcome instead of ending
    // the whole call.
    if (callId != null) {
      // Mark handled LOCALLY first so the Firestore snapshot listener never
      // re-shows the incoming-call screen, even if the Firestore write fails
      // (e.g. PERMISSION_DENIED in release mode after R8 minification).
      CallService.markCallHandled(callId);
      CallService.cancelRingCleanupTimer(callId);
      final isGroup = extra?['isGroup'] == 'true';
      if (isGroup) {
        final currentUser = await _waitForAuth();
        if (currentUser != null) {
          await CallService.markGroupMemberOutcome(
            callId: callId,
            uid: currentUser.uid,
            outcome: 'declined',
          );
        }
        await FlutterCallkitIncoming.endCall(callId);
      } else {
        try {
          await CallService.updateCallStatus(callId, 'declined');
        } catch (e) {
          debugPrint('Failed to update Firestore on decline: $e');
        }
        await FlutterCallkitIncoming.endCall(callId);
      }
      debugPrint('Declined call: $callId');
    }
  }

  if (name == Event.actionCallTimeout) {
    // Receiver never answered → caller sees "Call Timed Out". For group calls
    // this only marks this member as missed; the group call keeps going.
    if (callId != null) {
      CallService.markCallHandled(callId);
      CallService.cancelRingCleanupTimer(callId);
      final isGroup = extra?['isGroup'] == 'true';
      if (isGroup) {
        final currentUser = await _waitForAuth();
        if (currentUser != null) {
          await CallService.markGroupMemberOutcome(
            callId: callId,
            uid: currentUser.uid,
            outcome: 'no_answer',
          );
        }
        await FlutterCallkitIncoming.endCall(callId);
      } else {
        try {
          await CallService.updateCallStatus(callId, 'no_answer');
        } catch (e) {
          debugPrint('Failed to update Firestore on timeout: $e');
        }
        await FlutterCallkitIncoming.endCall(callId);
      }
      debugPrint('Call timed out: $callId');
    }
  }

  if (name == Event.actionCallEnded) {
    if (callId != null) {
      CallService.markCallHandled(callId);
      CallService.cancelRingCleanupTimer(callId);
      try {
        await CallService.updateCallStatus(callId, 'ended');
      } catch (e) {
        debugPrint('Failed to update Firestore on ended: $e');
      }
      await FlutterCallkitIncoming.endCall(callId);
      debugPrint('Ended call: $callId');
    }
  }
}

Future<User?> _waitForAuth() async {
  int attempts = 0;
  while (FirebaseAuth.instance.currentUser == null && attempts < 150) {
    await Future.delayed(const Duration(milliseconds: 100));
    attempts++;
  }
  return FirebaseAuth.instance.currentUser;
}

Future<void> _waitForNavigator() async {
  int attempts = 0;
  while (navigatorKey.currentState == null && attempts < 200) {
    await Future.delayed(const Duration(milliseconds: 100));
    attempts++;
  }
  if (navigatorKey.currentState == null) {
    debugPrint('Navigator timed out for call navigation');
  }
}