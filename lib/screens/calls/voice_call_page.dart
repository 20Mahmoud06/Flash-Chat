import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:agora_token_generator/agora_token_generator.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:permission_handler/permission_handler.dart';
import 'dart:async';
import '../../models/group_model.dart';
import '../../models/user_model.dart';
import '../../utils/agora_config.dart';
import '../../utils/call_utils.dart';

class VoiceCallPage extends StatefulWidget {
  final bool isGroup;
  final GroupModel? group;
  final UserModel? contact;
  final String? callerId;
  final String? callerName;
  final String callId;
  final String? groupName;

  const VoiceCallPage({
    super.key,
    required this.isGroup,
    this.group,
    this.contact,
    this.callerId,
    this.callerName,
    required this.callId,
    this.groupName,
  });

  @override
  State<VoiceCallPage> createState() => _VoiceCallPageState();
}

class _VoiceCallPageState extends State<VoiceCallPage> {
  late RtcEngine _engine;
  final List<int> _remoteUids = [];
  StreamSubscription<DocumentSnapshot>? _callSub;

  bool _joined = false;
  bool _muted = false;
  bool _engineReady = false;

  late final String _channelName;

  @override
  void initState() {
    super.initState();
    _channelName = buildChannelName(
      isGroup: widget.isGroup,
      group: widget.group,
      contact: widget.contact,
      otherUid: widget.callerId,
    );
    _initAgora();
    _listenToCallStatus();
  }

  void _listenToCallStatus() {
    _callSub = FirebaseFirestore.instance
        .collection('calls')
        .doc(widget.callId)
        .snapshots()
        .listen((snapshot) {
      final data = snapshot.data();
      if (data != null && data['status'] == 'ended') {
        _leaveCall();
      }
    });
  }

  Future<void> _initAgora() async {
    try {
      final status = await [Permission.microphone].request();
      if (!status.values.every((s) => s.isGranted)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone permission needed for call.')));
          await Future.delayed(const Duration(seconds: 2));
          Navigator.pop(context);
        }
        return;
      }

      _engine = createAgoraRtcEngine();
      await _engine.initialize(
        const RtcEngineContext(
          appId: AgoraConfig.appId,
          channelProfile: ChannelProfileType.channelProfileCommunication,
        ),
      );

      _engine.registerEventHandler(
        RtcEngineEventHandler(
          onJoinChannelSuccess: (RtcConnection connection, int elapsed) {
            setState(() => _joined = true);
          },
          onUserJoined: (_, uid, __) {
            setState(() => _remoteUids.add(uid));
          },
          onUserOffline: (_, uid, __) {
            setState(() => _remoteUids.remove(uid));
          },
          onLeaveChannel: (_, __) {
            setState(() => _joined = false);
          },
          onError: (err, msg) {
            debugPrint('Agora Error: $err - $msg');
            if (mounted) {
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Call error: $msg')));
            }
          },
        ),
      );

      setState(() {
        _engineReady = true;
      });

      const int expirationInSeconds = 3600;

      final token = RtcTokenBuilder.buildTokenWithUid(
        appId: AgoraConfig.appId,
        appCertificate: AgoraConfig.appCertificate,
        channelName: _channelName,
        uid: agoraUidFromFirebase(
          FirebaseAuth.instance.currentUser!.uid,
        ),
        tokenExpireSeconds: expirationInSeconds,
      );

      await _engine.joinChannel(
        token: token,
        channelId: _channelName,
        uid: agoraUidFromFirebase(
          FirebaseAuth.instance.currentUser!.uid,
        ),
        options: const ChannelMediaOptions(publishMicrophoneTrack: true),
      );
    } catch (e) {
      debugPrint('Agora init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to start call. Please try again.')));
        Navigator.pop(context);
      }
    }
  }

  Future<void> _leaveCall() async {
    if (!_engineReady) {
      if (mounted) Navigator.pop(context);
      return;
    }

    try {
      await _engine.leaveChannel();

      await FirebaseFirestore.instance
          .collection('calls')
          .doc(widget.callId)
          .update({'status': 'ended'});

      await FlutterCallkitIncoming.endCall(widget.callId);

      await _engine.release();
    } catch (e) {
      debugPrint('Error leaving call: $e');
    } finally {
      if (mounted) Navigator.pop(context);
    }
  }

  void _toggleMute() {
    if (!_engineReady) return;
    setState(() => _muted = !_muted);
    _engine.muteLocalAudioStream(_muted);
  }

  @override
  void dispose() {
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.isGroup
        ? widget.group?.name ?? widget.groupName ?? "Group Call"
        : (widget.contact?.fullName ?? widget.callerName ?? "Unknown");

    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: Text(displayName),
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            const Icon(Icons.call, color: Colors.green, size: 80),
            const SizedBox(height: 20),
            Text(
              !_engineReady
                  ? "Initializing..."
                  :_joined
                  ? widget.isGroup
                  ? "Connected to ${_remoteUids.length + 1} participants"
                  : "Connected"
                  : "Connecting...",
              style: const TextStyle(color: Colors.white, fontSize: 18),
            ),
            const SizedBox(height: 40),
            _engineReady
                ? Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(
                    _muted ? Icons.mic_off : Icons.mic,
                    color: Colors.white,
                    size: 32,
                  ),
                  onPressed: _toggleMute,
                ),
                const SizedBox(width: 30),
                IconButton(
                  icon: const Icon(
                    Icons.call_end,
                    color: Colors.red,
                    size: 40,
                  ),
                  onPressed: _leaveCall,
                ),
              ],
            )
                : const CircularProgressIndicator(color: Colors.white),
          ],
        ),
      ),
    );
  }

  int agoraUidFromFirebase(String uid) {
    return uid.hashCode & 0x7fffffff;
  }

}