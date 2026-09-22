import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flash_chat_app/core/utils/friendly_error_messages.dart';
import '../models/group_model.dart';
import '../../profile/models/user_model.dart';
import 'group_state.dart';

class GroupCubit extends Cubit<GroupState> {
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  final FirebaseAuth _auth = FirebaseAuth.instance;

  GroupCubit() : super(GroupInitial());

  // ===============================
  // 🛡️ PERMISSION HELPERS
  // ===============================

  /// Whether the current user can manage the group. Admin rights come from
  /// [GroupModel.adminUids]; legacy groups created before admin support
  /// (empty admin list) treat the creator as the admin.
  bool _isCurrentUserAdmin(GroupModel group) {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return false;
    if (group.adminUids.contains(currentUser.uid)) return true;
    return group.adminUids.isEmpty && group.createdBy == currentUser.uid;
  }

  /// A deleted group is a read-only archive: no membership changes, no role
  /// changes, no group edits, no leaving. Only viewing stays possible.
  /// Returns true (and emits a GroupError) if the mutation must be blocked.
  bool _rejectIfDeleted(GroupModel group) {
    if (group.isDeleted) {
      emit(const GroupError(
          'This group was deleted and is now read-only.'));
      return true;
    }
    return false;
  }

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

      // Create join timestamps for all members
      final now = Timestamp.now();
      final joinTimestamps = {
        currentUser.uid: now,
        for (var member in initialMembers) member.uid: now,
      };

      final newGroup = GroupModel(
        id: '',
        name: name.trim(),
        avatarEmoji: emoji,
        memberUids: memberUids,
        adminUids: [currentUser.uid],
        createdBy: currentUser.uid,
        createdAt: Timestamp.now(),
        bio: bio?.trim().isEmpty ?? true ? null : bio!.trim(),
        memberJoinTimestamps: joinTimestamps,
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
        memberJoinTimestamps: newGroup.memberJoinTimestamps,
      );

