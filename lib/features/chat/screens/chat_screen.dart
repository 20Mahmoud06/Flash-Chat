import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/features/profile/screens/sender_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:swipe_to/swipe_to.dart';

import '../../../core/routes/route_names.dart';
import '../../../core/utils/call_utils.dart';
import '../../../core/utils/page_transition.dart';
import '../../../models/call_arguments.dart';
import '../../../services/block/block_service.dart';
import '../../../services/chat/active_chat.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/fcm/fcm_service.dart';
import '../../../services/notifications/missed_notifications_service.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../calls/services/call_service.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../widgets/chat_presence_subtitle.dart';
import '../widgets/chat_search_overlay.dart';
import '../widgets/day_separator.dart';
import '../widgets/message_bubble.dart';
import '../widgets/message_composer.dart';
import '../widgets/pinned_message_banner.dart';
import '../widgets/typing_indicator.dart';

class ChatScreen extends StatefulWidget {
  final UserModel contact;

  /// When set, the chat opens scrolled to this message (used by the
  /// favorites list to open the exact starred message).
  final String? initialJumpMessageId;

  const ChatScreen({
    super.key,
    required this.contact,
    this.initialJumpMessageId,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final String _chatId;
  late String _chatName;

  /// The contact's real name, kept so a nickname (set by me, stored in my
  /// `nicknames` map) can replace it without losing the original.
  late String _realChatName;
  late String _chatAvatar;

  /// My nickname for this contact (null when not set). Only I see it.
  String? _myNickname;

  UserModel? _myUser;

  Set<String> _myBlockedUids = {};
  bool _blockedMe = false;
  bool _isAccountDeleted = false;
  bool _isMyAccountDeleted = false;
  StreamSubscription<DocumentSnapshot>? _myUserBlockSub;
  StreamSubscription<DocumentSnapshot>? _contactBlockSub;

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

    final contact = widget.contact;

    _chatId = buildChannelName(
      isGroup: false,
      contact: contact,
    );

    _isAccountDeleted = contact.isDeleted;
    _realChatName = contact.isDeleted
        ? 'Deleted User'
        : '${contact.firstName} ${contact.lastName}';
    _chatName = _realChatName;
    _chatAvatar = contact.isDeleted ? '❌' : contact.avatarEmoji;

    activeChatUserId = contact.uid;
    activeGroupId = null;

    // Clear this conversation's notifications.
    FcmService.clearChatNotifications(contact.uid, isGroup: false);

    // Tell the missed-notifications backfill this chat is now being read, so
    // it stops notifying (and doesn't re-notify) this conversation.
    MissedNotificationsService.instance
        .markChatOpened(contact.uid, isGroup: false);

    _fetchMyUser();
    _listenToBlockState();

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

  /// Live-tracks the block status between me and the contact so the UI
  /// (composer, call buttons, banner) reacts immediately to block/unblock.
  void _listenToBlockState() {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final contactUid = widget.contact.uid;

    _myUserBlockSub = FirebaseFirestore.instance
        .collection('users')
        .doc(myUid)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() {
        _myBlockedUids =
            Set<String>.from(doc.data()?['blockedUids'] ?? const []);
        // My account can be tombstoned (isDeleted) live: keep read access,
        // but stop sending/calling.
        _isMyAccountDeleted = doc.data()?['isDeleted'] ?? false;
        // Apply my nickname for this contact: it replaces the real name
        // everywhere in the chat (app bar, banners, message prefix).
        final nicknames = doc.data()?['nicknames'];
        final nickname = nicknames is Map ? nicknames[contactUid] : null;
        _myNickname = nickname is String ? nickname : null;
        if (!_isAccountDeleted) {
          _chatName = (_myNickname != null && _myNickname!.isNotEmpty)
              ? _myNickname!
              : _realChatName;
        }
      });
    });

