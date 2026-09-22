import 'dart:async';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../groups/models/group_model.dart';
import '../../profile/models/user_model.dart';
import '../../../core/utils/call_utils.dart';
import '../bloc/call_bloc.dart';
import '../bloc/call_state.dart';
import '../models/call_info.dart';
import '../services/call_avatar_loader.dart';
import '../services/native_pip.dart';
import '../widgets/video_call_pip_layout.dart';
import '../widgets/video_call_scaffold.dart';

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
    return BlocProvider<CallBloc>.value(
      value: CallBloc.instance,
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

    // The bloc is app-wide: only initialize a brand-new call; re-opening a
    // minimized call must keep the running engine untouched.
    final cubit = CallBloc.instance;
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
          if (CallBloc.instance.isCallActive) {
            CallBloc.instance.endCall(widget.callId);
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
    final cubit = CallBloc.instance;
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
    final ownFuture = CallAvatarLoader.loadOwnAvatar();
    final participantsFuture = (widget.isGroup && widget.groupId != null)
        ? CallAvatarLoader.loadGroupParticipants(widget.groupId!)
        : Future.value(<int, CallParticipantInfo>{});
    final results = await Future.wait([ownFuture, participantsFuture]);
    if (mounted) {
      setState(() {
        _ownAvatar = results[0] as String?;
        _participants = results[1] as Map<int, CallParticipantInfo>;
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

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<CallBloc, CallState>(
      listener: (context, state) {
        if (state is CallPermissionDenied) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: CustomText(text: state.message)),
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
        final cubit = context.read<CallBloc>();
        final engine = cubit.engine;

        final isEngineReady = state is CallEngineReady;
        final readyState = isEngineReady ? state : null;
        final remoteUids = readyState?.remoteUids ?? <int>[];
        final mutedRemoteUids = readyState?.mutedRemoteUids ?? <int>{};
        final mutedRemoteAudioUids =
            readyState?.mutedRemoteAudioUids ?? <int>{};
        final speakingUids = readyState?.speakingUids ?? <int>{};
        final isCameraOff = readyState?.isCameraOff ?? false;
        final isMuted = readyState?.isMuted ?? false;
        final isJoined = readyState?.isJoined ?? false;
        final hadRemoteUser = readyState?.hadRemoteUser ?? false;

        // Compact Picture-in-Picture layout: the full call UI (header bar,
        // big controls, local preview) overflows in the small PiP window, so
        // show only the video plus small end/mute/camera buttons.
        if (_inPip) {
          return VideoCallPipLayout(
            displayName: widget.displayName,
            avatarEmoji: widget.avatarEmoji,
            ownAvatar: _ownAvatar,
            isGroup: widget.isGroup,
            engine: engine,
            isEngineReady: isEngineReady,
            channelName: widget.channelName,
            remoteUids: remoteUids,
            mutedRemoteUids: mutedRemoteUids,
            isCameraOff: isCameraOff,
            isMuted: isMuted,
            onToggleMute: () => cubit.toggleMute(),
            onSwitchCamera: () => cubit.switchCamera(),
            onEndCall: () {
              cubit.endCall(widget.callId);
              if (mounted) Navigator.pop(context);
            },
          );
        }

        return VideoCallScaffold(
          displayName: widget.displayName,
          avatarEmoji: widget.avatarEmoji,
          ownAvatar: _ownAvatar,
          isGroup: widget.isGroup,
          channelName: widget.channelName,
          engine: engine,
          isEngineReady: isEngineReady,
          remoteUids: remoteUids,
          mutedRemoteUids: mutedRemoteUids,
          mutedRemoteAudioUids: mutedRemoteAudioUids,
          speakingUids: speakingUids,
          isCameraOff: isCameraOff,
          isMuted: isMuted,
          isJoined: isJoined,
          hadRemoteUser: hadRemoteUser,
          participants: _participants,
          controlsAnimation: _controlsAnimation,
          showControls: _showControls,
          endedReason: _endedReason,
          callDuration: _callDuration,
          canPop: _endedReason != null,
          onPopInvoked: (didPop, result) {
            if (didPop) return;
            _enterPipOrMinimize();
          },
          onToggleControls: () {
            setState(() => _showControls = !_showControls);
            _showControls
                ? _controlsAnimation.forward()
                : _controlsAnimation.reverse();
          },
          onBack: _enterPipOrMinimize,
          onToggleMute: () => cubit.toggleMute(),
          onSwitchCamera: () => cubit.switchCamera(),
          onCameraToggle: () => cubit.toggleCamera(),
          onEndCall: () => cubit.endCall(widget.callId),
          onDismissEnded: () {
            if (context.mounted) Navigator.pop(context);
          },
        );
      },
    );
  }
}