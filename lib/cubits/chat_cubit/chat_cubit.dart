import 'dart:async';
import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/services/fcm_v1_sender.dart';
import 'chat_state.dart';

class ChatCubit extends Cubit<ChatState> {
  final String chatId;
  final bool isGroupChat;
  final String? recipientId;
  final UserModel? recipient;

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  StreamSubscription? _messagesSubscription;

  ChatCubit({
    required this.chatId,
    this.recipientId,
    this.recipient,
    this.isGroupChat = false,
  }) : super(ChatInitial()) {
    assert(isGroupChat || (recipientId != null && recipient != null),
    'Recipient info must be provided for one-on-one chats');
    _listenToMessages();
  }

  void _listenToMessages() {
    emit(ChatLoading());
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    final messagesRef = _firestore
        .collection(collectionPath)
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true);

    _messagesSubscription = messagesRef.snapshots().listen((snapshot) {
      final messages = snapshot.docs
          .map((doc) => MessageModel.fromFirestore(doc))
          .toList();
      if (state is ChatLoaded) {
        emit(ChatLoaded(
          messages,
          replyingTo: (state as ChatLoaded).replyingTo,
          replyingToSenderName: (state as ChatLoaded).replyingToSenderName,
        ));
      } else {
        emit(ChatLoaded(messages));
      }
      // Only mark messages as seen in one-on-one chats
      if (!isGroupChat) {
        _markMessagesAsSeen();
      }
    }, onError: (error) {
      emit(ChatError("Failed to load messages: $error"));
    });
  }

  Future<void> sendMessage(String text, UserModel sender) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    Map<String, dynamic>? repliedTo;
    if (state is ChatLoaded && (state as ChatLoaded).replyingTo != null) {
      final replyingState = state as ChatLoaded;
      repliedTo = {
        'id': replyingState.replyingTo!.id,
        'senderName': replyingState.replyingToSenderName,
        'text': replyingState.replyingTo!.text,
      };
      setReplyingTo(null, null);
    }

    final messageData = {
      'text': text,
      'senderId': currentUser.uid,
      'senderName': '${sender.firstName} ${sender.lastName}',
      if (!isGroupChat) 'recipientId': recipientId ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      'status': 'sent',
      'reactions': {},
      'isDeleted': false,
      'isEdited': false,
      if (repliedTo != null) 'repliedTo': repliedTo,
    };

    try {
      final collectionPath = isGroupChat ? 'groups' : 'chats';

      final chatRef = _firestore.collection(collectionPath).doc(chatId);

      // Ensure parent document has required fields
      if (!isGroupChat) {
        final uids = [currentUser.uid, recipientId!]..sort();
        await chatRef.set({
          'uids': uids,
          'hiddenFor': [],
        }, SetOptions(merge: true));
      } else {
        await chatRef.update({
          'membersUids': FieldValue.arrayUnion([currentUser.uid]),
        });
        await chatRef.set({
          'hiddenFor': [],
        }, SetOptions(merge: true));
      }

      // add message
      await chatRef.collection('messages').add(messageData);

      // update last message on the parent document
      await chatRef.set({
        'lastMessage': text,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastSenderId': currentUser.uid,
      }, SetOptions(merge: true));

      // send notifications...
      if (isGroupChat) {
        await _sendGroupNotification(sender, text);
      } else {
        await _sendDirectNotification(sender, text);
      }
    } catch (e) {
      emit(ChatError("Failed to send message: $e"));
    }
  }

  Future<void> _sendDirectNotification(UserModel sender, String text) async {
    if (recipientId == null) return;

    try {
      final doc = await _firestore.collection('users').doc(recipientId).get();
      if (!doc.exists) return;

      final tokens = List<String>.from(doc.data()?['fcmTokens'] ?? []);

      // Initialize the V1 Sender
      final fcmSender = await FcmV1Sender.getInstance();

      for (final token in tokens) {
        await fcmSender.sendMessageToToken(
          token: token,
          title: '${sender.firstName} ${sender.lastName}',
          body: text,
          chatType: 'chat',      // Required for deep link
          targetId: sender.uid,  // The Sender ID allows the receiver to open the chat
          receiverId: recipientId, // Required for cleaning up dead tokens
        );
      }
    } catch (e) {
      debugPrint("Error sending direct notification: $e");
    }
  }

  Future<void> _sendGroupNotification(UserModel sender, String text) async {
    try {
      final groupDoc = await _firestore.collection('groups').doc(chatId).get();
      if (!groupDoc.exists) return;

      final membersUids = List<String>.from(groupDoc.data()?['membersUids'] ?? []);
      // Don't send a notification to the person who sent the message
      final recipientUids = membersUids.where((uid) => uid != sender.uid).toList();

      if (recipientUids.isEmpty) return;

      // Initialize the V1 Sender
      final fcmSender = await FcmV1Sender.getInstance();

      // Chunk the queries if > 10 items (Firestore limit for 'whereIn' is 10)
      // For simplicity here we assume <= 10, but in prod you should chunk logic.
      final usersSnapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: recipientUids.take(10).toList())
          .get();

      for (final userDoc in usersSnapshot.docs) {
        final tokens = List<String>.from(userDoc.data()['fcmTokens'] ?? []);

        for (final token in tokens) {
          await fcmSender.sendMessageToToken(
            token: token,
            // For groups, the title is the group name
            title: groupDoc.data()?['name'] ?? 'New Group Message',
            // Body shows who sent the message
            body: '${sender.firstName}: $text',
            chatType: 'group_chat', // Required for deep link
            targetId: chatId,       // The Group ID allows opening the group chat
            receiverId: userDoc.id, // Required for cleaning up dead tokens for this specific user
          );
        }
      }
    } catch (e) {
      debugPrint("Error sending group notification: $e");
    }
  }

  void _markMessagesAsSeen() {
    // This logic is only for one-on-one chats
    if (isGroupChat || _auth.currentUser == null) return;

    _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('recipientId', isEqualTo: _auth.currentUser!.uid)
        .where('status', isNotEqualTo: 'seen')
        .get()
        .then((snapshot) {
      WriteBatch batch = _firestore.batch();
      for (var doc in snapshot.docs) {
        batch.update(doc.reference, {'status': 'seen'});
      }
      batch.commit();
    }).catchError((e) {
      debugPrint("Failed to update message status: $e");
    });
  }

  Future<void> _performMessageUpdate(
      String messageId, Map<String, dynamic> data) async {
    try {
      final collectionPath = isGroupChat ? 'groups' : 'chats';
      await _firestore
          .collection(collectionPath)
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update(data);
    } catch (e) {
      emit(ChatError("Failed to update message: $e"));
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await _performMessageUpdate(messageId, {'isDeleted': true, 'text': ''});
  }

  Future<void> editMessage(String messageId, String newText) async {
    await _performMessageUpdate(
        messageId, {'text': newText, 'isEdited': true});
  }

  Future<void> updateReaction(String messageId, String emoji) async {
    final uid = _auth.currentUser!.uid;
    await _performMessageUpdate(messageId, {'reactions.$uid': emoji});
  }

  void removeReaction(String messageId) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    FirebaseFirestore.instance
        .collection(collectionPath)
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'reactions.$uid': FieldValue.delete()});

    // Update local state (find the message in state.messages, remove the reaction, and emit ChatLoaded)
    if (state is ChatLoaded) {
      final loadedState = state as ChatLoaded;
      final updatedMessages = List<MessageModel>.from(loadedState.messages);
      final index = updatedMessages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final updatedReactions = Map<String, String>.from(updatedMessages[index].reactions);
        updatedReactions.remove(uid);
        updatedMessages[index] = updatedMessages[index].copyWith(reactions: updatedReactions);
        emit(ChatLoaded(
          updatedMessages,
          replyingTo: loadedState.replyingTo,
          replyingToSenderName: loadedState.replyingToSenderName,
        ));
      }
    }
  }

  void setReplyingTo(MessageModel? message, String? senderName) {
    if (state is ChatLoaded) {
      emit(ChatLoaded(
        (state as ChatLoaded).messages,
        replyingTo: message,
        replyingToSenderName: senderName,
      ));
    }
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    return super.close();
  }
}