    _contactBlockSub = FirebaseFirestore.instance
        .collection('users')
        .doc(contactUid)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() {
        _blockedMe =
            (doc.data()?['blockedUids'] as List<dynamic>?)?.contains(myUid) ??
                false;
        // Check if the account is deleted
        if (!doc.exists) {
          _isAccountDeleted = true;
          _chatName = 'Deleted User';
          _chatAvatar = '❌';
        } else {
          _isAccountDeleted = doc.data()?['isDeleted'] ?? false;
          if (_isAccountDeleted) {
            _chatName = 'Deleted User';
            _chatAvatar = '❌';
          } else {
            // Live profile edits (name / avatar) appear immediately instead
            // of waiting for the screen to be reopened. The real name stays
            // underneath so my nickname keeps its precedence.
            final data = doc.data();
            final firstName = data?['firstName']?.toString() ?? '';
            final lastName = data?['lastName']?.toString() ?? '';
            final avatar = data?['avatarEmoji'];
            if (firstName.isNotEmpty) {
              _realChatName = '$firstName $lastName'.trim();
              _chatName = (_myNickname != null && _myNickname!.isNotEmpty)
                  ? _myNickname!
                  : _realChatName;
            }
            if (avatar is String && avatar.isNotEmpty) _chatAvatar = avatar;
          }
        }
      });
    });
  }

  @override
  void dispose() {
    ConnectivityService.instance.isConnected
        .removeListener(_onConnectivityChanged);
    _myUserBlockSub?.cancel();
    _contactBlockSub?.cancel();
    _highlightTimer?.cancel();
    activeChatUserId = null;
    activeGroupId = null;
    _scrollController.dispose();
    _chatCubit?.close();
    super.dispose();
  }

  bool get _iBlockedContact =>
      _myBlockedUids.contains(widget.contact.uid);

  bool get _isBlockedChat => _iBlockedContact || _blockedMe;

  bool get _isDeletedOrBlocked => _isAccountDeleted || _isBlockedChat;

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
          _myUser = UserModel.fromFirestore(doc);
          _isMyAccountDeleted = doc.exists &&
            ((doc.data() as Map<String, dynamic>?)?['isDeleted'] ?? false);
        });
      }
    } catch (e) {
      debugPrint("Error fetching my user: $e");
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
  /// connectivity returns, so no cubit teardown is needed here.  This
  /// listener is kept as a no-op placeholder in case future screen-level
  /// reconnect logic is required.
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

  void _startVoiceCall() async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (widget.contact.uid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: CustomText(text: 'Cannot call yourself')));
      return;
    }
    if (!_ensureOnlineForCall()) return;
    if (_isMyAccountDeleted) {
      _showMyDeletedCallMessage();
      return;
    }
    if (_isDeletedOrBlocked) {
      _showBlockedCallMessage();
      return;
    }

    final channel = buildChannelName(isGroup: false, contact: widget.contact);

    final existingCallId = await CallService.getActiveCallId(channel, false);
    String callId;
    if (existingCallId != null) {
      callId = existingCallId;
      debugPrint('Joining existing voice call: $callId');
    } else {
      try {
        callId = await CallService.startCall(
            receiver: widget.contact,
            group: null,
            isVideo: false,
            channelName: channel);
      } on CallBlockedException {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const CustomText(text: 'You cannot call this user.'),
            backgroundColor: Colors.red.shade400,
          ));
        return;
      }
    }

    if (!mounted) return;
    Navigator.pushNamed(context, RouteNames.voiceCallPage,
        arguments: CallArguments(
            isGroup: false,
            contact: widget.contact,
            callerName: _chatName,
            callId: callId,
            isVideo: false));
  }

  void _startVideoCall() async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (widget.contact.uid == currentUid) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Cannot call yourself')));
      return;
    }
    if (!_ensureOnlineForCall()) return;
    if (_isMyAccountDeleted) {
      _showMyDeletedCallMessage();
      return;
    }
    if (_isDeletedOrBlocked) {
      _showBlockedCallMessage();
      return;
    }

    final channel = buildChannelName(isGroup: false, contact: widget.contact);

    final existingCallId = await CallService.getActiveCallId(channel, true);
    String callId;
    if (existingCallId != null) {
      callId = existingCallId;
      debugPrint('Joining existing video call: $callId');
    } else {
      try {
        callId = await CallService.startCall(
            receiver: widget.contact,
            group: null,
            isVideo: true,
            channelName: channel);
      } on CallBlockedException {
        if (!mounted) return;
        ScaffoldMessenger.of(context)
          ..hideCurrentSnackBar()
          ..showSnackBar(SnackBar(
            content: const CustomText(text: 'You cannot call this user.'),
            backgroundColor: Colors.red.shade400,
          ));
        return;
      }
    }

    if (!mounted) return;
    Navigator.pushNamed(context, RouteNames.videoCallPage,
        arguments: CallArguments(
            isGroup: false,
            contact: widget.contact,
            callerName: _chatName,
            callId: callId,
            isVideo: true));
  }

  void _showMyDeletedCallMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(const SnackBar(
        content: CustomText(
            text: 'Your account was deleted. You can no longer make calls.'),
        backgroundColor: Colors.red,
      ));
  }

  void _showBlockedCallMessage() {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: CustomText(
            text: _isAccountDeleted
                ? 'This user has deleted their account. You cannot call them.'
                : _iBlockedContact
                    ? 'Unblock this user before calling.'
                    : 'You cannot call this user.'),
        backgroundColor: Colors.red.shade400,
      ));
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);

    final chatCubit = _chatCubit ??= ChatCubit(
      chatId: _chatId,
      isGroupChat: false,
      recipientId: widget.contact.uid,
      recipient: widget.contact,
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
              if (_isDeletedOrBlocked || _isMyAccountDeleted)
                _buildBlockedBanner(context),
              if (_searchActive)
                ChatSearchOverlay(
                  isGroup: false,
                  myUid: FirebaseAuth.instance.currentUser!.uid,
                  members: _searchMembers,
                  onClose: () => setState(() => _searchActive = false),
                  onJumpTo: _jumpToMessage,
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
                    isGroup: false,
                    members: const {},
                    contactAvatar: widget.contact.avatarEmoji,
                  );
                },
              ),
              if (_isDeletedOrBlocked || _isMyAccountDeleted)
                _buildBlockedComposer(context)
              else
                MessageComposer(chatId: _chatId, isGroup: false),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar(BuildContext context) {
    final colors = FcAppColors.of(context);
    final Widget subtitleWidget = ChatPresenceSubtitle(
      recipientUid: widget.contact.uid,
      typingStream: _chatCubit!.typingStream,
      isDeleted: _isAccountDeleted || _isMyAccountDeleted,
      isBlocked: _isBlockedChat,
    );

    return AppBar(
      elevation: 1,
      backgroundColor: Colors.lightBlueAccent,
      centerTitle: false,
      titleSpacing: 0,
      iconTheme: const IconThemeData(color: Colors.white),
      title: InkWell(
        onTap: () {
          if (!_isAccountDeleted) {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    SenderProfileScreen(user: widget.contact),
                transitionsBuilder: PageTransition.slideFromRight,
              ),
            );
          }
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
                    subtitleWidget,
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
          visualDensity: VisualDensity.compact,
          onPressed: () {
            setState(() {
              _searchActive = true;
            });
          },
        ),
        if (!_isDeletedOrBlocked &&
            !_isMyAccountDeleted &&
            widget.contact.uid != FirebaseAuth.instance.currentUser!.uid) ...[
          IconButton(
            icon: const Icon(Icons.call, color: Colors.white, size: 22),
            tooltip: 'Voice Call',
            visualDensity: VisualDensity.compact,
            onPressed: _startVoiceCall,
          ),
          IconButton(
            icon: const Icon(Icons.videocam, color: Colors.white, size: 22),
            tooltip: 'Video Call',
            visualDensity: VisualDensity.compact,
            onPressed: _startVideoCall,
          ),
        ],
      ],
    );
  }

  Widget _buildBlockedBanner(BuildContext context) {
    if (_isMyAccountDeleted) {
      return _buildMyAccountDeletedBanner(context);
    }
    if (_isAccountDeleted) {
      return _buildDeletedAccountBanner(context);
    }

    final contactName = _chatName;
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: _iBlockedContact ? Colors.red.shade50 : Colors.orange.shade50,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(
              Icons.block,
              color: _iBlockedContact
                  ? Colors.red.shade400
                  : Colors.orange.shade700,
              size: 20,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: CustomText(
                text: _iBlockedContact
                    ? 'You blocked $contactName. You cannot send messages to this user.'
                    : 'You cannot send messages to $contactName.',
                fontSize: 13.sp,
                textColor: _iBlockedContact
                    ? Colors.red.shade700
                    : Colors.orange.shade900,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            if (_iBlockedContact)
              TextButton(
                onPressed: () async {
                  await BlockService.unblockUser(widget.contact.uid);
                },
                child: CustomText(
                  text: 'Unblock',
                  fontSize: 13.sp,
                  fontWeight: FontWeight.bold,
                  textColor: Colors.red.shade400,
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

  Widget _buildDeletedAccountBanner(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Container(
      width: double.infinity,
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 10.h),
      color: colors.tile,
      child: SafeArea(
        bottom: false,
        child: Row(
          children: [
            Icon(
              Icons.person_remove,
              color: colors.textSecondary,
              size: 20,
            ),
            SizedBox(width: 10.w),
            Expanded(
              child: CustomText(
                text:
                    'This user has deleted their account. You cannot send messages or call them.',
                fontSize: 13.sp,
                textColor: colors.textSecondary,
                maxLines: 2,
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
              _isMyAccountDeleted
                  ? Icons.remove_circle_outline
                  : (_isAccountDeleted ? Icons.person_remove : Icons.lock_outline),
              color: colors.textWeak,
              size: 20,
            ),
            SizedBox(width: 8.w),
            Flexible(
              child: CustomText(
                text: _isMyAccountDeleted
                    ? 'Your account is deleted — you can only read messages'
                    : _isAccountDeleted
                        ? 'This user has deleted their account'
                        : _iBlockedContact
                            ? 'You blocked this user'
                            : 'You cannot send messages to this user',
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
            Widget buildEmptyChatState() {
              if (_isMyAccountDeleted) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.remove_circle_outline,
                        size: 56,
                        color: Colors.red,
                      ),
                      SizedBox(height: 12.h),
                      CustomText(
                        text: 'Your account was deleted.',
                        textAlign: TextAlign.center,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        textColor: colors.textSecondary,
                      ),
                      SizedBox(height: 8.h),
                      CustomText(
                        text: 'You can only read your previous chats.',
                        textAlign: TextAlign.center,
                        fontSize: 14.sp,
                        textColor: colors.textWeak,
                      ),
                    ],
                  ),
                );
              } else if (_isAccountDeleted) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_remove,
                        size: 56,
                        color: colors.textWeak,
                      ),
                      SizedBox(height: 12.h),
                      CustomText(
                        text: 'This user has deleted their account.',
                        textAlign: TextAlign.center,
                        fontSize: 18.sp,
                        fontWeight: FontWeight.bold,
                        textColor: colors.textSecondary,
                      ),
                      SizedBox(height: 8.h),
                      CustomText(
                        text: 'You cannot send messages or call them.',
                        textAlign: TextAlign.center,
                        fontSize: 14.sp,
                        textColor: colors.textWeak,
                      ),
                    ],
                  ),
                );
              } else if (_isBlockedChat) {
                return Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.block,
                        size: 56,
                        color: _iBlockedContact
                            ? Colors.red.shade200
                            : Colors.orange.shade200,
                      ),
                      SizedBox(height: 12.h),
                      CustomText(
                        text: _iBlockedContact
                            ? 'You blocked $_chatName. Unblock to start chatting again.'
                            : '$_chatName has blocked you.',
                        textAlign: TextAlign.center,
                        fontSize: 15.sp,
                        textColor: colors.textSecondary,
                      ),
                    ],
                  ),
                );
              }

              return const Center(child: CustomText(text: "Say hello! 👋"));
            }

            if (_isDeletedOrBlocked || _isMyAccountDeleted) {
              return buildEmptyChatState();
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
        Expanded(child: list),
      ],
    );
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

    final senderAvatar = isMe
        ? (_myUser?.avatarEmoji ?? '👤')
        : (_isAccountDeleted ? '❌' : widget.contact.avatarEmoji);

    final senderName = isMe ? 'You' : _chatName;

    final key = _messageKeys[message.id] ??= GlobalKey();

    final messageWidget = MessageBubble(
      key: key,
      message: message,
      isMe: isMe,
      isGroup: false,
      sender: null,
      senderAvatar: senderAvatar,
      contactName: _chatName,
      members: members,
      highlighted: _highlightedMessageId == message.id,
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
    if (!message.isDeleted) {
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
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final authUser = FirebaseAuth.instance.currentUser;
    // Local fallback so search works even before my user doc finishes
    // loading (normally it lands instantly and the real avatar replaces it).
    final displayName = authUser?.displayName ?? '';
    final nameParts = displayName.split(' ');
    return {
      myUid: _myUser ??
          UserModel(
            uid: myUid,
            email: authUser?.email ?? '',
            firstName: nameParts.isNotEmpty ? nameParts.first : 'Me',
            lastName: nameParts.length > 1
                ? nameParts.skip(1).join(' ')
                : '',
            phoneNumber: authUser?.phoneNumber ?? '',
            avatarEmoji: '👤',
          ),
      widget.contact.uid: widget.contact,
    };
  }
}