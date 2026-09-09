import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/utils/call_utils.dart';
import 'package:flash_chat_app/core/utils/last_seen_formatter.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/services/block/block_service.dart';
import 'package:flash_chat_app/services/mute/mute_service.dart';
import 'package:flash_chat_app/services/presence/presence_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:quickalert/quickalert.dart';
import '../../../core/routes/route_names.dart';
import '../../../core/utils/page_transition.dart';
import '../../../models/call_arguments.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../calls/services/call_service.dart';
import 'media_gallery_screen.dart';

class SenderProfileScreen extends StatefulWidget {
  final UserModel user;
  const SenderProfileScreen({super.key, required this.user});

  @override
  State<SenderProfileScreen> createState() => _SenderProfileScreenState();
}

class _SenderProfileScreenState extends State<SenderProfileScreen> {
  bool _isBlocked = false;
  bool _blockedMe = false;
  bool _loading = true;
  String? _myNickname;
  DateTime? _mutedUntil;
  bool _mutedAlways = false;
  Duration? _mutedDuration;

  @override
  void initState() {
    super.initState();
    _loadBlockState();
  }

  Future<void> _loadBlockState() async {
    try {
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      final myDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(myUid)
          .get();
      final nicknames = myDoc.data()?['nicknames'];
      final myNickname =
          nicknames is Map ? nicknames[widget.user.uid]?.toString() : null;
      final mutedChats = myDoc.data()?['mutedChats'];
      final mutedEntry =
          mutedChats is Map ? mutedChats[widget.user.uid] : null;
      DateTime? mutedUntil;
      Duration? mutedDuration;
      var mutedAlways = false;
      if (mutedEntry is Map) {
        final until = mutedEntry['until'];
        if (until == null) {
          mutedAlways = true;
        } else if (until is Timestamp) {
          mutedUntil = until.toDate();
          if (mutedUntil.isAfter(DateTime.now())) {
            final createdAt = mutedEntry['createdAt'];
            if (createdAt is Timestamp) {
              mutedDuration = mutedUntil.difference(createdAt.toDate());
            }
          } else {
            mutedUntil = null;
          }
        }
      }
      final blocked = await BlockService.getBlockedUids(myUid);
      final contactDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(widget.user.uid)
          .get();
      final blockedMe = contactDoc.exists &&
          List<String>.from(contactDoc.data()?['blockedUids'] ?? const [])
              .contains(myUid);
      if (mounted) {
        setState(() {
          _myNickname = myNickname;
          _isBlocked = blocked.contains(widget.user.uid);
          _blockedMe = blockedMe;
          _mutedUntil = mutedUntil;
          _mutedAlways = mutedAlways;
          _mutedDuration = mutedDuration;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load block state: $e');
      if (mounted) setState(() => _loading = false);
    }
  }

  /// Saves a nickname on my own user doc (`nicknames.<contactUid>`) — only I
  /// ever see it. An empty value removes it.
  Future<void> _saveNickname(String value) async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance.collection('users').doc(myUid);
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await ref.update({
        'nicknames.${widget.user.uid}': FieldValue.delete(),
      });
    } else {
      await ref.update({
        'nicknames.${widget.user.uid}': trimmed,
      });
    }
    if (mounted) {
      setState(() => _myNickname = trimmed.isEmpty ? null : trimmed);
    }
  }

  Future<void> _showNicknameDialog() async {
    final colors = FcAppColors.of(context);
    final controller = TextEditingController(text: _myNickname ?? '');
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: colors.surface,
        title: CustomText(
          text: 'Nickname',
          fontSize: 18.sp,
          fontWeight: FontWeight.bold,
          textColor: colors.textPrimary,
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CustomText(
              text:
                  'Only you can see this name. It replaces ${widget.user.fullName} in your chats.',
              fontSize: 13.sp,
              textColor: colors.textSecondary,
            ),
            SizedBox(height: 14.h),
            TextField(
              controller: controller,
              autofocus: true,
              maxLength: 30,
              decoration: InputDecoration(
                hintText: 'Enter a nickname',
                hintStyle: TextStyle(color: colors.textWeak),
                filled: true,
                fillColor: colors.tile,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ],
        ),
        actions: [
          if (_myNickname != null)
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, '__clear__'),
              child: CustomText(
                text: 'Remove',
                textColor: Colors.red.shade400,
                fontSize: 14.sp,
              ),
            ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: CustomText(
              text: 'Cancel',
              textColor: Colors.grey,
              fontSize: 14.sp,
            ),
          ),
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, controller.text),
            child: CustomText(
              text: 'Save',
              textColor: Colors.lightBlueAccent,
              fontSize: 14.sp,
            ),
          ),
        ],
      ),
    );
    if (result == null || !mounted) return;
    if (result == '__clear__') {
      await _saveNickname('');
    } else if (result.trim() != (_myNickname ?? '')) {
      try {
        await _saveNickname(result);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: CustomText(
                text: result.trim().isEmpty
                    ? 'Nickname removed'
                    : 'Nickname saved',
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
  }

  /// Mute/unmute state lives on my own user doc (`mutedChats.<contactUid>`)
  /// so only I can change it. `choice == always` mutes forever.
  Future<void> _applyMuteChoice(_MuteChoice choice) async {
    try {
      if (choice == _MuteChoice.unmute) {
        await MuteService.unmute(widget.user.uid);
      } else if (choice == _MuteChoice.always) {
        await MuteService.setMute(widget.user.uid);
      } else {
        await MuteService.setMute(widget.user.uid, duration: choice.duration);
      }
      if (mounted) {
        setState(() {
          if (choice == _MuteChoice.unmute) {
            _mutedUntil = null;
            _mutedAlways = false;
            _mutedDuration = null;
          } else if (choice == _MuteChoice.always) {
            _mutedUntil = null;
            _mutedAlways = true;
            _mutedDuration = null;
          } else {
            _mutedUntil = DateTime.now().add(choice.duration!);
            _mutedAlways = false;
            _mutedDuration = choice.duration;
          }
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: CustomText(
              text: choice == _MuteChoice.unmute
                  ? 'Notifications enabled'
                  : choice == _MuteChoice.always
                      ? 'Notifications muted forever'
                      : 'Muted for ${choice.label.toLowerCase()}',
            ),
            backgroundColor: Colors.lightBlueAccent,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: CustomText(text: 'Failed to update mute. Try again.'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _showMuteSheet() async {
    final colors = FcAppColors.of(context);
    final isMuted = _mutedAlways || _mutedUntil != null;
    final result = await showModalBottomSheet<_MuteChoice>(
      context: context,
      backgroundColor: colors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: EdgeInsets.symmetric(vertical: 16.h),
              child: CustomText(
                text: 'Mute ${widget.user.firstName}',
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                textColor: colors.textPrimary,
              ),
            ),
            if (isMuted)
              _muteOption(
                sheetContext,
                choice: _MuteChoice.unmute,
                label: 'Unmute',
                icon: Icons.notifications_active_outlined,
                isRed: true,
              ),
            _muteOption(
              sheetContext,
              choice: _MuteChoice.oneHour,
              label: 'For 1 hour',
            ),
            _muteOption(
              sheetContext,
              choice: _MuteChoice.eightHours,
              label: 'For 8 hours',
            ),
            _muteOption(
              sheetContext,
              choice: _MuteChoice.oneDay,
              label: 'For 24 hours',
            ),
            _muteOption(
              sheetContext,
              choice: _MuteChoice.oneWeek,
              label: 'For 1 week',
            ),
            _muteOption(
              sheetContext,
              choice: _MuteChoice.always,
              label: 'Always',
              icon: Icons.notifications_off_outlined,
            ),
            SizedBox(height: 8.h),
          ],
        ),
      ),
    );
    if (result == null) return;
    await _applyMuteChoice(result);
  }

  Widget _muteOption(
    BuildContext context, {
    required _MuteChoice choice,
    required String label,
    IconData? icon,
    bool isRed = false,
  }) {
    final colors = FcAppColors.of(context);
    final selected = choice == _MuteChoice.always
        ? _mutedAlways
        : choice == _MuteChoice.unmute
            ? !_mutedAlways && _mutedUntil == null
            : _isMutedFor(choice.duration!);
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: (isRed ? Colors.red : Colors.lightBlueAccent)
            .withValues(alpha: 0.1),
        child: Icon(
          icon ?? Icons.notifications_off_outlined,
          color: isRed ? Colors.red : Colors.lightBlueAccent,
          size: 20,
        ),
      ),
      title: CustomText(
        text: label,
        fontSize: 15.sp,
        fontWeight: FontWeight.w500,
        textColor: isRed ? Colors.red : colors.textPrimary,
      ),
      trailing: selected
          ? const Icon(Icons.check_circle,
              color: Colors.lightBlueAccent, size: 22)
          : null,
      onTap: () => Navigator.pop(context, choice),
    );
  }

  bool _isMutedFor(Duration duration) {
    final until = _mutedUntil;
    if (until == null || _mutedAlways || _mutedDuration == null) return false;
    return _mutedDuration == duration;
  }

  String get _muteSubtitle {
    if (_mutedAlways) return 'Muted forever';
    if (_mutedUntil != null) {
      return 'Muted until ${DateFormat('EEE, d MMM, h:mm a').format(_mutedUntil!)}';
    }
    return 'Notifications are on';
  }

  void _showBlockConfirmation() {
    QuickAlert.show(
      context: context,
      type: QuickAlertType.confirm,
      title: 'Block ${widget.user.fullName}?',
      text:
          'You will no longer receive messages or calls from this user. You can unblock them anytime from your profile.',
      confirmBtnText: 'Block',
      cancelBtnText: 'Cancel',
      confirmBtnColor: Colors.red.shade400,
      showCancelBtn: true,
      backgroundColor: FcAppColors.of(context).surface,
      headerBackgroundColor: FcAppColors.of(context).surface,
      titleColor: FcAppColors.of(context).textPrimary,
      textColor: FcAppColors.of(context).textSecondary,
      onConfirmBtnTap: () async {
        Navigator.of(context, rootNavigator: true).pop();
        try {
          await BlockService.blockUser(widget.user.uid);
          if (mounted) {
            setState(() => _isBlocked = true);
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: CustomText(
                    text: '${widget.user.fullName} has been blocked'),
                backgroundColor: Colors.red.shade400,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: CustomText(text: 'Failed to block user. Try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _unblock() async {
    try {
      await BlockService.unblockUser(widget.user.uid);
      if (mounted) {
        setState(() => _isBlocked = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: CustomText(
                text: '${widget.user.fullName} has been unblocked'),
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

  Future<void> _startCall(bool isVideo) async {
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
    if (_isBlocked || _blockedMe) {
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
      debugPrint('Joining existing ${isVideo ? "video" : "voice"} call: $callId');
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
    Navigator.pushNamed(
      context,
      isVideo ? RouteNames.videoCallPage : RouteNames.voiceCallPage,
      arguments: CallArguments(
        isGroup: false,
        contact: widget.user,
        callerName: (_myNickname != null && _myNickname!.isNotEmpty)
            ? _myNickname!
            : widget.user.fullName,
        callId: callId,
        isVideo: isVideo,
      ),
    );
  }

  /// Live presence status shown right under the contact's name.
  ///
  /// "Online" (green) while the user is actively online; otherwise a
  /// relative "active X minutes ago" from their last seen. Nothing is shown
  /// when they disabled their online status or have never been online.
  Widget _buildPresenceStatus() {
    final colors = FcAppColors.of(context);
    if (widget.user.isDeleted) return const SizedBox.shrink();
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('presence')
          .doc(widget.user.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null || !data.exists) return const SizedBox.shrink();
        final lastSeen = data['lastSeen'];
        final isOnline = data['online'] == true;
        final isStale = lastSeen is Timestamp &&
            DateTime.now()
                    .difference(lastSeen.toDate())
                    .compareTo(PresenceService.presenceStaleAfter) >
                0;
        if (isOnline && !isStale) {
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 8.w,
                height: 8.w,
                decoration: const BoxDecoration(
                  color: Colors.greenAccent,
                  shape: BoxShape.circle,
                ),
              ),
              SizedBox(width: 6.w),
              CustomText(
                text: 'Online',
                fontSize: 14.sp,
                textColor: Colors.greenAccent,
                fontWeight: FontWeight.w600,
              ),
            ],
          );
        }
        if (lastSeen is Timestamp) {
          return CustomText(
            text: formatLastSeenCompact(lastSeen.toDate()),
            fontSize: 14.sp,
            textColor: colors.textSecondary,
          );
        }
        return const SizedBox.shrink();
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    final canCall = !widget.user.isDeleted;
    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: AppBar(
        title: CustomText(
            text: "Contact Info",
            textColor: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 20.sp),
        backgroundColor: Colors.lightBlueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          if (canCall) ...[
            IconButton(
              icon: const Icon(Icons.call, color: Colors.white),
              tooltip: 'Call',
              onPressed: () => _startCall(false),
            ),
            IconButton(
              icon: const Icon(Icons.videocam, color: Colors.white),
              tooltip: 'Video Call',
              onPressed: () => _startCall(true),
            ),
          ],
        ],
      ),
      body: Center(
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              SizedBox(height: 40.h),
              CircleAvatar(
                radius: 60.r,
                backgroundColor: colors.avatarBackground,
                child: CustomText(
                    text: widget.user.isDeleted
                        ? '❌'
                        : widget.user.avatarEmoji,
                    fontSize: 60.sp),
              ),
              SizedBox(height: 20.h),
              CustomText(
                  text: (_myNickname != null && _myNickname!.isNotEmpty)
                      ? _myNickname!
                      : widget.user.fullName,
                  fontSize: 24.sp, fontWeight: FontWeight.bold
              ),
              SizedBox(height: 6.h),
              _buildPresenceStatus(),
              SizedBox(height: 14.h),
              if (widget.user.isDeleted)
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.red.shade200),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.remove_circle_outline,
                          color: Colors.red, size: 20),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: CustomText(
                          text: 'This user has deleted their account. '
                              'You cannot message or call them.',
                          fontSize: 13.sp,
                          textColor: Colors.red,
                        ),
                      ),
                    ],
                  ),
                ),
              if (_blockedMe)
                Container(
                  margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
                  padding: EdgeInsets.all(12.w),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(12.r),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.block, color: Colors.orange.shade700, size: 20),
                      SizedBox(width: 8.w),
                      Expanded(
                        child: CustomText(
                          text:
                              'This user has blocked you. You cannot message or call them.',
                          fontSize: 13.sp,
                          textColor: Colors.orange.shade900,
                        ),
                      ),
                    ],
                  ),
                ),
              _buildInfoCard(
                context,
                icon: Icons.phone_outlined,
                title: "Phone",
                subtitle: widget.user.phoneNumber,
                color: Colors.green,
              ),
              _buildInfoCard(
                context,
                icon: Icons.email_outlined,
                title: "Email",
                subtitle: widget.user.email,
                color: Colors.orange,
              ),
              if (widget.user.bio != null && widget.user.bio!.isNotEmpty)
                _buildInfoCard(
                  context,
                  icon: Icons.info_outline,
                  title: "Bio",
                  subtitle: widget.user.bio!,
                  color: Colors.lightBlue,
                ),
              SizedBox(height: 16.h),
              Card(
                margin:
                    EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  side: BorderSide(color: colors.divider),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.tile,
                    child: const Icon(
                      Icons.badge_outlined,
                      color: Colors.lightBlueAccent,
                    ),
                  ),
                  title: CustomText(
                    text: 'Nickname',
                    fontWeight: FontWeight.w600,
                    textColor: colors.textPrimary,
                  ),
                  subtitle: CustomText(
                    text: (_myNickname == null || _myNickname!.isEmpty)
                        ? 'Only visible to you'
                        : _myNickname!,
                    fontSize: 13.sp,
                    textColor: _myNickname == null
                        ? colors.textSecondary
                        : Colors.lightBlueAccent,
                    fontWeight: _myNickname == null
                        ? FontWeight.normal
                        : FontWeight.w600,
                  ),
                  trailing: const Icon(
                    Icons.edit_outlined,
                    color: Colors.grey,
                  ),
                  onTap: _showNicknameDialog,
                ),
              ),
              SizedBox(height: 16.h),
              Card(
                margin:
                    EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
                elevation: 2,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12.r),
                  side: BorderSide(color: colors.divider),
                ),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: colors.tile,
                    child: Icon(
                      _mutedAlways || _mutedUntil != null
                          ? Icons.notifications_off_outlined
                          : Icons.notifications_none,
                      color: _mutedAlways || _mutedUntil != null
                          ? Colors.orange
                          : Colors.lightBlueAccent,
                    ),
                  ),
                  title: CustomText(
                    text: 'Mute notifications',
                    fontWeight: FontWeight.w600,
                    textColor: colors.textPrimary,
                  ),
                  subtitle: CustomText(
                    text: _muteSubtitle,
                    fontSize: 13.sp,
                    textColor: _mutedAlways || _mutedUntil != null
                        ? Colors.orange
                        : colors.textSecondary,
                    fontWeight: _mutedAlways || _mutedUntil != null
                        ? FontWeight.w600
                        : FontWeight.normal,
                  ),
                  trailing: const Icon(
                    Icons.chevron_right,
                    color: Colors.grey,
                  ),
                  onTap: _showMuteSheet,
                ),
              ),
              SizedBox(height: 16.h),
              _buildMediaSection(context),
              SizedBox(height: 16.h),
              if (_loading)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: CircularProgressIndicator(color: Colors.lightBlueAccent),
                )
              else if (widget.user.isDeleted)
                const SizedBox.shrink()
              else
                Card(
                  margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
                  elevation: 2,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12.r)),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor:
                          _isBlocked ? Colors.red.shade50 : colors.tile,
                      child: Icon(
                        _isBlocked ? Icons.block : Icons.block_outlined,
                        color: _isBlocked ? Colors.red : colors.textSecondary,
                      ),
                    ),
                    title: CustomText(
                      text: _isBlocked ? 'Unblock ${widget.user.firstName}' : 'Block ${widget.user.firstName}',
                      fontWeight: FontWeight.w600,
                      textColor: _isBlocked ? Colors.red : colors.textPrimary,
                    ),
                    subtitle: CustomText(
                      text: _isBlocked
                          ? 'This user is currently blocked'
                          : 'Stop receiving messages and calls from this user',
                      fontSize: 13.sp,
                      textColor: colors.textSecondary,
                    ),
                    trailing: Icon(
                      _isBlocked ? Icons.lock_open : Icons.chevron_right,
                      color: _isBlocked ? Colors.red : colors.textWeak,
                    ),
                    onTap: _isBlocked ? _unblock : _showBlockConfirmation,
                  ),
                ),
              SizedBox(height: 24.h),
            ],
          ),
        ),
      ),
    );
  }

  static final _urlRegExp = RegExp(r'''(https?://|www\.)[^\s<>"']+''');

  String get _chatId => buildOneOnOneChatId(
        FirebaseAuth.instance.currentUser!.uid,
        widget.user.uid,
      );

  void _openGallery(BuildContext context, int tab) {
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

  Widget _buildMediaSection(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 4.h),
      elevation: 2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16.r),
        side: BorderSide(color: colors.divider),
      ),
      child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('chats')
            .doc(_chatId)
            .collection('messages')
            .snapshots(),
        builder: (context, snapshot) {
          var photos = 0, videos = 0, voice = 0, links = 0;
          final docs = snapshot.data?.docs ?? const [];
          for (final doc in docs) {
            final data = doc.data();
            if (data['isDeleted'] == true) continue;
            final type = data['messageType'];
            if (type == 'image') {
              photos += (data['mediaUrls'] as List?)?.length ?? 0;
            } else if (type == 'video') {
              videos++;
            } else if (type == 'voice') {
              voice++;
            // Text messages (also the legacy ones sent before the
            // `messageType` field existed, whose type is null) count as
            // links when their text contains a URL.
            } else if ((type == null || type == 'text') &&
                _urlRegExp.hasMatch(data['text'] ?? '')) {
              links++;
            }
          }
          return Padding(
            padding: EdgeInsets.symmetric(vertical: 12.h),
            child: Row(
              children: [
                _MediaTile(
                  icon: Icons.photo_library_outlined,
                  color: Colors.blue,
                  label: 'Photos',
                  count: photos,
                  onTap: () => _openGallery(context, 0),
                ),
                _MediaTile(
                  icon: Icons.videocam_outlined,
                  color: Colors.deepOrange,
                  label: 'Videos',
                  count: videos,
                  onTap: () => _openGallery(context, 1),
                ),
                _MediaTile(
                  icon: Icons.mic_none,
                  color: Colors.green,
                  label: 'Voice',
                  count: voice,
                  onTap: () => _openGallery(context, 2),
                ),
                _MediaTile(
                  icon: Icons.link,
                  color: Colors.purple,
                  label: 'Links',
                  count: links,
                  onTap: () => _openGallery(context, 3),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildInfoCard(
      BuildContext context,
      {required IconData icon,
        required String title,
        required String subtitle,
        required Color color}) {
    final colors = FcAppColors.of(context);
    return Card(
      margin: EdgeInsets.symmetric(horizontal: 20.w, vertical: 8.h),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12.r)),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: color.withValues(alpha: 0.1),
          child: Icon(icon, color: color),
        ),
        title: CustomText(
            text: title,
            fontWeight: FontWeight.w600, textColor: colors.textSecondary),
        subtitle: CustomText(text: subtitle,fontSize: 15.sp),
      ),
    );
  }
}

class _MuteChoice {
  const _MuteChoice._(this.label, [this.duration]);

  final String label;
  final Duration? duration;

  static const unmute = _MuteChoice._('Unmute');
  static const always = _MuteChoice._('Always');
  static const oneHour = _MuteChoice._('1 hour', Duration(hours: 1));
  static const eightHours = _MuteChoice._('8 hours', Duration(hours: 8));
  static const oneDay = _MuteChoice._('24 hours', Duration(days: 1));
  static const oneWeek = _MuteChoice._('1 week', Duration(days: 7));
}

class _MediaTile extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final int count;
  final VoidCallback onTap;

  const _MediaTile({
    required this.icon,
    required this.color,
    required this.label,
    required this.count,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(12.r),
        child: Padding(
          padding: EdgeInsets.symmetric(vertical: 6.h),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 22.r,
                backgroundColor: color.withValues(alpha: 0.12),
                child: Icon(icon, color: color, size: 22.sp),
              ),
              SizedBox(height: 6.h),
              CustomText(
                text: '$count',
                fontSize: 16.sp,
                fontWeight: FontWeight.bold,
                textColor: colors.textPrimary,
              ),
              CustomText(
                text: label,
                fontSize: 12.sp,
                textColor: colors.textSecondary,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
