import 'dart:async';
import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../core/constants/app_colors.dart';
import '../../../models/group_model.dart';
import '../../../models/user_model.dart';
import '../../../core/utils/call_utils.dart';
import '../cubit/call_cubit.dart';
import '../cubit/call_state.dart';
import '../services/call_avatar_loader.dart';
import '../services/native_pip.dart';
import '../widgets/call_controls.dart';
import '../widgets/call_ended_overlay.dart';
import '../widgets/call_timer_widget.dart';
import '../widgets/animated_call_grid.dart';
import '../widgets/video_call_avatar_placeholder.dart';

class VideoCallPage extends StatelessWidget {
  final bool isGroup;
  final GroupModel? group;
  final UserModel? contact;
  final String? callerId;
  final String? callerName;
  final String? callerAvatar;
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
    this.callerAvatar,
    required this.callId,
    this.groupName,
    this.groupId,
  });

  @override
  Widget build(BuildContext context) {
    final channelName = buildChannelName(
      isGroup: isGroup,
      group: group,
      groupId: groupId,
      contact: contact,
      otherUid: callerId,
    );
    return BlocProvider<CallCubit>.value(
      value: CallCubit.instance,
      child: _VideoCallView(
        isGroup: isGroup,
        displayName: isGroup
            ? group?.name ?? groupName ?? "Group Call"
            : (callerName ?? contact?.fullName ?? "Unknown"),
        avatarEmoji: isGroup
            ? group?.avatarEmoji
            : (contact?.avatarEmoji ?? callerAvatar),
        groupId: group?.id ?? groupId,
        callerId: callerId,
        callId: callId,
        channelName: channelName,
      ),
    );
  }
}

class _VideoCallView extends StatefulWidget {
  final bool isGroup;
  final String displayName;
  final String? avatarEmoji;
  final String? groupId;
  final String? callerId;
  final String callId;
  final String channelName;

  const _VideoCallView({
    required this.isGroup,
    required this.displayName,
    this.avatarEmoji,
    this.groupId,
    this.callerId,
    required this.callId,
    required this.channelName,
  });

  @override
  State<_VideoCallView> createState() => _VideoCallViewState();
}

