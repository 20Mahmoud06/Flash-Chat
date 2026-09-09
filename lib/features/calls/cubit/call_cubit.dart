import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../config/agora_config.dart';
import '../../../models/message_model.dart';
import '../../../services/presence/presence_service.dart';
import '../services/call_audio_manager.dart';
import '../services/call_notif.dart';
import 'call_state.dart';

class CallCubit extends Cubit<CallState> {
  RtcEngine? _engine;
  StreamSubscription<DocumentSnapshot>? _callStatusSubscription;
  bool _isEnding = false;
  DateTime? _connectedAt;

  /// How long the caller lets the recipient ring before giving up
  /// (Messenger-style no-answer timeout).
  static const Duration ringTimeout = Duration(seconds: 30);

  Timer? _ringTimeoutTimer;

  /// App-wide instance: the Agora engine must survive the call page being
  /// popped (voice-call minimize / video-call PiP), so the cubit lives at
  /// the app root instead of inside the page route.
  static final CallCubit instance = CallCubit();

  /// Whether the call page was dismissed but the call is still active
  /// (voice-call minimize). Restoring the page clears this.
  bool minimized = false;

  /// Metadata of the active call, used to reopen the call page after the
  /// user minimized it.
  CallInfo? activeCall;

  CallCubit() : super(CallInitial());

  // ===============================
  // 📱 APP-LEVEL LIFECYCLE
  // ===============================
  bool get isCallActive => _engine != null && !_isEnding;

  /// Clears the previous call so a new call can be started. Safe to call
  /// even after the page popped (the singleton is never disposed).
  void reset() {
    _callStatusSubscription?.cancel();
    _callStatusSubscription = null;
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _isEnding = false;
    _connectedAt = null;
    minimized = false;
    activeCall = null;
    // Defensive: ensure no call audio keeps playing across a reset/discard.
    CallAudioManager.instance.dispose();
    emit(CallInitial());
  }

  /// The user left the call page but the call keeps running.
  void minimize() {
    if (_engine == null || _isEnding) return;
    minimized = true;
  }

  /// The user returned to the call page.
  void restore() {
    minimized = false;
  }

