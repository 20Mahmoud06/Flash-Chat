import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flash_chat_app/core/routes/navigation_service.dart';
import 'package:flash_chat_app/core/routes/route_names.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/calls/bloc/call_bloc.dart';
import 'package:flash_chat_app/features/calls/bloc/call_state.dart';
import 'package:flash_chat_app/features/calls/models/call_arguments.dart';
import 'package:flash_chat_app/features/groups/models/group_model.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

/// Global "call in progress" pill shown when a call was minimized (voice
/// calls and video calls without PiP support). Tapping it reopens the call
/// page while the call keeps running. A tap opens the call page exactly once
/// (rapid extra taps in the same instant are ignored), and the pill hides as
/// soon as a call page is on the stack and reappears when the call page is
/// popped back to the home screen.
class CallInProgressPill extends StatelessWidget {
  const CallInProgressPill({super.key});

  /// App-wide re-entry lock for [openActiveCall]. Set synchronously *before*
  /// the named push so a rapid second tap (pill or sticky notification) can
  /// never stack a duplicate call page — the navigator observer only counts
  /// the new page once the route is added to the stack, which is not
  /// synchronous with the tap. Cleared when the opened call page is popped.
  static bool _openingCall = false;

  /// Reopens the running call's page (used by the pill and by the sticky
  /// voice-call notification's tap action).
  static void openActiveCall() {
    final cubit = CallBloc.instance;
    final info = cubit.activeCall;
    if (info == null) return;
    // Re-entry guard: a second tap can arrive in the instant it takes for the
    // pushed route to land on the stack. Locking synchronously makes it a
    // no-op, so the call page opens at most once per tap.
    if (_openingCall) return;
    // A call page is already on the stack (rapid taps on the pill, or a tap
    // while the call page is still animating in): never stack a duplicate.
    if (CallRouteObserver.instance.openCallPages > 0) return;
    _openingCall = true;
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
              lastName:
                  nameParts.length > 1 ? nameParts.sublist(1).join(' ') : '',
              phoneNumber: '',
              avatarEmoji: info.avatarEmoji ?? '👤',
            )
          : null,
    );
    final navigator = navigatorKey.currentState;
    if (navigator == null) {
      _openingCall = false;
      return;
    }
    navigator
        .pushNamed(
          info.isVideo ? RouteNames.videoCallPage : RouteNames.voiceCallPage,
          arguments: args,
        )
        // The push future completes when the call page is popped — exactly
        // when the pill must become tappable again.
        .whenComplete(() => _openingCall = false);
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    // The pill renders above the Navigator, so it stays tappable even while
    // the call page is (re)opening. Hide it as soon as a call page exists on
    // the stack so it can never be tapped again to stack a duplicate.
    return ValueListenableBuilder<int>(
      valueListenable: CallRouteObserver.instance.openCallPagesNotifier,
      builder: (context, openCallPages, _) {
        return BlocBuilder<CallBloc, CallState>(
          buildWhen: (previous, current) {
            final cubit = CallBloc.instance;
            final prevVisible =
                previous is! CallInitial && previous is! CallEnded;
            final curVisible = current is! CallInitial && current is! CallEnded;
            return prevVisible != curVisible || cubit.minimized;
          },
          builder: (context, state) {
            final cubit = CallBloc.instance;
            final info = cubit.activeCall;
            if (_openingCall ||
                openCallPages > 0 ||
                !cubit.minimized ||
                !cubit.isCallActive ||
                info == null) {
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
                    onTap: openActiveCall,
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
                                const CustomText(
                                  text: "Call in progress",
                                  textColor: Colors.white,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                                CustomText(
                                  text: info.displayName,
                                  textColor: Colors.white70,
                                  fontSize: 11,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
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
      },
    );
  }
}