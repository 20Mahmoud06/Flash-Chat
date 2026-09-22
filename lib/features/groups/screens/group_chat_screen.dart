import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/groups/models/group_model.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/routes/route_names.dart';
import '../../../core/utils/call_utils.dart';
import '../../../core/utils/page_transition.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/fcm/fcm_service.dart';
import '../../../services/notifications/missed_notifications_service.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../calls/bloc/call_bloc.dart';
import '../../calls/models/call_arguments.dart';
import '../../calls/services/call_service.dart';
import '../../calls/services/group_call_tracker.dart';
import '../../chat/cubit/chat_cubit.dart';
import '../../chat/cubit/chat_state.dart';
import '../../chat/services/active_chat.dart';
import '../../chat/widgets/chat_call_helpers.dart';
import '../../chat/widgets/chat_message_scroll.dart';
import '../../chat/widgets/chat_scroll_down_button.dart';
import '../../chat/widgets/chat_search_overlay.dart';
import '../../chat/widgets/message_composer/message_composer.dart';
import '../../chat/widgets/typing_indicator.dart';
import '../widgets/group_chat_app_bar.dart';
import '../widgets/group_chat_banners.dart';
import '../widgets/group_chat_composers.dart';
import '../widgets/group_chat_messages_body.dart';
import 'group_info_screen.dart' show GroupInfoScreen;

class GroupChatScreen extends StatefulWidget {
  final GroupModel group;

  /// When set, the chat opens scrolled to this message (used by the
  /// favorites list to open the exact starred message).
  final String? initialJumpMessageId;

  const GroupChatScreen({
    super.key,
    required this.group,
    this.initialJumpMessageId,
  });

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  late final String _chatId;
  late String _chatName;
  late String _chatAvatar;

  Map<String, UserModel> _groupMembers = {};

  /// Live member list of the group, kept in sync from the group document so
  /// the app bar count, call buttons and the removed-from-group guard react
  /// immediately when members are added/removed.
  List<String> _groupMemberUids = [];
  Map<String, Timestamp> _groupJoinTimestamps = {};
  Map<String, Timestamp> _groupLeaveTimestamps = {};
  bool _removedFromGroup = false;
  bool _isGroupDeleted = false;
  StreamSubscription<DocumentSnapshot>? _groupSub;

