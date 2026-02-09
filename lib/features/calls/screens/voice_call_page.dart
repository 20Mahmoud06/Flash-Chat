import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../models/group_model.dart';
import '../../../models/user_model.dart';
import '../../../core/utils/call_utils.dart';
import '../cubit/call_cubit.dart';
import '../cubit/call_state.dart';
import '../widgets/call_controls.dart';
import '../widgets/call_status_display.dart';

class VoiceCallPage extends StatelessWidget {
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
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => CallCubit()
        ..initializeVoiceCall(
          channelName: buildChannelName(
            isGroup: isGroup,
            group: group,
            contact: contact,
            otherUid: callerId,
          ),
          callId: callId,
        ),
      child: _VoiceCallView(
        isGroup: isGroup,
        displayName: isGroup
            ? group?.name ?? groupName ?? "Group Call"
            : (contact?.fullName ?? callerName ?? "Unknown"),
        callId: callId,
      ),
    );
  }
}

class _VoiceCallView extends StatelessWidget {
  final bool isGroup;
  final String displayName;
  final String callId;

  const _VoiceCallView({
    required this.isGroup,
    required this.displayName,
    required this.callId,
  });

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

        final isEngineReady = state is CallEngineReady;
        final isJoined = isEngineReady ? (state as CallEngineReady).isJoined : false;
        final isMuted = isEngineReady ? (state as CallEngineReady).isMuted : false;
        final remoteUids = isEngineReady ? (state as CallEngineReady).remoteUids : <int>[];

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
                CallStatusDisplay(
                  displayName: displayName,
                  isEngineReady: isEngineReady,
                  isJoined: isJoined,
                  isGroup: isGroup,
                  remoteUsersCount: remoteUids.length,
                ),
                const SizedBox(height: 40),
                if (isEngineReady)
                  CallControls(
                    isMuted: isMuted,
                    isCameraOff: false,
                    isVideo: false,
                    onMuteToggle: () => cubit.toggleMute(),
                    onEndCall: () => cubit.endCall(callId),
                  )
                else
                  const CircularProgressIndicator(color: Colors.white),
              ],
            ),
          ),
        );
      },
    );
  }
}