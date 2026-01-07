import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/screens/profile/sender_profile_screen.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flash_chat_app/widgets/message_bubble.dart';
import 'package:flash_chat_app/widgets/message_composer.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:swipe_to/swipe_to.dart';
import '../../core/routes/route_names.dart';
import '../../cubits/chat_cubit/chat_cubit.dart';
import '../../cubits/chat_cubit/chat_state.dart';
import '../../models/call_arguments.dart';
import '../../services/active_chat.dart';
import '../../services/call_service.dart';
import '../../utils/call_utils.dart';
import '../../utils/page_transition.dart';
import '../profile/group_info_screen.dart';

class ChatScreen extends StatefulWidget {
  final UserModel? contact;
  final GroupModel? group;

  const ChatScreen({super.key, this.contact, this.group})
      : assert(contact != null || group != null,
  'Either a contact or a group must be provided');

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  late final String _chatId;
  late final bool _isGroupChat;
  late final String _chatName;
  late final String _chatAvatar;

  Map<String, UserModel> _groupMembers = {};
  UserModel? _myUser;
  bool _isLoadingMembers = false;
  bool _isLoadingMyUser = true;

  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};

  @override
  void initState() {
    super.initState();

    // 🔹 Determine chat type
    _isGroupChat = widget.group != null;

    if (_isGroupChat) {
      // -------- GROUP CHAT --------
      final group = widget.group!;

      _chatId = group.id;
      _chatName = group.name;
      _chatAvatar = group.avatarEmoji ?? '👥';

      activeGroupId = group.id;
      activeChatUserId = null;

      _isLoadingMembers = true;
      _fetchGroupMembers(group.memberUids);
    } else {
      // -------- 1-to-1 CHAT --------
      final contact = widget.contact!;

      _chatId = buildChannelName(
        isGroup: false,
        contact: contact,
      );

      _chatName = '${contact.firstName} ${contact.lastName}';
      _chatAvatar = contact.avatarEmoji ?? '👤';

      activeChatUserId = contact.uid;
      activeGroupId = null;
    }

    _fetchMyUser();
  }

  @override
  void dispose() {
    activeChatUserId = null;
    activeGroupId = null;
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _fetchMyUser() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser!;
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(currentUser.uid)
          .get();
      if (mounted) {
        setState(() {
          _myUser = UserModel.fromFirestore(doc);
          _isLoadingMyUser = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching my user: $e");
    }
  }

  Future<void> _fetchGroupMembers(List<String> uids) async {
    try {
      final usersSnapshot = await FirebaseFirestore.instance
          .collection('users')
          .where(FieldPath.documentId, whereIn: uids)
          .get();

      final members = <String, UserModel>{};
      for (var doc in usersSnapshot.docs) {
        members[doc.id] = UserModel.fromFirestore(doc);
      }
      if (mounted) {
        setState(() {
          _groupMembers = members;
          _isLoadingMembers = false;
        });
      }
    } catch (e) {
      debugPrint("Error fetching group members: $e");
      if (mounted) {
        setState(() => _isLoadingMembers = false);
      }
    }
  }

  void scrollToMessage(String messageId) {
    final key = _messageKeys[messageId];
    final ctx = key?.currentContext;
    if (ctx != null) {
      Scrollable.ensureVisible(
        ctx,
        alignment: 0.5,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    }
  }

  void _startVoiceCall() async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (widget.contact?.uid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: CustomText(text: 'Cannot call yourself')));
      return;
    }

    final channel = buildChannelName(isGroup: false, contact: widget.contact);

    final existingCallId = await CallService.getActiveCallId(channel, false);
    String callId;
    if (existingCallId != null) {
      callId = existingCallId;
      debugPrint('Joining existing voice call: $callId');
    } else {
      callId = await CallService.startCall(receiver: widget.contact, group: null, isVideo: false, channelName: channel);
    }

    Navigator.pushNamed(context, RouteNames.voiceCallPage,
        arguments: CallArguments(isGroup: false, contact: widget.contact, callId: callId, isVideo: false));
  }

  void _startVideoCall() async {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (widget.contact?.uid == currentUid) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot call yourself')));
      return;
    }

    final channel = buildChannelName(isGroup: false, contact: widget.contact);

    final existingCallId = await CallService.getActiveCallId(channel, true);
    String callId;
    if (existingCallId != null) {
      callId = existingCallId;
      debugPrint('Joining existing video call: $callId');
    } else {
      callId = await CallService.startCall(receiver: widget.contact, group: null, isVideo: true, channelName: channel);
    }

    Navigator.pushNamed(context, RouteNames.videoCallPage,
        arguments: CallArguments(isGroup: false, contact: widget.contact, callId: callId, isVideo: true));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatCubit(
        chatId: _chatId,
        isGroupChat: _isGroupChat,
        recipientId: _isGroupChat ? null : widget.contact!.uid,
        recipient: _isGroupChat ? null : widget.contact,
      ),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: Colors.grey.shade200,
          appBar: _buildAppBar(),
          body: Column(
            children: [
              Expanded(child: _buildChatBody()),
              MessageComposer(chatId: _chatId, isGroup: _isGroupChat),
            ],
          ),
        ),
      ),
    );
  }

  AppBar _buildAppBar() {
    return AppBar(
      elevation: 1,
      backgroundColor: Colors.lightBlueAccent,
      iconTheme: const IconThemeData(color: Colors.white),
      title: GestureDetector(
        onTap: () {
          if (_isGroupChat) {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    GroupInfoScreen(group: widget.group!),
                transitionsBuilder: PageTransition.slideFromRight,
              ),
            );
          } else {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    SenderProfileScreen(user: widget.contact!),
                transitionsBuilder: PageTransition.slideFromRight,
              ),
            );
          }
        },
        child: Row(
          children: [
            CircleAvatar(
              backgroundColor: Colors.lightBlue.shade50,
              child: CustomText(text: _chatAvatar, fontSize: 20.sp),
            ),
            SizedBox(width: 8.w),
            Expanded(
              child: Text(
                _chatName,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18.sp,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (!_isGroupChat && widget.contact?.uid != FirebaseAuth.instance.currentUser!.uid)
          IconButton(icon: const Icon(Icons.call, color: Colors.white), onPressed: _startVoiceCall),
        if (!_isGroupChat && widget.contact?.uid != FirebaseAuth.instance.currentUser!.uid)
          IconButton(icon: const Icon(Icons.videocam, color: Colors.white), onPressed: _startVideoCall),
        IconButton(
          icon: Icon(
            _isGroupChat ? Icons.group_outlined : Icons.person_outline,
            color: Colors.white,
            size: 28,
          ),
          onPressed: () {
            if (_isGroupChat && widget.group != null) {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      GroupInfoScreen(group: widget.group!),
                  transitionsBuilder: PageTransition.slideFromRight,
                ),
              );
            } else if (!_isGroupChat && widget.contact != null) {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      SenderProfileScreen(user: widget.contact!),
                  transitionsBuilder: PageTransition.slideFromRight,
                ),
              );
            }
          },
        ),
        SizedBox(width: 8.w),
      ],
    );
  }

  Widget _buildChatBody() {
    return BlocConsumer<ChatCubit, ChatState>(
      listener: (context, state) {
        if (state is ChatError) {
          ScaffoldMessenger.of(context)
            ..hideCurrentSnackBar()
            ..showSnackBar(SnackBar(
              content: Text(state.message),
              backgroundColor: Colors.red,
            ));
        }
      },
      builder: (context, state) {
        if (state is ChatLoading ||
            state is ChatInitial ||
            _isLoadingMyUser ||
            _isLoadingMembers) {
          return const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent));
        }

        if (state is ChatLoaded) {
          if (state.messages.isEmpty) {
            return const Center(child: CustomText(text: "Say hello! 👋"));
          }
          final members = _isGroupChat
              ? _groupMembers
              : {
            FirebaseAuth.instance.currentUser!.uid: _myUser!,
            widget.contact!.uid: widget.contact!,
          };
          return NotificationListener<ScrollNotification>(
            onNotification: (scroll) {
              if (scroll.metrics.pixels == scroll.metrics.maxScrollExtent) {
                context.read<ChatCubit>().loadMoreMessages();
              }
              return false;
            },
            child: ListView.builder(
              controller: _scrollController,
              reverse: true,
              itemCount: state.messages.length,
              itemBuilder: (context, index) {
                final message = state.messages[index];
                final isMe = message.senderId == FirebaseAuth.instance.currentUser!.uid;

                final sender = _isGroupChat ? _groupMembers[message.senderId] : null;

                final senderAvatar = _isGroupChat
                    ? (sender?.avatarEmoji ?? '👤')
                    : (isMe ? (_myUser?.avatarEmoji ?? '👤') : widget.contact!.avatarEmoji);

                final senderName = _isGroupChat
                    ? (sender != null ? '${sender.firstName} ${sender.lastName}' : 'Unknown')
                    : (isMe ? 'You' : _chatName ?? 'Unknown');

                final key = _messageKeys[message.id] ??= GlobalKey();

                final messageWidget = MessageBubble(
                  key: key,
                  message: message,
                  isMe: isMe,
                  isGroup: _isGroupChat,
                  sender: sender,
                  senderAvatar: senderAvatar,
                  contactName: _chatName,
                  members: members,
                  onTapReplied: () {
                    final repliedId = message.repliedTo?['id'] as String?;
                    if (repliedId != null) {
                      scrollToMessage(repliedId);
                    }
                  },
                );

                if (message.isDeleted) {
                  return messageWidget;
                }

                return SwipeTo(
                  onLeftSwipe: isMe ? (details) {
                    context.read<ChatCubit>().setReplyingTo(message, senderName);
                  } : null,
                  onRightSwipe: !isMe ? (details) {
                    context.read<ChatCubit>().setReplyingTo(message, senderName);
                  } : null,
                  child: messageWidget,
                );
              },
            ),
          );
        }
        return const Center(child: CustomText(text: "Something went wrong."));
      },
    );
  }
}