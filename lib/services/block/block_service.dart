import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter/foundation.dart';

/// Thrown when an action (message/call) is attempted against a blocked user.
class CallBlockedException implements Exception {
  final String message;
  const CallBlockedException([this.message = 'You cannot call this user.']);
}

class BlockService {
  static final _firestore = FirebaseFirestore.instance;
  static final _auth = FirebaseAuth.instance;

  /// Blocks [targetUid] for the current user.
  static Future<void> blockUser(String targetUid) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).update({
      'blockedUids': FieldValue.arrayUnion([targetUid]),
    });
  }

  /// Unblocks [targetUid] for the current user.
  static Future<void> unblockUser(String targetUid) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    await _firestore.collection('users').doc(uid).update({
      'blockedUids': FieldValue.arrayRemove([targetUid]),
    });
  }

  static Future<List<String>> getBlockedUids([String? uid]) async {
    final myUid = uid ?? _auth.currentUser?.uid;
    if (myUid == null) return const [];
    final doc = await _firestore.collection('users').doc(myUid).get();
    return List<String>.from(doc.data()?['blockedUids'] ?? const []);
  }

  /// True when the current user has blocked [targetUid].
  static Future<bool> isBlockedByMe(String targetUid) async {
    return (await getBlockedUids()).contains(targetUid);
  }

  /// True when [otherUid] has blocked the current user.
  static Future<bool> hasBlockedMe(String otherUid) async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return false;
    final doc = await _firestore.collection('users').doc(otherUid).get();
    if (!doc.exists) return false;
    return List<String>.from(doc.data()?['blockedUids'] ?? const [])
        .contains(myUid);
  }

  /// True when either side of the conversation has blocked the other.
  static Future<bool> isEitherBlocked(String otherUid) async {
    if (await isBlockedByMe(otherUid)) return true;
    return await hasBlockedMe(otherUid);
  }

  /// True when either side has blocked the other (no auth dependency).
  static Future<bool> isBlockedPair(String uidA, String uidB) async {
    if (uidA == uidB) return false;
    try {
      final docA = await _firestore.collection('users').doc(uidA).get();
      if (docA.exists &&
          List<String>.from(docA.data()?['blockedUids'] ?? const [])
              .contains(uidB)) {
        return true;
      }
      final docB = await _firestore.collection('users').doc(uidB).get();
      if (docB.exists &&
          List<String>.from(docB.data()?['blockedUids'] ?? const [])
              .contains(uidA)) {
        return true;
      }
    } catch (e) {
      debugPrint('BlockService.isBlockedPair error: $e');
    }
    return false;
  }

  /// Returns full user documents for everyone the current user blocked.
  static Future<List<UserModel>> getBlockedUsers() async {
    final myUid = _auth.currentUser?.uid;
    if (myUid == null) return const [];

    final blockedUids = await getBlockedUids(myUid);
    if (blockedUids.isEmpty) return const [];

    final users = <UserModel>[];
    // Firestore 'whereIn' is limited to 10 ids per query.
    for (var i = 0; i < blockedUids.length; i += 10) {
      final chunk = blockedUids.sublist(
          i, i + 10 > blockedUids.length ? blockedUids.length : i + 10);
      final snapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      for (final doc in snapshot.docs) {
        users.add(UserModel.fromFirestore(doc));
      }
    }

    users.sort((a, b) =>
        a.fullName.toLowerCase().compareTo(b.fullName.toLowerCase()));
    return users;
  }
}