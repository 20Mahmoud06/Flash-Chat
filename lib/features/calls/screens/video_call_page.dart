import 'package:agora_rtc_engine/agora_rtc_engine.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../models/group_model.dart';
import '../../../models/user_model.dart';
import '../../../core/utils/call_utils.dart';
import '../cubit/call_cubit.dart';
import '../cubit/call_state.dart';
import '../widgets/call_controls.dart';

class VideoCallPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CallCubit()
        ..initializeVideoCall(
          channelName: buildChannelName(
            isGroup: isGroup,
            group: group,
            groupId: groupId,
            contact: contact,
            otherUid: callerId,
          ),
          callId: callId,
        ),
      child: _VideoCallView(
        isGroup: isGroup,
        displayName: isGroup
            ? group?.name ?? groupName ?? "Group Call"
            : (contact?.fullName ?? callerName ?? "Unknown"),
        callId: callId,
      ),
    );
  }
}

class _VideoCallView extends StatefulWidget {
  final bool isGroup;
  final String displayName;
  final String callId;

  const _VideoCallView({
    required this.isGroup,
    required this.displayName,
    required this.callId,
  });

  @override
  State<_VideoCallView> createState() => _VideoCallViewState();
}

class _VideoCallViewState extends State<_VideoCallView>
    with SingleTickerProviderStateMixin {
  late AnimationController _controlsAnimation;
  bool _showControls = true;

  @override
  void initState() {
    super.initState();
    _controlsAnimation = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 300),
    )..forward();
  }

  @override
  void dispose() {
    _controlsAnimation.dispose();
    super.dispose();
  }

  Widget _buildLocalVideo(RtcEngine engine) {
    return AgoraVideoView(
      controller: VideoViewController(
        rtcEngine: engine,
        canvas: const VideoCanvas(
          uid: 0,
          renderMode: RenderModeType.renderModeFit,
        ),
      ),
    );
  }

  Widget _buildRemoteVideo(RtcEngine engine, int uid, String channelName) {
    return AgoraVideoView(
      controller: VideoViewController.remote(
        rtcEngine: engine,
        canvas: VideoCanvas(
          uid: uid,
          renderMode: RenderModeType.renderModeFit,
        ),
        connection: RtcConnection(channelId: channelName),
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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(state.message)),
          );
        } else if (state is CallEnded) {
          Navigator.pop(context);
        }
      },
      builder: (context, state) {
        final cubit = context.read<CallCubit>();
        final engine = cubit.engine;

        final isEngineReady = state is CallEngineReady;
        final remoteUids = isEngineReady ? (state as CallEngineReady).remoteUids : <int>[];
        final isCameraOff = isEngineReady ? (state as CallEngineReady).isCameraOff : false;
        final isMuted = isEngineReady ? (state as CallEngineReady).isMuted : false;

        return GestureDetector(
          onTap: () {
            setState(() => _showControls = !_showControls);
            _showControls
                ? _controlsAnimation.forward()
                : _controlsAnimation.reverse();
          },
          child: Scaffold(
            backgroundColor: Colors.black,
            appBar: AppBar(
              backgroundColor: Colors.black.withOpacity(0.5),
              title: Text(
                widget.displayName,
                style: const TextStyle(color: Colors.white),
              ),
            ),
            body: Stack(
              children: [
                // Video display
                if (!isEngineReady || engine == null)
                  const Center(
                    child: CircularProgressIndicator(color: Colors.white),
                  )
                else if (remoteUids.isEmpty)
                  Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          "Calling ${widget.displayName}...",
                          style: const TextStyle(color: Colors.white, fontSize: 18),
                        ),
                        const SizedBox(height: 20),
                        const CircularProgressIndicator(color: Colors.white),
                      ],
                    ),
                  )
                else if (!widget.isGroup && remoteUids.length == 1)
                  // 1-1: Full remote video
                    _buildRemoteVideo(
                      engine,
                      remoteUids[0],
                      buildChannelName(
                        isGroup: widget.isGroup,
                        group: null,
                        contact: null,
                        otherUid: null,
                      ),
                    )
                  else
                  // Group: Grid view
                    LayoutBuilder(
                      builder: (context, constraints) {
                        List<int> allUids = [0, ...remoteUids];
                        int count = allUids.length;
                        int crossCount = count == 1
                            ? 1
                            : (count <= 4 ? 2 : (count <= 9 ? 3 : 4));
                        double spacing = 4.0;
                        double padding = 4.0;
                        int rows = (count / crossCount).ceil();
                        double availableHeight = constraints.maxHeight -
                            2 * padding -
                            (rows - 1) * spacing;
                        double tileHeight = availableHeight / rows;
                        double tileWidth = (constraints.maxWidth -
                            2 * padding -
                            (crossCount - 1) * spacing) /
                            crossCount;
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
                              if (isCameraOff) {
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
                                video = _buildLocalVideo(engine);
                              }
                            } else {
                              video = _buildRemoteVideo(
                                engine,
                                uid,
                                buildChannelName(
                                  isGroup: widget.isGroup,
                                  group: null,
                                  contact: null,
                                  otherUid: null,
                                ),
                              );
                            }

                            return ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: video,
                            );
                          },
                        );
                      },
                    ),

                // Small local preview (1-1 only)
                if (isEngineReady && !isCameraOff && !widget.isGroup && engine != null)
                  Positioned(
                    right: 16,
                    top: 16,
                    width: 120,
                    height: 160,
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(8),
                      child: _buildLocalVideo(engine),
                    ),
                  ),

                // Controls
                if (isEngineReady)
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
              ],
            ),
          ),
        );
      },
    );
  }
}