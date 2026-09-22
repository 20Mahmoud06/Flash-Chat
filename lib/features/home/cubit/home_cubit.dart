import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/utils/call_utils.dart';
import 'package:flash_chat_app/core/utils/friendly_error_messages.dart';
import 'package:flash_chat_app/features/groups/models/group_model.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'home_state.dart';

/// Screen-scoped cubit owning all of HomeScreen's data logic: the live my-user
/// document, the lazily-subscribed chats / groups snapshots, legacy-chat
/// migration, new-chat detection timers, the contact cache, and pin/unpin
/// writes. The screen only renders [HomeState]; behavior is byte-for-byte the
/// logic that previously lived in `_HomeScreenState`.
class HomeCubit extends Cubit<HomeState> {
  HomeCubit() : super(const HomeState()) {
    _uid = _auth.currentUser?.uid;
    if (_uid != null) {
      _listenToCurrentUser();
      _subscribeChats();
    }
  }

  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  String? _uid;
  Map<String, dynamic>? _userData;
  StreamSubscription<DocumentSnapshot>? _userSub;
  StreamSubscription<QuerySnapshot>? _chatsSub;
  StreamSubscription<QuerySnapshot>? _groupsSub;

  int _currentIndex = 0; // 0: Chats, 1: Groups

  bool _chatsLoading = false;
  String? _chatsError;
  bool _groupsLoading = false;
  String? _groupsError;

  /// Ensures the Firestore cache for the groups query is seeded from the
  /// server exactly once per screen lifecycle, so a newly-added member
  /// sees the group appear immediately rather than after a stale-cache delay.
  bool _isGroupsWarmed = false;

  Future<void> _warmGroupsQueryFromServer(String uid) async {
    if (_isGroupsWarmed) return;
    _isGroupsWarmed = true;
    try {
      await _firestore
          .collection('groups')
          .where('memberUids', arrayContains: uid)
          .get(const GetOptions(source: Source.server));
    } catch (_) {}
  }

  /// Same cache-warm-up for 1-1 chats, so a new or re-added contact
  /// appears in the chats list without waiting for the cache to reconcile.
  bool _isChatsWarmed = false;

  Future<void> _warmChatsQueryFromServer(String uid) async {
    if (_isChatsWarmed) return;
    _isChatsWarmed = true;
    try {
      await _firestore
          .collection('chats')
          .where('uids', arrayContains: uid)
          .get(const GetOptions(source: Source.server));
    } catch (_) {}
  }

  /// Live-tracks my user document (blockedUids, name, avatar...) so the
  /// blocked banners react immediately when I unblock from anywhere.
  void _listenToCurrentUser() {
    _userSub?.cancel();
    final uid = _uid;
    if (uid == null) return;
    _userSub = _firestore.collection('users').doc(uid).snapshots().listen(
          (doc) {
            _userData = doc.data();
            _emitHome();
          },
          onError: (Object e) => debugPrint('Home user listener error: $e'),
        );
  }

  Set<String> get _pinnedChatIds => Set<String>.from(
      (_userData?['pinnedChats'] as Map<String, dynamic>?)?.keys ??
          const <String>[]);

