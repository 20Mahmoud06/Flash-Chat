import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flash_chat_app/features/sender_profile/screens/sender_profile_screen.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/routes/route_names.dart';
import '../../../core/utils/call_utils.dart';
import '../../../core/utils/page_transition.dart';
import '../../calls/models/call_arguments.dart';
import '../../../services/block/block_service.dart';
import '../services/active_chat.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../services/fcm/fcm_service.dart';
import '../../../services/notifications/missed_notifications_service.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../calls/services/call_service.dart';
import '../cubit/chat_cubit.dart';
import '../cubit/chat_state.dart';
import '../widgets/chat_app_bar.dart';
import '../widgets/chat_blocked_banner.dart';
import '../widgets/chat_blocked_composer.dart';
import '../widgets/chat_call_helpers.dart';
import '../widgets/chat_message_scroll.dart';
import '../widgets/chat_messages_body.dart';
import '../widgets/chat_presence_subtitle.dart';
import '../widgets/chat_scroll_down_button.dart';
import '../widgets/chat_search_overlay.dart';
import '../widgets/message_composer/message_composer.dart';
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

  bool get _iBlockedContact => _myBlockedUids.contains(widget.contact.uid);

  bool get _isBlockedChat => _iBlockedContact || _blockedMe;

  bool get _isDeletedOrBlocked => _isAccountDeleted || _isBlockedChat;

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
  /// connectivity returns, so no bloc teardown is needed here.  This
  /// listener is kept as a no-op placeholder in case future screen-level
  /// reconnect logic is required.
  void _onConnectivityChanged() {}

  void _startVoiceCall() async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (widget.contact.uid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: CustomText(text: 'Cannot call yourself')));
      return;
    }
    if (!ensureOnlineForCall(context)) return;
    if (_isMyAccountDeleted) {
      showMyDeletedCallMessage(context);
      return;
    }
    if (_isDeletedOrBlocked) {
      showBlockedCallMessage(context,
          accountDeleted: _isAccountDeleted, iBlockedContact: _iBlockedContact);
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
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: CustomText(text: 'Cannot call yourself')));
      return;
    }
    if (!ensureOnlineForCall(context)) return;
    if (_isMyAccountDeleted) {
      showMyDeletedCallMessage(context);
      return;
    }
    if (_isDeletedOrBlocked) {
      showBlockedCallMessage(context,
          accountDeleted: _isAccountDeleted, iBlockedContact: _iBlockedContact);
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

  void _openContactProfile() {
    Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) =>
            SenderProfileScreen(user: widget.contact),
        transitionsBuilder: PageTransition.slideFromRight,
      ),
    );
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

    final showBlockUi = _isDeletedOrBlocked || _isMyAccountDeleted;

    return BlocProvider.value(
      value: chatCubit,
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: colors.screen,
          appBar: buildChatAppBar(
            context: context,
            chatName: _chatName,
            chatAvatar: _chatAvatar,
            subtitle: ChatPresenceSubtitle(
              recipientUid: widget.contact.uid,
              typingStream: chatCubit.typingStream,
              isDeleted: _isAccountDeleted || _isMyAccountDeleted,
              isBlocked: _isBlockedChat,
            ),
            onTitleTap: _isAccountDeleted ? null : _openContactProfile,
            showCallButtons: !showBlockUi &&
                widget.contact.uid != FirebaseAuth.instance.currentUser!.uid,
            onSearch: () => setState(() => _searchActive = true),
            onVoiceCall: _startVoiceCall,
            onVideoCall: _startVideoCall,
          ),
          body: Column(
            children: [
              if (showBlockUi)
                ChatBlockedBanner(
                  myAccountDeleted: _isMyAccountDeleted,
                  accountDeleted: _isAccountDeleted,
                  iBlockedContact: _iBlockedContact,
                  chatName: _chatName,
                  onUnblock: () async {
                    await BlockService.unblockUser(widget.contact.uid);
                  },
                ),
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
                    Positioned.fill(
                      child: ChatMessagesBody(
                        scrollController: _scrollController,
                        messageKeys: _messageKeys,
                        members: _searchMembers,
                        chatName: _chatName,
                        myAvatar: _myUser?.avatarEmoji ?? '👤',
                        contactAvatar:
                            _isAccountDeleted ? '❌' : widget.contact.avatarEmoji,
                        highlightedMessageId: _highlightedMessageId,
                        accountDeleted: _isAccountDeleted,
                        myAccountDeleted: _isMyAccountDeleted,
                        blockedChat: _isBlockedChat,
                        iBlockedContact: _iBlockedContact,
                        onJumpToMessage: _jumpToMessage,
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
                    isGroup: false,
                    members: const {},
                    contactAvatar: widget.contact.avatarEmoji,
                  );
                },
              ),
              if (showBlockUi)
                ChatBlockedComposer(
                  myAccountDeleted: _isMyAccountDeleted,
                  accountDeleted: _isAccountDeleted,
                  iBlockedContact: _iBlockedContact,
                )
              else
                MessageComposer(chatId: _chatId, isGroup: false),
            ],
          ),
        ),
      ),
    );
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
            lastName: nameParts.length > 1 ? nameParts.skip(1).join(' ') : '',
            phoneNumber: authUser?.phoneNumber ?? '',
            avatarEmoji: '👤',
          ),
      widget.contact.uid: widget.contact,
    };
  }
}