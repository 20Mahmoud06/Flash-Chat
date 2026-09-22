import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../services/block/block_service.dart';
import 'sender_profile_state.dart';

/// Screen-scoped cubit for the sender/contact-info screen. Owns every read and
/// write about this contact's nickname and block state — all stored on my own
/// user doc so only I can change them.
class SenderProfileCubit extends Cubit<SenderProfileState> {
  SenderProfileCubit({required String contactUid})
      : _contactUid = contactUid,
        super(const SenderProfileState());

  final String _contactUid;

  /// Reads my user doc (nicknames), my blocked list, and the contact's blocked
  /// list to populate the whole initial state.
  Future<void> loadState() async {
    try {
      final myUid = FirebaseAuth.instance.currentUser!.uid;
      final myDoc =
          await FirebaseFirestore.instance.collection('users').doc(myUid).get();
      final nicknames = myDoc.data()?['nicknames'];
      final myNickname =
          nicknames is Map ? nicknames[_contactUid]?.toString() : null;
      final blocked = await BlockService.getBlockedUids(myUid);
      final contactDoc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_contactUid)
          .get();
      final blockedMe = contactDoc.exists &&
          List<String>.from(contactDoc.data()?['blockedUids'] ?? const [])
              .contains(myUid);
      if (isClosed) return;
      emit(state.copyWith(
        myNickname: () => myNickname,
        isBlocked: blocked.contains(_contactUid),
        blockedMe: blockedMe,
        loading: false,
      ));
    } catch (e) {
      debugPrint('Failed to load block state: $e');
      if (!isClosed) emit(state.copyWith(loading: false));
    }
  }

  /// Saves a nickname on my own user doc (`nicknames.<contactUid>`) — only I
  /// ever see it. An empty value removes it.
  Future<void> updateNickname(String value) async {
    final myUid = FirebaseAuth.instance.currentUser!.uid;
    final ref = FirebaseFirestore.instance.collection('users').doc(myUid);
    final trimmed = value.trim();
    if (trimmed.isEmpty) {
      await ref.update({
        'nicknames.$_contactUid': FieldValue.delete(),
      });
    } else {
      await ref.update({
        'nicknames.$_contactUid': trimmed,
      });
    }
    if (isClosed) return;
    emit(state.copyWith(myNickname: () => trimmed.isEmpty ? null : trimmed));
  }

  Future<void> blockUser() async {
    await BlockService.blockUser(_contactUid);
    if (isClosed) return;
    emit(state.copyWith(isBlocked: true));
  }

  Future<void> unblockUser() async {
    await BlockService.unblockUser(_contactUid);
    if (isClosed) return;
    emit(state.copyWith(isBlocked: false));
  }
}