  void _emitHome() {
    if (isClosed) return;
    final uid = _uid;
    final pinned = _pinnedChatIds;

    final chatTiles = <HomeChatTileData>[];
    if (uid != null) {
      final sorted = List<QueryDocumentSnapshot>.from(_chatRows)
        ..sort((a, b) => _sortChats(a, b, uid, pinned));
      for (final doc in sorted) {
        final data = doc.data() as Map<String, dynamic>;
        final List<dynamic> uids = data['uids'] ?? [];
        if (uids.isEmpty) continue;

        final bool isSelfChat =
            uids.toSet().length == 1 && uids.isNotEmpty && uids.first == uid;
        final String? contactUid = isSelfChat
            ? uid
            : uids.firstWhere((u) => u != uid, orElse: () => null);
        if (contactUid == null) continue;

        final contact = _cachedChatUsers[contactUid];
        if (contact == null) continue;

        // My nickname for this contact replaces their real name.
        final nicknames =
            (_userData?['nicknames'] as Map<String, dynamic>?) ?? const {};
        final nickname = nicknames[contactUid] as String?;
        final displayName = (nickname != null && nickname.isNotEmpty)
            ? nickname
            : '${contact.firstName} ${contact.lastName}';

        final myBlockedUids = Set<String>.from(
            (_userData?['blockedUids'] as List<dynamic>?) ?? const []);
        final isBlockedChat = myBlockedUids.contains(contactUid) ||
            contact.blockedUids.contains(uid);
        final isDeletedAccount = contact.isDeleted;

        // Delete actions target the canonical chat so "delete for me"
        // keeps working once the legacy chat is migrated away.
        final canonicalId = buildOneOnOneChatId(uid, contactUid);
        final actionChatId = _canonicalContacts.contains(contactUid)
            ? canonicalId
            : doc.id;

        final unreadCounts =
            (data['unreadCounts'] as Map<String, dynamic>?) ?? const {};
        final unreadCount = (unreadCounts[uid] as num?)?.toInt() ?? 0;

        final pinId = canonicalId;

        chatTiles.add(HomeChatTileData(
          chatDocId: doc.id,
          contactUid: contactUid,
          displayName: displayName,
          avatar: isDeletedAccount ? '❌' : contact.avatarEmoji,
          isSelfChat: isSelfChat,
          isBlocked: isBlockedChat && !isDeletedAccount,
          isDeleted: isDeletedAccount,
          isNewChat: _newChatContactUids.contains(contactUid),
          isPinned: pinned.contains(pinId),
          pinId: pinId,
          actionChatId: actionChatId,
          unreadCount: unreadCount,
          contact: contact,
        ));
      }
    }

    final groupTiles = <HomeGroupTileData>[];
    final sortedGroups = List<QueryDocumentSnapshot>.from(_groupRows)
      ..sort((a, b) => _sortGroups(a, b, pinned));
    for (final doc in sortedGroups) {
      final group = GroupModel.fromFirestore(doc);
      final data = doc.data() as Map<String, dynamic>;
      final unreadCounts =
          (data['unreadCounts'] as Map<String, dynamic>?) ?? const {};
      final unreadCount = (unreadCounts[_uid] as num?)?.toInt() ?? 0;
      final lastSeen =
          (data['lastSeen'] as Map<String, dynamic>?) ?? const {};
      final lastSeenAt = lastSeen[_uid];
      groupTiles.add(HomeGroupTileData(
        group: group,
        unreadCount: unreadCount,
        lastSeenAt: lastSeenAt is Timestamp ? lastSeenAt : null,
        isPinned: pinned.contains(group.id),
      ));
    }

    emit(HomeState(
      firstName: _userData?['firstName'] as String?,
      avatarEmoji: _userData?['avatarEmoji'] as String?,
      pinnedChatIds: pinned,
      chats: chatTiles,
      groups: groupTiles,
      chatsLoading: _chatsLoading,
      chatsError: _chatsError,
      chatUsersLoading: _chatsUsersPending && _cachedChatUsers.isEmpty,
      chatUsersError: _chatUsersError,
      groupsLoading: _groupsLoading,
      groupsError: _groupsError,
    ));
  }

  /// Whether a 1-1 chat doc is pinned, keyed by its canonical chat id so the
  /// pin survives the legacy-chat migration.
  bool _chatDocPinned(dynamic data, String myUid, Set<String> pinnedChatIds) {
    final uids =
        (data as Map<String, dynamic>)['uids'] as List<dynamic>? ?? const [];
    if (uids.isEmpty) return false;
    final other = uids.firstWhere((u) => u != myUid, orElse: () => uids.first);
    return pinnedChatIds.contains(buildOneOnOneChatId(myUid, other.toString()));
  }

