import 'package:flash_chat_app/core/constants/app_colors.dart';
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
import '../services/call_notif.dart';
import '../services/native_pip.dart';
import '../widgets/call_controls.dart';
import '../widgets/call_ended_overlay.dart';
import '../widgets/voice_call_display_area.dart';
import '../widgets/voice_call_top_bar.dart';

class VoiceCallPage extends StatelessWidget {
  final bool isGroup;
  final GroupModel? group;
  final UserModel? contact;
  final String? callerId;
  final String? callerName;
  final String? callerAvatar;
  final String callId;
  final String? groupName;

  const VoiceCallPage({
    super.key,
    required this.isGroup,
    this.group,
    this.contact,
    this.callerId,
    this.callerName,
    this.callerAvatar,
    required this.callId,
    this.groupName,
  });

  @override
  Widget build(BuildContext context) {
    final channelName = buildChannelName(
      isGroup: isGroup,
      group: group,
      contact: contact,
      otherUid: callerId,
    );
    return BlocProvider<CallBloc>.value(
      value: CallBloc.instance,
      child: _VoiceCallView(
        isGroup: isGroup,
        displayName: isGroup
            ? group?.name ?? groupName ?? "Group Call"
            : (callerName ?? contact?.fullName ?? "Unknown"),
        avatarEmoji: isGroup
            ? group?.avatarEmoji
            : (contact?.avatarEmoji ?? callerAvatar),
        groupId: group?.id,
        callerId: callerId,
        callId: callId,
        channelName: channelName,
      ),
    );
  }
}

class _VoiceCallView extends StatefulWidget {
  final bool isGroup;
  final String displayName;
  final String? avatarEmoji;
  final String? groupId;
  final String? callerId;
  final String callId;
  final String channelName;

  const _VoiceCallView({
    required this.isGroup,
    required this.displayName,
    this.avatarEmoji,
    this.groupId,
    this.callerId,
    required this.callId,
    required this.channelName,
  });

  @override
  State<_VoiceCallView> createState() => _VoiceCallViewState();
}

class _VoiceCallViewState extends State<_VoiceCallView>
    with WidgetsBindingObserver {
  String? _endedReason;
  Duration? _callDuration;
  String? _ownAvatar;
  Map<int, CallParticipantInfo> _participants = {};

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Show over the lock screen while the call UI is up, so answering a call
    // from the lock screen lands directly in the call (see MainActivity).
    NativePip.instance.setCallMode(true);
    _loadAvatars();

    // The bloc is app-wide: only initialize a brand-new call; re-opening a
    // minimized call must keep the running engine untouched.
    final cubit = CallBloc.instance;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!cubit.isCallActive) {
        cubit.initializeVoiceCall(
          channelName: widget.channelName,
          callId: widget.callId,
          info: CallInfo(
            isGroup: widget.isGroup,
            isVideo: false,
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
    });
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
    WidgetsBinding.instance.removeObserver(this);
    NativePip.instance.setCallMode(false);
    super.dispose();
  }

  /// While the call page is not on screen, surface the sticky ongoing
  /// notification (elapsed time + mute / end actions). Coming back to the
  /// page removes it again.
  void _showCallNotification() {
    final cubit = CallBloc.instance;
    if (!cubit.isCallActive) return;
    CallNotifBridge.instance.show(
      callId: widget.callId,
      title: widget.displayName,
      startTimeMs: (cubit.connectedAt ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cubit = CallBloc.instance;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _showCallNotification();
    } else if (state == AppLifecycleState.resumed && !cubit.minimized) {
      CallNotifBridge.instance.hide();
    }
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
        }
      },
      builder: (context, state) {
        final cubit = context.read<CallBloc>();

        final isEngineReady = state is CallEngineReady;
        final readyState = isEngineReady ? state : null;
        final isJoined = readyState?.isJoined ?? false;
        final hadRemoteUser = readyState?.hadRemoteUser ?? false;
        final isMuted = readyState?.isMuted ?? false;
        final remoteUids = readyState?.remoteUids ?? <int>[];
        final mutedRemoteAudioUids =
            readyState?.mutedRemoteAudioUids ?? <int>{};
        final speakingUids = readyState?.speakingUids ?? <int>{};

        return PopScope(
          canPop: _endedReason != null,
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            _minimizeCall();
          },
          child: Scaffold(
            backgroundColor: AppColors.callBackgroundTop,
            body: Stack(
              children: [
                // 1. MAIN DISPLAY AREA (1v1 vs GROUP)
                VoiceCallDisplayArea(
                  isGroup: widget.isGroup,
                  displayName: widget.displayName,
                  avatarEmoji: widget.avatarEmoji,
                  ownAvatar: _ownAvatar,
                  isEngineReady: isEngineReady,
                  isJoined: isJoined,
                  hadRemoteUser: hadRemoteUser,
                  isMuted: isMuted,
                  remoteUids: remoteUids,
                  speakingUids: speakingUids,
                  mutedRemoteAudioUids: mutedRemoteAudioUids,
                  participants: _participants,
                ),

                // 2. TOP GLASSMORPHIC BAR
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: VoiceCallTopBar(
                    displayName: widget.displayName,
                    ownAvatar: _ownAvatar,
                    showTimer: remoteUids.isNotEmpty,
                    endedReason: _endedReason,
                    isJoined: isJoined,
                    isGroup: widget.isGroup,
                    remoteUsersCount: remoteUids.length,
                    hadRemoteUser: hadRemoteUser,
                    isEngineReady: isEngineReady,
                    onMinimize: _minimizeCall,
                  ),
                ),

                // 3. FLOATING BOTTOM CONTROLS
                if (isEngineReady)
                  Positioned(
                    bottom: 30,
                    left: 0,
                    right: 0,
                    child: CallControls(
                      isMuted: isMuted,
                      isCameraOff: false,
                      isVideo: false,
                      onMuteToggle: () => cubit.toggleMute(),
                      onEndCall: () => cubit.endCall(widget.callId),
                    ),
                  )
                else
                  const Positioned(
                    bottom: 40,
                    left: 0,
                    right: 0,
                    child: Center(
                      child:
                          CircularProgressIndicator(color: Colors.white70),
                    ),
                  ),

                // 4. CALL ENDED OVERLAY
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
        );
      },
    );
  }

  /// Back = minimize: pop to the chat while the call keeps running behind the
  /// sticky ongoing notification (elapsed time + mute / end actions). The
  /// global "call in progress" pill also lets the user return to the call.
  void _minimizeCall() {
    final cubit = CallBloc.instance;
    if (!cubit.isCallActive) {
      cubit.endCall(widget.callId);
      return;
    }
    cubit.minimize();
    _showCallNotification();
    if (mounted) Navigator.pop(context);
  }
}