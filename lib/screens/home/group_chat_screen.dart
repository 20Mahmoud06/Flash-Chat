import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/screens/profile/group_info_screen.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flash_chat_app/widgets/message_bubble.dart'; // Extracted
import 'package:flash_chat_app/widgets/message_composer.dart'; // Extracted
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

class GroupChatScreen extends StatefulWidget {
  final GroupModel group;

  const GroupChatScreen({super.key, required this.group});

  @override
  State<GroupChatScreen> createState() => _GroupChatScreenState();
}

class _GroupChatScreenState extends State<GroupChatScreen> {
  final ScrollController _scrollController = ScrollController();
  final Map<String, GlobalKey> _messageKeys = {};
  Map<String, UserModel> _groupMembers = {};
  UserModel? _myUser;
  bool _isLoadingMembers = false;
  bool _isLoadingMyUser = true;

  @override
  void initState() {

    activeChatUserId = null;

    super.initState();
    activeGroupId = widget.group.id;
    _isLoadingMembers = true;
    _fetchGroupMembers(widget.group.memberUids);
    _fetchMyUser();
  }

  @override
  void dispose() {
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
    if (widget.group.memberUids.length <= 1) {  // Only self
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: CustomText(text:'Cannot start call in solo group')));
      return;
    }

    final channel = buildChannelName(isGroup: true, group: widget.group);

    final existingCallId = await CallService.getActiveCallId(channel, false);
    String callId;
    if (existingCallId != null) {
      callId = existingCallId;
      debugPrint('Joining existing group voice call: $callId');
    } else {
      callId = await CallService.startCall(receiver: null, group: widget.group, isVideo: false, channelName: channel);
    }

    Navigator.pushNamed(context, RouteNames.voiceCallPage,
        arguments: CallArguments(isGroup: true, group: widget.group, callId: callId, isVideo: false));
  }

  void _startVideoCall() async {
    if (widget.group.memberUids.length <= 1) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Cannot start call in solo group')));
      return;
    }

    final channel = buildChannelName(isGroup: true, group: widget.group);

    final existingCallId = await CallService.getActiveCallId(channel, true);
    String callId;
    if (existingCallId != null) {
      callId = existingCallId;
      debugPrint('Joining existing group video call: $callId');
    } else {
      callId = await CallService.startCall(receiver: null, group: widget.group, isVideo: true, channelName: channel);
    }

    Navigator.pushNamed(context, RouteNames.videoCallPage,
        arguments: CallArguments(isGroup: true, group: widget.group, callId: callId, isVideo: true));
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => ChatCubit(
        chatId: widget.group.id,
        isGroupChat: true,
      ),
      child: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: Scaffold(
          backgroundColor: Colors.grey.shade200,
          appBar: AppBar(
            elevation: 1,
            backgroundColor: Colors.lightBlueAccent,
            iconTheme: const IconThemeData(color: Colors.white),
            title: GestureDetector(
              onTap: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        GroupInfoScreen(group: widget.group),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              },
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: Colors.lightBlue.shade50,
                    child: CustomText(text: widget.group.avatarEmoji, fontSize: 20.sp),
                  ),
                  SizedBox(width: 8.w),
                  Expanded(
                    child: Text(
                      widget.group.name,
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
              if (widget.group.memberUids.length > 1)
                IconButton(
                  icon: const Icon(Icons.call, color: Colors.white),
                  onPressed: _startVoiceCall,
                ),
              if (widget.group.memberUids.length > 1)
                IconButton(
                  icon: const Icon(Icons.videocam, color: Colors.white),
                  onPressed: _startVideoCall,
                ),
              IconButton(
                icon: const Icon(Icons.group_outlined, color: Colors.white, size: 28),
                onPressed: () {
                  Navigator.push(
                    context,
                    PageRouteBuilder(
                      pageBuilder: (context, animation, secondaryAnimation) =>
                          GroupInfoScreen(group: widget.group),
                      transitionsBuilder: PageTransition.slideFromRight,
                    ),
                  );
                },
              ),
              SizedBox(width: 8.w),
            ],
          ),
          body: Column(
            children: [
              Expanded(
                child: BlocConsumer<ChatCubit, ChatState>(
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

                            final sender = _groupMembers[message.senderId];

                            final senderAvatar = sender?.avatarEmoji ?? '👤';

                            final senderName = sender != null ? '${sender.firstName} ${sender.lastName}' : 'Unknown';

                            final key = _messageKeys[message.id] ??= GlobalKey();

                            final messageWidget = MessageBubble(
                              key: key,
                              message: message,
                              isMe: isMe,
                              isGroup: true,
                              sender: sender,
                              senderAvatar: senderAvatar,
                              members: _groupMembers,
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
                ),
              ),
              MessageComposer(chatId: widget.group.id, isGroup: true),
            ],
          ),
        ),
      ),
    );
  }
}