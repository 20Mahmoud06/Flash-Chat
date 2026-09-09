import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../core/constants/app_colors.dart';
import '../../../models/group_model.dart';
import '../../../models/user_model.dart';
import '../../../core/utils/call_utils.dart';
import '../cubit/call_cubit.dart';
import '../cubit/call_state.dart';
import '../services/call_avatar_loader.dart';
import '../services/call_notif.dart';
import '../services/native_pip.dart';
import '../widgets/call_controls.dart';
import '../widgets/call_ended_overlay.dart';
import '../widgets/call_status_display.dart';
import '../widgets/call_timer_widget.dart';
import '../widgets/animated_call_grid.dart';
import '../widgets/group_voice_grid_tile.dart';

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
    return BlocProvider<CallCubit>.value(
      value: CallCubit.instance,
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
    with SingleTickerProviderStateMixin, WidgetsBindingObserver {
  late AnimationController _pulseController;
  late Animation<double> _pulseAnimation;
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
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2000),
    )..repeat(reverse: true);

    _pulseAnimation = Tween<double>(begin: 1.0, end: 1.15).animate(
      CurvedAnimation(parent: _pulseController, curve: Curves.easeInOut),
    );

    _loadAvatars();

    // The cubit is app-wide: only initialize a brand-new call; re-opening a
    // minimized call must keep the running engine untouched.
    final cubit = CallCubit.instance;
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
    WidgetsBinding.instance.removeObserver(this);
    NativePip.instance.setCallMode(false);
    _pulseController.dispose();
    super.dispose();
  }

  /// While the call page is not on screen, surface the sticky ongoing
  /// notification (elapsed time + mute / end actions). Coming back to the
  /// page removes it again.
  void _showCallNotification() {
    final cubit = CallCubit.instance;
    if (!cubit.isCallActive) return;
    CallNotifBridge.instance.show(
      callId: widget.callId,
      title: widget.displayName,
      startTimeMs:
          (cubit.connectedAt ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final cubit = CallCubit.instance;
    if (state == AppLifecycleState.paused ||
        state == AppLifecycleState.hidden) {
      _showCallNotification();
    } else if (state == AppLifecycleState.resumed && !cubit.minimized) {
      CallNotifBridge.instance.hide();
    }
  }

  String _getInitials(String name) {
    if (name.trim().isEmpty) return "?";
    final parts = name.trim().split(' ');
    if (parts.length >= 2 && parts[1].isNotEmpty) {
      return '${parts[0][0]}${parts[1][0]}'.toUpperCase();
    }
    return name[0].toUpperCase();
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
        }
      },
      builder: (context, state) {
        final cubit = context.read<CallCubit>();

        final isEngineReady = state is CallEngineReady;
        final readyState = isEngineReady ? state : null;
        final isJoined = readyState?.isJoined ?? false;
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
              Container(
                width: double.infinity,
                height: double.infinity,
                decoration: const BoxDecoration(
                  gradient: LinearGradient(
                    colors: [
                      AppColors.callBackgroundTop,
                      AppColors.callBackgroundMiddle,
                      AppColors.callBackgroundBottom,
                    ],
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                  ),
                ),
                child: widget.isGroup && remoteUids.isNotEmpty
                    ? SafeArea(
                        child: Padding(
                          padding: const EdgeInsets.only(
                            top: 80,
                            left: 16,
                            right: 16,
                            bottom: 110,
                          ),
                          child: AnimatedCallGrid(
                            uids: [0, ...remoteUids],
                            spacing: 12,
                            itemBuilder: (context, uid) {
                              if (uid == 0) {
                                return GroupVoiceGridTile(
                                  name: "You",
                                  avatarEmoji: _ownAvatar ??
                                      widget.avatarEmoji,
                                  isMuted: isMuted,
                                  isLocal: true,
                                  isSpeaking: speakingUids.contains(0),
                                );
                              } else {
                                final info = _participants[uid];
                                return GroupVoiceGridTile(
                                  name: info?.name ?? "Participant $uid",
                                  avatarEmoji: info?.avatarEmoji,
                                  isMuted:
                                      mutedRemoteAudioUids.contains(uid),
                                  isLocal: false,
                                  isSpeaking: speakingUids.contains(uid),
                                );
                              }
                            },
                          ),
                        ),
                      )
                    : LayoutBuilder(
                        builder: (context, constraints) =>
                            SingleChildScrollView(
                          child: ConstrainedBox(
                            constraints:
                                BoxConstraints(minHeight: constraints.maxHeight),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                          AnimatedBuilder(
                            animation: _pulseAnimation,
                            builder: (context, child) {
                              return Transform.scale(
                                scale: remoteUids.isNotEmpty
                                    ? 1.0
                                    : _pulseAnimation.value,
                                child: Container(
                                  padding: const EdgeInsets.all(4),
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    boxShadow: [
                                      BoxShadow(
                                        color: Colors.lightBlueAccent
                                            .withValues(alpha: 0.35),
                                        blurRadius: 36,
                                        spreadRadius: 8,
                                      ),
                                    ],
                                  ),
                                  child: child,
                                ),
                              );
                            },
                            child: Container(
                              width: 120,
                              height: 120,
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                gradient: const LinearGradient(
                                  colors: [
                                    Colors.lightBlueAccent,
                                    Color(0xFF0288D1),
                                  ],
                                  begin: Alignment.topLeft,
                                  end: Alignment.bottomRight,
                                ),
                                border: Border.all(
                                  color: Colors.white.withValues(alpha: 0.4),
                                  width: 2.5,
                                ),
                              ),
                              child: Center(
                                child: widget.avatarEmoji != null &&
                                        widget.avatarEmoji!.isNotEmpty
                                    ? Text(
                                        widget.avatarEmoji!,
                                        style: const TextStyle(fontSize: 56),
                                      )
                                    : Text(
                                        _getInitials(widget.displayName),
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold,
                                          fontSize: 44,
                                        ),
                                      ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 28),
                          Text(
                            widget.displayName,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 24,
                              fontWeight: FontWeight.bold,
                              letterSpacing: 0.5,
                            ),
                          ),
                          const SizedBox(height: 14),
                          CallStatusDisplay(
                            isEngineReady: isEngineReady,
                            isJoined: isJoined,
                            isGroup: widget.isGroup,
                            remoteUsersCount: remoteUids.length,
                          ),
                              ],
                            ),
                          ),
                        ),
                      ),
              ),

              // 2. TOP GLASSMORPHIC BAR
              Positioned(
                top: 0,
                left: 0,
                right: 0,
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
                          onPressed: _minimizeCall,
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
                        // Own avatar chip
                        Container(
                          width: 38,
                          height: 38,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: const LinearGradient(
                              colors: [
                                Colors.lightBlueAccent,
                                Color(0xFF0288D1),
                              ],
                              begin: Alignment.topLeft,
                              end: Alignment.bottomRight,
                            ),
                            border: Border.all(
                              color: Colors.white.withValues(alpha: 0.4),
                              width: 1.5,
                            ),
                          ),
                          child: Center(
                            child: Text(
                              _ownAvatar ?? '👤',
                              style: const TextStyle(fontSize: 17),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
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
                    child: CircularProgressIndicator(color: Colors.white70),
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
    final cubit = CallCubit.instance;
    if (!cubit.isCallActive) {
      cubit.endCall(widget.callId);
      return;
    }
    cubit.minimize();
    _showCallNotification();
    if (mounted) Navigator.pop(context);
  }
}