class _VideoCallViewState extends State<_VideoCallView>
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _controlsAnimation;
  bool _showControls = true;
  String? _endedReason;
  Duration? _callDuration;
  String? _ownAvatar;
  Map<int, CallParticipantInfo> _participants = {};

  bool _pipAvailable = false;
  bool _inPip = false;

  /// Confirms a PiP dismissal: some devices report `dismissed` before the
  /// expand transition has finished. If the activity resumes within the grace
  /// period the dismissal is cancelled and the call keeps running.
  Timer? _dismissGraceTimer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Show over the lock screen while the call UI is up, so answering a call
    // from the lock screen lands directly in the call (see MainActivity).
    NativePip.instance.setCallMode(true);
    _controlsAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
    _loadAvatars();
    NativePip.instance.onEvent = _onNativePipEvent;

    // The cubit is app-wide: only initialize a brand-new call; re-opening a
    // minimized call must keep the running engine untouched.
    final cubit = CallCubit.instance;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!cubit.isCallActive) {
        cubit.initializeVideoCall(
          channelName: widget.channelName,
          callId: widget.callId,
          info: CallInfo(
            isGroup: widget.isGroup,
            isVideo: true,
            channelName: widget.channelName,
            callId: widget.callId,
            peerUid: widget.callerId,
            groupId: widget.groupId,
            displayName: widget.displayName,
            avatarEmoji: widget.avatarEmoji,
            callerId: widget.callerId,
          ),
        );
      } else {
        cubit.restore();
      }
      _setupPip();
    });
  }

  Future<void> _setupPip() async {
    final pip = NativePip.instance;
    _pipAvailable = await pip.isSupported();
    if (!_pipAvailable || !mounted) return;
    await pip.setup(
      aspectRatioX: 9,
      aspectRatioY: 16,
      autoEnterEnabled: true,
      seamlessResizeEnabled: true,
    );
  }

  /// Native PiP events: the OS reports why PiP exited, so no lifecycle
  /// guessing is needed. Dismissal is still confirmed by a short grace period
  /// so an expand that looks like a dismiss (OEM activity recreation) can
  /// never kill the call.
  void _onNativePipEvent(NativePipEvent event) {
    switch (event) {
      case NativePipEvent.started:
        _dismissGraceTimer?.cancel();
        if (mounted) setState(() => _inPip = true);
        break;
      case NativePipEvent.expanded:
        // The user brought the call back to full screen: surface the
        // controls again so they can end the call or minimize again.
        _dismissGraceTimer?.cancel();
        if (!mounted) return;
        _inPip = false;
        setState(() => _showControls = true);
        _controlsAnimation.forward();
        break;
      case NativePipEvent.dismissed:
        // The user closed the PiP window: the call is over. Wait a beat and
        // let a resume (proving it was actually an expand) cancel this.
        if (mounted) setState(() => _inPip = false);
        _dismissGraceTimer?.cancel();
        _dismissGraceTimer = Timer(const Duration(milliseconds: 1500), () {
          if (!mounted) return;
          if (CallCubit.instance.isCallActive) {
            CallCubit.instance.endCall(widget.callId);
          }
          Navigator.pop(context);
        });
        break;
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      // The activity came back: if we were still waiting to confirm a PiP
      // dismissal this proves it was an expand — cancel the hang-up.
      _dismissGraceTimer?.cancel();
      if (!_inPip) {
        // Resurface the controls so the user can always find the hang-up
        // button.
        setState(() => _showControls = true);
        _controlsAnimation.forward();
      }
    }
  }

  Future<void> _enterPipOrMinimize() async {
    final cubit = CallCubit.instance;
    if (!cubit.isCallActive) {
      cubit.endCall(widget.callId);
      return;
    }
    if (_pipAvailable && !_inPip) {
      final started = await NativePip.instance.start();
      if (started && mounted) {
        // The system animates the activity into PiP; do not pop.
        return;
      }
    }
    // No PiP support (old device / failed): fall back to minimizing like a
    // voice call - the call keeps running and the global pill brings it back.
    cubit.minimize();
    if (mounted) Navigator.pop(context);
  }

  Future<void> _loadAvatars() async {
    final own = await CallAvatarLoader.loadOwnAvatar();
    var participants = <int, CallParticipantInfo>{};
    if (widget.isGroup && widget.groupId != null) {
      participants =
          await CallAvatarLoader.loadGroupParticipants(widget.groupId!);
    }
    if (mounted) {
      setState(() {
        _ownAvatar = own;
        _participants = participants;
      });
    }
  }

  @override
  void dispose() {
    _dismissGraceTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    NativePip.instance.setCallMode(false);
    if (NativePip.instance.onEvent == _onNativePipEvent) {
      NativePip.instance.onEvent = null;
    }
    if (_pipAvailable) {
      // Clear the activity's auto-enter PiP flag so the app never pops into
      // PiP on the Home button from ANY screen after the first video call.
      NativePip.instance.disableAutoEnter();
    }
    _controlsAnimation.dispose();
    super.dispose();
  }

  Widget _buildLocalVideo(RtcEngine engine,
      {RenderModeType renderMode = RenderModeType.renderModeFit}) {
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: engine,
        canvas: VideoCanvas(
          uid: 0,
          renderMode: renderMode,
        ),
      ),
    );
  }

  Widget _buildRemoteVideo(RtcEngine engine, int uid, String channelName,
      {RenderModeType renderMode = RenderModeType.renderModeFit}) {
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: engine,
        canvas: VideoCanvas(
          uid: uid,
          renderMode: renderMode,
        ),
        connection: RtcConnection(channelId: channelName),
      ),
    );
  }

  /// Renders inside the Android PiP window: the video fills the small screen
  /// and a row of small round buttons (end call / mute / switch camera) sits
  /// at the bottom — the same compact style as AURA's player PiP.
  Widget _buildPipLayout({
    required CallCubit cubit,
    required RtcEngine? engine,
    required bool isEngineReady,
    required List<int> remoteUids,
    required Set<int> mutedRemoteUids,
    required bool isCameraOff,
    required bool isMuted,
  }) {
    Widget placeholder(String emoji) => ColoredBox(
          color: const Color(0xFF0F0F18),
          child: Center(
            child: Text(emoji, style: const TextStyle(fontSize: 34)),
          ),
        );

    Widget video;
    if (!isEngineReady || engine == null || remoteUids.isEmpty) {
      video = placeholder(widget.avatarEmoji ?? '👤');
    } else if (!widget.isGroup && remoteUids.length == 1) {
      video = mutedRemoteUids.contains(remoteUids[0])
          ? placeholder(widget.avatarEmoji ?? '👤')
          : _buildRemoteVideo(engine, remoteUids[0], widget.channelName);
    } else {
      // Group call: the grid does not fit a PiP window, show my camera.
      video = isCameraOff
          ? placeholder(_ownAvatar ?? '👤')
          : _buildLocalVideo(engine);
    }

    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          video,
          // Caller name chip (WhatsApp/Messenger style).
          Align(
            alignment: Alignment.topCenter,
            child: Padding(
              padding: const EdgeInsets.only(top: 6),
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    widget.displayName,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
            ),
          ),
          // Compact control pill: mute / end / switch camera.
          Align(
            alignment: Alignment.bottomCenter,
            child: Padding(
              padding: const EdgeInsets.only(bottom: 8),
              // PiP windows can be very narrow; scale the whole pill down
              // instead of overflowing (buttons stay tappable).
              child: FittedBox(
                fit: BoxFit.scaleDown,
                child: Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.45),
                    borderRadius: BorderRadius.circular(30),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _PipCallButton(
                        icon: isMuted
                            ? Icons.mic_off_rounded
                            : Icons.mic_rounded,
                        iconColor: isMuted ? Colors.amber : Colors.white,
                        backgroundColor: Colors.transparent,
                        onTap: isEngineReady ? cubit.toggleMute : null,
                      ),
                      const SizedBox(width: 4),
                      _PipCallButton(
                        icon: Icons.call_end_rounded,
                        backgroundColor: Colors.red.shade600,
                        size: 40,
                        onTap: () {
                          cubit.endCall(widget.callId);
                          if (mounted) Navigator.pop(context);
                        },
                      ),
                      const SizedBox(width: 4),
                      _PipCallButton(
                        icon: Icons.cameraswitch_rounded,
                        backgroundColor: Colors.transparent,
                        onTap: (isEngineReady && !isCameraOff)
                            ? cubit.switchCamera
                            : null,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CallCubit, CallState>(
      listener: (context, state) {
        if (state is CallPermissionDenied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
          Future.delayed(const Duration(seconds: 2), () {
            if (context.mounted) Navigator.pop(context);
          });
        } else if (state is CallError) {
          setState(() {
            _endedReason = 'failed';
            _callDuration = null;
          });
        } else if (state is CallEnded) {
          setState(() {
            _endedReason = state.reason ?? 'ended';
            _callDuration = state.duration;
          });
          if (_inPip && context.mounted) {
            // Call ended while minimized: leave the PiP window.
            Future.delayed(const Duration(milliseconds: 300), () {
              if (context.mounted) Navigator.pop(context);
            });
          }
        }
      },
      builder: (context, state) {
        final cubit = context.read<CallCubit>();
        final engine = cubit.engine;

        final isEngineReady = state is CallEngineReady;
        final readyState = isEngineReady ? state : null;
        final remoteUids = readyState?.remoteUids ?? <int>[];
        final mutedRemoteUids = readyState?.mutedRemoteUids ?? <int>{};
        final mutedRemoteAudioUids = readyState?.mutedRemoteAudioUids ?? <int>{};
        final speakingUids = readyState?.speakingUids ?? <int>{};
        final isCameraOff = readyState?.isCameraOff ?? false;
        final isMuted = readyState?.isMuted ?? false;
        final isJoined = readyState?.isJoined ?? false;

        // Compact Picture-in-Picture layout: the full call UI (header bar,
        // big controls, local preview) overflows in the small PiP window, so
        // show only the video plus small end/mute/camera buttons.
        if (_inPip) {
          return _buildPipLayout(
            cubit: cubit,
            engine: engine,
            isEngineReady: isEngineReady,
            remoteUids: remoteUids,
            mutedRemoteUids: mutedRemoteUids,
            isCameraOff: isCameraOff,
            isMuted: isMuted,
          );
        }

        return GestureDetector(
          onTap: () {
            setState(() => _showControls = !_showControls);
            _showControls
                ? _controlsAnimation.forward()
                : _controlsAnimation.reverse();
          },
          child: PopScope(
            canPop: _endedReason != null,
            onPopInvokedWithResult: (didPop, result) {
              if (didPop) return;
              _enterPipOrMinimize();
            },
            child: Scaffold(
            backgroundColor: const Color(0xFF0F0F18),
            body: Stack(
              children: [
                // 1. VIDEO OR PLACEHOLDER DISPLAY AREA
                if (!isEngineReady || engine == null)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        const CircularProgressIndicator(color: Colors.white70),
                        const SizedBox(height: 16),
                        Text(
                          "Connecting to ${widget.displayName}...",
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 16,
                          ),
                        ),
                      ],
                    ),
                  )
                else if (remoteUids.isEmpty)
                  // Calling / Ringing state placeholder
                  VideoCallAvatarPlaceholder(
                    displayName: widget.displayName,
                    avatarEmoji: widget.avatarEmoji,
                    statusText: isJoined ? "Ringing..." : "Connecting...",
                    statusIcon: Icons.phone_forwarded_rounded,
                  )
                else if (!widget.isGroup && remoteUids.length == 1)
                  // 1-on-1: Full screen view
                  (mutedRemoteUids.contains(remoteUids[0])
                      ? VideoCallAvatarPlaceholder(
                          displayName: widget.displayName,
                          avatarEmoji: widget.avatarEmoji,
                          statusText: "${widget.displayName} turned off camera",
                          statusIcon: Icons.videocam_off_rounded,
                        )
                      : _buildRemoteVideo(
                          engine,
                          remoteUids[0],
                          widget.channelName,
                        ))
                else
                  // Group Grid View. Tiles are computed by AnimatedCallGrid
                  // from the screen bounds so they fill ALL the available
                  // surface (no giant black letterbox) and animate smoothly
                  // when someone joins/leaves.
                  SafeArea(
                    child: Padding(
                      padding: const EdgeInsets.only(
                        top: 60,
                        left: 8,
                        right: 8,
                        bottom: 8,
                      ),
                      child: AnimatedCallGrid(
                        uids: [0, ...remoteUids],
                        spacing: 6,
                        itemBuilder: (context, uid) {
                          Widget content;
                          String participantName;
                          final bool isSpeaking = speakingUids.contains(uid);
                          // Crop fills each tile edge-to-edge (WhatsApp
                          // look); Fit would letterbox the video inside it.
                          const tileRenderMode =
                              RenderModeType.renderModeHidden;

                          if (uid == 0) {
                            participantName = "You";
                            if (isCameraOff) {
                              content = VideoCallAvatarPlaceholder(
                                displayName: participantName,
                                avatarEmoji: _ownAvatar,
                                statusText: "Camera off",
                                isCompact: true,
                              );
                            } else {
                              content = _buildLocalVideo(
                                engine,
                                renderMode: tileRenderMode,
                              );
                            }
                          } else {
                            final info = _participants[uid];
                            participantName =
                                info?.name ?? "Participant $uid";
                            if (mutedRemoteUids.contains(uid)) {
                              content = VideoCallAvatarPlaceholder(
                                displayName: participantName,
                                avatarEmoji: info?.avatarEmoji,
                                statusText: "Camera off",
                                isCompact: true,
                              );
                            } else {
                              content = _buildRemoteVideo(
                                engine,
                                uid,
                                widget.channelName,
                                renderMode: tileRenderMode,
                              );
                            }
                          }

                          return Stack(
                            children: [
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Container(
                                    decoration: BoxDecoration(
                                      border: Border.all(
                                        color: isSpeaking
                                            ? const Color(0xFF66BB6A)
                                            : Colors.transparent,
                                        width: 3,
                                      ),
                                    ),
                                    child: Container(
                                      color: const Color(0xFF1E1E2E),
                                      child: content,
                                    ),
                                  ),
                                ),
                              ),
                              // Speaking indicator badge (green mic)
                              if (isSpeaking)
                                Positioned(
                                  top: 8,
                                  left: 8,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: BoxDecoration(
                                      color: const Color(0xFF4CAF50),
                                      shape: BoxShape.circle,
                                      border: Border.all(
                                        color: Colors.white.withValues(
                                            alpha: 0.5),
                                        width: 1,
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.graphic_eq_rounded,
                                      color: Colors.white,
                                      size: 13,
                                    ),
                                  ),
                                ),
                              // Participant name tag overlay
                              Positioned(
                                left: 8,
                                bottom: 8,
                                child: Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 8,
                                    vertical: 4,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.black.withValues(
                                        alpha: 0.65),
                                    borderRadius: BorderRadius.circular(12),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Text(
                                        participantName,
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.w500,
                                        ),
                                      ),
                                      if (uid != 0 &&
                                          mutedRemoteAudioUids
                                              .contains(uid)) ...[
                                        const SizedBox(width: 4),
                                        const Icon(
                                          Icons.mic_off_rounded,
                                          color: Colors.redAccent,
                                          size: 12,
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                // 2. SMALL LOCAL PREVIEW PIP (1-on-1 only)
                if (isEngineReady && !widget.isGroup && engine != null)
                  Positioned(
                    right: 16,
                    top: MediaQuery.of(context).padding.top + 64,
                    width: 110,
                    height: 150,
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(16),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.25),
                          width: 1.5,
                        ),
                        boxShadow: const [
                          BoxShadow(
                            color: Colors.black45,
                            blurRadius: 16,
                            spreadRadius: 2,
                          ),
                        ],
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(15),
                          child: Container(
                            color: const Color(0xFF1E1E2E),
                            child: isCameraOff
                                ? Center(
                                    child: Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          _ownAvatar ?? '👤',
                                          style:
                                              const TextStyle(fontSize: 34),
                                        ),
                                        const SizedBox(height: 6),
                                        const Text(
                                          "You (Off)",
                                          style: TextStyle(
                                            color: Colors.white60,
                                            fontSize: 11,
                                          ),
                                        ),
                                      ],
                                    ),
                                  )
                                : _buildLocalVideo(engine),
                          ),
                      ),
                    ),
                  ),

                // 3. TOP GLASSMORPHIC BAR
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: AnimatedBuilder(
                    animation: _controlsAnimation,
                    builder: (context, child) => IgnorePointer(
                      // Hidden controls must not swallow taps: let them pass
                      // through to the GestureDetector that shows controls.
                      ignoring: !_showControls,
                      child: Opacity(
                        opacity: _controlsAnimation.value,
                        child: child,
                      ),
                    ),
                    child: SafeArea(
                      child: Container(
                        margin: const EdgeInsets.all(12),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: AppColors.callHeaderBg.withValues(alpha: 0.85),
                          borderRadius: BorderRadius.circular(24),
                          border: Border.all(
                            color: Colors.white.withValues(alpha: 0.15),
                            width: 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.arrow_back_ios_new_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                              onPressed: _enterPipOrMinimize,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    widget.displayName,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                    ),
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                  const SizedBox(height: 2),
                                  remoteUids.isNotEmpty
                                      ? const CallTimerWidget()
                                      : Text(
                                          _endedReason != null
                                              ? CallEndedOverlay.statusLabel(
                                                  _endedReason)
                                              : (isJoined
                                                  ? "Ringing..."
                                                  : "Connecting..."),
                                          style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12,
                                          ),
                                        ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // 4. FLOATING BOTTOM CONTROLS
                if (isEngineReady)
                  Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                      animation: _controlsAnimation,
                      builder: (context, child) => IgnorePointer(
                        // Hidden controls must not swallow taps: let them
                        // pass through to the GestureDetector below.
                        ignoring: !_showControls,
                        child: Opacity(
                          opacity: _controlsAnimation.value,
                          child: child,
                        ),
                      ),
                      child: CallControls(
                        isMuted: isMuted,
                        isCameraOff: isCameraOff,
                        isVideo: true,
                        onMuteToggle: () => cubit.toggleMute(),
                        onCameraToggle: () => cubit.toggleCamera(),
                        onSwitchCamera: () => cubit.switchCamera(),
                        onEndCall: () => cubit.endCall(widget.callId),
                      ),
                    ),
                  ),

                // 5. CALL ENDED / TERMINATION OVERLAY
                if (_endedReason != null)
                  Positioned.fill(
                    child: CallEndedOverlay(
                      reason: _endedReason,
                      duration: _callDuration,
                      onDismiss: () {
                        if (context.mounted) Navigator.pop(context);
                      },
                    ),
                  ),
              ],
            ),
          ),
          ),
        );
      },
    );
  }
}

/// Small round button used in the PiP window (end call / mute / switch
/// camera). Disabled ([onTap] null) renders dimmed.
class _PipCallButton extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final Color backgroundColor;
  final double size;
  final VoidCallback? onTap;

  const _PipCallButton({
    required this.icon,
    this.iconColor = Colors.white,
    required this.backgroundColor,
    this.size = 34,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: enabled
              ? backgroundColor
              : backgroundColor.withValues(alpha: 0.35),
        ),
        child: Icon(
          icon,
          color: enabled ? iconColor : Colors.white54,
          size: size * 0.52,
        ),
      ),
    );
  }
}
