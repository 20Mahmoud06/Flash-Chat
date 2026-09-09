import 'dart:async';
import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:lottie/lottie.dart';
import '../../../core/utils/call_utils.dart';
import '../../../core/utils/message_preview.dart';
import '../../../core/utils/page_transition.dart';
import '../../../services/connectivity/connectivity_service.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../profile/screens/profile_screen.dart';
import '../../profile/screens/sender_profile_screen.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';
import 'contacts_screen.dart';
import '../widgets/day_separator.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final _auth = FirebaseAuth.instance;
  final _firestore = FirebaseFirestore.instance;

  Map<String, dynamic>? _userData;
  DateTime? _lastBackPressed;
  StreamSubscription<DocumentSnapshot>? _userSub;

  int _currentIndex = 0; // 0: Chats, 1: Groups

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

  @override
  void initState() {
    super.initState();
    _listenToCurrentUser();
  }

  /// Live-tracks my user document (blockedUids, name, avatar...) so the
  /// blocked banners react immediately when I unblock from anywhere.
  void _listenToCurrentUser() {
    _userSub?.cancel();
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _userSub = _firestore.collection('users').doc(uid).snapshots().listen(
      (doc) {
        if (!mounted) return;
        setState(() => _userData = doc.data());
      },
      onError: (Object e) => debugPrint('Home user listener error: $e'),
    );
  }

  /// Whether a 1-1 chat doc is pinned, keyed by its canonical chat id so the
  /// pin survives the legacy-chat migration.
  bool _chatDocPinned(dynamic data, String myUid, Set<String> pinnedChatIds) {
    final uids = (data as Map<String, dynamic>)['uids'] as List<dynamic>? ??
        const [];
    if (uids.isEmpty) return false;
    final other =
        uids.firstWhere((u) => u != myUid, orElse: () => uids.first);
    return pinnedChatIds.contains(buildOneOnOneChatId(myUid, other.toString()));
  }

  Set<String> get _pinnedChatIds => Set<String>.from(
      (_userData?['pinnedChats'] as Map<String, dynamic>?)?.keys ??
          const <String>[]);

  void _pinChat(String chatId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    if (_pinnedChatIds.length >= 3) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: CustomText(text: 'You can pin up to 3 chats'),
          backgroundColor: Colors.lightBlueAccent,
          behavior: SnackBarBehavior.floating,
        ),
      );
      return;
    }
    _firestore
        .collection('users')
        .doc(uid)
        .update({'pinnedChats.$chatId': FieldValue.serverTimestamp()})
        .catchError((Object e) =>
            debugPrint('Failed to pin chat: $e'));
  }

  void _unpinChat(String chatId) {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _firestore
        .collection('users')
        .doc(uid)
        .update({'pinnedChats.$chatId': FieldValue.delete()})
        .catchError((Object e) =>
            debugPrint('Failed to unpin chat: $e'));
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  Future<bool> _onWillPop() async {
    DateTime now = DateTime.now();
    if (_lastBackPressed == null ||
        now.difference(_lastBackPressed!) > const Duration(seconds: 2)) {
      _lastBackPressed = now;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: CustomText(text: 'Press back again to exit'),
          duration: Duration(seconds: 2),
        ),
      );
      return false;
    }
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final currentUser = _auth.currentUser;
    final colors = FcAppColors.of(context);

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) async {
        if (didPop) return;
        final shouldPop = await _onWillPop();
        if (shouldPop) {
          SystemNavigator.pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.lightBlueAccent,
          elevation: 0,
          title: Text(
            _currentIndex == 0
                ? 'Hello, ${_userData?['firstName'] ?? ''} 👋'
                : 'Groups 👥',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 18.sp,
            ),
          ),
          actions: [
            Padding(
              padding: EdgeInsets.only(right: 8.w),
              child: Center(
                child: FadeInDown(
                  child: GestureDetector(
                    onTap: () {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder: (context, animation,
                                  secondaryAnimation) =>
                              const ProfileScreen(),
                          transitionsBuilder: PageTransition.slideFromRight,
                        ),
                      );
                    },
                    child: CircleAvatar(
                      radius: 20.r,
                      backgroundColor: colors.surface,
                      child: CustomText(
                          text: _userData?['avatarEmoji'] ?? "👤",
                          fontSize: 18.sp),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
        body: currentUser == null
            ? const Center(
                child: CircularProgressIndicator(color: Colors.lightBlueAccent))
            : _currentIndex == 0
                ? _buildChatsOrEmpty()
                : _buildGroupsOrEmpty(),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const ContactsScreen(),
                transitionsBuilder: PageTransition.slideFromRight,
              ),
            );
          },
          backgroundColor: Colors.lightBlueAccent,
          child: Icon(
            _currentIndex == 0 ? Icons.message_outlined : Icons.group_add,
            color: Colors.white,
          ),
        ),
        bottomNavigationBar: BottomNavigationBar(
          currentIndex: _currentIndex,
          selectedItemColor: Colors.lightBlueAccent,
          unselectedItemColor: colors.textWeak,
          backgroundColor: colors.surface,
          onTap: (index) {
            setState(() {
              _currentIndex = index;
            });
          },
          items: const [
            BottomNavigationBarItem(
                icon: Icon(Icons.chat_bubble_outline), label: "Chats"),
            BottomNavigationBarItem(
                icon: Icon(Icons.groups_outlined), label: "Groups"),
          ],
        ),
      ),
    );
  }

  // --- MODIFIED: This function now detects self-chats ---
  // It adds the current user's ID to the list of users to fetch from Firestore
  // if a self-chat is found. This ensures your own user data is available for display.
  Future<Map<String, UserModel>> _loadChatUsers(
      List<QueryDocumentSnapshot> chatDocs, String currentUid) async {
    Set<String> uids = {};
    for (var doc in chatDocs) {
      List<dynamic> chatUids = doc['uids'] ?? [];

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
    var futures = uids
        .map((uid) async {
          try {
            return await _firestore.collection('users').doc(uid).get();
          } catch (_) {
            return null;
          }
        })
        .toList();
    var userDocs = await Future.wait(futures);
    Map<String, UserModel> map = {};
    for (var doc in userDocs) {
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

  final Set<String> _migratingChatIds = {};

  /// Conversations already present on the previous snapshot: used to detect
  /// brand-new chats (a first message from a new contact) so the tile can
  /// animate its arrival instead of just fading in like every reload.
  final Set<String> _seenChatContacts = {};

  /// Contacts whose chat is currently "new" and should show the entrance
  /// highlight. Cleared a few seconds after they appear.
  final Set<String> _newChatContacts = {};

  /// The first snapshot only seeds [_seenChatContacts]; a fresh install or
  /// app reopen must never animate every existing chat as "new".
  bool _chatsSnapshotSeeded = false;

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

  Widget _buildChatsOrEmpty() {
    final currentUser = _auth.currentUser!;
    _warmChatsQueryFromServer(currentUser.uid);
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('chats')
          .where('uids', arrayContains: currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(color: Colors.lightBlueAccent));
        }
        if (snapshot.hasError) {
          return _buildOfflineOrError(context, snapshot.error.toString(),
              thing: 'chats');
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(context);
        }

        var availableDocs = snapshot.data!.docs.where((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          final hiddenFor = data?['hiddenFor'] as List<dynamic>? ?? [];
          return !hiddenFor.contains(currentUser.uid);
        }).toList();

        if (availableDocs.isEmpty) {
          return _buildEmptyState(context);
        }

        // Group docs by contactUid to prevent duplicate chat items
        final Map<String, List<QueryDocumentSnapshot>> groupedByContact = {};

        for (var doc in availableDocs) {
          final data = doc.data() as Map<String, dynamic>;
          final List<dynamic> uids = data['uids'] ?? [];
          if (uids.isEmpty) continue;

          final bool isSelfChat =
              uids.toSet().length == 1 && uids.first == currentUser.uid;
          final String? contactUid = isSelfChat
              ? currentUser.uid
              : uids.firstWhere((uid) => uid != currentUser.uid,
                  orElse: () => null);

          if (contactUid == null) continue;
          groupedByContact.putIfAbsent(contactUid, () => []).add(doc);
        }

        final List<QueryDocumentSnapshot> chatDocs = [];
        final Set<String> contactsWithCanonicalChat = {};

        groupedByContact.forEach((contactUid, docs) {
          final canonicalId = buildOneOnOneChatId(currentUser.uid, contactUid);

          QueryDocumentSnapshot? canonicalDoc;
          for (var d in docs) {
            if (d.id == canonicalId) {
              canonicalDoc = d;
              break;
            }
          }

          if (canonicalDoc != null) {
            contactsWithCanonicalChat.add(contactUid);
          }

          for (var d in docs) {
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
            if (contactUid == currentUser.uid) continue;
            _newChatContacts.add(contactUid);
            Timer(const Duration(seconds: 6), () {
              if (!mounted) return;
              setState(() => _newChatContacts.remove(contactUid));
            });
          }
          final gone = _seenChatContacts.difference(currentContacts);
          if (gone.isNotEmpty) _seenChatContacts.removeAll(gone);
        }

        if (chatDocs.isEmpty) {
          return _buildEmptyState(context);
        }

        final pinnedChatIds = _pinnedChatIds;

        chatDocs.sort((a, b) {
          final aPinned =
              _chatDocPinned(a.data(), currentUser.uid, pinnedChatIds);
          final bPinned =
              _chatDocPinned(b.data(), currentUser.uid, pinnedChatIds);
          if (aPinned != bPinned) return aPinned ? -1 : 1;
          Timestamp? aTimestamp =
              (a.data() as Map<String, dynamic>)['lastMessageTimestamp'];
          Timestamp? bTimestamp =
              (b.data() as Map<String, dynamic>)['lastMessageTimestamp'];
          if (aTimestamp == null && bTimestamp == null) return 0;
          if (aTimestamp == null) return 1;
          if (bTimestamp == null) return -1;
          return bTimestamp.compareTo(aTimestamp);
        });

        // Cache user loading so the list never re-spins on every new message.
        // Each tile streams its own last message, so a fresh message only
        // updates that chat's preview — no full-page reload.
        final usersKey = chatDocs
            .map((d) => (d.data() as Map<String, dynamic>)['uids'].toString())
            .join('|');
        if (_chatsUsersKey != usersKey || _chatsUsersFuture == null) {
          _chatsUsersKey = usersKey;
          _chatsUsersFuture =
              _loadChatUsers(chatDocs, currentUser.uid).then((map) {
            _cachedChatUsers = map;
            return map;
          });
        }

        return FutureBuilder<Map<String, UserModel>>(
          future: _chatsUsersFuture,
          builder: (context, futureSnapshot) {
            final userMap = futureSnapshot.hasData
                ? futureSnapshot.data!
                : _cachedChatUsers;

            // Only show the full-screen spinner on the very first load.
            if (futureSnapshot.connectionState == ConnectionState.waiting &&
                userMap.isEmpty) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.lightBlueAccent),
              );
            }
            if (futureSnapshot.hasError && userMap.isEmpty) {
              return _buildOfflineOrError(context,
                  futureSnapshot.error.toString(),
                  thing: 'contact details');
            }

            return ListView.builder(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              itemCount: chatDocs.length,
              itemBuilder: (context, index) {
                final chatDoc = chatDocs[index];
                final chatData = chatDoc.data() as Map<String, dynamic>;
                final List<dynamic> uids = chatData['uids'] ?? [];

                // --- MODIFIED: Logic to detect self-chat ---
                final bool isSelfChat = uids.toSet().length == 1 &&
                    uids.isNotEmpty &&
                    uids.first == currentUser.uid;

                // --- MODIFIED: Determine the correct user ID to display ---
                final String? contactUid = isSelfChat
                    ? currentUser.uid
                    : uids.firstWhere((uid) => uid != currentUser.uid,
                        orElse: () => null);

                if (contactUid == null) return const SizedBox.shrink();

                final contact = userMap[contactUid];
                if (contact == null) return const SizedBox.shrink();

                // My nickname for this contact replaces their real name.
                final nicknames =
                    (_userData?['nicknames'] as Map<String, dynamic>?) ??
                        const {};
                final nickname = nicknames[contactUid] as String?;
                final displayName = (nickname != null && nickname.isNotEmpty)
                    ? nickname
                    : '${contact.firstName} ${contact.lastName}';

                final myBlockedUids = Set<String>.from(
                    (_userData?['blockedUids'] as List<dynamic>?) ?? const []);
                final isBlockedChat = myBlockedUids.contains(contactUid) ||
                    contact.blockedUids.contains(currentUser.uid);
                final isDeletedAccount = contact.isDeleted;

                // Delete actions target the canonical chat so "delete for me"
                // keeps working once the legacy chat is migrated away.
                final actionChatId =
                    contactsWithCanonicalChat.contains(contactUid)
                        ? buildOneOnOneChatId(currentUser.uid, contactUid)
                        : chatDoc.id;

                final unreadCounts =
                    (chatData['unreadCounts'] as Map<String, dynamic>?) ?? {};
                final unreadCount =
                    (unreadCounts[currentUser.uid] as num?)?.toInt() ?? 0;

                return _ChatListTile(
                  key: ValueKey(chatDoc.id),
                  chatDocId: chatDoc.id,
                  collectionName: 'chats',
                  avatar: isDeletedAccount ? '❌' : contact.avatarEmoji,
                  title: isSelfChat
                      ? '$displayName (You)'
                      : displayName,
                  prefixName: displayName,
                  isGroup: false,
                  isSelfChat: isSelfChat,
                  currentUid: currentUser.uid,
                  unreadCount: unreadCount,
                  isBlocked: isBlockedChat && !isDeletedAccount,
                  isDeleted: isDeletedAccount,
                  isNewChat: _newChatContacts.contains(contactUid),
                  isPinned: pinnedChatIds
                      .contains(buildOneOnOneChatId(currentUser.uid, contactUid)),
                  onTap: () {
                    if (isDeletedAccount) {
                      // Show profile for deleted accounts
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  SenderProfileScreen(user: contact),
                          transitionsBuilder: PageTransition.slideFromRight,
                        ),
                      ).then((_) => _listenToCurrentUser());
                    } else {
                      Navigator.push(
                        context,
                        PageRouteBuilder(
                          pageBuilder:
                              (context, animation, secondaryAnimation) =>
                                  ChatScreen(contact: contact),
                          transitionsBuilder: PageTransition.slideFromRight,
                        ),
                      ).then((_) => _listenToCurrentUser());
                    }
                  },
                  onLongPress: () => _showDeleteOptions(
                    context,
                    actionChatId,
                    'chats',
                    pinId: buildOneOnOneChatId(currentUser.uid, contactUid),
                    isPinned: pinnedChatIds
                        .contains(buildOneOnOneChatId(currentUser.uid, contactUid)),
                    isSelfChat: isSelfChat,
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildGroupsOrEmpty() {
    final currentUser = _auth.currentUser!;

    // Fire a one-time server read to warm the Firestore cache for this query.
    // With persistence enabled, a newly-added member may see a stale cached
    // list that predates their membership. The server fetch populates the
    // local cache so the live listener below delivers the full, up-to-date
    // list almost immediately.
    _warmGroupsQueryFromServer(currentUser.uid);

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('groups')
          .where('memberUids', arrayContains: currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
              child: CircularProgressIndicator(
            color: Colors.lightBlueAccent,
          ));
        }
        if (snapshot.hasError) {
          return _buildOfflineOrError(context, snapshot.error.toString(),
              thing: 'groups');
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState(context);
        }

        var groupDocs = snapshot.data!.docs;

        groupDocs.removeWhere((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          final hiddenFor = data?['hiddenFor'] as List<dynamic>? ?? [];
          return hiddenFor.contains(currentUser.uid);
        });

        if (groupDocs.isEmpty) {
          return _buildEmptyState(context);
        }

        final pinnedChatIds = _pinnedChatIds;

        groupDocs.sort((a, b) {
          final aPinned = pinnedChatIds.contains(a.id);
          final bPinned = pinnedChatIds.contains(b.id);
          if (aPinned != bPinned) return aPinned ? -1 : 1;
          Timestamp? aTimestamp =
              (a.data() as Map<String, dynamic>)['lastMessageTimestamp'];
          Timestamp? bTimestamp =
              (b.data() as Map<String, dynamic>)['lastMessageTimestamp'];
          if (aTimestamp == null && bTimestamp == null) return 0;
          if (aTimestamp == null) return 1;
          if (bTimestamp == null) return -1;
          return bTimestamp.compareTo(aTimestamp);
        });

        return ListView.builder(
          padding: EdgeInsets.symmetric(vertical: 8.h),
          itemCount: groupDocs.length,
          itemBuilder: (context, index) {
            final group = GroupModel.fromFirestore(groupDocs[index]);
            final groupData = groupDocs[index].data() as Map<String, dynamic>;

            final unreadCounts =
                (groupData['unreadCounts'] as Map<String, dynamic>?) ?? {};
            final unreadCount =
                (unreadCounts[currentUser.uid] as num?)?.toInt() ?? 0;

            return _ChatListTile(
              key: ValueKey(group.id),
              chatDocId: group.id,
              collectionName: 'groups',
              avatar: group.avatarEmoji,
              title: group.name,
              prefixName: group.name,
              isGroup: true,
              isSelfChat: false,
              currentUid: currentUser.uid,
              unreadCount: unreadCount,
              isPinned: pinnedChatIds.contains(group.id),
              isDeleted: group.isDeleted,
              onTap: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        GroupChatScreen(group: group),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              },
              onLongPress: () => _showGroupOptions(
                    context,
                    group,
                    isCreator: group.createdBy == currentUser.uid,
                    isAdmin: group.adminUids.contains(currentUser.uid),
                    isPinned: pinnedChatIds.contains(group.id),
                  ),
            );
          },
        );
      },
    );
  }

  Widget _buildOfflineOrError(
    BuildContext context,
    String error, {
    required String thing,
  }) {
    final colors = FcAppColors.of(context);
    final offline = !ConnectivityService.instance.isConnected.value;
    return Center(
      child: Padding(
        padding: EdgeInsets.all(24.w),
        child: CustomText(
          text: offline
              ? 'No saved $thing to read offline yet. Connect to the '
                  'internet once to save them for offline reading.'
              : 'Could not load $thing.\n$error',
          fontSize: 14.sp,
          textAlign: TextAlign.center,
          textColor: colors.textSecondary,
        ),
      ),
    );
  }

  Widget _buildEmptyState(BuildContext context) {
    final colors = FcAppColors.of(context);
    final String type = _currentIndex == 0 ? 'Chats' : 'Groups';
    final String buttonLabel = _currentIndex == 0 ? 'message' : 'add group';
    final String actionLabel = _currentIndex == 0 ? 'chat' : 'group';
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Lottie.asset('assets/animations/empty_chat.json',
              width: 250.w, height: 250.h),
          SizedBox(height: 24.h),
          CustomText(
              text: 'No $type Yet',
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              textColor: colors.textPrimary),
          SizedBox(height: 8.h),
          CustomText(
              text:
                  'Tap the $buttonLabel button to start a new $actionLabel 👇',
              textAlign: TextAlign.center,
              fontSize: 16.sp,
              textColor: colors.textSecondary),
        ],
      ),
    );
  }

