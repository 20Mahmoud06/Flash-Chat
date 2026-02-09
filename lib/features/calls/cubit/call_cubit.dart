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
import 'call_state.dart';

class CallCubit extends Cubit<CallState> {
  RtcEngine? _engine;
  StreamSubscription<DocumentSnapshot>? _callStatusSubscription;

  CallCubit() : super(CallInitial());

  // ===============================
  // 🎥 VIDEO CALL INITIALIZATION
  // ===============================
  Future<void> initializeVideoCall({
    required String channelName,
    required String callId,
  }) async {
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

      // Join channel
      await _joinChannel(channelName);

      // Listen to call status
      _listenToCallStatus(callId);

      emit(const CallEngineReady());
    } catch (e) {
      debugPrint('Agora init error: $e');
      emit(CallError('Failed to start video call: $e'));
    }
  }

  // ===============================
  // 🎙️ VOICE CALL INITIALIZATION
  // ===============================
  Future<void> initializeVoiceCall({
    required String channelName,
    required String callId,
  }) async {
    emit(CallInitializing());

    try {
      // Request permissions
      final status = await [Permission.microphone].request();
      if (!status.values.every((s) => s.isGranted)) {
        emit(const CallPermissionDenied('Microphone permission needed for call.'));
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

      emit(const CallEngineReady());
    } catch (e) {
      debugPrint('Agora init error: $e');
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
      if (data != null && data['status'] == 'ended') {
        endCall(callId);
      }
    });
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
  // 📞 END CALL
  // ===============================
  Future<void> endCall(String callId) async {
    if (_engine == null) {
      emit(CallEnded());
      return;
    }

    try {
      await _engine!.leaveChannel();

      await FirebaseFirestore.instance
          .collection('calls')
          .doc(callId)
          .update({'status': 'ended'});

      await FlutterCallkitIncoming.endCall(callId);

      await _engine!.release();
      _engine = null;

      emit(CallEnded());
    } catch (e) {
      debugPrint('Error ending call: $e');
      emit(CallEnded());
    }
  }

  // ===============================
  // 🔄 STATE UPDATES
  // ===============================
  void _updateJoinedState(bool joined) {
    if (state is CallEngineReady) {
      final current = state as CallEngineReady;
      emit(current.copyWith(isJoined: joined));
    }
  }

  void _addRemoteUser(int uid) {
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
      emit(current.copyWith(remoteUids: updatedUids));
    }
  }

  // ===============================
  // 🛠️ HELPERS
  // ===============================
  int _agoraUidFromFirebase(String uid) {
    return uid.hashCode & 0x7fffffff;
  }

  RtcEngine? get engine => _engine;

  // ===============================
  // 🧹 CLEANUP
  // ===============================
  @override
  Future<void> close() {
    _callStatusSubscription?.cancel();
    _engine?.release();
    return super.close();
  }
}