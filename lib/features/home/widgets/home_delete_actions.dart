import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../groups/models/group_model.dart';
import '../../../shared/widgets/custom_text.dart';

/// Hides the conversation from my home list and clears every message for me,
/// then shows a success/error snackbar. Messages stay intact for everyone
/// else (Telegram-style "delete chat for me").
Future<void> hideConversationForCurrentUser({
  required FirebaseFirestore firestore,
  required String myUid,
  required String id,
  required String collectionName,
  required BuildContext context,
}) async {
  final String type = collectionName == 'chats' ? 'Chat' : 'Group';
  final String lowerType = type.toLowerCase();
  try {
    // Hide the chat from my home list.
    await firestore.collection(collectionName).doc(id).update({
      'hiddenFor': FieldValue.arrayUnion([myUid]),
    });

    // Also clear all the messages for me: mark every message in this chat
    // as deleted-for-me so the conversation history no longer shows the
    // content. This keeps the other side's copy intact, exactly like
    // Telegram's "delete chat for me".
    await deleteAllMessagesForMe(firestore, id, collectionName, myUid);

    // Show success message
    if (!context.mounted) return;
    _showDeleteStatus(context, '$type deleted successfully', isError: false);
  } catch (e) {
    if (!context.mounted) return;
    _showDeleteStatus(context, 'Failed to hide $lowerType', isError: true);
  }
}

/// Marks every message in a chat/group as deleted-for-me for the given uid,
/// so the conversation content no longer appears on this device. Messages
/// stay intact for everyone else (Telegram-style "delete chat for me").
/// Handles arbitrarily large histories by batching (Firestore allows at most
/// 500 writes per batch) and pages through the whole subcollection.
Future<void> deleteAllMessagesForMe(
  FirebaseFirestore firestore,
  String chatId,
  String collectionName,
  String uid,
) async {
  final messagesRef =
      firestore.collection(collectionName).doc(chatId).collection('messages');

  // Page through the whole subcollection, batching writes (Firestore allows
  // at most 500 writes per batch), advancing by the last document seen so
  // the cursor never revisits the same docs (which would loop forever).
  QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
  while (true) {
    Query<Map<String, dynamic>> query = messagesRef.limit(400);
    if (cursor != null) query = query.startAfterDocument(cursor);

    final snapshot = await query.get();
    if (snapshot.docs.isEmpty) break;

    final batch = firestore.batch();
    for (final doc in snapshot.docs) {
      final deletedForMe =
          List<String>.from(doc.data()['deletedForMe'] ?? const []);
      if (deletedForMe.contains(uid)) continue;
      batch.update(doc.reference, {
        'deletedForMe': FieldValue.arrayUnion([uid]),
      });
    }
    await batch.commit();

    cursor = snapshot.docs.last;
    if (snapshot.docs.length < 400) break;
  }
}

/// Marks the whole group as deleted (soft delete) and posts a system
/// message announcing it, mirroring the admin's delete in Group Info.
/// The group doc and messages stay in place so every member keeps reading
/// the history, but the chat becomes read-only (no sending / calling).
Future<void> softDeleteGroupForEveryone({
  required FirebaseFirestore firestore,
  required String myUid,
  required GroupModel group,
  required BuildContext context,
}) async {
  try {
    await firestore.collection('groups').doc(group.id).update({
      'isDeleted': true,
    });

    // Post a system message so every member can see why the chat went
    // read-only. Fire-and-forget: a failure here must not undo the delete.
    try {
      final myDoc = await firestore.collection('users').doc(myUid).get();
      final data = myDoc.exists ? myDoc.data() : null;
      final myName =
          '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim();
      final actorName = myName.isNotEmpty ? myName : 'A member';
      await firestore
          .collection('groups')
          .doc(group.id)
          .collection('messages')
          .add({
        'text': '$actorName deleted this group',
        'senderId': myUid,
        'senderName': actorName,
        'messageType': 'system',
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'sent',
        'reactions': {},
        'starredBy': [],
        'deletedForMe': [],
        'imageReactions': {},
        'isDeleted': false,
        'isEdited': false,
      });
    } catch (e) {
      debugPrint('Failed to post group-deleted system message: $e');
    }

    if (!context.mounted) return;
    _showDeleteStatus(context, 'Group deleted', isError: false);
  } catch (e) {
    if (!context.mounted) return;
    _showDeleteStatus(context, 'Failed to delete group', isError: true);
  }
}

/// Permanently deletes a conversation (chat or group) and all its messages
/// for everyone.
Future<void> deleteConversationForEveryone({
  required FirebaseFirestore firestore,
  required String id,
  required String collectionName,
  required BuildContext context,
}) async {
  final String type = collectionName == 'chats' ? 'Chat' : 'Group';
  final String lowerType = type.toLowerCase();
  try {
    // Delete all messages in the conversation
    final messagesSnapshot = await firestore
        .collection(collectionName)
        .doc(id)
        .collection('messages')
        .get();

    // Delete messages in batches
    final batch = firestore.batch();
    for (var doc in messagesSnapshot.docs) {
      batch.delete(doc.reference);
    }
    await batch.commit();

    // Delete the conversation document itself
    await firestore.collection(collectionName).doc(id).delete();

    // Show success message
    if (!context.mounted) return;
    _showDeleteStatus(context, '$type deleted for everyone', isError: false);
  } catch (e) {
    if (!context.mounted) return;
    _showDeleteStatus(context, 'Failed to delete $lowerType', isError: true);
  }
}

void _showDeleteStatus(BuildContext context, String text,
    {required bool isError}) {
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Row(
        children: [
          Icon(
            isError ? Icons.error_outline : Icons.check_circle,
            color: Colors.white,
            size: 20.sp,
          ),
          SizedBox(width: 12.w),
          CustomText(text: text),
        ],
      ),
      backgroundColor: isError ? Colors.red : Colors.lightBlueAccent,
      behavior: SnackBarBehavior.floating,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
      margin: EdgeInsets.all(16.w),
      duration:
          isError ? const Duration(seconds: 4) : const Duration(seconds: 2),
    ),
  );
}