// --------------------------------
  // 👥 GROUP OPTIONS (LONG PRESS)
  // --------------------------------
  /// Bottom sheet shown when long-pressing a group on the Groups tab.
  /// Everyone can pin/unpin and (on an active group) hide it from their own
  /// list with "Delete for me". Deleting the whole group is an option ONLY
  /// for the creator, and once a group is deleted no delete options are
  /// offered at all, so members always keep read access to the history.
  void _showGroupOptions(
    BuildContext context,
    GroupModel group, {
    required bool isCreator,
    required bool isAdmin,
    required bool isPinned,
  }) {
    final pinId = group.id;
    final isDeleted = group.isDeleted;
    final colors = FcAppColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) {
        return Container(
          margin: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  margin: EdgeInsets.only(top: 12.h),
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: colors.surfaceDim,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
                SizedBox(height: 20.h),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: CustomText(
                    text: 'Group Options',
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    textColor: colors.textPrimary,
                  ),
                ),
                SizedBox(height: 16.h),
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    if (isPinned) {
                      _unpinChat(pinId);
                    } else {
                      _pinChat(pinId);
                    }
                  },
                  child: Container(
                    padding: EdgeInsets.symmetric(
                        horizontal: 20.w, vertical: 16.h),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            color: Colors.lightBlueAccent
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(
                            isPinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            color: Colors.lightBlueAccent,
                            size: 24.sp,
                          ),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CustomText(
                                text: isPinned
                                    ? 'Unpin group'
                                    : 'Pin group',
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                                textColor: colors.textPrimary,
                              ),
                              SizedBox(height: 4.h),
                              CustomText(
                                text: isPinned
                                    ? 'Show this group normally'
                                    : 'Pin this group to the top of your list',
                                fontSize: 13.sp,
                                textColor: colors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: colors.textWeak,
                          size: 20.sp,
                        ),
                      ],
                    ),
                  ),
                ),
                Divider(
                    height: 1.h,
                    thickness: 1,
                    indent: 70.w,
                    endIndent: 20.w),
                // "Delete for me" (hide from my list) — available to everyone.
                // This also lets a member remove a DELETED group from their
                // home list, while the read-only archive stays intact for the
                // members who still want to read it.
                InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _deleteForCurrentUser(group.id, 'groups');
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 20.w, vertical: 16.h),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(
                              Icons.delete_outline,
                              color: Colors.red.shade400,
                              size: 24.sp,
                            ),
                          ),
                          SizedBox(width: 16.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CustomText(
                                  text: 'Delete for me',
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600,
                                  textColor: colors.textPrimary,
                                ),
                                SizedBox(height: 4.h),
                                CustomText(
                                  text: 'Delete this group from your list',
                                  fontSize: 13.sp,
                                  textColor: colors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: colors.textWeak,
                            size: 20.sp,
                          ),
                        ],
                      ),
                    ),
                  ),
                if ((isCreator || isAdmin) && !isDeleted) ...[
                  Divider(
                      height: 1.h,
                      thickness: 1,
                      indent: 70.w,
                      endIndent: 20.w),
                  InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _confirmDeleteGroup(context, group);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 20.w, vertical: 16.h),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              color: Colors.red.shade50,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(
                              Icons.delete_forever,
                              color: Colors.red.shade400,
                              size: 24.sp,
                            ),
                          ),
                          SizedBox(width: 16.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CustomText(
                                  text: 'Delete Group',
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600,
                                  textColor: Colors.red.shade400,
                                ),
                                SizedBox(height: 4.h),
                                CustomText(
                                  text: 'Delete the whole group and make it '
                                      'read-only for everyone',
                                  fontSize: 13.sp,
                                  textColor: colors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: colors.textWeak,
                            size: 20.sp,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
                SizedBox(height: 12.h),
              ],
            ),
          ),
        );
      },
    );
  }

  /// Confirms the creator's group deletion and marks the group as deleted.
  /// The group doc and messages stay in place so every member keeps reading
  /// the history, but the chat becomes read-only (no sending / calling).
  Future<void> _confirmDeleteGroup(BuildContext context, GroupModel group) {
    final colors = FcAppColors.of(context);
    return showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        elevation: 8,
        child: Container(
          padding: EdgeInsets.all(24.w),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade400,
                  size: 40.sp,
                ),
              ),
              SizedBox(height: 20.h),
              CustomText(
                text: 'Delete Group?',
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                textColor: colors.textPrimary,
              ),
              SizedBox(height: 12.h),
              Text(
                'This group will become read-only for all members. Nobody '
                'will be able to send messages or make calls, but everyone '
                'can still read the conversation from before the deletion. '
                'This action cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 24.h),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        side: BorderSide(color: colors.divider, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: CustomText(
                        text: 'Cancel',
                        textColor: colors.textPrimary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _deleteGroupForEveryone(group);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: CustomText(
                        text: 'Delete',
                        textColor: Colors.white,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// Marks the whole group as deleted (soft delete) and posts a system
  /// message announcing it, mirroring the admin's delete in Group Info.
  Future<void> _deleteGroupForEveryone(GroupModel group) async {
    try {
      await _firestore.collection('groups').doc(group.id).update({
        'isDeleted': true,
      });

      // Post a system message so every member can see why the chat went
      // read-only. Fire-and-forget: a failure here must not undo the delete.
      try {
        final myUid = _auth.currentUser!.uid;
        final myDoc =
            await _firestore.collection('users').doc(myUid).get();
        final data = myDoc.exists ? myDoc.data() : null;
        final myName = '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'
            .trim();
        final actorName = myName.isNotEmpty ? myName : 'A member';
        await _firestore
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
          'isDeleted': false,
          'isEdited': false,
        });
      } catch (e) {
        debugPrint('Failed to post group-deleted system message: $e');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20.sp),
              SizedBox(width: 12.w),
              const CustomText(text: 'Group deleted'),
            ],
          ),
          backgroundColor: Colors.lightBlueAccent,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.r)),
          margin: EdgeInsets.all(16.w),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20.sp),
              SizedBox(width: 12.w),
              const CustomText(text: 'Failed to delete group'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10.r)),
          margin: EdgeInsets.all(16.w),
        ),
      );
    }
  }

