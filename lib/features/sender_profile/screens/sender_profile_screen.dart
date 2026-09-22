import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/routes/route_names.dart';
import '../../../core/theme/app_theme.dart';
import '../../../core/utils/call_utils.dart';
import '../../../core/utils/page_transition.dart';
import '../../../services/block/block_service.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../calls/models/call_arguments.dart';
import '../../calls/services/call_service.dart';
import '../../profile/models/user_model.dart';
import '../../profile/screens/media_gallery_screen.dart';
import '../cubit/sender_profile_cubit.dart';
import '../cubit/sender_profile_state.dart';
import '../widgets/sender_profile_actions.dart';
import '../widgets/sender_profile_block_confirm.dart';
import '../widgets/sender_profile_contact_info.dart';
import '../widgets/sender_profile_header.dart';
import '../widgets/sender_profile_nickname_dialog.dart';

/// Contact info screen for a 1-on-1 chat: nickname, block, media counts, and
/// call shortcuts. Block/nickname state lives on my own user doc so only I can
/// change it.
class SenderProfileScreen extends StatefulWidget {
  final UserModel user;

  const SenderProfileScreen({super.key, required this.user});

  @override
  State<SenderProfileScreen> createState() => _SenderProfileScreenState();
}

class _SenderProfileScreenState extends State<SenderProfileScreen> {
  late final SenderProfileCubit _cubit;

  String get _chatId => buildOneOnOneChatId(
        FirebaseAuth.instance.currentUser!.uid,
        widget.user.uid,
      );

  @override
  void initState() {
    super.initState();
    _cubit = SenderProfileCubit(contactUid: widget.user.uid)..loadState();
  }

  @override
  void dispose() {
    _cubit.close();
    super.dispose();
  }

  Future<void> _showNicknameDialog(SenderProfileState state) async {
    final result = await showSenderProfileNicknameDialog(
      context,
      currentNickname: state.myNickname,
      contactFullName: widget.user.fullName,
    );
    if (result == null || !mounted) return;
    try {
      await _cubit.updateNickname(result);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: CustomText(
              text:
                  result.trim().isEmpty ? 'Nickname removed' : 'Nickname saved',
            ),
            backgroundColor: Colors.lightBlueAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: CustomText(text: 'Failed to save nickname'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  void _showBlockConfirmation() {
    showSenderProfileBlockConfirmation(
      context: context,
      user: widget.user,
      cubit: _cubit,
    );
  }

  Future<void> _unblock() async {
    try {
      await _cubit.unblockUser();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                CustomText(text: '${widget.user.fullName} has been unblocked'),
            backgroundColor: Colors.lightBlueAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: CustomText(text: 'Failed to unblock user. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _startCall(bool isVideo, SenderProfileState state) async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (widget.user.uid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: CustomText(text: 'Cannot call yourself')));
      return;
    }
    if (!ConnectivityService.instance.isConnected.value) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: CustomText(
              text: 'You are offline. You cannot make calls right now.'),
          backgroundColor: Colors.orange,
        ));
      return;
    }
    if (state.isBlocked || state.blockedMe) {
      ScaffoldMessenger.of(context)
        ..hideCurrentSnackBar()
        ..showSnackBar(const SnackBar(
          content: CustomText(text: 'You cannot call this user.'),
          backgroundColor: Colors.red,
        ));
      return;
    }

    final channel = buildChannelName(isGroup: false, contact: widget.user);

    final existingCallId = await CallService.getActiveCallId(channel, isVideo);
    String callId;
    if (existingCallId != null) {
      callId = existingCallId;
      debugPrint(
          'Joining existing ${isVideo ? "video" : "voice"} call: $callId');
    } else {
      try {
        callId = await CallService.startCall(
            receiver: widget.user,
            group: null,
            isVideo: isVideo,
            channelName: channel);
      } on CallBlockedException {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(const SnackBar(
            content: CustomText(text: 'You cannot call this user.'),
            backgroundColor: Colors.red,
          ));
        return;
      }
    }

    if (!mounted) return;
    final myNickname = state.myNickname;
    Navigator.pushNamed(
      context,
      isVideo ? RouteNames.videoCallPage : RouteNames.voiceCallPage,
      arguments: CallArguments(
        isGroup: false,
        contact: widget.user,
        callerName: (myNickname != null && myNickname.isNotEmpty)
            ? myNickname
            : widget.user.fullName,
        callId: callId,
        isVideo: isVideo,
      ),
    );
  }

  void _openGallery(int tab) {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            MediaGalleryScreen(
          contact: widget.user,
          chatId: _chatId,
          initialTab: tab,
        ),
        transitionsBuilder: PageTransition.slideFromRight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<SenderProfileCubit>.value(
      value: _cubit,
      child: BlocBuilder<SenderProfileCubit, SenderProfileState>(
        builder: (context, state) {
          final colors = FcAppColors.of(context);
          final canCall = !widget.user.isDeleted;
          final myNickname = state.myNickname;
          final displayName =
              (myNickname != null && myNickname.isNotEmpty)
                  ? myNickname
                  : widget.user.fullName;

          return Scaffold(
            backgroundColor: colors.surfaceMuted,
            appBar: AppBar(
              title: CustomText(
                text: 'Contact Info',
                textColor: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 20.sp,
              ),
              backgroundColor: Colors.lightBlueAccent,
              iconTheme: const IconThemeData(color: Colors.white),
              actions: [
                if (canCall) ...[
                  IconButton(
                    icon: const Icon(Icons.call, color: Colors.white),
                    tooltip: 'Call',
                    onPressed: () => _startCall(false, state),
                  ),
                  IconButton(
                    icon: const Icon(Icons.videocam, color: Colors.white),
                    tooltip: 'Video Call',
                    onPressed: () => _startCall(true, state),
                  ),
                ],
              ],
            ),
            body: Center(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    SenderProfileHeader(
                      user: widget.user,
                      displayName: displayName,
                      blockedMe: state.blockedMe,
                    ),
                    SenderProfileContactInfo(user: widget.user),
                    SenderProfileActions(
                      user: widget.user,
                      state: state,
                      chatId: _chatId,
                      onEditNickname: () => _showNicknameDialog(state),
                      onOpenGallery: _openGallery,
                      onToggleBlock: state.isBlocked
                          ? _unblock
                          : _showBlockConfirmation,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}