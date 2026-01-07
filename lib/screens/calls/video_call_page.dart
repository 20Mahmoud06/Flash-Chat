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

class VideoCallPage extends StatefulWidget {
  final bool isGroup;
  final GroupModel? group;
  final UserModel? contact;
  final String? callerId;
  final String? callerName;
  final String callId;
  final String? groupName;
  final String? groupId;

  const VideoCallPage({
    super.key,
    required this.isGroup,
    this.group,
    this.contact,
    this.callerId,
    this.callerName,
    required this.callId,
    this.groupName,
    this.groupId,
  });

  @override
  State<VideoCallPage> createState() => _VideoCallPageState();
}

class _VideoCallPageState extends State<VideoCallPage> with SingleTickerProviderStateMixin {
  late RtcEngine _engine;
  final List<int> _remoteUids = [];
  StreamSubscription<DocumentSnapshot>? _callSub;
  bool _joined = false;
  bool _cameraOff = false;
  bool _muted = false;
  bool _engineReady = false;
  late final String _channelName;
  late AnimationController _controlsAnimation;
  bool _showControls = true;

  int agoraUidFromFirebase(String uid) {
    return uid.hashCode & 0x7fffffff;
  }

  @override
  void initState() {
    super.initState();
    _channelName = buildChannelName(
      isGroup: widget.isGroup,
      group: widget.group,
      groupId: widget.groupId,
      contact: widget.contact,
      otherUid: widget.callerId,
    );
    _initAgora();
    _listenToCallStatus();
    _controlsAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
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
      final status = await [Permission.microphone, Permission.camera].request();
      if (!status.values.every((s) => s.isGranted)) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Microphone and camera permissions needed for video call.')));
          await Future.delayed(const Duration(seconds: 2));
          Navigator.pop(context);
        }
        return;
      }
      _engine = createAgoraRtcEngine();
      await _engine.initialize(
        const RtcEngineContext(
          appId: AgoraConfig.appId,
          channelProfile: ChannelProfileType.channelProfileLiveBroadcasting,
        ),
      );
      await _engine.setClientRole(role: ClientRoleType.clientRoleBroadcaster);
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
      await _engine.enableVideo();
      await _engine.startPreview();
      setState(() {
        _engineReady = true;
      });
      const int expirationInSeconds = 3600;
      int myUid = agoraUidFromFirebase(FirebaseAuth.instance.currentUser!.uid);
      final token = RtcTokenBuilder.buildTokenWithUid(
        appId: AgoraConfig.appId,
        appCertificate: AgoraConfig.appCertificate,
        channelName: _channelName,
        uid: myUid,
        tokenExpireSeconds: expirationInSeconds,
      );
      await _engine.joinChannel(
        token: token,
        channelId: _channelName,
        uid: myUid,
        options: const ChannelMediaOptions(
          publishCameraTrack: true,
          publishMicrophoneTrack: true,
        ),
      );
    } catch (e) {
      debugPrint('Agora init error: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Failed to start video call. Please try again.')));
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

  void _toggleCamera() {
    if (!_engineReady) return;
    setState(() => _cameraOff = !_cameraOff);
    _engine.muteLocalVideoStream(_cameraOff);
  }

  void _toggleMute() {
    if (!_engineReady) return;
    setState(() => _muted = !_muted);
    _engine.muteLocalAudioStream(_muted);
  }

  void _switchCamera() {
    _engine.switchCamera();
  }

  Widget _buildLocalVideo() {
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: _engine,
        canvas: const VideoCanvas(
          uid: 0,
          renderMode: RenderModeType.renderModeFit,
        ),
      ),
    );
  }

  Widget _buildRemoteVideo(int uid) {
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: _engine,
        canvas: VideoCanvas(
          uid: uid,
          renderMode: RenderModeType.renderModeFit,
        ),
        connection: RtcConnection(channelId: _channelName),
      ),
    );
  }

  @override
  void dispose() {
    _controlsAnimation.dispose();
    _callSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final displayName = widget.isGroup
        ? widget.group?.name ?? widget.groupName ?? "Group Call"
        : (widget.contact?.fullName ?? widget.callerName ?? "Unknown");
    return GestureDetector(
      onTap: () {
        setState(() => _showControls = !_showControls);
        _showControls ? _controlsAnimation.forward() : _controlsAnimation.reverse();
      },
      child: Scaffold(
        backgroundColor: Colors.black,
        appBar: AppBar(
          backgroundColor: Colors.black.withOpacity(0.5),
          title: Text(displayName, style: const TextStyle(color: Colors.white)),
        ),
        body: Stack(
          children: [
            if (!_engineReady)
              const Center(child: CircularProgressIndicator(color: Colors.white))
            else if (_remoteUids.isEmpty)
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      "Calling $displayName...",
                      style: const TextStyle(color: Colors.white, fontSize: 18),
                    ),
                    const SizedBox(height: 20),
                    const CircularProgressIndicator(color: Colors.white),
                  ],
                ),
              )
            else if (!widget.isGroup && _remoteUids.length == 1)
              // 1-1 Connected: Full remote, small local top-right
                _buildRemoteVideo(_remoteUids[0])
              else
              // Group: Adaptive grid including local
                LayoutBuilder(
                  builder: (context, constraints) {
                    List<int> allUids = [0, ..._remoteUids]; // Include local tile always
                    int count = allUids.length;
                    int crossCount = count == 1 ? 1 : (count <= 4 ? 2 : (count <= 9 ? 3 : 4));
                    double spacing = 4.0;
                    double padding = 4.0;
                    int rows = (count / crossCount).ceil();
                    double availableHeight = constraints.maxHeight - 2 * padding - (rows - 1) * spacing;
                    double tileHeight = availableHeight / rows;
                    double tileWidth = (constraints.maxWidth - 2 * padding - (crossCount - 1) * spacing) / crossCount;
                    double aspectRatio = tileWidth / tileHeight;
                    return GridView.builder(
                      padding: EdgeInsets.all(padding),
                      itemCount: count,
                      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: crossCount,
                        childAspectRatio: aspectRatio,
                        mainAxisSpacing: spacing,
                        crossAxisSpacing: spacing,
                      ),
                      itemBuilder: (context, index) {
                        int uid = allUids[index];
                        Widget video;
                        if (uid == 0) {
                          if (_cameraOff) {
                            video = Container(
                              color: Colors.black,
                              child: const Center(
                                child: Text(
                                  'You\n(Camera off)',
                                  style: TextStyle(color: Colors.white),
                                  textAlign: TextAlign.center,
                                ),
                              ),
                            );
                          } else {
                            video = _buildLocalVideo();
                          }
                        } else {
                          video = _buildRemoteVideo(uid);
                        }
                        return ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: video,
                        );
                      },
                    );
                  },
                ),
            // Small local preview (only for 1-1 if engine ready and camera on)
            if (_engineReady && !_cameraOff && !widget.isGroup)
              Positioned(
                right: 16,
                top: 16,
                width: 120,
                height: 160,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: _buildLocalVideo(),
                ),
              ),
            // Controls (fade in/out)
            Positioned(
              bottom: 30,
              left: 0,
              right: 0,
              child: AnimatedBuilder(
                animation: _controlsAnimation,
                builder: (context, child) => Opacity(
                  opacity: _controlsAnimation.value,
                  child: child,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(_muted ? Icons.mic_off : Icons.mic, color: Colors.white, size: 32),
                      onPressed: _toggleMute,
                    ),
                    IconButton(
                      icon: Icon(_cameraOff ? Icons.videocam_off : Icons.videocam, color: Colors.white, size: 32),
                      onPressed: _toggleCamera,
                    ),
                    const SizedBox(width: 30),
                    IconButton(
                      icon: const Icon(Icons.call_end, color: Colors.red, size: 40),
                      onPressed: _leaveCall,
                    ),
                    const SizedBox(width: 30),
                    IconButton(
                      icon: const Icon(Icons.switch_camera, color: Colors.white, size: 32),
                      onPressed: _switchCamera,
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}