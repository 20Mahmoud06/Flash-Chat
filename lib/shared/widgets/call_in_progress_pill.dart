import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/core/routes/navigation_service.dart';
import 'package:flash_chat_app/core/routes/route_names.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/calls/cubit/call_cubit.dart';
import 'package:flash_chat_app/features/calls/cubit/call_state.dart';
import 'package:flash_chat_app/models/call_arguments.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Global "call in progress" pill shown when a call was minimized (voice
/// calls and video calls without PiP support). Tapping it reopens the call
/// page while the call keeps running.
class CallInProgressPill extends StatelessWidget {
  const CallInProgressPill({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return BlocBuilder<CallCubit, CallState>(
      buildWhen: (previous, current) {
        final cubit = CallCubit.instance;
        final prevVisible = previous is! CallInitial && previous is! CallEnded;
        final curVisible = current is! CallInitial && current is! CallEnded;
        return prevVisible != curVisible || cubit.minimized;
      },
      builder: (context, state) {
        final cubit = CallCubit.instance;
        final info = cubit.activeCall;
        if (!cubit.minimized || !cubit.isCallActive || info == null) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          minimum: const EdgeInsets.only(bottom: 12),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: Material(
              color: colors.bubbleMine,
              borderRadius: BorderRadius.circular(28),
              elevation: 6,
              shadowColor: Colors.black45,
              child: InkWell(
                borderRadius: BorderRadius.circular(28),
                onTap: () => _reopenCall(cubit),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(
                        width: 34,
                        height: 34,
                        decoration: const BoxDecoration(
                          color: Colors.white,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          info.isVideo
                              ? Icons.videocam_rounded
                              : Icons.phone_in_talk_rounded,
                          color: colors.bubbleMine,
                          size: 18,
                        ),
                      ),
                      const SizedBox(width: 10),
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 200),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              "Call in progress",
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            Text(
                              info.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                color: Colors.white70,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      const Icon(
                        Icons.keyboard_arrow_up_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  void _reopenCall(CallCubit cubit) {
    openActiveCall();
  }

  /// Reopens the running call's page (used by the pill and by the sticky
  /// voice-call notification's tap action).
  static void openActiveCall() {
    final cubit = CallCubit.instance;
    final info = cubit.activeCall;
    if (info == null) return;
    final nameParts = info.displayName.split(' ');
    final args = CallArguments(
      isGroup: info.isGroup,
      callId: info.callId,
      isVideo: info.isVideo,
      callerId: info.isGroup ? null : info.peerUid,
      callerName: info.displayName,
      callerAvatar: info.avatarEmoji,
      groupName: info.isGroup ? info.displayName : null,
      group: info.isGroup && info.groupId != null
          ? GroupModel(
              id: info.groupId!,
              name: info.displayName,
              avatarEmoji: info.avatarEmoji ?? '👥',
              memberUids: [],
              adminUids: [],
              createdBy: '',
              createdAt: Timestamp.now(),
            )
          : null,
      contact: !info.isGroup && info.peerUid != null
          ? UserModel(
              uid: info.peerUid!,
              email: '',
              firstName: nameParts.isNotEmpty ? nameParts.first : '',
              lastName: nameParts.length > 1
                  ? nameParts.sublist(1).join(' ')
                  : '',
              phoneNumber: '',
              avatarEmoji: info.avatarEmoji ?? '👤',
            )
          : null,
    );
    navigatorKey.currentState?.pushNamed(
      info.isVideo ? RouteNames.videoCallPage : RouteNames.voiceCallPage,
      arguments: args,
    );
  }
}