  // ===============================
  // 🎥 VIDEO CALL INITIALIZATION
  // ===============================
  Future<void> initializeVideoCall({
    required String channelName,
    required String callId,
    required CallInfo info,
  }) async {
    reset();
    activeCall = info;
    emit(CallInitializing());

    try {
      // Request permissions
      final status = await [Permission.microphone, Permission.camera].request();
      if (!status.values.every((s) => s.isGranted)) {
        emit(const CallPermissionDenied(
          'Microphone and camera permissions needed for video call.',
        ));
        return;
      }

      // Initialize Agora Engine
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        const RtcEngineContext(
          appId: AgoraConfig.appId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );

      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      // Register event handlers
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            _updateJoinedState(true);
          },
          onUserJoined: (connection, uid, elapsed) {
            _addRemoteUser(uid);
          },
          onUserOffline: (connection, uid, reason) {
            _removeRemoteUser(uid);
          },
          onUserMuteVideo: (connection, remoteUid, muted) {
            _handleRemoteVideoMute(remoteUid, muted);
          },
          onRemoteVideoStateChanged:
              (connection, remoteUid, state, reason, elapsed) {
            if (reason ==
                RemoteVideoStateReason.remoteVideoStateReasonRemoteMuted) {
              _handleRemoteVideoMute(remoteUid, true);
            } else if (reason ==
                RemoteVideoStateReason.remoteVideoStateReasonRemoteUnmuted) {
              _handleRemoteVideoMute(remoteUid, false);
            }
          },
          onUserMuteAudio: (connection, remoteUid, muted) {
            _handleRemoteAudioMute(remoteUid, muted);
          },
          onAudioVolumeIndication:
              (connection, speakers, speakerNumber, totalVolume) {
            _handleAudioVolumeIndication(speakers);
          },
          onLeaveChannel: (connection, stats) {
            _updateJoinedState(false);
          },
          onError: (err, msg) {
            debugPrint('Agora Error: $err - $msg');
            emit(CallError('Call error: $msg'));
          },
        ),
      );

      // Enable video
      await _engine!.enableVideo();
      await _engine!.startPreview();
      // Enable per-user volume reporting so the UI can show who is speaking.
      await _enableVolumeIndication();

      // Join channel
      await _joinChannel(channelName);

      // Listen to call status
      _listenToCallStatus(callId);

      // Caller-side ring timeout + reachability (Messenger-style behaviour).
      await _startRingTimeout(callId);

      // The caller starts hearing the "waiting for answer" tone now; it stops
      // as soon as a remote user joins (see _addRemoteUser) or the call ends.
      _startWaitingToneIfCaller();
      emit(const CallEngineReady());
    } catch (e) {
      debugPrint('Agora init error: $e');
      _stopWaitingTone();
      emit(CallError('Failed to start video call: $e'));
    }
  }

  // ===============================
  // 🎙️ VOICE CALL INITIALIZATION
  // ===============================
  Future<void> initializeVoiceCall({
    required String channelName,
    required String callId,
    required CallInfo info,
  }) async {
    reset();
    activeCall = info;
    emit(CallInitializing());

    try {
      // Request permissions
      final status = await [Permission.microphone].request();
      if (!status.values.every((s) => s.isGranted)) {
        emit(const CallPermissionDenied(
            'Microphone permission needed for call.'));
        return;
      }

      // Initialize Agora Engine
      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        const RtcEngineContext(
          appId: AgoraConfig.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      // Register event handlers
      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) {
            _updateJoinedState(true);
          },
          onUserJoined: (connection, uid, elapsed) {
            _addRemoteUser(uid);
          },
          onUserOffline: (connection, uid, reason) {
            _removeRemoteUser(uid);
          },
          onUserMuteAudio: (connection, remoteUid, muted) {
            _handleRemoteAudioMute(remoteUid, muted);
          },
          onAudioVolumeIndication:
              (connection, speakers, speakerNumber, totalVolume) {
            _handleAudioVolumeIndication(speakers);
          },
          onLeaveChannel: (connection, stats) {
            _updateJoinedState(false);
          },
          onError: (err, msg) {
            debugPrint('Agora Error: $err - $msg');
            emit(CallError('Call error: $msg'));
          },
        ),
      );

      // Join channel
      await _joinChannel(channelName);

      // Listen to call status
      _listenToCallStatus(callId);

      // Caller-side ring timeout + reachability (Messenger-style behaviour).
      await _startRingTimeout(callId);

      // Enable per-user volume reporting so the UI can show who is speaking.
      await _enableVolumeIndication();

      // The caller starts hearing the "waiting for answer" tone now; it stops
      // as soon as a remote user joins (see _addRemoteUser) or the call ends.
      _startWaitingToneIfCaller();
      emit(const CallEngineReady());
    } catch (e) {
      debugPrint('Agora init error: $e');
      _stopWaitingTone();
      emit(CallError('Failed to start call: $e'));
    }
  }

  // ===============================
  // 🔗 JOIN CHANNEL
  // ===============================
  Future<void> _joinChannel(String channelName) async {
    const int expirationInSeconds = 3600;
    final myUid = _agoraUidFromFirebase(FirebaseAuth.instance.currentUser!.uid);

    final token = RtcTokenBuilder.buildTokenWithUid(
      appId: AgoraConfig.appId,
      appCertificate: AgoraConfig.appCertificate,
      channelName: channelName,
      uid: myUid,
      tokenExpireSeconds: expirationInSeconds,
    );

    await _engine!.joinChannel(
      token: token,
      channelId: channelName,
      uid: myUid,
      options: const ChannelMediaOptions(
        publishCameraTrack: true,
        publishMicrophoneTrack: true,
      ),
    );
  }

  // ===============================
  // 👂 LISTEN TO CALL STATUS
  // ===============================
  void _listenToCallStatus(String callId) {
    _callStatusSubscription = FirebaseFirestore.instance
        .collection('calls')
        .doc(callId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data != null) {
        final status = data['status'] as String?;
        if (status == 'ended') {
          endCall(callId, reason: 'ended');
        } else if (status == 'cancelled') {
          endCall(callId, reason: 'cancelled');
        } else if (status == 'declined' || status == 'rejected') {
          endCall(callId, reason: 'declined');
        } else if (status == 'busy') {
          endCall(callId, reason: 'busy');
        } else if (status == 'unavailable' || status == 'offline') {
          // The recipient is offline / not reachable, so the call can't
          // connect. Caller sees a clear "unavailable" message.
          endCall(callId, reason: 'unavailable');
        } else if (status == 'timeout' || status == 'no_answer') {
          // The caller missed the answer ("Timed Out"); the receiver who
          // opens the call afterwards sees a "Missed Call" instead.
          final callerId = data['callerId'] as String?;
          final isCaller = callerId != null &&
              callerId == FirebaseAuth.instance.currentUser?.uid;
          endCall(callId, reason: isCaller ? 'timeout' : 'missed');
        } else if (status == 'failed') {
          endCall(callId, reason: 'failed');
        }
      }
    });
  }

  // ===============================
  // ⏱️ RING TIMEOUT & REACHABILITY (caller side)
  // ===============================
  /// Whether the current user is the one who placed the call. The initiator
  /// drives the 30s no-answer timeout so the call never hangs when the
  /// receiver's device is offline, killed, or on an unsupported platform.
  bool get _isCaller => activeCall?.callerId == null;

  Future<void> _startRingTimeout(String callId) async {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;

    if (!_isCaller) {
      // Only the initiator enforces the ring timeout / reachability, so a
      // single writer updates the `calls` doc regardless of the receiver's
      // platform state (offline / killed / GMS / HMS).
      return;
    }

    // 1. Reachability: if the 1:1 recipient is provably offline at ring time,
    // don't ring forever — mark the call unavailable right away so the caller
    // gets a clear "user is offline / unavailable" message.
    await _checkReachability(callId);

    // 2. No-answer timeout: if nobody joins within [ringTimeout], end the
    // call with a "no answer" outcome (Messenger behaviour). Not started if
    // the reachability check already ended the call.
    if (_isEnding) return;
    _ringTimeoutTimer = Timer(ringTimeout, () => _handleRingTimeout(callId));
  }

  Future<void> _checkReachability(String callId) async {
    final info = activeCall;
    if (info == null || info.isGroup || info.peerUid == null) return;

    try {
      final offline = await PresenceService.instance.isOffline(info.peerUid!);
      if (!offline || _isEnding || _connectedAt != null) return;
      _ringTimeoutTimer?.cancel();
      _ringTimeoutTimer = null;
      debugPrint('Recipient offline — ending call as unavailable.');
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({'status': 'unavailable'});
      // End locally so the caller immediately sees the unavailable message
      // (the Firestore listener would also catch it, but we act now to avoid
      // a transient "ready" state flashing on the page).
      endCall(callId, reason: 'unavailable');
    } catch (e) {
      debugPrint('Reachability check failed: $e');
    }
  }

  Future<void> _handleRingTimeout(String callId) async {
    if (_isEnding || _connectedAt != null) return;
    if (state is! CallEngineReady) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .get();
      final status = (doc.data()?['status'] as String?) ?? 'ringing';
      if (status == 'ringing' || status == 'accepted') {
        // Nothing answered within 30s → no answer.
        await FirebaseFirestore.instance
            .collection('calls')
            .doc(callId)
            .update({'status': 'no_answer'});
        endCall(callId, reason: 'timeout');
      }
    } catch (e) {
      debugPrint('Ring timeout check failed (ending anyway): $e');
      endCall(callId, reason: 'timeout');
    }
  }

  // ===============================
  // 🎛️ CALL CONTROLS
  // ===============================
  void toggleMute() {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final newMuted = !current.isMuted;
      _engine?.muteLocalAudioStream(newMuted);
      emit(current.copyWith(isMuted: newMuted));
      // Keep the sticky voice-call notification's action label in sync.
      CallNotifBridge.instance.updateMute(newMuted);
    }
  }

  void toggleCamera() {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final newCameraOff = !current.isCameraOff;
      _engine?.muteLocalVideoStream(newCameraOff);
      emit(current.copyWith(isCameraOff: newCameraOff));
    }
  }

  void switchCamera() {
    _engine?.switchCamera();
  }

  // ===============================
  // 🔊 CALL UX AUDIO (side-effect of state)
  // ===============================
  //
  // The call state is the single source of truth. Audio only reacts to it:
  // these calls never decide whether the call is still active, and any
  // failure is swallowed by the manager so the call keeps working even if
  // the ringtone cannot play.

  /// Plays the outgoing "waiting for answer" tone for the caller while the
  /// channel is still ringing (no remote user joined). Only the initiator
  /// (caller) hears this; the receiver's ringing is handled natively by the
  /// CallKit plugin so this is never reproduced here.
  void _startWaitingToneIfCaller() {
    if (_isCaller) {
      CallAudioManager.instance.playWaitingRingtone();
    }
  }

  /// Stops the waiting tone. Safe to call on any connected or terminal
  /// transition, and safe to call repeatedly (idempotent).
  void _stopWaitingTone() {
    CallAudioManager.instance.stop();
  }

  // ===============================
  // 📞 END CALL
  // ===============================
  Future<void> endCall(String callId, {String? reason}) async {
    if (_isEnding) return;
    _isEnding = true;
    // Terminal state — the waiting tone must never survive the call ending.
    _stopWaitingTone();
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;

    final duration = _connectedAt != null
        ? DateTime.now().difference(_connectedAt!)
        : Duration.zero;

    // Hanging up before anyone joined means the call was cancelled rather
    // than completed.
    final finalReason =
        reason ?? (_connectedAt != null ? 'ended' : 'cancelled');

    // The reason surfaced in the "call ended / you left" overlay. For a group
    // call where a non-caller member leaves while others stay, we present it
    // as "left the call" instead of "call ended".
    String displayReason = finalReason;

    final info = activeCall;

    // For group calls, one participant hanging up must NOT end the call for
    // everyone on the call (WhatsApp/Messenger behaviour): only the caller
    // (host) or the last remaining participant ends the whole call. Everyone
    // else simply leaves the channel while the call keeps going.
    if (info != null && info.isGroup) {
      final doesEndGroupCall =
          await _groupHangupEndsCall(callId, info, finalReason);
      if (!doesEndGroupCall) {
        displayReason = 'left';
      }
    }

    minimized = false;
    // Remove the sticky voice-call notification (no-op for video/PiP calls).
    CallNotifBridge.instance.hide();
    emit(CallEnded(reason: displayReason, duration: duration));

    _callStatusSubscription?.cancel();

    final engine = _engine;
    _engine = null;
    try {
      if (engine != null) {
        await engine.leaveChannel();
        await engine.release();
      }
      // Always clear the platform call, even when the engine was already gone:
      // otherwise the CallKit ongoing "Calling…" notification started on accept
      // would linger after the call ended (or after a group member left).
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      debugPrint('Error ending call engine: $e');
    }

    // A group member left while the call continues: stop here — the call and
    // its Join-call card stay live for the remaining members, and no history
    // message is written.
    if (displayReason == 'left') {
      _isEnding = false;
      activeCall = null;
      return;
    }

    // Write the call-history message to the chat. Only the caller writes it
    // (single writer) so both participants end up sharing one message.
    //
    // The Join-call card deletion is handled separately below (it must run
    // even when a non-caller ends the call as the last participant).
    try {
      await _writeCallHistoryMessage(callId, finalReason, duration);
    } catch (e) {
      debugPrint('Error writing call history message: $e');
    }

    // The call has ended — remove the WhatsApp-style "Join call" card that
    // was written into the group chat when the call started, since it is no
    // longer valid. Runs for every participant that ends the call (host or
    // last member), not just the original caller.
    if (info != null && info.isGroup && info.groupId != null) {
      await _deleteActiveCallMessage(info.groupId!, callId);
    }

    try {
      // Only local user actions write the status: listener-driven reasons
      // (declined / busy / no_answer / failed) were already written by the
      // other side, so overwriting them with 'ended' would lose them.
      if (finalReason == 'cancelled' || finalReason == 'ended') {
        await FirebaseFirestore.instance
            .collection('calls')
            .doc(callId)
            .update({'status': finalReason});
      }
    } catch (e) {
      debugPrint('Error updating firestore call status: $e');
    }
  }

  /// Decides whether hanging up on a [group] call should end the entire call
  /// for everyone, or just leave the current participant. Returns true when
  /// the call should be fully ended (caller/host hangs up, or the last
  /// participant hangs up); false when the caller should just leave while the
  /// call continues. Also removes the current user from the participants,
  /// so the remaining members stay connected.
  Future<bool> _groupHangupEndsCall(
    String callId,
    CallInfo info,
    String finalReason,
  ) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    final myUid = currentUser?.uid;
    if (myUid == null) return true;

    DocumentSnapshot callDoc;
    try {
      callDoc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .get();
    } catch (e) {
      debugPrint('Failed to read call doc on hangup: $e');
      // Can't tell — fall back to ending the call.
      return true;
    }
    final data = callDoc.data() as Map<String, dynamic>?;
    if (data == null) return true;

    final callerId = (data['callerId'] as String?)?.trim();
    final participants =
        List<String>.from((data['participants'] as List?) ?? const []);

    // Remove the current user from the participants so the other members
    // know they left (idempotent array remove).
    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({
        'participants': FieldValue.arrayRemove([myUid]),
        if (finalReason == 'cancelled' || finalReason == 'ended')
          'participantStatus.$myUid': 'left',
      });
    } catch (e) {
      debugPrint('Failed to remove participant on hangup: $e');
    }

    final remaining = participants.where((p) => p != myUid).toSet();

    // The caller/host hanging up ends the call for everyone.
    final amCaller = myUid == callerId;
    if (amCaller) return true;

    // A non-caller member is the last one left → end the call.
    if (remaining.isEmpty) return true;

    // Otherwise other members are still connected — just leave, don't end.
    return false;
  }

  /// Writes a WhatsApp-style call-history message into the chat once the call
  /// ends. Only the caller writes (single-writer) so both participants share
  /// a single message. The bubble later renders it viewer-aware ("You" vs the
  /// caller's name) from [MessageModel.callerId].
  Future<void> _writeCallHistoryMessage(
    String callId,
    String finalReason,
    Duration duration,
  ) async {
    final info = activeCall;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (info == null || currentUser == null) return;

    // The truth about who placed the call lives on the `calls` doc (the page's
    // `callerId` param is null for the initiator), so read it there and make
    // this a single-writer operation: only the caller records the message.
    String? callerId;
    int offlineCount = 0;
    try {
      final callDoc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .get();
      callerId = (callDoc.data()?['callerId'] as String?)?.trim();

      // Group calls annotate members who were offline at call time so the
      // history summary can mention how many members never saw the call.
      if (info.isGroup) {
        final participantStatus =
            callDoc.data()?['participantStatus'] as Map<String, dynamic>?;
        if (participantStatus != null) {
          offlineCount = participantStatus.values
              .where((v) => v == 'offline')
              .length;
        }
      }
    } catch (e) {
      debugPrint('Error loading call doc for history message: $e');
      return;
    }
    if (callerId == null || callerId.isEmpty) return;
    if (callerId != currentUser.uid) return;

    // Map the raw end reason to a stored outcome.
    String outcome;
    switch (finalReason) {
      case 'declined':
      case 'rejected':
        outcome = 'declined';
        break;
      case 'busy':
        outcome = 'busy';
        break;
      case 'cancelled':
        outcome = 'cancelled';
        break;
      case 'missed':
        outcome = 'missed';
        break;
      case 'ended':
        outcome = 'completed';
        break;
      case 'unavailable':
      case 'offline':
      case 'timeout':
      case 'no_answer':
      case 'failed':
        // The call didn't go through — recorded as a missed call.
        outcome = 'missed';
        break;
      default:
        outcome = 'missed';
    }

    // Resolve the caller's display name (used for the sender of the shared
    // message the other participant sees).
    String callerName = info.displayName;
    try {
      final userDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(callerId)
          .get();
      if (userDoc.exists) {
        final data = userDoc.data() ?? {};
        callerName =
            '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
      }
    } catch (e) {
      debugPrint('Error loading caller name for history message: $e');
    }
    if (callerName.isEmpty) callerName = 'Unknown';

    // Resolve the destination chat (1:1 or group).
    final String collectionPath;
    final String chatId;
    if (info.isGroup) {
      if (info.groupId == null) return;
      collectionPath = 'groups';
      chatId = info.groupId!;
    } else {
      // 1:1: the channel name == the chat id (chat_<uid>_<uid>).
      collectionPath = 'chats';
      chatId = info.channelName;
    }

    final chatRef =
        FirebaseFirestore.instance.collection(collectionPath).doc(chatId);

    final messageData = <String, dynamic>{
      'senderId': callerId,
      'senderName': callerName,
      'recipientId': info.peerUid ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
      'reactions': {},
      'isDeleted': false,
      'isEdited': false,
      'messageType': MessageType.call.name,
      'callType': info.isVideo ? 'video' : 'voice',
      'callOutcome': outcome,
      'callDuration': duration.inSeconds,
      'callerId': callerId,
      if (info.isGroup && offlineCount > 0) 'offlineCount': offlineCount,
    };

    await chatRef.collection('messages').add(messageData);
  }

  /// Deletes the active-call ("Join call") card message for [groupId] that
  /// was written when the group call started. Matches by storing the callId
  /// in the message's `text` field, so we never touch unrelated messages.
  ///
  /// Uses a single-field query (auto-indexed) and filters in Dart to avoid
  /// requiring a new composite index in the Firestore console.
  Future<void> _deleteActiveCallMessage(String groupId, String callId) async {
    try {
      final query = await FirebaseFirestore.instance
          .collection('groups')
          .doc(groupId)
          .collection('messages')
          .where('messageType', isEqualTo: MessageType.callActive.name)
          .limit(20)
          .get();
      for (final doc in query.docs) {
        if (doc.data()['text'] == callId) {
          await doc.reference.delete();
          break;
        }
      }
    } catch (e) {
      debugPrint('Failed to delete active call message: $e');
    }
  }

  // ===============================
  // 🔄 STATE UPDATES
  // ===============================
  void _updateJoinedState(bool joined) {
    if (_isEnding) return;
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      emit(current.copyWith(isJoined: joined));
    }
  }

  void _addRemoteUser(int uid) {
    _connectedAt ??= DateTime.now();
    // The ring timeout is no longer relevant.
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    if (_isEnding) return;
    // Someone joined: the call is connected, so the caller's waiting tone
    // stops. No-op for the receiver (nothing ever started).
    _stopWaitingTone();
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final updatedUids = [...current.remoteUids, uid];
      emit(current.copyWith(remoteUids: updatedUids));
    }
  }

  void _removeRemoteUser(int uid) {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final updatedUids = current.remoteUids.where((u) => u != uid).toList();
      final updatedMutedVideo = Set<int>.from(current.mutedRemoteUids)
        ..remove(uid);
      final updatedMutedAudio = Set<int>.from(current.mutedRemoteAudioUids)
        ..remove(uid);
      final updatedSpeaking = Set<int>.from(current.speakingUids)
        ..remove(uid);
      emit(current.copyWith(
        remoteUids: updatedUids,
        mutedRemoteUids: updatedMutedVideo,
        mutedRemoteAudioUids: updatedMutedAudio,
        speakingUids: updatedSpeaking,
      ));
    }
  }

  void _handleRemoteVideoMute(int remoteUid, bool muted) {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final updatedMuted = Set<int>.from(current.mutedRemoteUids);
      if (muted) {
        updatedMuted.add(remoteUid);
      } else {
        updatedMuted.remove(remoteUid);
      }
      emit(current.copyWith(mutedRemoteUids: updatedMuted));
    }
  }

  void _handleRemoteAudioMute(int remoteUid, bool muted) {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final updatedMuted = Set<int>.from(current.mutedRemoteAudioUids);
      if (muted) {
        updatedMuted.add(remoteUid);
      } else {
        updatedMuted.remove(remoteUid);
      }
      emit(current.copyWith(mutedRemoteAudioUids: updatedMuted));
    }
  }

  // ===============================
  // 🗣️ WHO IS SPEAKING
  // ===============================

  /// Minimum per-user volume (0-255) before a participant can be considered
  /// "speaking". Filters out mic noise/ambience (a resting phone easily leaks
  /// 5-20) so the indicator only lights for actual speech.
  static const int _speakingThreshold = 25;

  Future<void> _enableVolumeIndication() async {
    try {
      await _engine?.enableAudioVolumeIndication(
        interval: 200,
        smooth: 3,
        reportVad: true,
      );
    } catch (e) {
      debugPrint('Failed to enable audio volume indication: $e');
    }
  }

  void _handleAudioVolumeIndication(List<AudioVolumeInfo> speakers) {
    if (state is! CallEngineReady) return;
    final current = state as CallEngineReady;

    // Eligible participants: every remote in the grid (when not audio-muted)
    // plus the local user (uid 0, only while the local mic is unmuted).
    // Ignoring unknown uids prevents a phantom indicator when the SDK reports
    // a user the grid does not know about.
    bool eligible(int? uid) {
      if (uid == null) return false;
      if (uid == 0) return !current.isMuted;
      return current.remoteUids.contains(uid) &&
          !current.mutedRemoteAudioUids.contains(uid);
    }

    // Only the SINGLE loudest speaker above the threshold is highlighted, so
    // the indicator is tied to the person actually talking instead of lighting
    // every tile whose mic leaks noise (old behaviour). speech has pauses, but
    // Agora's `smooth: 3` averages the volumes so the loudest is stable.
    AudioVolumeInfo? loudest;
    for (final s in speakers) {
      final volume = s.volume ?? 0;
      if (!eligible(s.uid) || volume < _speakingThreshold) continue;
      if (loudest == null || volume > (loudest.volume ?? 0)) loudest = s;
    }

    final speaking = <int>{if (loudest != null) loudest.uid!};
    // Only rebuild when the set actually changed (this fires every 200ms).
    if (speaking.length != current.speakingUids.length ||
        !speaking.containsAll(current.speakingUids)) {
      emit(current.copyWith(speakingUids: speaking));
    }
  }

  // ===============================
  // 🛠️ HELPERS
  // ===============================
  int _agoraUidFromFirebase(String uid) {
    return uid.hashCode & 0x7fffffff;
  }

  RtcEngine? get engine => _engine;

  /// The moment the remote party joined (used by the sticky call
  /// notification's live timer). Null while the call is still ringing.
  DateTime? get connectedAt => _connectedAt;

  // ===============================
  // 🧹 CLEANUP
  // ===============================
  @override
  Future<void> close() {
    // The singleton must never be closed by a page popping; the engine is
    // released inside [endCall]. close() still cleans up defensively.
    _callStatusSubscription?.cancel();
    _callStatusSubscription = null;
    if (_engine != null) {
      try {
        _engine!.release();
      } catch (_) {}
      _engine = null;
    }
    return super.close();
  }
}

/// Metadata needed to reopen a minimized call's page (via the global
/// "call in progress" pill) and to rebuild the same Agora channel name.
class CallInfo {
  final bool isGroup;
  final bool isVideo;
  final String channelName;
  final String callId;

  /// 1:1 calls: uid of the other party (needed by [buildChannelName]).
  final String? peerUid;

  /// Group calls: the group id.
  final String? groupId;

  final String displayName;
  final String? avatarEmoji;

  /// Uid of the user who placed the call (needed to write the call-history
  /// message and to show the correct caller name to both participants).
  final String? callerId;

  const CallInfo({
    required this.isGroup,
    required this.isVideo,
    required this.channelName,
    required this.callId,
    this.peerUid,
    this.groupId,
    required this.displayName,
    this.avatarEmoji,
    this.callerId,
  });
}