      emit(GroupCreated(createdGroup));
    } catch (e) {
      emit(GroupError(friendlyErrorMessage(
          e, fallback: 'We could not create the group. Please try again.')));
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
    if (!_isCurrentUserAdmin(currentGroup)) {
      emit(const GroupError('Only group admins can change group settings.'));
      return;
    }
    if (_rejectIfDeleted(currentGroup)) return;

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
        memberJoinTimestamps: currentGroup.memberJoinTimestamps,
      );

      emit(GroupUpdated(updatedGroup));
    } catch (e) {
      emit(GroupError(friendlyErrorMessage(
          e, fallback: 'We could not update the group. Please try again.')));
    }
  }

  // ===============================
  // 👥 FETCH GROUP MEMBERS
  // ===============================
  Future<void> fetchGroupMembers(GroupModel group) async {
    emit(GroupLoading());

    try {
      await _loadGroupAndEmit(group.id);
    } catch (e) {
      emit(GroupError(friendlyErrorMessage(
          e, fallback: 'We could not load the group members. Please try again.')));
    }
  }

  /// Refreshes a group document and its member profiles from Firestore and
  /// emits [GroupMembersLoaded] with the real member list and the current
  /// user's admin status. Used after any membership change.
  Future<void> _loadGroupAndEmit(String groupId) async {
    final groupDoc = await _firestore.collection('groups').doc(groupId).get();
    if (!groupDoc.exists) {
      emit(GroupMemberRemoved());
      return;
    }
    final group = GroupModel.fromFirestore(groupDoc);
    final currentUser = _auth.currentUser;

    // Current user is no longer a member (e.g. removed themselves).
    if (currentUser != null && !group.memberUids.contains(currentUser.uid)) {
      emit(GroupMemberRemoved());
      return;
    }

    final isAdmin = _isCurrentUserAdmin(group);

    if (group.memberUids.isEmpty) {
      emit(GroupMembersLoaded(
        group: group,
        members: const [],
        isAdmin: isAdmin,
      ));
      return;
    }

    // Firestore allows at most 30 uids per whereIn query, so large groups
    // are fetched in parallel chunks.
    final chunks = <List<String>>[];
    for (int i = 0; i < group.memberUids.length; i += 30) {
      final end = i + 30 < group.memberUids.length
          ? i + 30
          : group.memberUids.length;
      chunks.add(group.memberUids.sublist(i, end));
    }

    final snapshots = await Future.wait(
      chunks.map(
        (chunk) => _firestore
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      ),
    );

    final members = <UserModel>[];
    final seen = <String>{};
    for (final snapshot in snapshots) {
      for (final doc in snapshot.docs) {
        if (seen.add(doc.id)) {
          members.add(UserModel.fromFirestore(doc));
        }
      }
    }

    emit(GroupMembersLoaded(
      group: group,
      members: members,
      isAdmin: isAdmin,
    ));
  }

  // ===============================
  // 🔄 REFRESH GROUP DATA
  // ===============================
  Future<void> refreshGroup(GroupModel group) async {
    await fetchGroupMembers(group);
  }

  // ===============================
  // 💬 GROUP SYSTEM MESSAGES
  // ===============================

  Future<String> _fetchUserName(String uid) async {
    try {
      final doc = await _firestore.collection('users').doc(uid).get();
      if (doc.exists) {
        final data = doc.data() as Map<String, dynamic>;
        final name = '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}'.trim();
        if (name.isNotEmpty) return name;
      }
      final user = _auth.currentUser;
      if (user != null && user.uid == uid && user.displayName != null) {
        return user.displayName!;
      }
    } catch (_) {}
    return 'Member';
  }

  /// Writes a centered system message (e.g. "Mahmoud removed Sara") into the
  /// group's message stream. Rendered by [MessageBubble] as plain text.
  Future<void> _postGroupSystemMessage(String groupId, String text) async {
    final actor = _auth.currentUser;
    if (actor == null) return;
    try {
      await _firestore.collection('groups').doc(groupId).collection('messages').add({
        'text': text,
        'senderId': actor.uid,
        'senderName': await _fetchUserName(actor.uid),
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
      if (kDebugMode) print('Failed to post group system message: $e');
    }
  }

  // ===============================
  // 👥 ADD MEMBERS TO GROUP
  // ===============================
  Future<void> addMembersToGroup({
    required GroupModel group,
    required List<String> newMemberUids,
  }) async {
    if (!_isCurrentUserAdmin(group)) {
      emit(const GroupError('Only group admins can add members.'));
      return;
    }
    if (_rejectIfDeleted(group)) return;
    if (newMemberUids.isEmpty) return;

    emit(GroupLoading());

    try {
      // Create join timestamps for new members
      final now = Timestamp.now();

      // Clear any previous leave timestamp for re-added members so their
      // read window is [new join, now] instead of an inverted empty range.
      // FieldValue.delete() must target individual leaf fields via dotted
      // paths, because Firestore rejects it when nested inside a map value.
      final updates = <String, dynamic>{
        'memberUids': FieldValue.arrayUnion(newMemberUids),
      };
      for (final uid in newMemberUids) {
        updates['memberJoinTimestamps.$uid'] = now;
        updates['memberLeaveTimestamps.$uid'] = FieldValue.delete();
      }

      await _firestore.collection('groups').doc(group.id).update(updates);

      final actorName = await _fetchUserName(_auth.currentUser!.uid);
      for (final uid in newMemberUids) {
        await _postGroupSystemMessage(
          group.id,
          '$actorName added ${await _fetchUserName(uid)}',
        );
      }

      await _loadGroupAndEmit(group.id);
    } catch (e) {
      emit(GroupError(friendlyErrorMessage(
          e, fallback: 'We could not add the members. Please try again.')));
    }
  }

  // ===============================
  // 🚫 REMOVE MEMBER FROM GROUP
  // ===============================
  Future<void> removeMemberFromGroup({
    required GroupModel group,
    required String memberUidToRemove,
  }) async {
    if (!_isCurrentUserAdmin(group)) {
      emit(const GroupError('Only group admins can remove members.'));
      return;
    }
    if (_rejectIfDeleted(group)) return;
    if (group.createdBy == memberUidToRemove) {
      emit(const GroupError('The group creator cannot be removed.'));
      return;
    }

    emit(GroupLoading());

    try {
      // Check if the member to remove is an admin
      final isAdmin = group.adminUids.contains(memberUidToRemove);

      // Keep the member's join time (so they can still read the messages
      // sent while they were a member) and record when they were removed so
      // the chat shows a read-only view hiding anything sent after that.
      final updatedLeaveTimestamps =
          Map<String, Timestamp>.from(group.memberLeaveTimestamps);
      updatedLeaveTimestamps[memberUidToRemove] = Timestamp.now();

      // Update group members
      await _firestore.collection('groups').doc(group.id).update({
        'memberUids': FieldValue.arrayRemove([memberUidToRemove]),
        'memberLeaveTimestamps': updatedLeaveTimestamps,
      });

      // If the member was an admin, also remove from admin list
      if (isAdmin) {
        await _firestore.collection('groups').doc(group.id).update({
          'adminUids': FieldValue.arrayRemove([memberUidToRemove]),
        });
      }

      final actorName = await _fetchUserName(_auth.currentUser!.uid);
      final removedName = await _fetchUserName(memberUidToRemove);
      await _postGroupSystemMessage(
        group.id,
        '$removedName was removed by $actorName',
      );

      await _loadGroupAndEmit(group.id);
    } catch (e) {
      emit(GroupError(friendlyErrorMessage(
          e, fallback: 'We could not remove the member. Please try again.')));
    }
  }

  // ===============================
  // 🚪 LEAVE GROUP (SELF-REMOVE)
  // ===============================
  /// Removes the current user from the group. Same read-only outcome as being
  /// removed by an admin: the leaver keeps reading messages sent while they
  /// were a member but can no longer send/call/react.
  Future<void> leaveGroup(GroupModel group) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    final myUid = currentUser.uid;

    if (_rejectIfDeleted(group)) return;

    emit(GroupLoading());

    try {
      final remainingMemberUids =
          group.memberUids.where((uid) => uid != myUid).toList();

      // Last one out turns out the lights: an empty group is deleted
      // automatically.
      if (remainingMemberUids.isEmpty) {
        await _firestore.collection('groups').doc(group.id).delete();
        emit(GroupMemberRemoved());
        return;
      }

      final updatedLeaveTimestamps =
          Map<String, Timestamp>.from(group.memberLeaveTimestamps);
      updatedLeaveTimestamps[myUid] = Timestamp.now();

      final updates = <String, dynamic>{
        'memberUids': FieldValue.arrayRemove([myUid]),
        'memberLeaveTimestamps': updatedLeaveTimestamps,
      };

      // A non-creator admin who leaves just loses their admin bit.
      if (group.adminUids.contains(myUid) && group.createdBy != myUid) {
        updates['adminUids'] = FieldValue.arrayRemove([myUid]);
      }

      String? newOwnerUid;
      if (group.createdBy == myUid) {
        // The creator is leaving: hand ownership to the oldest remaining
        // admin (by join time), else the oldest remaining member. Every
        // remaining member is promoted to admin so whoever stays behind can
        // manage the group — or delete it — without the creator.
        newOwnerUid = _chooseNewOwner(group, remaining: remainingMemberUids);
        updates['createdBy'] = newOwnerUid;
        updates['adminUids'] = remainingMemberUids;
      }

      await _firestore.collection('groups').doc(group.id).update(updates);

      final actorName = await _fetchUserName(myUid);
      await _postGroupSystemMessage(group.id, '$actorName left the group');
      if (newOwnerUid != null) {
        final ownerName = await _fetchUserName(newOwnerUid);
        await _postGroupSystemMessage(
            group.id, '$ownerName is now the group owner');
      }

      // I am no longer a member: notify the UI so it can switch to the
      // read-only view of the conversation.
      emit(GroupMemberRemoved());
    } catch (e) {
      emit(GroupError(friendlyErrorMessage(
          e, fallback: 'We could not complete leaving the group. Please try again.')));
    }
  }

  /// Chooses who should own the group after the current creator leaves:
  /// the oldest remaining admin (by join time), else the oldest remaining
  /// member by join time. [remaining] is the member list after the leaver
  /// was removed and is never empty here.
  String _chooseNewOwner(GroupModel group, {required List<String> remaining}) {
    String? oldest(Iterable<String> candidates) {
      String? best;
      Timestamp? bestTs;
      for (final uid in candidates) {
        if (!remaining.contains(uid)) continue;
        final ts = group.memberJoinTimestamps[uid] ?? group.createdAt;
        if (best == null || ts.compareTo(bestTs!) < 0) {
          best = uid;
          bestTs = ts;
        }
      }
      return best;
    }

    return oldest(group.adminUids) ?? oldest(remaining)!;
  }

  // ===============================
  // 🗑️ DELETE GROUP (ADMINS)
  // ===============================
  /// Marks the whole group as deleted. The group document and all messages
  /// stay in place so every member keeps read access to the conversation
  /// history, but the chat becomes read-only for everyone: no more sending,
  /// calling, or reacting. Any admin (or the creator) can delete the group so
  /// a group is never orphaned once the creator leaves.
  Future<void> deleteGroup(GroupModel group) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;
    if (!_isCurrentUserAdmin(group)) {
      emit(const GroupError('Only group admins can delete the group.'));
      return;
    }
    // Already deleted: nothing to do (avoids a duplicate system message).
    if (group.isDeleted) return;

    emit(GroupLoading());

    try {
      await _firestore.collection('groups').doc(group.id).update({
        'isDeleted': true,
      });

      final actorName = await _fetchUserName(currentUser.uid);
      await _postGroupSystemMessage(group.id, '$actorName deleted this group');

      emit(GroupDeleted());
    } catch (e) {
      emit(GroupError(friendlyErrorMessage(
          e, fallback: 'We could not delete the group. Please try again.')));
    }
  }

  // ===============================
  // 👑 PROMOTE MEMBER TO ADMIN
  // ===============================
  Future<void> promoteMemberToAdmin({
    required GroupModel group,
    required String memberUidToPromote,
  }) async {
    if (!_isCurrentUserAdmin(group)) {
      emit(const GroupError('Only group admins can promote members.'));
      return;
    }
    if (_rejectIfDeleted(group)) return;
    if (group.adminUids.contains(memberUidToPromote)) return;

    emit(GroupLoading());

    try {
      await _firestore.collection('groups').doc(group.id).update({
        'adminUids': FieldValue.arrayUnion([memberUidToPromote]),
      });

      final promotedName = await _fetchUserName(memberUidToPromote);
      await _postGroupSystemMessage(group.id, '$promotedName is now an admin');

      await _loadGroupAndEmit(group.id);
    } catch (e) {
      emit(GroupError(friendlyErrorMessage(
          e, fallback: 'We could not promote the member. Please try again.')));
    }
  }

  // ===============================
  // 👑 DEMOTE ADMIN TO MEMBER
  // ===============================
  Future<void> demoteAdminToMember({
    required GroupModel group,
    required String adminUidToDemote,
  }) async {
    if (!_isCurrentUserAdmin(group)) {
      emit(const GroupError('Only group admins can demote admins.'));
      return;
    }
    if (_rejectIfDeleted(group)) return;
    if (group.createdBy == adminUidToDemote) {
      emit(const GroupError('The group creator cannot be demoted.'));
      return;
    }
    final currentUser = _auth.currentUser;
    if (currentUser != null && currentUser.uid == adminUidToDemote) {
      emit(const GroupError('You cannot demote yourself.'));
      return;
    }

    emit(GroupLoading());

    try {
      await _firestore.collection('groups').doc(group.id).update({
        'adminUids': FieldValue.arrayRemove([adminUidToDemote]),
      });

      final demotedName = await _fetchUserName(adminUidToDemote);
      await _postGroupSystemMessage(
        group.id,
        '$demotedName is no longer an admin',
      );

      await _loadGroupAndEmit(group.id);
    } catch (e) {
      emit(GroupError(friendlyErrorMessage(
          e, fallback: 'We could not demote the admin. Please try again.')));
    }
  }

  // ===============================
  // 🔄 MIGRATE GROUP FOR JOIN TIMESTAMPS
  // ===============================
  /// This method should be called once to migrate existing groups
  /// to include join timestamps for existing members
  Future<void> migrateGroupForJoinTimestamps(String groupId) async {
    try {
      final groupDoc = await _firestore.collection('groups').doc(groupId).get();
      if (!groupDoc.exists) return;

      final data = groupDoc.data() as Map<String, dynamic>;
      final memberUids = List<String>.from(data['memberUids'] ?? []);

      // Check if already migrated
      if (data['memberJoinTimestamps'] != null) {
        return;
      }

      // Create join timestamps for all existing members (set to group creation time)
      final groupCreatedAt = data['createdAt'] ?? Timestamp.now();
      final joinTimestamps = {
        for (var uid in memberUids) uid: groupCreatedAt
      };

      await _firestore.collection('groups').doc(groupId).update({
        'memberJoinTimestamps': joinTimestamps,
      });
    } catch (e) {
      if (kDebugMode) {
        print('Error migrating group $groupId: $e');
      }
    }
  }
}