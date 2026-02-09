import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import '../../../models/group_model.dart';
import '../../../models/user_model.dart';
import 'group_state.dart';

class GroupCubit extends Cubit<GroupState> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  GroupCubit() : super(GroupInitial());

  // ===============================
  // 📝 CREATE GROUP
  // ===============================
  Future<void> createGroup({
    required String name,
    required String emoji,
    required List<UserModel> initialMembers,
    String? bio,
  }) async {
    if (name.trim().isEmpty) {
      emit(const GroupError('Please enter a group name.'));
      return;
    }

    emit(GroupCreating());

    try {
      final currentUser = _auth.currentUser!;
      final memberUids = {
        currentUser.uid,
        ...initialMembers.map((e) => e.uid),
      }.toList();

      final newGroup = GroupModel(
        id: '',
        name: name.trim(),
        avatarEmoji: emoji,
        memberUids: memberUids,
        adminUids: [currentUser.uid],
        createdBy: currentUser.uid,
        createdAt: Timestamp.now(),
        bio: bio?.trim().isEmpty ?? true ? null : bio!.trim(),
      );

      final docRef = await _firestore
          .collection('groups')
          .add(newGroup.toFirestore());

      final createdGroup = GroupModel(
        id: docRef.id,
        name: newGroup.name,
        avatarEmoji: newGroup.avatarEmoji,
        memberUids: newGroup.memberUids,
        adminUids: newGroup.adminUids,
        createdBy: newGroup.createdBy,
        createdAt: newGroup.createdAt,
        bio: newGroup.bio,
      );

      emit(GroupCreated(createdGroup));
    } catch (e) {
      emit(GroupError('Failed to create group: $e'));
    }
  }

  // ===============================
  // ✏️ UPDATE GROUP
  // ===============================
  Future<void> updateGroup({
    required GroupModel currentGroup,
    required String name,
    required String emoji,
    String? bio,
  }) async {
    final trimmedName = name.trim();
    final trimmedBio = bio?.trim() ?? '';

    // Check if nothing changed
    if (trimmedName == currentGroup.name &&
        trimmedBio == (currentGroup.bio ?? '') &&
        emoji == currentGroup.avatarEmoji) {
      // No changes
      emit(GroupUpdated(currentGroup));
      return;
    }

    emit(GroupUpdating());

    try {
      await _firestore.collection('groups').doc(currentGroup.id).update({
        'name': trimmedName,
        'avatarEmoji': emoji,
        'bio': trimmedBio.isEmpty ? FieldValue.delete() : trimmedBio,
      });

      final updatedGroup = GroupModel(
        id: currentGroup.id,
        name: trimmedName,
        avatarEmoji: emoji,
        memberUids: currentGroup.memberUids,
        adminUids: currentGroup.adminUids,
        createdBy: currentGroup.createdBy,
        createdAt: currentGroup.createdAt,
        bio: trimmedBio.isEmpty ? null : trimmedBio,
      );

      emit(GroupUpdated(updatedGroup));
    } catch (e) {
      emit(GroupError('Failed to update group: $e'));
    }
  }

  // ===============================
  // 👥 FETCH GROUP MEMBERS
  // ===============================
  Future<void> fetchGroupMembers(GroupModel group) async {
    emit(GroupLoading());

    try {
      final currentUser = _auth.currentUser;
      final isAdmin = currentUser != null &&
          group.adminUids.contains(currentUser.uid);

      if (group.memberUids.isEmpty) {
        emit(GroupMembersLoaded(
          group: group,
          members: [],
          isAdmin: isAdmin,
        ));
        return;
      }

      final snapshots = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: group.memberUids)
          .get();

      final members = snapshots.docs
          .map((doc) => UserModel.fromFirestore(doc))
          .toList();

      emit(GroupMembersLoaded(
        group: group,
        members: members,
        isAdmin: isAdmin,
      ));
    } catch (e) {
      emit(GroupError('Error fetching members: $e'));
    }
  }

  // ===============================
  // 🔄 REFRESH GROUP DATA
  // ===============================
  Future<void> refreshGroup(GroupModel group) async {
    await fetchGroupMembers(group);
  }
}