  /// My account can be tombstoned (isDeleted) live: keep read access, but
  /// stop sending/calling.
  bool _isMyAccountDeleted = false;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};

  /// True when the user has scrolled up far enough that the jump-to-bottom
  /// arrow button should appear.
  bool _showScrollDownBtn = false;

  // ----- in-chat search -----
  bool _searchActive = false;
  String? _highlightedMessageId;
  Timer? _highlightTimer;

  /// Created lazily in [build] so the State itself can reach it (its own
  /// context sits ABOVE the BlocProvider, so `context.read<ChatCubit>()`
  /// from State methods would throw ProviderNotFoundException).
  ChatCubit? _chatCubit;

  @override
  void initState() {
    super.initState();

    final group = widget.group;

    _chatId = group.id;
    _chatName = group.name;
    _chatAvatar = group.avatarEmoji;

    activeGroupId = group.id;
    activeChatUserId = null;

    // Clear this group's notifications (tray stays tidy when reading).
    FcmService.clearChatNotifications(group.id, isGroup: true);

    // Tell the missed-notifications backfill this group is now being read, so
    // it stops notifying (and doesn't re-notify) this conversation.
    MissedNotificationsService.instance.markChatOpened(group.id, isGroup: true);

    _groupMemberUids = List.of(group.memberUids);
    _groupJoinTimestamps = Map.of(group.memberJoinTimestamps);
    _isGroupDeleted = group.isDeleted;
    _fetchGroupMembers(group.memberUids);
    _listenToGroupDoc(group.id);

    // The group passed in could come from a stale cached document (e.g. a
    // notification tap that opened before the server confirmed my membership
    // in a group I was just added to). Refresh from the server so the UI
    // never thinks a valid member was kicked out.
    _refreshGroupFromServer();

    _fetchMyUser();

    // Re-subscribe the message/typing/pin streams after a reconnect: an
    // errored Firestore snapshot never recovers by itself, so the chat
    // would stay stuck showing cached data and queued sends would flush
    // only after reopening the screen.
    ConnectivityService.instance.isConnected
        .addListener(_onConnectivityChanged);

    _scrollController.addListener(() {
      if (!_scrollController.hasClients) return;
      final show = _scrollController.position.pixels > 200;
      if (show != _showScrollDownBtn) {
        setState(() => _showScrollDownBtn = show);
      }
    });

    // Opened from the favorites list: jump to the exact starred message.
    if (widget.initialJumpMessageId != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _jumpToMessage(widget.initialJumpMessageId!);
      });
    }
  }

  /// Live-tracks the group document: membership (removed-from-group guard),
  /// the member count and join timestamps. When I am removed, the chat
  /// bloc is torn down so its messages stream stops spamming permission
  /// errors.
  void _listenToGroupDoc(String groupId) {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    _groupSub = FirebaseFirestore.instance
        .collection('groups')
        .doc(groupId)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      final data = doc.data();
      if (data == null) return;
      final memberUids =
          List<String>.from(data['memberUids'] ?? const <String>[]);
      final rawJoinTimestamps = data['memberJoinTimestamps'];
      final rawLeaveTimestamps = data['memberLeaveTimestamps'];
      final removed = !memberUids.contains(myUid);
      final isDeleted = data['isDeleted'] == true;

      // When membership changes, push the newest join/leave timestamps into
      // the bloc so message visibility and the read-only flag update live
      // (a new member stops seeing pre-join messages; a removed/left member
      // keeps reading their membership window without being able to interact).
      Map<String, Timestamp> joinTimestamps;
      Map<String, Timestamp> leaveTimestamps;
      try {
        joinTimestamps = rawJoinTimestamps is Map
            ? rawJoinTimestamps
                .map((k, v) => MapEntry(k.toString(), v as Timestamp))
            : <String, Timestamp>{};
        leaveTimestamps = rawLeaveTimestamps is Map
            ? rawLeaveTimestamps
                .map((k, v) => MapEntry(k.toString(), v as Timestamp))
            : <String, Timestamp>{};
      } catch (e) {
        debugPrint('Failed to parse group membership timestamps: $e');
        joinTimestamps = _groupJoinTimestamps;
        leaveTimestamps = _groupLeaveTimestamps;
      }
      _chatCubit?.refreshGroupMembership(
        memberJoinTimestamps: joinTimestamps,
        memberLeaveTimestamps: leaveTimestamps,
      );
      // Live edits (rename, new avatar, membership changes) must appear
      // immediately instead of waiting for the screen to be reopened.
      final name = data['name'];
      final avatar = data['avatarEmoji'];
      final memberUidsChanged = memberUids.length != _groupMemberUids.length ||
          memberUids.any((uid) => !_groupMemberUids.contains(uid));
      if (memberUidsChanged) _fetchGroupMembers(memberUids);
      setState(() {
        if (name is String && name.isNotEmpty) _chatName = name;
        if (avatar is String && avatar.isNotEmpty) _chatAvatar = avatar;
        _groupMemberUids = memberUids;
        _groupJoinTimestamps = joinTimestamps;
        _groupLeaveTimestamps = leaveTimestamps;
        _removedFromGroup = removed;
        _isGroupDeleted = isDeleted;
      });
    }, onError: (e) {
      // A transient snapshot error (offline, reconnect, cached read race) must
      // never permanently kick a member out of the chat. Re-verify membership
      // against the server; only a confirmed "not a member" outcome switches
      // the screen into the read-only removed state.
      debugPrint('Failed to listen to group doc: $e');
      if (!mounted) return;
      _refreshGroupFromServer();
    });
  }

  /// Server-first read of the group document used to resolve the real
  /// membership state after a cached/stale snapshot. A member who was just
  /// added must never see the "removed" read-only screen, and a genuinely
  /// removed user's state is only applied from a confirmed server read.
  Future<void> _refreshGroupFromServer() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || !mounted) return;
    try {
      final doc = await FirebaseFirestore.instance
          .collection('groups')
          .doc(_chatId)
          .get(const GetOptions(source: Source.server));
      if (!mounted) return;
      final data = doc.data();
      if (data == null) {
        setState(() => _removedFromGroup = true);
        return;
      }
      final memberUids = List<String>.from(data['memberUids'] ?? const []);
      final rawJoin = data['memberJoinTimestamps'];
      final rawLeave = data['memberLeaveTimestamps'];
      Map<String, Timestamp> joinTimestamps;
      Map<String, Timestamp> leaveTimestamps;
      try {
        joinTimestamps = rawJoin is Map
            ? rawJoin.map((k, v) => MapEntry(k.toString(), v as Timestamp))
            : <String, Timestamp>{};
        leaveTimestamps = rawLeave is Map
            ? rawLeave.map((k, v) => MapEntry(k.toString(), v as Timestamp))
            : <String, Timestamp>{};
      } catch (_) {
        joinTimestamps = _groupJoinTimestamps;
        leaveTimestamps = _groupLeaveTimestamps;
      }
      final name = data['name'];
      final avatar = data['avatarEmoji'];
      final memberUidsChanged = memberUids.length != _groupMemberUids.length ||
          memberUids.any((uid) => !_groupMemberUids.contains(uid));
      if (memberUidsChanged) _fetchGroupMembers(memberUids);
      _chatCubit?.refreshGroupMembership(
        memberJoinTimestamps: joinTimestamps,
        memberLeaveTimestamps: leaveTimestamps,
      );
      setState(() {
        if (name is String && name.isNotEmpty) _chatName = name;
        if (avatar is String && avatar.isNotEmpty) _chatAvatar = avatar;
        _groupMemberUids = memberUids;
        _groupJoinTimestamps = joinTimestamps;
        _groupLeaveTimestamps = leaveTimestamps;
        _removedFromGroup = !memberUids.contains(myUid);
        _isGroupDeleted = data['isDeleted'] == true;
      });
    } catch (e) {
      // Offline: keep the current UI state; the live listener will catch up.
      debugPrint('Failed to refresh group from server: $e');
    }
  }

  @override
  void dispose() {
    ConnectivityService.instance.isConnected
        .removeListener(_onConnectivityChanged);
    _groupSub?.cancel();
    _highlightTimer?.cancel();
    activeChatUserId = null;
    activeGroupId = null;
    _scrollController.dispose();
    _chatCubit?.close();
    super.dispose();
  }

  Future<void> _fetchMyUser() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser!;
      final userRef =
          FirebaseFirestore.instance.collection('users').doc(currentUser.uid);

      // Server-first read falls back to the on-device cache when offline.
      DocumentSnapshot doc;
      try {
        doc = await userRef.get();
      } catch (_) {
        doc = await userRef.get(const GetOptions(source: Source.cache));
      }
      if (mounted) {
        setState(() {
          _isMyAccountDeleted = doc.exists &&
              ((doc.data() as Map<String, dynamic>?)?['isDeleted'] ?? false);
        });
      }
    } catch (e) {
      debugPrint("Error fetching my user: $e");
    }
  }

  Future<void> _fetchGroupMembers(List<String> uids) async {
    try {
      // Firestore allows at most 30 uids per whereIn query, so large groups
      // are fetched in parallel chunks (new members also pop in live via
      // the group-doc listener instead of a full reload).
      final chunks = <List<String>>[];
      for (int i = 0; i < uids.length; i += 30) {
        final end = i + 30 < uids.length ? i + 30 : uids.length;
        chunks.add(uids.sublist(i, end));
      }
      if (chunks.isEmpty) return;

      final snapshots = await Future.wait(chunks.map(
        (chunk) => FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      ));

      final members = <String, UserModel>{};
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          members[doc.id] = UserModel.fromFirestore(doc);
        }
      }
      if (mounted) {
        setState(() => _groupMembers = members);
      }
    } catch (e) {
      debugPrint("Error fetching group members: $e");
    }
  }

  void scrollToMessage(String messageId) {
    scrollMessageToViewport(
      controller: _scrollController,
      messageKeys: _messageKeys,
      cubit: _chatCubit!,
      isMounted: () => mounted,
      messageId: messageId,
    );
  }

  /// Jumps to the newest messages (offset 0 in the reversed list).
  Future<void> _scrollToBottom() async {
    if (!_scrollController.hasClients) return;
    await _scrollController.animateTo(
      0,
      duration: const Duration(milliseconds: 300),
      curve: Curves.easeOut,
    );
  }

  bool _isTargetFullyVisible(String messageId) => isMessageFullyVisible(
        controller: _scrollController,
        messageKeys: _messageKeys,
        messageId: messageId,
      );

  /// Jumps to a message and briefly highlights it like WhatsApp/Telegram.
  Future<void> _jumpToMessage(String messageId) async {
    final cubit = _chatCubit!;
    final loadedState =
        cubit.state is ChatLoaded ? cubit.state as ChatLoaded : null;
    final isAlreadyLoaded = loadedState != null &&
        loadedState.messages.any((m) => m.id == messageId);

    // Only load the whole history when the target is not already in memory;
    // an already-loaded message must not trigger a pagination reload.
    if (!isAlreadyLoaded) {
      await cubit.loadAllMessages();
      if (!mounted) return;
    }
    if (!mounted) return;

    _highlightTimer?.cancel();
    setState(() => _highlightedMessageId = messageId);
    _highlightTimer = Timer(const Duration(milliseconds: 900), () {
      if (mounted) setState(() => _highlightedMessageId = null);
    });

    // The message is already in front of the user: nothing to scroll.
    if (_isTargetFullyVisible(messageId)) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      scrollToMessage(messageId);
    });
  }

  /// The bloc now reconnects its own Firestore listeners internally when
  /// connectivity returns, so no bloc teardown is needed here.
  void _onConnectivityChanged() {}

  Future<void> _startGroupCall({required bool isVideo}) async {
    if (_groupMemberUids.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: CustomText(text: 'Cannot start call in solo group')));
      return;
    }
    if (!ensureOnlineForCall(context)) return;

    final channel = buildChannelName(isGroup: true, group: widget.group);

    final existingCallId = await CallService.getActiveCallId(channel, isVideo);
    String callId;
    if (existingCallId != null) {
      callId = existingCallId;
      debugPrint(
          'Joining existing group ${isVideo ? 'video' : 'voice'} call: $callId');
    } else {
      callId = await CallService.startCall(
          receiver: null,
          group: widget.group,
          isVideo: isVideo,
          channelName: channel);
    }

    if (!mounted) return;
    Navigator.pushNamed(
        context,
        isVideo ? RouteNames.videoCallPage : RouteNames.voiceCallPage,
        arguments: CallArguments(
            isGroup: true,
            group: widget.group,
            callId: callId,
            isVideo: isVideo));
  }

  void _openGroupInfo() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            GroupInfoScreen(group: widget.group),
        transitionsBuilder: PageTransition.slideFromRight,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);

    // Removed/left users still build the chat (their bloc keeps loading the
    // messages from their membership window), but in read-only mode: no
    // composer, no calls, no reactions.
    final chatCubit = _chatCubit ??= ChatCubit(
      chatId: _chatId,
      isGroupChat: true,
    );
    return BlocProvider.value(
      value: chatCubit,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: colors.screen,
          appBar: buildGroupChatAppBar(
            context: context,
            chatName: _chatName,
            chatAvatar: _chatAvatar,
            memberCount: _groupMemberUids.length,
            onTitleTap: _removedFromGroup ? null : _openGroupInfo,
            showCallButtons: !_removedFromGroup &&
                !_isGroupDeleted &&
                _groupMemberUids.length > 1,
            onSearch: () => setState(() => _searchActive = true),
            onVoiceCall: () => _startGroupCall(isVideo: false),
            onVideoCall: () => _startGroupCall(isVideo: true),
          ),
          body: Column(
            children: [
              if (_isMyAccountDeleted) const GroupMyAccountDeletedBanner(),
              if (_removedFromGroup) const GroupRemovedBanner(),
              if (_isGroupDeleted) const GroupDeletedBanner(),
              if (_searchActive)
                Flexible(
                  child: ChatSearchOverlay(
                    isGroup: true,
                    myUid: FirebaseAuth.instance.currentUser!.uid,
                    members: _searchMembers,
                    onClose: () => setState(() => _searchActive = false),
                    onJumpTo: _jumpToMessage,
                  ),
                ),
              Expanded(
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: GroupChatMessagesBody(
                        scrollController: _scrollController,
                        messageKeys: _messageKeys,
                        groupMembers: _groupMembers,
                        chatName: _chatName,
                        joinTimestamps: _groupJoinTimestamps,
                        iCreatedGroup: widget.group.createdBy ==
                            FirebaseAuth.instance.currentUser?.uid,
                        highlightedMessageId: _highlightedMessageId,
                        readOnly: _removedFromGroup || _isGroupDeleted,
                        onJumpToMessage: _jumpToMessage,
                        onJoinActiveCall: _joinActiveGroupCall,
                        onJoinCallFromMessage: _joinActiveCallFromMessage,
                      ),
                    ),
                    Positioned(
                      right: 12.w,
                      bottom: 8.h,
                      child: ChatScrollDownButton(
                        visible: _showScrollDownBtn,
                        onTap: _scrollToBottom,
                      ),
                    ),
                  ],
                ),
              ),
              StreamBuilder<List<String>>(
                stream: chatCubit.typingStream,
                initialData: const [],
                builder: (context, snapshot) {
                  final typingUids = snapshot.data ?? const <String>[];
                  if (typingUids.isEmpty) return const SizedBox.shrink();
                  return TypingIndicator(
                    typingUids: typingUids,
                    isGroup: true,
                    members: _groupMembers,
                  );
                },
              ),
              if (_removedFromGroup)
                const GroupRemovedComposer()
              else if (_isMyAccountDeleted)
                const GroupMyAccountDeletedComposer()
              else if (_isGroupDeleted)
                const GroupDeletedComposer()
              else
                MessageComposer(chatId: _chatId, isGroup: true),
            ],
          ),
        ),
      ),
    );
  }

  /// Joins a group call that is already running and opens its call page.
  /// Mirrors the existing "call button when a call is active" flow: reuse the
  /// active call id, add the user to the call, then open the call page.
  void _joinActiveGroupCall(ActiveGroupCall call) {
    if (_removedFromGroup || _isGroupDeleted) return;
    if (!ensureOnlineForCall(context)) return;

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    // Add the user to the call participants (idempotent array union).
    CallService.joinCall(call.callId, myUid);

    final group = widget.group;
    Navigator.pushNamed(
      context,
      call.isVideo ? RouteNames.videoCallPage : RouteNames.voiceCallPage,
      arguments: CallArguments(
        isGroup: true,
        group: group,
        callId: call.callId,
        isVideo: call.isVideo,
        groupName: call.groupName,
      ),
    );
  }

  /// Invoked when the user taps "Join call" on the active-call card rendered
  /// as a chat message. Resolves the still-active group call from the tracker
  /// and joins it (no-op if the call already ended).
  void _joinActiveCallFromMessage(MessageModel message) {
    final track = GroupCallTracker.instance.callForGroup(_chatId);
    if (track == null) return;
    // Safety: only offer joining when the card's type matches the live call
    // (a stale card after a ended/replaced call should not mis-route).
    if (track.isVideo != (message.callType == 'video')) return;
    if (_removedFromGroup || _isGroupDeleted) return;
    if (CallBloc.instance.isCallActive) return;
    _joinActiveGroupCall(track);
  }

  /// uid -> UserModel used for both the chat list and the search results.
  Map<String, UserModel> get _searchMembers {
    return _groupMembers;
  }
}