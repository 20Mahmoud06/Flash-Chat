import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';
import '../../../config/agora_config.dart';
import '../../../core/utils/friendly_error_messages.dart';
import '../../chat/models/message_model.dart';
import '../../../services/presence/presence_service.dart';
import '../models/call_info.dart';
import '../services/call_audio_manager.dart';
import '../services/call_notif.dart';
import '../services/call_service.dart';
import 'call_event.dart';
import 'call_state.dart';

class CallBloc extends Bloc<CallEvent, CallState> {
  // ──────────────────────────────────────────────────────────────────────
  // INTERNAL STATE
  // ──────────────────────────────────────────────────────────────────────
  RtcEngine? _engine;
  StreamSubscription<DocumentSnapshot>? _callStatusSubscription;
  bool _isEnding = false;
  DateTime? _connectedAt;

  /// How long the caller lets the recipient ring before giving up
  /// (Messenger-style no-answer timeout).
  static const Duration ringTimeout = Duration(seconds: 30);

  Timer? _ringTimeoutTimer;

  /// Minimum per-user volume (0-255) before a participant can be considered
  /// "speaking". Filters out mic noise/ambience (a resting phone easily leaks
  /// 5-20) so the indicator only lights for actual speech.
  static const int _speakingThreshold = 20;

  // ──────────────────────────────────────────────────────────────────────
  // PUBLIC API (preserves the app's existing call-management surface)
  // ──────────────────────────────────────────────────────────────────────

  /// App-wide instance: the Agora engine must survive the call page being
  /// popped (voice-call minimize / video-call PiP), so the bloc lives at
  /// the app root instead of inside the page route.
  static final CallBloc instance = CallBloc();

  /// Whether the call page was dismissed but the call is still active
  /// (voice-call minimize). Restoring the page clears this.
  bool minimized = false;

  /// Metadata of the active call, used to reopen the call page after the
  /// user minimized it.
  CallInfo? activeCall;

  // ──────────────────────────────────────────────────────────────────────
  // GETTERS
  // ──────────────────────────────────────────────────────────────────────
  bool get isCallActive => _engine != null && !_isEnding;

  RtcEngine? get engine => _engine;

  /// The moment the remote party joined (used by the sticky call
  /// notification's live timer). Null while the call is still ringing.
  DateTime? get connectedAt => _connectedAt;

  /// Whether the current user is the one who placed the call. The initiator
  /// drives the 30s no-answer timeout so the call never hangs when the
  /// receiver's device is offline, killed, or on an unsupported platform.
  bool get _isCaller => activeCall?.callerId == null;

  // ──────────────────────────────────────────────────────────────────────
  // BLOC REGISTRATION
  // ──────────────────────────────────────────────────────────────────────
  CallBloc() : super(CallInitial()) {
    // User-initiated
    on<CallReset>(_onReset);
    on<CallInitVideo>(_onInitVideo);
    on<CallInitVoice>(_onInitVoice);
    on<CallToggleMute>(_onToggleMute);
    on<CallToggleCamera>(_onToggleCamera);
    on<CallSwitchCamera>((event, emit) {
      _engine?.switchCamera();
    });
    on<CallMinimize>(_onMinimize);
    on<CallRestore>(_onRestore);
    on<CallEnd>(_onEnd);

    // Engine-driven
    on<CallJoinStateChanged>(_onJoinStateChanged);
    on<CallRemoteUserJoined>(_onRemoteUserJoined);
    on<CallRemoteUserLeft>(_onRemoteUserLeft);
    on<CallRemoteVideoMuted>(_onRemoteVideoMuted);
    on<CallRemoteAudioMuted>(_onRemoteAudioMuted);
    on<CallAudioVolumeChanged>(_onAudioVolumeChanged);
    on<CallEngineError>(_onEngineError);
  }

  // ──────────────────────────────────────────────────────────────────────
  // PUBLIC DISPATCHERS (thin wrappers preserving the app's existing API)
  // ──────────────────────────────────────────────────────────────────────
  void reset() => add(const CallReset());

  /// The user left the call page but the call keeps running.
  void minimize() => add(const CallMinimize());

  /// The user returned to the call page.
  void restore() => add(const CallRestore());

  void toggleMute() => add(const CallToggleMute());

  void toggleCamera() => add(const CallToggleCamera());

  void switchCamera() => add(const CallSwitchCamera());

  void endCall(String callId, {String? reason}) =>
      add(CallEnd(callId, reason: reason));