  int _sortChats(QueryDocumentSnapshot a, QueryDocumentSnapshot b, String uid,
      Set<String> pinnedChatIds) {
    final aPinned = _chatDocPinned(a.data(), uid, pinnedChatIds);
    final bPinned = _chatDocPinned(b.data(), uid, pinnedChatIds);
    if (aPinned != bPinned) return aPinned ? -1 : 1;
    Timestamp? aTimestamp =
        (a.data() as Map<String, dynamic>)['lastMessageTimestamp'];
    Timestamp? bTimestamp =
        (b.data() as Map<String, dynamic>)['lastMessageTimestamp'];
    if (aTimestamp == null && bTimestamp == null) return 0;
    if (aTimestamp == null) return 1;
    if (bTimestamp == null) return -1;
    return bTimestamp.compareTo(aTimestamp);
  }

  int _sortGroups(
      QueryDocumentSnapshot a, QueryDocumentSnapshot b, Set<String> pinnedIds) {
    final aPinned = pinnedIds.contains(a.id);
    final bPinned = pinnedIds.contains(b.id);
    if (aPinned != bPinned) return aPinned ? -1 : 1;
    Timestamp? aTimestamp =
        (a.data() as Map<String, dynamic>)['lastMessageTimestamp'];
    Timestamp? bTimestamp =
        (b.data() as Map<String, dynamic>)['lastMessageTimestamp'];
    if (aTimestamp == null && bTimestamp == null) return 0;
    if (aTimestamp == null) return 1;
    if (bTimestamp == null) return -1;
    return bTimestamp.compareTo(aTimestamp);
  }

  // --- MODIFIED: This function now detects self-chats ---
  // It adds the current user's ID to the list of users to fetch from Firestore
  // if a self-chat is found. This ensures your own user data is available for display.
  Future<Map<String, UserModel>> _loadChatUsers(
      List<QueryDocumentSnapshot> chatDocs, String currentUid) async {
    Set<String> uids = {};
    for (final doc in chatDocs) {
      final List<dynamic> chatUids = doc['uids'] ?? [];

      // A self-chat has a 'uids' array where all elements are the current user's ID.
      // e.g., ['my_uid', 'my_uid']. The Set of this will have a length of 1.
      final bool isSelfChat = chatUids.toSet().length == 1 &&
          chatUids.isNotEmpty &&
          chatUids.first == currentUid;

      if (isSelfChat) {
        uids.add(currentUid); // Add your own ID to fetch your user data
      } else {
        String other = chatUids.firstWhere(
          (u) => u != currentUid,
          orElse: () => '',
        );
        if (other.isNotEmpty) {
          uids.add(other);
        }
      }
    }

    // Fetch each contact separately so one uncached user (offline) only
    // hides that single tile instead of failing the whole chat list.
    final futures = uids.map((uid) async {
      try {
        return await _firestore.collection('users').doc(uid).get();
      } catch (_) {
        return null;
      }
    }).toList();
    final userDocs = await Future.wait(futures);
    final map = <String, UserModel>{};
    for (final doc in userDocs) {
      if (doc != null && doc.exists) {
        map[doc.id] = UserModel.fromFirestore(doc);
      }
    }
    return map;
  }

  // Cached user data so the chat list never re-shows a full-screen spinner
  // when a new message arrives (only refetched when the chat set changes).
  Future<Map<String, UserModel>>? _chatsUsersFuture;
  String? _chatsUsersKey;
  Map<String, UserModel> _cachedChatUsers = {};
  bool _chatsUsersPending = false;
  String? _chatUsersError;

  final Set<String> _migratingChatIds = {};

  /// Conversations already present on the previous snapshot: used to detect
  /// brand-new chats (a first message from a new contact) so the tile can
  /// animate its arrival instead of just fading in like every reload.
  final Set<String> _seenChatContacts = {};

  /// Contacts whose chat is currently "new" and should show the entrance
  /// highlight. Cleared a few seconds after they appear.
  final Set<String> _newChatContactUids = {};

  /// The first snapshot only seeds [_seenChatContacts]; a fresh install or
  /// app reopen must never animate every existing chat as "new".
  bool _chatsSnapshotSeeded = false;

  final List<Timer> _newChatTimers = [];

