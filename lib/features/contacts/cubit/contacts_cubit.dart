import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/utils/friendly_error_messages.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'contacts_state.dart';

/// Screen-scoped cubit owning all of ContactsScreen's data logic: matching the
/// phone book against app users, collecting conversation history so deleted
/// accounts stay reachable, live-tracking my blocked uids, and the multi-select
/// group-creation state. Behavior mirrors the logic that previously lived in
/// `_ContactsScreenState`.
class ContactsCubit extends Cubit<ContactsState> {
  ContactsCubit() : super(const ContactsState()) {
    loadContacts();
    _listenToMyBlockedUids();
  }

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;
  StreamSubscription<DocumentSnapshot>? _myBlockSub;

  /// Live-tracks the uids I have blocked so the Blocked chip reacts
  /// immediately when I unblock from anywhere.
  void _listenToMyBlockedUids() {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _myBlockSub = _firestore
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (isClosed) return;
      emit(state.copyWith(
          myBlockedUids:
              Set<String>.from(doc.data()?['blockedUids'] ?? const [])));
    });
  }

  String _normalizePhoneNumber(String phone) {
    String digitsOnly = phone.replaceAll(RegExp(r'\D'), '');
    if (digitsOnly.startsWith('20')) {
      return digitsOnly.substring(2);
    }
    if (digitsOnly.startsWith('0')) {
      return digitsOnly.substring(1);
    }
    return digitsOnly;
  }

  Future<void> loadContacts() async {
    try {
      final currentUser = _auth.currentUser;
      if (currentUser == null) {
        emit(state.copyWith(errorMessage: 'You are not logged in.'));
        return;
      }

      if (await FlutterContacts.requestPermission()) {
        if (isClosed) return;
        final usersSnapshot =
            await _firestore.collection('users').get();
        final allAppUsers = usersSnapshot.docs
            .map((doc) => UserModel.fromFirestore(doc))
            .toList();
        final appUsersMap = <String, UserModel>{
          for (final user in allAppUsers)
            if (user.phoneNumber.isNotEmpty)
              _normalizePhoneNumber(user.phoneNumber): user
        };

        final phoneContacts =
            await FlutterContacts.getContacts(withProperties: true);

        final matchedContacts = <UserModel>[];
        for (final contact in phoneContacts) {
          for (final phone in contact.phones) {
            final normalizedPhone = _normalizePhoneNumber(phone.number);
            if (appUsersMap.containsKey(normalizedPhone)) {
              if (!matchedContacts
                  .any((c) => c.uid == appUsersMap[normalizedPhone]!.uid)) {
                matchedContacts.add(appUsersMap[normalizedPhone]!);
              }
            }
          }
        }
        UserModel? currentUserModel;
        final otherContacts = <UserModel>[];
        for (final contact in allAppUsers) {
          if (contact.uid == currentUser.uid) {
            currentUserModel = contact;
            break;
          }
        }
        for (final matched in matchedContacts) {
          if (matched.uid != currentUser.uid) {
            otherContacts.add(matched);
          }
        }
        otherContacts.sort((a, b) =>
            a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()));
        final finalContacts = <UserModel>[];
        if (currentUserModel != null) {
          finalContacts.add(currentUserModel);
        }

        // Deleted accounts have no active profile to reach outside of an
        // existing conversation, so we only keep them in this list when there
        // is already a chat or a shared group tying them to history.
        final historyUids = await _buildContactHistoryUids();
        final liveContacts = otherContacts
            .where((u) => !u.isDeleted || historyUids.contains(u.uid))
            .toList();
        finalContacts.addAll(liveContacts);
        if (isClosed) return;
        emit(state.copyWith(
          contacts: finalContacts,
          myBlockedUids:
              Set<String>.from(currentUserModel?.blockedUids ?? const []),
        ));
      } else {
        if (isClosed) return;
        emit(state.copyWith(
            errorMessage:
                'Contacts permission is required to find your friends.'));
      }
    } catch (e) {
      if (isClosed) return;
      emit(state.copyWith(
          errorMessage: friendlyErrorMessage(
              e, fallback: 'We could not load your contacts. Please try again.')));
    } finally {
      if (!isClosed) {
        emit(state.copyWith(isLoading: false));
      }
    }
  }

  /// Collects the uids this account already has history with: the other party
  /// of every 1-1 chat I'm in, plus all members of every group I belong to.
  /// Deleted accounts are only surfaced in this list when they appear here, so
  /// an old chat or group keeps their history reachable.
  Future<Set<String>> _buildContactHistoryUids() async {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return const {};
    final Set<String> uids = {};

    try {
      final chats = await _firestore
          .collection('chats')
          .where('uids', arrayContains: currentUid)
          .get();
      for (final doc in chats.docs) {
        final chatUids = (doc.data()['uids'] as List<dynamic>?) ?? const [];
        uids.addAll(
            chatUids.map((u) => u.toString()).where((u) => u != currentUid));
      }
    } catch (_) {}

    try {
      final groups = await _firestore
          .collection('groups')
          .where('memberUids', arrayContains: currentUid)
          .get();
      for (final doc in groups.docs) {
        final memberUids =
            (doc.data()['memberUids'] as List<dynamic>?) ?? const [];
        uids.addAll(memberUids.map((u) => u.toString()));
      }
    } catch (_) {}

    return uids;
  }

  /// True when [user] is blocked by me or has blocked me.
  bool isBlockedContact(UserModel user) {
    final currentUid = _auth.currentUser?.uid;
    if (currentUid == null) return false;
    if (state.myBlockedUids.contains(user.uid)) return true;
    return user.blockedUids.contains(currentUid);
  }

  /// Contacts filtered by the live search text (name, last name, or digits).
  List<UserModel> get filteredContacts {
    if (state.searchQuery.isEmpty) return state.contacts;
    final q = state.searchQuery.toLowerCase();
    return state.contacts.where((u) {
      if (u.firstName.toLowerCase().contains(q)) return true;
      if (u.lastName.toLowerCase().contains(q)) return true;
      if (u.phoneNumber.replaceAll(RegExp(r'\D'), '').contains(q)) return true;
      return false;
    }).toList();
  }

  void updateSearchQuery(String query) {
    if (state.searchQuery == query) return;
    emit(state.copyWith(searchQuery: query));
  }

  /// Toggles a contact in/out of the selection while multi-select is on.
  void toggleSelectContact(UserModel user) {
    final currentUid = _auth.currentUser?.uid;
    if (user.uid == currentUid) return;
    final selected = Set<UserModel>.from(state.selectedContacts);
    if (selected.contains(user)) {
      selected.remove(user);
    } else {
      selected.add(user);
    }
    emit(state.copyWith(
      selectedContacts: selected,
      isSelectionMode: selected.isNotEmpty,
    ));
  }

  /// Long-press: enter selection mode with this contact pre-selected.
  void startSelection(UserModel user) {
    final currentUid = _auth.currentUser?.uid;
    if (user.uid == currentUid) return;
    if (state.isSelectionMode) return;
    emit(state.copyWith(
      isSelectionMode: true,
      selectedContacts: <UserModel>{...state.selectedContacts, user},
    ));
  }

  /// Closes the selection (AppBar close button).
  void clearSelection() {
    emit(state.copyWith(
      isSelectionMode: false,
      selectedContacts: const {},
    ));
  }

  @override
  Future<void> close() {
    _myBlockSub?.cancel();
    return super.close();
  }
}