  Future<void> initializeVideoCall({
    required String channelName,
    required String callId,
    required CallInfo info,
  }) {
    add(CallInitVideo(channelName: channelName, callId: callId, info: info));
    return Future.value();
  }

  Future<void> initializeVoiceCall({
    required String channelName,
    required String callId,
    required CallInfo info,
  }) {
    add(CallInitVoice(channelName: channelName, callId: callId, info: info));
    return Future.value();
  }

  // ──────────────────────────────────────────────────────────────────────
  // USER-INITIATED HANDLERS
  // ──────────────────────────────────────────────────────────────────────

  void _onReset(CallReset event, Emitter<CallState> emit) {
    _resetFields();
    emit(CallInitial());
  }

  Future<void> _onInitVideo(
    CallInitVideo event,
    Emitter<CallState> emit,
  ) async {
    _resetFields();
    emit(CallInitial());
    activeCall = event.info;
    emit(CallInitializing());

    try {
      final status =
          await [Permission.microphone, Permission.camera].request();
      if (!status.values.every((s) => s.isGranted)) {
        emit(const CallPermissionDenied(
          'Microphone and camera permissions needed for video call.',
        ));
        return;
      }

      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: AgoraConfig.appId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );

      await _engine!.setClientRole(role: ClientRoleType.clientRoleBroadcaster);

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) =>
              add(const CallJoinStateChanged(true)),
          onUserJoined: (connection, uid, elapsed) =>
              add(CallRemoteUserJoined(uid)),
          onUserOffline: (connection, uid, reason) =>
              add(CallRemoteUserLeft(uid)),
          onUserMuteVideo: (connection, remoteUid, muted) =>
              add(CallRemoteVideoMuted(remoteUid, muted)),
          onRemoteVideoStateChanged:
              (connection, remoteUid, state, reason, elapsed) {
            if (reason ==
                RemoteVideoStateReason
                    .remoteVideoStateReasonRemoteMuted) {
              add(CallRemoteVideoMuted(remoteUid, true));
            } else if (reason ==
                RemoteVideoStateReason
                    .remoteVideoStateReasonRemoteUnmuted) {
              add(CallRemoteVideoMuted(remoteUid, false));
            }
          },
          onUserMuteAudio: (connection, remoteUid, muted) =>
              add(CallRemoteAudioMuted(remoteUid, muted)),
          onAudioVolumeIndication:
              (connection, speakers, speakerNumber, totalVolume) {
            add(CallAudioVolumeChanged(speakers));
          },
          onLeaveChannel: (connection, stats) =>
              add(const CallJoinStateChanged(false)),
          onError: (err, msg) {
            debugPrint('Agora Error: $err - $msg');
            add(CallEngineError(msg));
          },
        ),
      );

      await _engine!.enableVideo();
      await _engine!.startPreview();
      await _enableVolumeIndication();
      await _joinChannel(event.channelName);
      _listenToCallStatus(event.callId);
      await _startRingTimeout(event.callId);
      _startWaitingToneIfCaller();
      emit(const CallEngineReady());
    } catch (e) {
      debugPrint('Agora init error: $e');
      _stopWaitingTone();
      emit(CallError(friendlyErrorMessage(
          e, fallback: 'Could not start the video call. Please try again.')));
    }
  }

  Future<void> _onInitVoice(
    CallInitVoice event,
    Emitter<CallState> emit,
  ) async {
    _resetFields();
    emit(CallInitial());
    activeCall = event.info;
    emit(CallInitializing());

    try {
      final status = await [Permission.microphone].request();
      if (!status.values.every((s) => s.isGranted)) {
        emit(const CallPermissionDenied(
            'Microphone permission needed for call.'));
        return;
      }

      _engine = createAgoraRtcEngine();
      await _engine!.initialize(
        RtcEngineContext(
          appId: AgoraConfig.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      _engine!.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (connection, elapsed) =>
              add(const CallJoinStateChanged(true)),
          onUserJoined: (connection, uid, elapsed) =>
              add(CallRemoteUserJoined(uid)),
          onUserOffline: (connection, uid, reason) =>
              add(CallRemoteUserLeft(uid)),
          onUserMuteAudio: (connection, remoteUid, muted) =>
              add(CallRemoteAudioMuted(remoteUid, muted)),
          onAudioVolumeIndication:
              (connection, speakers, speakerNumber, totalVolume) {
            add(CallAudioVolumeChanged(speakers));
          },
          onLeaveChannel: (connection, stats) =>
              add(const CallJoinStateChanged(false)),
          onError: (err, msg) {
            debugPrint('Agora Error: $err - $msg');
            add(CallEngineError(msg));
          },
        ),
      );

      await _joinChannel(event.channelName);
      _listenToCallStatus(event.callId);
      await _startRingTimeout(event.callId);
      await _enableVolumeIndication();
      _startWaitingToneIfCaller();
      emit(const CallEngineReady());
    } catch (e) {
      debugPrint('Agora init error: $e');
      _stopWaitingTone();
      emit(CallError(friendlyErrorMessage(
          e, fallback: 'Could not start the call. Please try again.')));
    }
  }

  void _onToggleMute(CallToggleMute event, Emitter<CallState> emit) {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final newMuted = !current.isMuted;
      _engine?.muteLocalAudioStream(newMuted);
      final updatedSpeaking = newMuted
          ? (Set<int>.from(current.speakingUids)..remove(0))
          : current.speakingUids;
      emit(current.copyWith(
        isMuted: newMuted,
        speakingUids: updatedSpeaking,
      ));
      CallNotifBridge.instance.updateMute(newMuted);
    }
  }

  void _onToggleCamera(CallToggleCamera event, Emitter<CallState> emit) {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final newCameraOff = !current.isCameraOff;
      _engine?.muteLocalVideoStream(newCameraOff);
      emit(current.copyWith(isCameraOff: newCameraOff));
    }
  }

  void _onMinimize(CallMinimize event, Emitter<CallState> emit) {
    if (_engine == null || _isEnding) return;
    minimized = true;
  }

  void _onRestore(CallRestore event, Emitter<CallState> emit) {
    minimized = false;
  }

  // ──────────────────────────────────────────────────────────────────────
  // END CALL
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _onEnd(CallEnd event, Emitter<CallState> emit) async {
    final callId = event.callId;
    final reason = event.reason;

    if (_isEnding) return;
    _isEnding = true;

    // Mark the call as locally handled BEFORE the Firestore write so the
    // incoming-call snapshot listener never re-presents this call's ring,
    // even if the hangup write fails in release mode.
    CallService.markCallHandled(callId);

    _stopWaitingTone();
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;

    final duration = _connectedAt != null
        ? DateTime.now().difference(_connectedAt!)
        : Duration.zero;

    final finalReason =
        reason ?? (_connectedAt != null ? 'ended' : 'cancelled');

    String displayReason = finalReason;

    final info = activeCall;

    if (info != null && info.isGroup) {
      final doesEndGroupCall =
          await _groupHangupEndsCall(callId, info, finalReason);
      if (!doesEndGroupCall) {
        displayReason = 'left';
      }
    }

    minimized = false;
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
      await FlutterCallkitIncoming.endCall(callId);
    } catch (e) {
      debugPrint('Error ending call engine: $e');
    }

    if (displayReason == 'left') {
      _isEnding = false;
      activeCall = null;
      return;
    }

    try {
      await _writeCallHistoryMessage(callId, finalReason, duration);
    } catch (e) {
      debugPrint('Error writing call history message: $e');
    }

    if (info != null && info.isGroup && info.groupId != null) {
      await _deleteActiveCallMessage(info.groupId!, callId);
    }

    try {
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

  // ──────────────────────────────────────────────────────────────────────
  // ENGINE-FIRED HANDLERS
  // ──────────────────────────────────────────────────────────────────────

  void _onJoinStateChanged(
    CallJoinStateChanged event,
    Emitter<CallState> emit,
  ) {
    if (_isEnding) return;
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      emit(current.copyWith(isJoined: event.joined));
    }
  }

  void _onRemoteUserJoined(
    CallRemoteUserJoined event,
    Emitter<CallState> emit,
  ) {
    _connectedAt ??= DateTime.now();
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    if (_isEnding) return;
    _stopWaitingTone();
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final updatedUids = [...current.remoteUids, event.uid];
      emit(current.copyWith(
        remoteUids: updatedUids,
        hadRemoteUser: true,
      ));
      _connectedAt ??= DateTime.now();
    }
  }

  void _onRemoteUserLeft(
    CallRemoteUserLeft event,
    Emitter<CallState> emit,
  ) {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final updatedUids = current.remoteUids.where((u) => u != event.uid).toList();
      final updatedMutedVideo = Set<int>.from(current.mutedRemoteUids)
        ..remove(event.uid);
      final updatedMutedAudio = Set<int>.from(current.mutedRemoteAudioUids)
        ..remove(event.uid);
      final updatedSpeaking = Set<int>.from(current.speakingUids)
        ..remove(event.uid);
      emit(current.copyWith(
        remoteUids: updatedUids,
        mutedRemoteUids: updatedMutedVideo,
        mutedRemoteAudioUids: updatedMutedAudio,
        speakingUids: updatedSpeaking,
      ));

      // Group safety net: when the channel empties, don't leave the survivor
      // stuck on "Waiting for others…". Verify the call doc — if no OTHER
      // participant remains, end the call locally even when the leaver's
      // terminal Firestore write was lost (offline hangup, killed app, or a
      // failed read/write during their hangup).
      if (updatedUids.isEmpty) {
        unawaited(_maybeEndGroupWhenAlone());
      }
    }
  }

  /// Ends the local call when this is a GROUP call whose channel just emptied
  /// and no other participant remains in Firestore. Prevents the 2-person
  /// group-call dead-end where the survivor is left viewing "Waiting for
  /// others…" forever because the leaver's hangup write never landed.
  Future<void> _maybeEndGroupWhenAlone() async {
    final info = activeCall;
    if (info == null || !info.isGroup || _isEnding) return;

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    try {
      final doc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(info.callId)
          .get();
      final status = (doc.data()?['status'] as String?) ?? 'ended';
      // Still an active call on paper but nobody else is a participant: the
      // terminal write never reached Firestore. End it somewhere.
      if (status == 'ringing' || status == 'accepted') {
        final participants = List<String>.from(
          doc.data()?['participants'] as List? ?? const <String>[],
        );
        final others = participants.where((p) => p != myUid).toList();
        if (others.isEmpty) {
          debugPrint(
              'Group channel empty with no other participants — ending call.');
          add(CallEnd(info.callId, reason: 'ended'));
        } else {
          // Someone else is still a participant; give the normal Firestore
          // 'ended' write from their hangup time to arrive before deciding.
          await Future<void>.delayed(const Duration(milliseconds: 1500));
          if ((state is CallEngineReady) &&
              (state as CallEngineReady).remoteUids.isEmpty &&
              !_isEnding) {
            add(CallEnd(info.callId, reason: 'ended'));
          }
        }
      }
    } catch (e) {
      debugPrint('Failed to verify group end state: $e');
    }
  }

  void _onRemoteVideoMuted(
    CallRemoteVideoMuted event,
    Emitter<CallState> emit,
  ) {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final updatedMuted = Set<int>.from(current.mutedRemoteUids);
      if (event.muted) {
        updatedMuted.add(event.uid);
      } else {
        updatedMuted.remove(event.uid);
      }
      emit(current.copyWith(mutedRemoteUids: updatedMuted));
    }
  }

  void _onRemoteAudioMuted(
    CallRemoteAudioMuted event,
    Emitter<CallState> emit,
  ) {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      final updatedMuted = Set<int>.from(current.mutedRemoteAudioUids);
      final updatedSpeaking = Set<int>.from(current.speakingUids);
      if (event.muted) {
        updatedMuted.add(event.uid);
        updatedSpeaking.remove(event.uid);
      } else {
        updatedMuted.remove(event.uid);
      }
      emit(current.copyWith(
        mutedRemoteAudioUids: updatedMuted,
        speakingUids: updatedSpeaking,
      ));
    }
  }

  void _onAudioVolumeChanged(
    CallAudioVolumeChanged event,
    Emitter<CallState> emit,
  ) {
    if (state is! CallEngineReady) return;
    final current = state as CallEngineReady;

    int myUid = 0;
    try {
      final user = FirebaseAuth.instance.currentUser;
      if (user != null) {
        myUid = _agoraUidFromFirebase(user.uid);
      }
    } catch (_) {}

    // 1. Separate local vs remote speaker reports.
    AudioVolumeInfo? localInfo;
    final List<AudioVolumeInfo> remoteSpeakers = [];

    for (final s in event.speakers) {
      final uid = s.uid;
      if (uid == null || uid == 0 || (myUid != 0 && uid == myUid)) {
        localInfo ??= s;
      } else {
        remoteSpeakers.add(s);
      }
    }

    // 2. Evaluate local speaking status.
    // Agora triggers two independent callbacks:
    // - One for local user (contains localInfo).
    // - One for remote users (does NOT contain localInfo).
    // If localInfo is present, update local speaking state based on VAD and volume.
    // Otherwise, preserve the current local speaking state.
    final bool hasLocalReport = localInfo != null;
    final bool isLocalSpeaking;
    if (hasLocalReport) {
      if (current.isMuted) {
        isLocalSpeaking = false;
      } else {
        final volume = localInfo.volume ?? 0;
        final vad = localInfo.vad;
        // VAD = 1 indicates genuine voice activity from the local user into the mic.
        // If VAD is 0, local user is silent (e.g. ambient noise or speaker acoustic feedback).
        if (vad != null) {
          isLocalSpeaking = vad == 1 && volume >= _speakingThreshold;
        } else {
          isLocalSpeaking = volume >= _speakingThreshold;
        }
      }
    } else {
      isLocalSpeaking = current.speakingUids.contains(0);
    }

    // 3. Evaluate remote speaking status.
    // If event.speakers is empty, Agora is signaling no remote user is speaking.
    // If remoteSpeakers is not empty, Agora is reporting remote speaker volumes.
    // If localInfo is present and remoteSpeakers is empty, this is a local-only
    // callback from Agora, so we MUST preserve the remote speaking status.
    final Set<int> newSpeaking = <int>{};
    if (isLocalSpeaking) {
      newSpeaking.add(0);
    }

    final bool isLocalOnlyCallback = hasLocalReport && remoteSpeakers.isEmpty;
    if (isLocalOnlyCallback) {
      // Preserve currently speaking remote users
      for (final uid in current.speakingUids) {
        if (uid != 0 &&
            current.remoteUids.contains(uid) &&
            !current.mutedRemoteAudioUids.contains(uid)) {
          newSpeaking.add(uid);
        }
      }
    } else {
      // Fresh remote report: add all remote users whose volume is above threshold
      for (final s in remoteSpeakers) {
        final uid = s.uid;
        if (uid == null) continue;
        final volume = s.volume ?? 0;
        if (volume >= _speakingThreshold &&
            current.remoteUids.contains(uid) &&
            !current.mutedRemoteAudioUids.contains(uid)) {
          newSpeaking.add(uid);
        }
      }
    }

    // 4. Emit update only if speaking set changed.
    if (newSpeaking.length != current.speakingUids.length ||
        !newSpeaking.containsAll(current.speakingUids)) {
      emit(current.copyWith(speakingUids: newSpeaking));
    }
  }

  void _onEngineError(
    CallEngineError event,
    Emitter<CallState> emit,
  ) {
    emit(CallError(friendlyErrorMessage(
        event.message, fallback: 'The call ran into a problem. Please try again.')));
  }

  // ──────────────────────────────────────────────────────────────────────
  // PRIVATE HELPERS (no emit)
  // ──────────────────────────────────────────────────────────────────────

  void _resetFields() {
    _callStatusSubscription?.cancel();
    _callStatusSubscription = null;
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;
    _isEnding = false;
    _connectedAt = null;
    minimized = false;
    activeCall = null;
    CallAudioManager.instance.dispose();
  }

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
          add(CallEnd(callId, reason: 'ended'));
        } else if (status == 'cancelled') {
          add(CallEnd(callId, reason: 'cancelled'));
        } else if (status == 'declined' || status == 'rejected') {
          add(CallEnd(callId, reason: 'declined'));
        } else if (status == 'busy') {
          add(CallEnd(callId, reason: 'busy'));
        } else if (status == 'unavailable' || status == 'offline') {
          add(CallEnd(callId, reason: 'unavailable'));
        } else if (status == 'timeout' || status == 'no_answer') {
          final callerId = data['callerId'] as String?;
          final isCaller = callerId != null &&
              callerId == FirebaseAuth.instance.currentUser?.uid;
          add(CallEnd(callId, reason: isCaller ? 'timeout' : 'missed'));
        } else if (status == 'failed') {
          add(CallEnd(callId, reason: 'failed'));
        }
      }
    });
  }

  // ──────────────────────────────────────────────────────────────────────
  // RING TIMEOUT & REACHABILITY (caller side)
  // ──────────────────────────────────────────────────────────────────────

  Future<void> _startRingTimeout(String callId) async {
    _ringTimeoutTimer?.cancel();
    _ringTimeoutTimer = null;

    if (!_isCaller) {
      return;
    }

    await _checkReachability(callId);

    if (_isEnding) return;
    _ringTimeoutTimer = Timer(ringTimeout, () => _handleRingTimeout(callId));
  }

  Future<void> _checkReachability(String callId) async {
    final info = activeCall;
    if (info == null || info.isGroup || info.peerUid == null) return;

    try {
      final offline =
          await PresenceService.instance.isOffline(info.peerUid!);
      if (!offline || _isEnding || _connectedAt != null) return;
      _ringTimeoutTimer?.cancel();
      _ringTimeoutTimer = null;
      debugPrint('Recipient offline — ending call as unavailable.');
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({'status': 'unavailable'});
      add(CallEnd(callId, reason: 'unavailable'));
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

      // Other participants are ALREADY actively in this call (someone joined
      // Agora but their arrival didn't cancel our timer): never kill a live
      // group call under them.
      final participants = List<String>.from(
        doc.data()?['participants'] as List? ?? const <String>[],
      );
      final currentUser = FirebaseAuth.instance.currentUser?.uid;
      final othersEngaged =
          participants.any((uid) => uid != currentUser);

      if (status == 'ringing' || !othersEngaged) {
        await FirebaseFirestore.instance
            .collection('calls')
            .doc(callId)
            .update({'status': 'no_answer'});
        add(CallEnd(callId, reason: 'timeout'));
      }
    } catch (e) {
      debugPrint('Ring timeout check failed (ending anyway): $e');
      add(CallEnd(callId, reason: 'timeout'));
    }
  }

  // ──────────────────────────────────────────────────────────────────────
  // CALL UX AUDIO
  // ──────────────────────────────────────────────────────────────────────

  void _startWaitingToneIfCaller() {
    if (_isCaller) {
      CallAudioManager.instance.playWaitingRingtone();
    }
  }

  void _stopWaitingTone() {
    CallAudioManager.instance.stop();
  }

  // ──────────────────────────────────────────────────────────────────────
  // GROUP HANGUP / HISTORY / HELPERS
  // ──────────────────────────────────────────────────────────────────────

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
      // Can't tell who else is still in the call — fall back to ending it.
      // Ending is the safe default: leaving the call open would strand the
      // remaining participant(s) on a dead "Waiting for others…" default.
      return true;
    }
    final data = callDoc.data() as Map<String, dynamic>?;
    if (data == null) return true;

    final callerId = (data['callerId'] as String?)?.trim();
    final participants =
        List<String>.from((data['participants'] as List?) ?? const []);

    // How many OTHER people are still in the call after I leave.
    final remaining = participants.where((p) => p != myUid).toSet();

    try {
      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({
        'participants': FieldValue.arrayRemove([myUid]),
        // Always record WHY I'm gone so the call history / UI can explain it.
        // (No longer gated on the final reason being cancelled/ended.)
        'participantStatus.$myUid': 'left',
        // NOTE: `memberUids` (the call's read/query roster) is deliberately
        // NOT touched here. Removing a leaver from it makes GroupCallTracker,
        // the incoming-call listener and the accepted-call recovery all lose
        // the terminal-state transition for that user and desync from reality.
      });
    } catch (e) {
      debugPrint('Failed to remove participant on hangup: $e');
    }

    final amCaller = myUid == callerId;
    if (amCaller) return true;

    // A group call only keeps running while at least two people are still in
    // it. When the last other participant leaves — the classic 2-person
    // group — the call ENDS for everyone instead of leaving the survivor
    // stuck on a dead "ringing" call with an orphaned "Join call" card.
    if (remaining.length >= 2) return false;
    return true;
  }

  Future<void> _writeCallHistoryMessage(
    String callId,
    String finalReason,
    Duration duration,
  ) async {
    final info = activeCall;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (info == null || currentUser == null) return;

    String? callerId;
    int offlineCount = 0;
    try {
      final callDoc = await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .get();
      callerId = (callDoc.data()?['callerId'] as String?)?.trim();

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
        outcome = 'missed';
        break;
      default:
        outcome = 'missed';
    }

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

    final String collectionPath;
    final String chatId;
    if (info.isGroup) {
      if (info.groupId == null) return;
      collectionPath = 'groups';
      chatId = info.groupId!;
    } else {
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
      'starredBy': [],
      'deletedForMe': [],
      'imageReactions': {},
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

  int _agoraUidFromFirebase(String uid) {
    return uid.hashCode & 0x7fffffff;
  }

  // ──────────────────────────────────────────────────────────────────────
  // CLEANUP
  // ──────────────────────────────────────────────────────────────────────
  @override
  Future<void> close() {
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
