import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:swipe_to/swipe_to.dart';
import '../../../core/routes/route_names.dart';
import '../../../core/utils/call_utils.dart';
import '../../../core/utils/page_transition.dart';
import '../../../models/call_arguments.dart';
import '../../../services/chat/active_chat.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/fcm/fcm_service.dart';
import '../../../services/notifications/missed_notifications_service.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../calls/cubit/call_cubit.dart';
import '../../calls/services/call_service.dart';
import '../../calls/services/group_call_tracker.dart';
import '../../groups/screens/group_info_screen.dart' show GroupInfoScreen;
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../widgets/chat_search_overlay.dart';
import '../widgets/day_separator.dart';
import '../widgets/join_call_card.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import '../widgets/pinned_message_banner.dart';
import '../widgets/typing_indicator.dart';

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

  /// Last loaded messages, kept so the list stays visible while a media
  /// upload is in progress (ChatUploading / ChatError replace ChatLoaded).
  List<MessageModel>? _lastMessages;

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
    MissedNotificationsService.instance
        .markChatOpened(group.id, isGroup: true);

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
    ConnectivityService.instance.isConnected.addListener(_onConnectivityChanged);

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
  /// cubit is torn down so its messages stream stops spamming permission
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
      // the cubit so message visibility and the read-only flag update live
      // (a new member stops seeing pre-join messages; a removed/left member
      // keeps reading their membership window without being able to interact).
      Map<String, Timestamp> joinTimestamps;
      Map<String, Timestamp> leaveTimestamps;
      try {
        joinTimestamps = rawJoinTimestamps is Map
            ? rawJoinTimestamps.map(
                (k, v) => MapEntry(k.toString(), v as Timestamp))
            : <String, Timestamp>{};
        leaveTimestamps = rawLeaveTimestamps is Map
            ? rawLeaveTimestamps.map(
                (k, v) => MapEntry(k.toString(), v as Timestamp))
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
      final memberUidsChanged =
          memberUids.length != _groupMemberUids.length ||
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
      final userRef = FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid);

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
    final cubit = _chatCubit!;

    /// Scrolls a message that is already built on screen to the center of
    /// the viewport. Handles the reversed list manually instead of using
    /// Scrollable.ensureVisible (which is unreliable with reverse: true).
    void centerMessage(BuildContext targetCtx) {
      if (!_scrollController.hasClients) return;
      final box = targetCtx.findRenderObject() as RenderBox?;
      final viewport = box == null ? null : RenderAbstractViewport.of(box);
      if (box == null || viewport == null) return;
      final viewportTop = (viewport as RenderBox).localToGlobal(Offset.zero).dy;
      final distanceFromTop = box.localToGlobal(Offset.zero).dy - viewportTop;
      final position = _scrollController.position;
      // Reversed list: content grows upward, so a larger offset = higher up.
      final target =
          (position.pixels + position.viewportDimension / 2 - distanceFromTop)
              .clamp(0.0, position.maxScrollExtent)
              .toDouble();
      position.animateTo(target,
          duration: const Duration(milliseconds: 350), curve: Curves.easeInOut);
    }

    void tryScroll([int attempt = 0]) {
      if (!mounted) return;
      final key = _messageKeys[messageId];
      final ctx = key?.currentContext;
      if (ctx != null && ctx.mounted) {
        centerMessage(ctx);
        return;
      }

      if (cubit.state is! ChatLoaded || !_scrollController.hasClients) {
        if (attempt < 14) {
          Future.delayed(const Duration(milliseconds: 80), () {
            if (mounted) tryScroll(attempt + 1);
          });
        }
        return;
      }

      final messages = (cubit.state as ChatLoaded).messages;
      final idToIndex = {
        for (int i = 0; i < messages.length; i++) messages[i].id: i,
      };
      final index = idToIndex[messageId];
      if (index == null) {
        // The message may still be loading (pagination in flight).
        if (attempt < 14) {
          Future.delayed(const Duration(milliseconds: 150), () {
            if (mounted) tryScroll(attempt + 1);
          });
        }
        return;
      }

      final position = _scrollController.position;
      final viewportH = position.viewportDimension;
      if (viewportH <= 0) {
        if (attempt < 14) {
          Future.delayed(const Duration(milliseconds: 80), () {
            if (mounted) tryScroll(attempt + 1);
          });
        }
        return;
      }

      // Estimate the target's position by anchoring on the closest message
      // that is already built (measured exactly). Guessing `index * 85`
      // fails badly when photos / videos / reply cards make bubbles taller.
      int? anchorIndex;
      double? anchorContentTop;
      double builtHeightSum = 0;
      int builtCount = 0;
      for (final entry in _messageKeys.entries) {
        final anchorCtx = entry.value.currentContext;
        if (anchorCtx == null || !anchorCtx.mounted) continue;
        final anchorMsgIndex = idToIndex[entry.key];
        if (anchorMsgIndex == null || anchorMsgIndex == index) continue;
        final anchorBox = anchorCtx.findRenderObject() as RenderBox;
        final viewportBox = RenderAbstractViewport.of(anchorBox) as RenderBox;
        final distanceFromTop = anchorBox.localToGlobal(Offset.zero).dy -
            viewportBox.localToGlobal(Offset.zero).dy;
        final contentTop = position.pixels + viewportH - distanceFromTop;

        final bool isCloser;
        if (anchorIndex == null) {
          isCloser = true;
        } else if (anchorMsgIndex < index) {
          isCloser = anchorMsgIndex > anchorIndex;
        } else {
          isCloser = anchorMsgIndex < anchorIndex;
        }
        if (isCloser) {
          anchorIndex = anchorMsgIndex;
          anchorContentTop = contentTop;
        }
        if (anchorMsgIndex < index) {
          builtHeightSum += anchorBox.size.height;
          builtCount++;
        }
      }

      // Estimated height of one message inside the unbuilt gap.
      final localAvg = builtCount > 0
          ? builtHeightSum / builtCount
          : (position.maxScrollExtent + viewportH) / messages.length;

      double targetContentTop;
      if (anchorIndex != null && anchorContentTop != null) {
        // The target is `gap` messages away from the measured anchor. Each
        // retry re-measures from the now-better built anchors, so the
        // estimate converges instead of overshooting.
        final gap = index - anchorIndex;
        targetContentTop = anchorContentTop + gap * localAvg;
      } else {
        // No built anchor yet: fall back to the whole-list average.
        targetContentTop = (index + 1) * localAvg;
      }

      final target = (targetContentTop - viewportH / 2)
          .clamp(0.0, position.maxScrollExtent)
          .toDouble();

      // Already where the estimate says: stop scrolling; the retries below
      // keep checking for the built bubble so the final center is exact.
      if ((target - position.pixels).abs() >= 4) {
        position.animateTo(target,
            duration: const Duration(milliseconds: 250),
            curve: Curves.easeInOut);
      }

      if (attempt < 14) {
        Future.delayed(const Duration(milliseconds: 120), () {
          if (mounted) tryScroll(attempt + 1);
        });
      }
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => tryScroll(0));
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

  Widget _buildScrollDownButton() {
    final colors = FcAppColors.of(context);
    if (!_showScrollDownBtn) return const SizedBox.shrink();
    return GestureDetector(
      onTap: _scrollToBottom,
      child: Container(
        width: 44,
        height: 44,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: colors.surface,
          border: Border.all(color: colors.divider),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 8,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        child: const Icon(Icons.arrow_downward, color: Colors.lightBlueAccent),
      ),
    );
  }

  /// True when [messageId]'s bubble is built and fully inside the viewport.
  /// Used to skip scrolling when the target is already on screen.
  bool _isTargetFullyVisible(String messageId) {
    if (!_scrollController.hasClients) return false;
    final ctx = _messageKeys[messageId]?.currentContext;
    if (ctx == null || !ctx.mounted) return false;
    final box = ctx.findRenderObject() as RenderBox?;
    if (box == null) return false;
    final viewportBox = RenderAbstractViewport.of(box) as RenderBox;
    final top = box.localToGlobal(Offset.zero).dy;
    final bottom = box.localToGlobal(Offset(0, box.size.height)).dy;
    final viewportTop = viewportBox.localToGlobal(Offset.zero).dy;
    final viewportBottom = viewportTop + viewportBox.size.height;
    return top >= viewportTop && bottom <= viewportBottom;
  }

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

  /// The cubit now reconnects its own Firestore listeners internally when
  /// connectivity returns, so no cubit teardown is needed here.
  void _onConnectivityChanged() {}

  /// Calls need a live connection; show a friendly message instead of
  /// starting a call that would immediately fail.
  bool _ensureOnlineForCall() {
    if (ConnectivityService.instance.isConnected.value) return true;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: CustomText(
            text: 'You are offline. You cannot make calls right now.'),
        backgroundColor: Colors.orange,
      ));
    return false;
  }

  void _startGroupVoiceCall() async {
    if (_groupMemberUids.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: CustomText(text: 'Cannot start call in solo group')));
      return;
    }
    if (!_ensureOnlineForCall()) return;

    final channel = buildChannelName(isGroup: true, group: widget.group);

    final existingCallId = await CallService.getActiveCallId(channel, false);
    String callId;
    if (existingCallId != null) {
      callId = existingCallId;
      debugPrint('Joining existing group voice call: $callId');
    } else {
      callId = await CallService.startCall(
          receiver: null,
          group: widget.group,
          isVideo: false,
          channelName: channel);
    }

    if (!mounted) return;
    Navigator.pushNamed(context, RouteNames.voiceCallPage,
        arguments: CallArguments(
            isGroup: true,
            group: widget.group,
            callId: callId,
            isVideo: false));
  }

  void _startGroupVideoCall() async {
    if (_groupMemberUids.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: CustomText(text: 'Cannot start call in solo group')));
      return;
    }
    if (!_ensureOnlineForCall()) return;

    final channel = buildChannelName(isGroup: true, group: widget.group);

    final existingCallId = await CallService.getActiveCallId(channel, true);
    String callId;
    if (existingCallId != null) {
      callId = existingCallId;
      debugPrint('Joining existing group video call: $callId');
    } else {
      callId = await CallService.startCall(
          receiver: null,
          group: widget.group,
          isVideo: true,
          channelName: channel);
    }

    if (!mounted) return;
    Navigator.pushNamed(context, RouteNames.videoCallPage,
        arguments: CallArguments(
            isGroup: true, group: widget.group, callId: callId, isVideo: true));
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);

    // Removed/left users still build the chat (their cubit keeps loading the
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
          appBar: _buildAppBar(context),
          body: Column(
            children: [
              if (_isMyAccountDeleted)
                _buildMyAccountDeletedBanner(context),
              if (_removedFromGroup)
                _buildRemovedInfoBanner(context),
              if (_isGroupDeleted)
                _buildGroupDeletedBanner(context),
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
                    Positioned.fill(child: _buildChatBody()),
                    Positioned(
                      right: 12.w,
                      bottom: 8.h,
                      child: _buildScrollDownButton(),
                    ),
                  ],
                ),
              ),
              StreamBuilder<List<String>>(
                stream: _chatCubit!.typingStream,
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
                _buildRemovedComposer(context)
              else if (_isMyAccountDeleted)
                _buildBlockedComposer(context)
              else if (_isGroupDeleted)
                _buildGroupDeletedComposer(context)
              else
                MessageComposer(chatId: _chatId, isGroup: true),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final colors = FcAppColors.of(context);

    return AppBar(
      elevation: 1,
      backgroundColor: Colors.lightBlueAccent,
      centerTitle: false,
      titleSpacing: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      title: InkWell(
        onTap: _removedFromGroup
            ? null
            : () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        GroupInfoScreen(group: widget.group),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              },
        borderRadius: BorderRadius.circular(24.r),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 2.w, vertical: 4.h),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              CircleAvatar(
                radius: 19.r,
                backgroundColor: colors.avatarBackground,
                child: CustomText(text: _chatAvatar, fontSize: 16.sp),
              ),
              SizedBox(width: 8.w),
              Flexible(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _chatName,
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.sp,
                      ),
                    ),
                    SizedBox(height: 1.h),
                    Text(
                      '${_groupMemberUids.length} members',
                      overflow: TextOverflow.ellipsis,
                      maxLines: 1,
                      style: TextStyle(
                        color: Colors.white.withValues(alpha: 0.85),
                        fontWeight: FontWeight.w400,
                        fontSize: 11.5.sp,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      actionsPadding: EdgeInsets.only(right: 6.w),
      actions: [
        IconButton(
          icon: const Icon(Icons.search, color: Colors.white, size: 22),
          tooltip: 'Search in chat',
          onPressed: () {
            setState(() {
              _searchActive = true;
            });
          },
        ),
        if (!_removedFromGroup && !_isGroupDeleted && _groupMemberUids.length > 1) ...[
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white, size: 22),
            tooltip: 'Voice Call',
            onPressed: _startGroupVoiceCall,
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white, size: 22),
            tooltip: 'Video Call',
            onPressed: _startGroupVideoCall,
          ),
        ],
      ],
    );
  }

  // Shown above the list so a removed/left member understands the chat is
  // now read-only: they keep seeing their earlier messages but can no longer
  // send, call, or react.
  Widget _buildRemovedInfoBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: Colors.orange.shade50,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.info_outline, color: Colors.orange, size: 20),
            SizedBox(width: 10.w),
            Expanded(
              child: CustomText(
                text: 'You are no longer a member of this group. You can '
                    'still read the messages from your time in the group, '
                    'but you cannot send, call, or react.',
                fontSize: 13.sp,
                textColor: Colors.orange.shade900,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Shown above the list when the creator has deleted the whole group: the
  // conversation stays fully readable but becomes read-only for everyone.
  Widget _buildGroupDeletedBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: Colors.grey.shade200,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(Icons.delete_outline, color: Colors.grey, size: 20),
            SizedBox(width: 10.w),
            Expanded(
              child: CustomText(
                text: 'This group was deleted by its creator. You can still '
                    'read the messages, but you cannot send, call, or react.',
                fontSize: 13.sp,
                textColor: Colors.grey.shade800,
                maxLines: 4,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Bottom bar replacing the composer once the group has been deleted.
  Widget _buildGroupDeletedComposer(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.3),
            spreadRadius: 2,
            blurRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.delete_outline, color: colors.textWeak, size: 20),
            SizedBox(width: 8.w),
            Flexible(
              child: CustomText(
                text: 'you can only read messages',
                fontSize: 14.sp,
                textColor: colors.textSecondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Bottom bar replacing the composer for removed/left members.
  Widget _buildRemovedComposer(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.grey.withValues(alpha: 0.3),
            spreadRadius: 2,
            blurRadius: 5,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.lock_outline, color: colors.textWeak, size: 20),
            SizedBox(width: 8.w),
            Flexible(
              child: CustomText(
                text: 'You can only read messages',
                fontSize: 14.sp,
                textColor: colors.textSecondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildMyAccountDeletedBanner(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: Colors.red.shade50,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            const Icon(
              Icons.remove_circle_outline,
              color: Colors.red,
              size: 20,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: CustomText(
                text: 'Your account was deleted. You can only read your '
                    'previous chats — you cannot send messages or call.',
                fontSize: 13.sp,
                textColor: Colors.red.shade900,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBlockedComposer(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 18.h),
      decoration: BoxDecoration(
        color: colors.surface,
        boxShadow: [
          BoxShadow(
              color: Colors.grey.withValues(alpha: 0.3),
              spreadRadius: 2,
              blurRadius: 5),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.remove_circle_outline,
              color: colors.textWeak,
              size: 20,
            ),
            SizedBox(width: 8.w),
            Flexible(
              child: CustomText(
                text: 'Your account is deleted — you can only read messages',
                fontSize: 14.sp,
                textColor: colors.textSecondary,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildChatBody() {
    return BlocConsumer<ChatCubit, ChatState>(
      listener: (context, state) {
        if (state is ChatError) {
          final isOffline = !ConnectivityService.instance.isConnected.value;
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(isOffline
                  ? 'You are offline — showing your saved messages.'
                  : state.message),
              backgroundColor: isOffline ? Colors.orange : Colors.red,
            ));
        }
      },
      builder: (context, state) {
        final colors = FcAppColors.of(context);
        if (state is ChatLoading || state is ChatInitial) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.lightBlueAccent));
        }

        if (state is ChatLoaded) {
          _lastMessages = state.messages;

          if (state.messages.isEmpty) {
            // Check if the user was recently added to the group: only show
            // the "joined" notice when there really is nothing to read.
            final currentUser = FirebaseAuth.instance.currentUser;
            if (currentUser != null) {
              final joinTimestamp =
                  _groupJoinTimestamps[currentUser.uid];
              if (joinTimestamp != null) {
                final iCreatedGroup =
                    widget.group.createdBy == currentUser.uid;
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.group_add,
                        size: 56,
                        color: Colors.lightBlue.shade200,
                      ),
                      SizedBox(height: 12.h),
                      CustomText(
                        text: iCreatedGroup
                            ? 'You created this group'
                            : 'You joined this group',
                        textAlign: TextAlign.center,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        textColor: colors.textSecondary,
                      ),
                      SizedBox(height: 8.h),
                      CustomText(
                        text: iCreatedGroup
                            ? 'Start the conversation by sending the '
                                'first message!'
                            : 'You can only see messages sent after you '
                                'joined',
                        textAlign: TextAlign.center,
                        fontSize: 14.sp,
                        textColor: colors.textWeak,
                      ),
                    ],
                  ),
                );
              }
            }

            return const Center(child: CustomText(text: "Say hello! 👋"));
          }

          return _buildMessagesList(context, state.messages,
              hasMore: state.hasMore, loadingMore: state.loadingMore);
        }

        // Keep the conversation visible while media uploads are running or
        // right after a transient error instead of flashing "Something went
        // wrong." (the old behavior when sending multiple photos).
        if ((state is ChatUploading || state is ChatError) &&
            _lastMessages != null &&
            _lastMessages!.isNotEmpty) {
          return _buildMessagesList(context, _lastMessages!);
        }

        if (state is ChatError) {
          final isOffline = !ConnectivityService.instance.isConnected.value;
          return Center(
            child: CustomText(
              text: isOffline
                  ? 'You are offline. Open this chat once with an internet '
                      'connection to save it for offline reading.'
                  : 'Something went wrong.',
              textAlign: TextAlign.center,
            ),
          );
        }

        return const Center(child: CustomText(text: "Something went wrong."));
      },
    );
  }

  Widget _buildMessagesList(
    BuildContext context,
    List<MessageModel> messages, {
    bool hasMore = true,
    bool loadingMore = false,
  }) {
    final members = _searchMembers;

    // Always render the lazy reversed list. Jumps to far-away messages work
    // through scrollToMessage's anchor-based estimate (bubbles get GlobalKeys
    // as soon as they are built near the viewport).
    final Widget list = NotificationListener<ScrollNotification>(
      onNotification: (scroll) {
        if (hasMore &&
            scroll.metrics.pixels >= scroll.metrics.maxScrollExtent - 40) {
          context.read<ChatCubit>().loadMoreMessages();
        }
        return false;
      },
      child: ListView.builder(
        controller: _scrollController,
        reverse: true,
        itemCount: messages.length + (loadingMore ? 1 : 0),
        itemBuilder: (context, index) {
          if (loadingMore && index == messages.length) {
            return const Padding(
              padding: EdgeInsets.symmetric(vertical: 16),
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2.5,
                    color: Colors.lightBlueAccent,
                  ),
                ),
              ),
            );
          }
          return _buildMessageItem(context, messages, index, members);
        },
      ),
    );

    // A group call currently in progress surfaces a WhatsApp-style "Join
    // call" card at the newest position of the list (top of the reversed
    // list) so any member who opens the chat late can join in one tap.

    return Column(
      children: [
        StreamBuilder<Map<String, dynamic>?>(
          stream: context.read<ChatCubit>().pinnedMessageStream,
          builder: (context, snapshot) {
            final pin = snapshot.data;
            if (pin == null) return const SizedBox.shrink();
            return PinnedMessageBanner(
              pin: pin,
              canUnpin: context.read<ChatCubit>().canPin,
              onTap: pin['messageId'] != null
                  ? () => _jumpToMessage(pin['messageId']!.toString())
                  : null,
              onUnpin: () => context.read<ChatCubit>().unpinMessage(),
            );
          },
        ),
        Expanded(
          child: ListenableBuilder(
            listenable: GroupCallTracker.instance,
            builder: (context, _) {
              final track = GroupCallTracker.instance.callForGroup(_chatId);
              if (track == null) return list;

              final showJoin = FirebaseAuth
                          .instance.currentUser?.uid !=
                      track.callerId &&
                  !CallCubit.instance.isCallActive &&
                  !_removedFromGroup &&
                  !_isGroupDeleted;

              return Stack(
                children: [
                  Positioned.fill(child: list),
                  if (showJoin)
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: JoinCallCard(
                        call: track,
                        callerId:
                            FirebaseAuth.instance.currentUser?.uid ?? '',
                        canJoin: true,
                        onJoin: () => _joinActiveGroupCall(track),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  /// Joins a group call that is already running and opens its call page.
  /// Mirrors the existing "call button when a call is active" flow: reuse the
  /// active call id, add the user to the call, then open the call page.
  void _joinActiveGroupCall(ActiveGroupCall call) {
    if (_removedFromGroup || _isGroupDeleted) return;
    if (!_ensureOnlineForCall()) return;

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
    if (CallCubit.instance.isCallActive) return;
    _joinActiveGroupCall(track);
  }


  Widget _buildMessageItem(
    BuildContext context,
    List<MessageModel> messages,
    int index,
    Map<String, UserModel> members,
  ) {
    final message = messages[index];
    final isMe = message.senderId == FirebaseAuth.instance.currentUser!.uid;

    final showDaySeparator = index > 0 &&
        !DaySeparator.isSameDay(
          message.timestamp.toDate(),
          messages[index - 1].timestamp.toDate(),
        );

    final sender = _groupMembers[message.senderId];

    final senderAvatar = sender?.avatarEmoji ?? '👤';

    final senderName = sender != null
        ? '${sender.firstName} ${sender.lastName}'
        : 'Unknown';

    final key = _messageKeys[message.id] ??= GlobalKey();

    final messageWidget = MessageBubble(
      key: key,
      message: message,
      isMe: isMe,
      isGroup: true,
      sender: sender,
      senderAvatar: senderAvatar,
      contactName: _chatName,
      members: members,
      highlighted: _highlightedMessageId == message.id,
      readOnly: _removedFromGroup || _isGroupDeleted,
      onJoinCall: () => _joinActiveCallFromMessage(message),
      onTapReplied: () {
        final repliedId = (message.repliedTo?['id'] ??
                message.repliedTo?['messageId'] ??
                message.repliedTo?['_id'])
            ?.toString();
        if (repliedId != null && repliedId.isNotEmpty) {
          _jumpToMessage(repliedId);
        }
      },
    );

    Widget result = messageWidget;
    if (!message.isDeleted && !_removedFromGroup && !_isGroupDeleted) {
      result = SwipeTo(
        onLeftSwipe: isMe
            ? (details) {
                context.read<ChatCubit>().setReplyingTo(message, senderName);
              }
            : null,
        onRightSwipe: !isMe
            ? (details) {
                context.read<ChatCubit>().setReplyingTo(message, senderName);
              }
            : null,
        child: messageWidget,
      );
    }

    if (showDaySeparator) {
      result = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DaySeparator(date: message.timestamp.toDate()),
          result,
        ],
      );
    }

    return result;
  }

  /// uid -> UserModel used for both the chat list and the search results.
  Map<String, UserModel> get _searchMembers {
    return _groupMembers;
  }
}