  /// Chat docs derived from the last chats snapshot, kept so the my-user
  /// document updates can re-render the list without re-reading Firestore.
  List<QueryDocumentSnapshot> _chatRows = [];

  /// Contacts (by uid) that already have a canonical chat doc, so delete
  /// actions target the canonical id.
  Set<String> _canonicalContacts = {};

  /// Group docs derived from the last groups snapshot.
  List<QueryDocumentSnapshot> _groupRows = [];

  void _setChatsEmpty() {
    _chatRows = [];
    _canonicalContacts = {};
    _emitHome();
  }

  Future<void> _migrateLegacyChat(String legacyId, String canonicalId) async {
    if (legacyId == canonicalId) return;
    if (!_migratingChatIds.add(legacyId)) return;
    try {
      final legacyRef = _firestore.collection('chats').doc(legacyId);
      final legacyDoc = await legacyRef.get();
      if (!legacyDoc.exists) return;
      final legacyData = legacyDoc.data() ?? {};

      final messagesSnapshot = await legacyRef.collection('messages').get();
      final canonicalRef = _firestore.collection('chats').doc(canonicalId);
      final canonicalDoc = await canonicalRef.get();
      final canonicalData =
          canonicalDoc.exists ? canonicalDoc.data() ?? {} : {};

      await canonicalRef.set({
        'uids': legacyData['uids'] ?? [],
      }, SetOptions(merge: true));

      // Keep chats hidden for users who deleted them, instead of resetting.
      final legacyHiddenFor =
          List<String>.from(legacyData['hiddenFor'] ?? const []);
      if (legacyHiddenFor.isNotEmpty) {
        await canonicalRef.update({
          'hiddenFor': FieldValue.arrayUnion(legacyHiddenFor),
        });
      }

      // Copy the last-message preview only when the canonical doc has no
      // newer one, so the chat list keeps showing the right message.
      final canonicalTs = (canonicalData['lastMessageTimestamp'] as Timestamp?)
              ?.millisecondsSinceEpoch ??
          0;
      final legacyTs = (legacyData['lastMessageTimestamp'] as Timestamp?)
              ?.millisecondsSinceEpoch ??
          0;
      if (legacyTs >= canonicalTs) {
        await canonicalRef.set({
          if (legacyData.containsKey('lastMessage'))
            'lastMessage': legacyData['lastMessage'],
          if (legacyData.containsKey('lastMessageTimestamp'))
            'lastMessageTimestamp': legacyData['lastMessageTimestamp'],
          if (legacyData.containsKey('lastSenderId'))
            'lastSenderId': legacyData['lastSenderId'],
        }, SetOptions(merge: true));
      }

      final batch = _firestore.batch();
      for (final msgDoc in messagesSnapshot.docs) {
        final newMsgRef = canonicalRef.collection('messages').doc(msgDoc.id);
        batch.set(newMsgRef, msgDoc.data());
        batch.delete(msgDoc.reference);
      }
      batch.delete(legacyRef);
      await batch.commit();
      debugPrint('HomeScreen: Migrated legacy chat $legacyId to $canonicalId');
    } catch (e) {
      debugPrint('HomeScreen: Error migrating legacy chat $legacyId: $e');
    }
  }

  int _chatTimestampMs(QueryDocumentSnapshot doc) {
    final ts = (doc.data() as Map<String, dynamic>)['lastMessageTimestamp'];
    return (ts as Timestamp?)?.millisecondsSinceEpoch ?? 0;
  }

  /// Picks the doc with the newest last-message timestamp so the preview is
  /// correct instantly, even before the legacy migration finishes.
  QueryDocumentSnapshot _pickMostRecentChatDoc(
      List<QueryDocumentSnapshot> docs) {
    QueryDocumentSnapshot best = docs.first;
    var bestTs = _chatTimestampMs(best);
    for (final doc in docs.skip(1)) {
      final ts = _chatTimestampMs(doc);
      if (ts > bestTs) {
        best = doc;
        bestTs = ts;
      }
    }
    return best;
  }

