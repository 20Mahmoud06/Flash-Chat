import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/constants/app_colors.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/page_transition.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/features/chat/screens/chat_screen.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flash_chat_app/services/connectivity/connectivity_service.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';

/// "Favorite Messages" scoped to a single 1:1 chat — every message the current
/// user starred in this conversation, newest first. Tapping an item opens the
/// chat and jumps to the exact starred message.
class ChatFavoriteMessagesScreen extends StatefulWidget {
  final String chatId;
  final UserModel contact;

  const ChatFavoriteMessagesScreen({
    super.key,
    required this.chatId,
    required this.contact,
  });

  @override
  State<ChatFavoriteMessagesScreen> createState() =>
      _ChatFavoriteMessagesScreenState();
}

class _ChatFavoriteMessagesScreenState
    extends State<ChatFavoriteMessagesScreen> {
  static const Color _gold = AppColors.amber;

  late final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  UserModel? _myUser;
  final Map<String, UserModel> _senders = {};

  Stream<QuerySnapshot<Map<String, dynamic>>> get _favoritesStream =>
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages')
          .where('starredBy', arrayContains: _myUid)
          // No orderBy here: it would require a composite index that may not
          // be deployed yet. Results are sorted client-side instead.
          .limit(200)
          .snapshots();

  @override
  void initState() {
    super.initState();
    _loadMyUser();
  }

  Future<void> _loadMyUser() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_myUid)
          .get();
      if (doc.exists && mounted) {
        setState(() => _myUser = UserModel.fromFirestore(doc));
      }
    } catch (_) {}
  }

  Future<void> _ensureSender(String uid) async {
    if (uid == _myUid || _senders.containsKey(uid) || uid == widget.contact.uid) {
      return;
    }
    try {
      final doc =
          await FirebaseFirestore.instance.collection('users').doc(uid).get();
      if (doc.exists && mounted) {
        setState(() => _senders[uid] = UserModel.fromFirestore(doc));
      }
    } catch (_) {}
  }

  Future<void> _openMessage(
      QueryDocumentSnapshot<Map<String, dynamic>> doc) async {
    final message = MessageModel.fromFirestore(doc);
    await Navigator.push(
      context,
      PageRouteBuilder(
        pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(
          contact: widget.contact,
          initialJumpMessageId: message.id,
        ),
        transitionsBuilder: PageTransition.slideFromRight,
      ),
    );
  }

  String _previewOf(MessageModel message) {
    switch (message.messageType) {
      case MessageType.text:
        return message.text;
      case MessageType.image:
        return '📷 Photo';
      case MessageType.video:
        return '🎬 Video';
      case MessageType.voice:
        return '🎤 Voice message';
      case MessageType.audio:
        return '🎵 Audio';
      case MessageType.file:
        return '📎 File';
      case MessageType.system:
        return message.text;
      case MessageType.call:
        return '📞 Call';
      case MessageType.callActive:
        return '📞 Live call';
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Scaffold(
      backgroundColor: colors.surface,
      appBar: AppBar(
        title: const CustomText(
          text: 'Favorite Messages',
          textColor: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 18,
        ),
        centerTitle: true,
        backgroundColor: Colors.lightBlueAccent,
        elevation: 1,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _favoritesStream,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            final offline = !ConnectivityService.instance.isConnected.value;
            return Center(
              child: Padding(
                padding: EdgeInsets.all(24.w),
                child: CustomText(
                  text: offline
                      ? 'No saved favorites to read offline yet.'
                      : 'Could not load your favorites. Please try again.',
                  fontSize: 14.sp,
                  textAlign: TextAlign.center,
                  textColor: colors.textSecondary,
                ),
              ),
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: Colors.lightBlueAccent),
            );
          }
          final docs = snapshot.data!.docs
              .where((d) => d.data()['isDeleted'] != true)
              .toList()
            // Newest favorites first (the stream itself is unordered).
            ..sort((a, b) {
              final ta = (a.data()['timestamp'] as Timestamp?)?.toDate();
              final tb = (b.data()['timestamp'] as Timestamp?)?.toDate();
              if (ta == null && tb == null) return 0;
              if (ta == null) return 1;
              if (tb == null) return -1;
              return tb.compareTo(ta);
            });
          for (final doc in docs) {
            final message = MessageModel.fromFirestore(doc);
            if (message.senderId != _myUid) {
              _ensureSender(message.senderId);
            }
          }
          if (docs.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.star_border, size: 52, color: _gold),
                  SizedBox(height: 12.h),
                  CustomText(
                    text: 'No favorite messages yet',
                    fontSize: 15.sp,
                    textColor: colors.textSecondary,
                  ),
                  SizedBox(height: 4.h),
                  CustomText(
                    text: 'Long-press a message and tap Favorite',
                    fontSize: 13.sp,
                    textColor: colors.textWeak,
                  ),
                ],
              ),
            );
          }
          return ListView.builder(
            padding: EdgeInsets.symmetric(vertical: 8.h),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final message = MessageModel.fromFirestore(doc);
              final isMe = message.senderId == _myUid;
              final sender = isMe ? _myUser : _senders[message.senderId];
              final senderName = isMe
                  ? 'You'
                  : (sender?.fullName ?? widget.contact.fullName);
              final avatar = isMe
                  ? (_myUser?.avatarEmoji ?? '👤')
                  : (sender?.avatarEmoji ?? widget.contact.avatarEmoji);
              final timeText = DateFormat('d MMM, h:mm a')
                  .format(message.timestamp.toDate());
              return Card(
                margin: EdgeInsets.symmetric(horizontal: 16.w, vertical: 5.h),
                elevation: 1,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                  side: BorderSide(color: colors.divider),
                ),
                child: ListTile(
                  contentPadding:
                      EdgeInsets.symmetric(horizontal: 14.w, vertical: 6.h),
                  leading: CircleAvatar(
                    radius: 20.r,
                    backgroundColor: colors.avatarBackground,
                    child: CustomText(text: avatar, fontSize: 18.sp),
                  ),
                  title: Row(
                    children: [
                      Flexible(
                        child: CustomText(
                          text: senderName,
                          fontSize: 15.sp,
                          fontWeight: FontWeight.w600,
                          textColor: colors.textPrimary,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      SizedBox(width: 6.w),
                      const Icon(Icons.star, size: 14, color: _gold),
                    ],
                  ),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(height: 3.h),
                      CustomText(
                        text: _previewOf(message),
                        fontSize: 13.sp,
                        textColor: colors.textSecondary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      SizedBox(height: 3.h),
                      CustomText(
                        text: timeText,
                        fontSize: 11.sp,
                        textColor: colors.textWeak,
                      ),
                    ],
                  ),
                  isThreeLine: true,
                  trailing: Icon(Icons.chevron_right,
                      color: colors.textWeak, size: 20),
                  onTap: () => _openMessage(doc),
                ),
              );
            },
          );
        },
      ),
    );
  }
}