void _showDeleteOptions(
    BuildContext context,
    String id,
    String collectionName, {
    required String pinId,
    required bool isPinned,
    bool isSelfChat = false,
  }) {
    final String type = collectionName == 'chats' ? 'Chat' : 'Group';
    final String lowerType = type.toLowerCase();
    final colors = FcAppColors.of(context);
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20.r)),
      ),
      builder: (ctx) {
        return Container(
          margin: EdgeInsets.all(12.w),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withValues(alpha: 0.1),
                blurRadius: 10,
                offset: const Offset(0, -3),
              ),
            ],
          ),
          child: SafeArea(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                // Handle bar
                Container(
                  margin: EdgeInsets.only(top: 12.h),
                  width: 40.w,
                  height: 4.h,
                  decoration: BoxDecoration(
                    color: colors.surfaceDim,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
                SizedBox(height: 20.h),

                // Title
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: CustomText(
                    text: '$type Options',
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    textColor: colors.textPrimary,
                  ),
                ),
                SizedBox(height: 16.h),

                // Pin / unpin option
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    if (isPinned) {
                      _unpinChat(pinId);
                    } else {
                      _pinChat(pinId);
                    }
                  },
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            color: Colors.lightBlueAccent
                                .withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(
                            isPinned
                                ? Icons.push_pin
                                : Icons.push_pin_outlined,
                            color: Colors.lightBlueAccent,
                            size: 24.sp,
                          ),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CustomText(
                                text: isPinned
                                    ? 'Unpin $lowerType'
                                    : 'Pin $lowerType',
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                                textColor: colors.textPrimary,
                              ),
                              SizedBox(height: 4.h),
                              CustomText(
                                text: isPinned
                                    ? 'Show this $lowerType normally'
                                    : 'Pin this $lowerType to the top of your list',
                                fontSize: 13.sp,
                                textColor: colors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: colors.textWeak,
                          size: 20.sp,
                        ),
                      ],
                    ),
                  ),
                ),

                Divider(
                    height: 1.h, thickness: 1, indent: 70.w, endIndent: 20.w),

                // Delete for me option
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _deleteForCurrentUser(id, collectionName);
                  },
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
                    child: Row(
                      children: [
                        Container(
                          padding: EdgeInsets.all(10.w),
                          decoration: BoxDecoration(
                            color: Colors.red.shade50,
                            borderRadius: BorderRadius.circular(12.r),
                          ),
                          child: Icon(
                            Icons.delete_outline,
                            color: Colors.red.shade400,
                            size: 24.sp,
                          ),
                        ),
                        SizedBox(width: 16.w),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              CustomText(
                                text: 'Delete for me',
                                fontSize: 16.sp,
                                fontWeight: FontWeight.w600,
                                textColor: colors.textPrimary,
                              ),
                              SizedBox(height: 4.h),
                              CustomText(
                                text: 'Delete this $lowerType from your list',
                                fontSize: 13.sp,
                                textColor: colors.textSecondary,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: colors.textWeak,
                          size: 20.sp,
                        ),
                      ],
                    ),
                  ),
                ),

                Divider(
                    height: 1.h, thickness: 1, indent: 70.w, endIndent: 20.w),

                // Delete for everyone option. Hidden for self-chats: in a
                // self-chat "for me" and "for everyone" are the same thing.
                if (!isSelfChat) ...[
                  InkWell(
                    onTap: () {
                      Navigator.pop(ctx);
                      _showConfirmDeleteEveryoneDialog(
                          context, id, collectionName);
                    },
                    child: Container(
                      padding: EdgeInsets.symmetric(
                          horizontal: 20.w, vertical: 16.h),
                      child: Row(
                        children: [
                          Container(
                            padding: EdgeInsets.all(10.w),
                            decoration: BoxDecoration(
                              color: Colors.red.shade100,
                              borderRadius: BorderRadius.circular(12.r),
                            ),
                            child: Icon(
                              Icons.delete_forever,
                              color: Colors.red.shade600,
                              size: 24.sp,
                            ),
                          ),
                          SizedBox(width: 16.w),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                CustomText(
                                  text: 'Delete for everyone',
                                  fontSize: 16.sp,
                                  fontWeight: FontWeight.w600,
                                  textColor: colors.textPrimary,
                                ),
                                SizedBox(height: 4.h),
                                CustomText(
                                  text: 'Remove $lowerType and messages permanently',
                                  fontSize: 13.sp,
                                  textColor: colors.textSecondary,
                                ),
                              ],
                            ),
                          ),
                          Icon(
                            Icons.chevron_right,
                            color: colors.textWeak,
                            size: 20.sp,
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                SizedBox(height: 12.h),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteForCurrentUser(String id, String collectionName) async {
    final String type = collectionName == 'chats' ? 'Chat' : 'Group';
    final String lowerType = type.toLowerCase();
    final currentUser = _auth.currentUser!;
    try {
      // Hide the chat from my home list.
      await _firestore.collection(collectionName).doc(id).update({
        'hiddenFor': FieldValue.arrayUnion([currentUser.uid]),
      });

      // Also clear all the messages for me: mark every message in this chat
      // as deleted-for-me so the conversation history no longer shows the
      // content. This keeps the other side's copy intact, exactly like
      // Telegram's "delete chat for me".
      await _deleteAllMessagesForMe(id, collectionName, currentUser.uid);

      // Show success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20.sp),
              SizedBox(width: 12.w),
              CustomText(text: '$type deleted successfully'),
            ],
          ),
          backgroundColor: Colors.lightBlueAccent,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          margin: EdgeInsets.all(16.w),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20.sp),
              SizedBox(width: 12.w),
              CustomText(text: 'Failed to hide $lowerType'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          margin: EdgeInsets.all(16.w),
        ),
      );
    }
  }

  /// Marks every message in a chat/group as deleted-for-me for the given uid,
  /// so the conversation content no longer appears on this device. Messages
  /// stay intact for everyone else (Telegram-style "delete chat for me").
  /// Handles arbitrarily large histories by batching (Firestore allows at most
  /// 500 writes per batch) and pages through the whole subcollection.
  Future<void> _deleteAllMessagesForMe(
    String chatId,
    String collectionName,
    String uid,
  ) async {
    final messagesRef = _firestore
        .collection(collectionName)
        .doc(chatId)
        .collection('messages');

    // Page through the whole subcollection, batching writes (Firestore allows
    // at most 500 writes per batch), advancing by the last document seen so
    // the cursor never revisits the same docs (which would loop forever).
    QueryDocumentSnapshot<Map<String, dynamic>>? cursor;
    while (true) {
      Query<Map<String, dynamic>> query = messagesRef.limit(400);
      if (cursor != null) query = query.startAfterDocument(cursor);

      final snapshot = await query.get();
      if (snapshot.docs.isEmpty) break;

      final batch = _firestore.batch();
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

  void _showConfirmDeleteEveryoneDialog(
      BuildContext context, String id, String collectionName) {
    final String type = collectionName == 'chats' ? 'Chat' : 'Group';
    final String lowerType = type.toLowerCase();
    final colors = FcAppColors.of(context);
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape:
            RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        elevation: 8,
        child: Container(
          padding: EdgeInsets.all(24.w),
          decoration: BoxDecoration(
            color: colors.surface,
            borderRadius: BorderRadius.circular(20.r),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Icon
              Container(
                padding: EdgeInsets.all(16.w),
                decoration: BoxDecoration(
                  color: Colors.red.shade50,
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  Icons.warning_amber_rounded,
                  color: Colors.red.shade400,
                  size: 40.sp,
                ),
              ),
              SizedBox(height: 20.h),

              // Title
              CustomText(
                text: 'Delete $type?',
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                textColor: colors.textPrimary,
              ),
              SizedBox(height: 12.h),

              // Description
              Text(
                'This will permanently delete the $lowerType and all messages for everyone. This action cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: colors.textSecondary,
                  height: 1.4,
                ),
              ),
              SizedBox(height: 24.h),

              // Buttons
              Row(
                children: [
                  // Cancel button
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => Navigator.of(ctx).pop(),
                      style: OutlinedButton.styleFrom(
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        side: BorderSide(color: colors.divider, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: CustomText(
                        text: 'Cancel',
                        textColor: colors.textPrimary,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: 12.w),

                  // Delete button
                  Expanded(
                    child: ElevatedButton(
                      onPressed: () async {
                        Navigator.of(ctx).pop();
                        await _deleteForEveryone(id, collectionName);
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        padding: EdgeInsets.symmetric(vertical: 14.h),
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: CustomText(
                        text: 'Delete',
                        textColor: Colors.white,
                        fontSize: 15.sp,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _deleteForEveryone(String id, String collectionName) async {
    final String type = collectionName == 'chats' ? 'Chat' : 'Group';
    final String lowerType = type.toLowerCase();
    try {
      // Delete all messages in the conversation
      final messagesSnapshot = await _firestore
          .collection(collectionName)
          .doc(id)
          .collection('messages')
          .get();

      // Delete messages in batches
      final batch = _firestore.batch();
      for (var doc in messagesSnapshot.docs) {
        batch.delete(doc.reference);
      }
      await batch.commit();

      // Delete the conversation document itself
      await _firestore.collection(collectionName).doc(id).delete();

      // Show success message
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.check_circle, color: Colors.white, size: 20.sp),
              SizedBox(width: 12.w),
              CustomText(text: '$type deleted for everyone'),
            ],
          ),
          backgroundColor: Colors.lightBlueAccent,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          margin: EdgeInsets.all(16.w),
          duration: const Duration(seconds: 2),
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Row(
            children: [
              Icon(Icons.error_outline, color: Colors.white, size: 20.sp),
              SizedBox(width: 12.w),
              CustomText(text: 'Failed to delete $lowerType'),
            ],
          ),
          backgroundColor: Colors.red,
          behavior: SnackBarBehavior.floating,
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(10.r)),
          margin: EdgeInsets.all(16.w),
        ),
      );
    }
  }
}

/// A single chat / group row on the home screen.
/// Each row owns its own live stream for the last message, so a new message
/// only updates that row — the rest of the list never flickers or reloads.
/// Unread conversations get the app's main color border + a count badge.
class _ChatListTile extends StatefulWidget {
  final String chatDocId;
  final String collectionName; // 'chats' | 'groups'
  final String avatar;
  final String title;
  final String prefixName;
  final bool isGroup;
  final bool isSelfChat;
  final String currentUid;
  final int unreadCount;
  final bool isBlocked;
  final bool isDeleted;
  final bool isNewChat;
  final bool isPinned;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  const _ChatListTile({
    super.key,
    required this.chatDocId,
    required this.collectionName,
    required this.avatar,
    required this.title,
    required this.prefixName,
    required this.isGroup,
    required this.isSelfChat,
    required this.currentUid,
    required this.unreadCount,
    this.isBlocked = false,
    this.isDeleted = false,
    this.isNewChat = false,
    this.isPinned = false,
    required this.onTap,
    this.onLongPress,
  });

  @override
  State<_ChatListTile> createState() => _ChatListTileState();
}

class _ChatListTileState extends State<_ChatListTile> {
  /// True while the brand-new-chat entrance glow and NEW pill are showing.
  /// Flips off a few seconds after the tile appears; the highlight fades via
  /// [AnimatedContainer] so the switch is smooth.
  bool _newHighlight = false;

  @override
  void initState() {
    super.initState();
    if (widget.isNewChat) {
      _newHighlight = true;
      Timer(const Duration(milliseconds: 2800), () {
        if (mounted) setState(() => _newHighlight = false);
      });
    }
  }
  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance
          .collection(widget.collectionName)
          .doc(widget.chatDocId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(20)
          .snapshots(),
      builder: (context, snapshot) {
        final docs = (snapshot.hasData ? snapshot.data!.docs : <dynamic>[])
            .cast<QueryDocumentSnapshot<Map<String, dynamic>>>();
        final msgData = docs.isNotEmpty
            ? docs.first.data()
            : <String, dynamic>{};

        // Count the unseen messages for 1-1 chats: messages from the other
        // side that have not been marked 'seen'. Group messages are never
        // marked 'seen', so the count badge is a 1-1 concept.
        int unseenCount = 0;
        if (!widget.isGroup) {
          for (final doc in docs) {
            final m = doc.data();
            if (m['senderId'] == widget.currentUid) continue;
            if (m['status'] == 'seen') continue;
            unseenCount++;
          }
        }

        var lastMessage = messagePreviewText(msgData);
        String time = '';
        String prefix = '';

        if (msgData.isNotEmpty) {
          if (msgData['timestamp'] != null) {
            time = lastMessageTimeLabel(
                (msgData['timestamp'] as Timestamp).toDate());
          }
          final senderId = msgData['senderId'] ?? '';
          if (senderId == widget.currentUid) {
            prefix = 'You: ';
          } else if (widget.isGroup) {
            prefix = '${msgData['senderName'] ?? 'Someone'}: ';
          } else {
            prefix = '${widget.prefixName}: ';
          }
        }

        // Unread detection. The message `status` is the authoritative read
        // state for 1-1 chats — using it (not the chat-doc `unreadCounts`,
        // which can be stale) avoids tiles flashing "unread" right after
        // opening home and then flipping to "seen". Groups never mark
        // messages 'seen', so they keep using the group-doc counter. A 1-1
        // stream is never shown as unread before it has data, so we don't
        // flash the reverse way either.
        final bool isUnread = widget.isGroup
            ? widget.unreadCount > 0
            : (snapshot.hasData && unseenCount > 0);
        final int badgeCount =
            widget.isGroup ? widget.unreadCount : unseenCount;

        final Widget tile = AnimatedContainer(
          duration: const Duration(milliseconds: 700),
          curve: Curves.easeOut,
          margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
          padding: EdgeInsets.symmetric(vertical: 8.h),
          decoration: BoxDecoration(
            color: _newHighlight
                ? Colors.lightBlue.withValues(alpha: 0.22)
                : (isUnread ? colors.avatarBackground : colors.surface),
            borderRadius: BorderRadius.circular(16.r),
            border: Border.all(
              color: _newHighlight || isUnread
                  ? Colors.lightBlueAccent
                  : Colors.transparent,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: _newHighlight
                    ? Colors.lightBlueAccent.withValues(alpha: 0.35)
                    : (isUnread
                        ? Colors.lightBlueAccent.withValues(alpha: 0.25)
                        : Colors.black.withValues(alpha: 0.08)),
                blurRadius: _newHighlight ? 16 : 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
            child: ListTile(
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 16.w, vertical: 4.h),
              leading: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Colors.lightBlueAccent.withValues(alpha: 0.65),
                    width: 2.w,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.lightBlueAccent.withValues(alpha: 0.35),
                      blurRadius: 8,
                      offset: const Offset(0, 2),
                    ),
                  ],
                ),
                padding: const EdgeInsets.all(1),
                child: CircleAvatar(
                  radius: 26.r,
                  backgroundColor: colors.avatarBackground,
                  child: CustomText(text: widget.avatar, fontSize: 26.sp),
                ),
              ),
              title: Row(
                children: [
                  if (widget.isPinned) ...[
                    const Icon(Icons.push_pin,
                        size: 14, color: Colors.lightBlueAccent),
                    SizedBox(width: 4.w),
                  ],
                  Flexible(
                    child: CustomText(
                      text: widget.title,
                      fontWeight: FontWeight.bold,
                      fontSize: 16.sp,
                      textColor: widget.isDeleted
                          ? colors.textSecondary
                          : colors.textPrimary,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (_newHighlight) ...[
                    SizedBox(width: 8.w),
                    AnimatedOpacity(
                      duration: const Duration(milliseconds: 500),
                      opacity: _newHighlight ? 1 : 0,
                      child: Container(
                        padding: EdgeInsets.symmetric(
                            horizontal: 8.w, vertical: 2.h),
                        decoration: BoxDecoration(
                          color: Colors.lightBlueAccent.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(8.r),
                        ),
                        child: CustomText(
                          text: 'NEW',
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                          textColor: Colors.lightBlueAccent,
                        ),
                      ),
                    ),
                  ],
                  if (widget.isDeleted) ...[
                    SizedBox(width: 8.w),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: colors.tile,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: CustomText(
                        text: 'Deleted',
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        textColor: colors.textSecondary,
                      ),
                    ),
                  ],
                  if (widget.isBlocked && !widget.isDeleted) ...[
                    SizedBox(width: 8.w),
                    Container(
                      padding:
                          EdgeInsets.symmetric(horizontal: 8.w, vertical: 2.h),
                      decoration: BoxDecoration(
                        color: Colors.red.shade50,
                        borderRadius: BorderRadius.circular(8.r),
                      ),
                      child: CustomText(
                        text: 'Blocked',
                        fontSize: 11.sp,
                        fontWeight: FontWeight.bold,
                        textColor: Colors.red.shade400,
                      ),
                    ),
                  ],
                ],
              ),
              subtitle: Padding(
                padding: EdgeInsets.only(top: 4.h),
                child: Row(
                  children: [
                    if (prefix.isNotEmpty)
                      CustomText(
                        text: prefix,
                        fontWeight: FontWeight.bold,
                        textColor: Colors.lightBlueAccent,
                        fontSize: 14.sp,
                      ),
                    Expanded(
                      child: Text(
                        lastMessage,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: widget.isDeleted
                              ? colors.textWeak
                              : (isUnread
                                  ? colors.textPrimary
                                  : colors.textSecondary),
                          fontSize: 14.sp,
                          fontWeight:
                              isUnread ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
              trailing: Column(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    time,
                    style: TextStyle(
                      color: isUnread
                          ? Colors.lightBlueAccent
                          : colors.textSecondary,
                      fontSize: 12.sp,
                      fontWeight:
                          isUnread ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  if (isUnread && badgeCount > 0) ...[
                    SizedBox(height: 6.h),
                    Container(
                      padding: EdgeInsets.symmetric(horizontal: 7.w, vertical: 2.h),
                      constraints: BoxConstraints(minWidth: 22.w, minHeight: 22.h),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                          colors: [
                            Colors.lightBlueAccent,
                            Color(0xFF0288D1),
                          ],
                        ),
                        borderRadius: BorderRadius.circular(12.r),
                        boxShadow: [
                          BoxShadow(
                            color:
                                Colors.lightBlueAccent.withValues(alpha: 0.4),
                            blurRadius: 6,
                            offset: const Offset(0, 2),
                          ),
                        ],
                      ),
                      child: Text(
                        badgeCount > 9 ? '9+' : '$badgeCount',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 11.sp,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
              onTap: widget.onTap,
              onLongPress: widget.onLongPress,
            ),
          );

        // Brand-new chats get a more noticeable entrance (slide from above),
        // every other tile keeps the usual quiet fade-in.
        return widget.isNewChat
            ? FadeInDown(
                duration: const Duration(milliseconds: 650),
                child: tile,
              )
            : FadeInUp(
                duration: const Duration(milliseconds: 300),
                child: tile,
              );
      },
    );
  }
}