  /// Lazily subscribes to the chats query. Called from the constructor
  /// (default tab) and when switching back to the Chats tab, mirroring the
  /// old StreamBuilder's mount/unmount lifecycle.
  void _subscribeChats() {
    final uid = _uid;
    if (uid == null) return;
    _warmChatsQueryFromServer(uid);
    _chatsSub?.cancel();
    _chatsLoading = true;
    _chatsError = null;
    _emitHome();
    _chatsSub = _firestore
        .collection('chats')
        .where('uids', arrayContains: uid)
        .snapshots()
        .listen(
      _onChatsSnapshot,
      onError: (Object e) {
        _chatsLoading = false;
        _chatsError =
            friendlyErrorMessage(e, fallback: 'Could not load your chats.');
        _emitHome();
      },
    );
  }

  void _onChatsSnapshot(QuerySnapshot snapshot) {
    final uid = _uid;
    if (uid == null) return;
    _chatsLoading = false;
    _chatsError = null;

    if (snapshot.docs.isEmpty) {
      _setChatsEmpty();
      return;
    }

    final availableDocs = snapshot.docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      final hiddenFor = data?['hiddenFor'] as List<dynamic>? ?? [];
      return !hiddenFor.contains(uid);
    }).toList();

    if (availableDocs.isEmpty) {
      _setChatsEmpty();
      return;
    }

    // Group docs by contactUid to prevent duplicate chat items
    final groupedByContact = <String, List<QueryDocumentSnapshot>>{};
    for (final doc in availableDocs) {
      final data = doc.data() as Map<String, dynamic>;
      final List<dynamic> uids = data['uids'] ?? [];
      if (uids.isEmpty) continue;

      final bool isSelfChat =
          uids.toSet().length == 1 && uids.first == uid;
      final String? contactUid = isSelfChat
          ? uid
          : uids.firstWhere((u) => u != uid, orElse: () => null);

      if (contactUid == null) continue;
      groupedByContact.putIfAbsent(contactUid, () => []).add(doc);
    }

    final chatDocs = <QueryDocumentSnapshot>[];
    final contactsWithCanonicalChat = <String>{};

    groupedByContact.forEach((contactUid, docs) {
      final canonicalId = buildOneOnOneChatId(uid, contactUid);

      QueryDocumentSnapshot? canonicalDoc;
      for (final d in docs) {
        if (d.id == canonicalId) {
          canonicalDoc = d;
          break;
        }
      }

      if (canonicalDoc != null) {
        contactsWithCanonicalChat.add(contactUid);
      }

      for (final d in docs) {
        if (d.id != canonicalId) {
          final legacyId = d.id;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _migrateLegacyChat(legacyId, canonicalId);
          });
        }
      }

      // Show the doc with the newest preview while migration runs in the
      // background; once migrated, the canonical doc takes its place.
      chatDocs.add(_pickMostRecentChatDoc(docs));
    });

    // NEW-CHAT DETECTION: diff the conversations on this snapshot against
    // what has been on screen before. The first snapshot (app open or a
    // cold reload) only seeds the baseline. Any contact that appears later
    // — a first message from someone new — marks the tile as "new" so it
    // animates with a highlight and a NEW pill. Chats removed from the
    // list are forgotten, so a chat that comes back animates again.
    final currentContacts = groupedByContact.keys.toSet();
    if (!_chatsSnapshotSeeded) {
      _chatsSnapshotSeeded = true;
      _seenChatContacts.addAll(currentContacts);
    } else {
      final fresh = currentContacts.difference(_seenChatContacts);
      for (final contactUid in fresh) {
        _seenChatContacts.add(contactUid);
        // Self-chats are never "new": messaging yourself shouldn't put a
        // NEW pill / entrance glow on your own chat when you come back.
        if (contactUid == uid) continue;
        _newChatContactUids.add(contactUid);
        final timer = Timer(const Duration(seconds: 6), () {
          if (isClosed) return;
          _newChatContactUids.remove(contactUid);
          _emitHome();
        });
        _newChatTimers.add(timer);
      }
      final gone = _seenChatContacts.difference(currentContacts);
      if (gone.isNotEmpty) _seenChatContacts.removeAll(gone);
    }

    if (chatDocs.isEmpty) {
      _setChatsEmpty();
      return;
    }

    _chatRows = chatDocs;
    _canonicalContacts = contactsWithCanonicalChat;

    // Cache user loading so the list never re-spins on every new message.
    // Each tile streams its own last message, so a fresh message only
    // updates that chat's preview — no full-page reload.
    final usersKey = chatDocs
        .map((d) => (d.data() as Map<String, dynamic>)['uids'].toString())
        .join('|');
    if (_chatsUsersKey != usersKey || _chatsUsersFuture == null) {
      _chatsUsersKey = usersKey;
      _chatUsersError = null;
      _chatsUsersPending = true;
      _emitHome();
      _chatsUsersFuture =
          _loadChatUsers(chatDocs, uid).then((Map<String, UserModel> map) {
        _cachedChatUsers = map;
        _chatsUsersPending = false;
        _chatUsersError = null;
        _emitHome();
        return map;
      });
    }
    _emitHome();
  }

  /// Lazily subscribes to the groups query, mirroring the old StreamBuilder
  /// lifecycle (Groups tab only).
  void _subscribeGroups() {
    final uid = _uid;
    if (uid == null) return;
    _warmGroupsQueryFromServer(uid);
    _groupsSub?.cancel();
    _groupsLoading = true;
    _groupsError = null;
    _emitHome();
    _groupsSub = _firestore
        .collection('groups')
        .where('memberUids', arrayContains: uid)
        .snapshots()
        .listen(
      _onGroupsSnapshot,
      onError: (Object e) {
        _groupsLoading = false;
        _groupsError =
            friendlyErrorMessage(e, fallback: 'Could not load your groups.');
        _emitHome();
      },
    );
  }

  void _onGroupsSnapshot(QuerySnapshot snapshot) {
    final uid = _uid;
    if (uid == null) return;
    _groupsLoading = false;
    _groupsError = null;

    if (snapshot.docs.isEmpty) {
      _groupRows = [];
      _emitHome();
      return;
    }

    final groupDocs = snapshot.docs.toList()
      ..removeWhere((doc) {
        final data = doc.data() as Map<String, dynamic>?;
        final hiddenFor = data?['hiddenFor'] as List<dynamic>? ?? [];
        return hiddenFor.contains(uid);
      });

    _groupRows = groupDocs;
    _emitHome();
  }

  /// Switches the active tab: cancel the other tab's subscription so only the
  /// visible tab listens, exactly like the old StreamBuilder mount/unmount.
  void setTab(int index) {
    if (index == _currentIndex) return;
    _currentIndex = index;
    if (index == 1) {
      _chatsSub?.cancel();
      _chatsSub = null;
      _subscribeGroups();
    } else {
      _groupsSub?.cancel();
      _groupsSub = null;
      _subscribeChats();
    }
  }

  /// Re-arms the my-user listener. Called after returning from screens that
  /// may have changed the user doc (e.g. unblocking from the chat screen).
  void refreshMyUser() => _listenToCurrentUser();

  /// Pins a chat by its canonical id. The max-3 guard lives in the UI so the
  /// "You can pin up to 3 chats" snackbar renders there, as before.
  void pinChat(String chatId) {
    final uid = _uid;
    if (uid == null) return;
    _firestore.collection('users').doc(uid).update({
      'pinnedChats.$chatId': FieldValue.serverTimestamp()
    }).catchError((Object e) => debugPrint('Failed to pin chat: $e'));
  }

  void unpinChat(String chatId) {
    final uid = _uid;
    if (uid == null) return;
    _firestore
        .collection('users')
        .doc(uid)
        .update({'pinnedChats.$chatId': FieldValue.delete()}).catchError(
            (Object e) => debugPrint('Failed to unpin chat: $e'));
  }

  @override
  Future<void> close() {
    _userSub?.cancel();
    _chatsSub?.cancel();
    _groupsSub?.cancel();
    for (final timer in _newChatTimers) {
      timer.cancel();
    }
    _newChatTimers.clear();
    return super.close();
  }
}