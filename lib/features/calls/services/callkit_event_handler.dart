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
import '../bloc/call_bloc.dart';
import '../models/call_arguments.dart';
import '../widgets/call_join_dialogs.dart';
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

      final joinResult = await CallService.joinCall(callId, currentUser.uid);
      if (joinResult != CallJoinResult.joined) {
        debugPrint('Accept blocked: $joinResult for $callId');
        // The call is already full or already over: drop the native ring and
        // never open the call page.
        await FlutterCallkitIncoming.endCall(callId);
        if (joinResult == CallJoinResult.full) {
          await showCallFullDialogGlobal();
        }
        return;
      }

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
      // In-app join dismisses a leftover CallKit ring via endCall, which can
      // synthesize DECLINE. Never mark a member who already joined as declined.
      if (CallService.wasAcceptedLocally(callId)) {
        debugPrint('Ignoring synthetic decline after local join: $callId');
        try {
          await FlutterCallkitIncoming.endCall(callId);
        } catch (_) {}
        return;
      }
      // Mark handled LOCALLY first so the Firestore snapshot listener never
      // re-shows the incoming-call screen, even if the Firestore write fails
      // (e.g. PERMISSION_DENIED in release mode after R8 minification).
      CallService.markCallHandled(callId);
      CallService.cancelRingCleanupTimer(callId);
      final callDoc = await _readCallDoc(callId);
      final data = callDoc?.data() as Map<String, dynamic>?;
      final isGroup = _extraBool(extra, 'isGroup') || data?['isGroup'] == true;
      if (isGroup) {
        final currentUser = await _waitForAuth();
        final memberUid = _extraString(extra, 'receiverId') ?? currentUser?.uid;
        if (memberUid != null) {
          await CallService.markGroupMemberOutcome(
            callId: callId,
            uid: memberUid,
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
      final callDoc = await _readCallDoc(callId);
      final data = callDoc?.data() as Map<String, dynamic>?;
      final isGroup = _extraBool(extra, 'isGroup') || data?['isGroup'] == true;
      if (isGroup) {
        final currentUser = await _waitForAuth();
        final memberUid = _extraString(extra, 'receiverId') ?? currentUser?.uid;
        if (memberUid != null) {
          await CallService.markGroupMemberOutcome(
            callId: callId,
            uid: memberUid,
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

      final currentUser = await _waitForAuth();
      final extraIsGroup = _extraBool(extra, 'isGroup');

      // Resolve the group flag from the doc too: the plugin call data
      // sometimes lacks the ring `extra` (e.g. teardown events), but a group
      // must NEVER be torn down up as a 1-to-1 (which writes a global
      // `ended` that kills the whole call).
      final doc = await _readCallDoc(callId);
      final data = doc?.data() as Map<String, dynamic>?;
      final isGroup = extraIsGroup || (data?['isGroup'] == true);

      try {
        if (!isGroup) {
          // 1-to-1: hangup / teardown ends the call for the receiver.
          // (Behaviour unchanged.)
          await CallService.updateCallStatus(callId, 'ended');
        } else if (data != null) {
          final status = data['status'] as String?;
          if (CallService.terminalCallStatuses.contains(status)) {
            // The call already ended for everyone (authoritative hangup /
            // timeout / orphan kill): nothing more to record globally.
          } else if (data['callerId'] == currentUser?.uid) {
            // The CALLER hung up: the whole group call ends for everyone.
            await CallService.updateCallStatus(callId, 'ended');
          } else if ((CallBloc.instance.isCallActive &&
                  CallBloc.instance.activeCall?.callId == callId) ||
              CallService.recentlyDismissedLocalRing(callId)) {
            // Still inside the Flutter call page, or tearing down the leftover
            // CallKit ring right after an in-app join. Do not record "left".
            debugPrint(
                'Ignoring synthetic ended while joining/in call: $callId');
          } else {
            // A member's own teardown (hang-up / PiP close / native kill)
            // must NEVER write a global `ended` for a group — that would end
            // the live call for every other member. Record the member's leave
            // only; the caller or the "survivor" logic ends the group.
            if (currentUser != null) {
              await CallService.markGroupMemberOutcome(
                callId: callId,
                uid: currentUser.uid,
                outcome: 'left',
              );
            }
          }
        }
        // isGroup && doc unreadable: best-effort — never guess a global
        // terminal status for a group, just tear the local call down.
      } catch (e) {
        debugPrint('Failed to update Firestore on ended: $e');
      }
      await FlutterCallkitIncoming.endCall(callId);
      debugPrint('Ended call: $callId');
    }
  }
}

bool _extraBool(dynamic extra, String key) {
  if (extra is! Map) return false;
  final value = extra[key];
  return value == true || value?.toString() == 'true';
}

String? _extraString(dynamic extra, String key) {
  if (extra is! Map) return null;
  final value = extra[key]?.toString();
  if (value == null || value.isEmpty) return null;
  return value;
}

Future<DocumentSnapshot?> _readCallDoc(String callId) async {
  try {
    return await FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .get();
  } catch (e) {
    debugPrint('Failed to read call doc $callId: $e');
    return null;
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
