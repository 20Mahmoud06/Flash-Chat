import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'dart:async';
import '../../../core/utils/page_transition.dart';
import '../../../features/profile/screens/sender_profile_screen.dart';
import '../../../models/user_model.dart' show UserModel;
import '../../../shared/widgets/custom_text.dart';
import '../../groups/screens/create_group_screen.dart';
import 'chat_screen.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  bool _isLoading = true;
  List<UserModel> _appContacts = [];
  String _errorMessage = '';

  bool _isSelectionMode = false;
  final Set<UserModel> _selectedContacts = {};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();

  Set<String> _myBlockedUids = {};
  StreamSubscription<DocumentSnapshot>? _myBlockSub;

  @override
  void initState() {
    super.initState();
    _getContacts();
    _listenToMyBlockedUids();
  }

  @override
  void dispose() {
    _myBlockSub?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  List<UserModel> get _filteredContacts {
    if (_searchQuery.isEmpty) return _appContacts;
    final q = _searchQuery.toLowerCase();
    return _appContacts.where((u) {
      if (u.firstName.toLowerCase().contains(q)) return true;
      if (u.lastName.toLowerCase().contains(q)) return true;
      if (u.phoneNumber.replaceAll(RegExp(r'\D'), '').contains(q)) return true;
      return false;
    }).toList();
  }

  void _listenToMyBlockedUids() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    _myBlockSub = FirebaseFirestore.instance
        .collection('users')
        .doc(uid)
        .snapshots()
        .listen((doc) {
      if (!mounted) return;
      setState(() {
        _myBlockedUids =
            Set<String>.from(doc.data()?['blockedUids'] ?? const []);
      });
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

  Future<void> _getContacts() async {
    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        setState(() => _errorMessage = 'You are not logged in.');
        return;
      }

      if (await FlutterContacts.requestPermission()) {
        final usersSnapshot =
            await FirebaseFirestore.instance.collection('users').get();
        final allAppUsers = usersSnapshot.docs
            .map((doc) => UserModel.fromFirestore(doc))
            .toList();
        final Map<String, UserModel> appUsersMap = {
          for (var user in allAppUsers)
            if (user.phoneNumber.isNotEmpty)
              _normalizePhoneNumber(user.phoneNumber): user
        };

        final phoneContacts =
            await FlutterContacts.getContacts(withProperties: true);

        final List<UserModel> matchedContacts = [];
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
        final List<UserModel> otherContacts = [];
        for (var contact in allAppUsers) {
          if (contact.uid == currentUser.uid) {
            currentUserModel = contact;
            break;
          }
        }
        for (var matched in matchedContacts) {
          if (matched.uid != currentUser.uid) {
            otherContacts.add(matched);
          }
        }
        otherContacts.sort((a, b) =>
            a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()));
        final List<UserModel> finalContacts = [];
        if (currentUserModel != null) {
          finalContacts.add(currentUserModel);
        }

        // Deleted accounts have no active profile to reach outside of an
        // existing conversation, so we only keep them in this list when there
        // is already a chat or a shared group tying them to history.
        final Set<String> historyUids = await _buildContactHistoryUids();
        final liveContacts = otherContacts
            .where((u) => !u.isDeleted || historyUids.contains(u.uid))
            .toList();
        finalContacts.addAll(liveContacts);
        if (mounted) {
          setState(() {
            _appContacts = finalContacts;
            _myBlockedUids =
                Set<String>.from(currentUserModel?.blockedUids ?? const []);
          });
        }
      } else {
        if (mounted) {
          setState(() {
            _errorMessage =
                'Contacts permission is required to find your friends.';
          });
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'An error occurred while fetching contacts: $e';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoading = false;
        });
      }
    }
  }

  /// Collects the uids this account already has history with: the other party
  /// of every 1-1 chat I'm in, plus all members of every group I belong to.
  /// Deleted accounts are only surfaced in this list when they appear here, so
  /// an old chat or group keeps their history reachable.
  Future<Set<String>> _buildContactHistoryUids() async {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return const {};
    final db = FirebaseFirestore.instance;
    final Set<String> uids = {};

    try {
      final chats = await db
          .collection('chats')
          .where('uids', arrayContains: currentUid)
          .get();
      for (final doc in chats.docs) {
        final chatUids = (doc.data()['uids'] as List<dynamic>?) ?? const [];
        uids.addAll(chatUids.map((u) => u.toString()).where((u) => u != currentUid));
      }
    } catch (_) {}

    try {
      final groups = await db
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

  void _onContactTapped(UserModel user) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (_isSelectionMode) {
      if (user.uid == currentUid) return;
      setState(() {
        if (_selectedContacts.contains(user)) {
          _selectedContacts.remove(user);
        } else {
          _selectedContacts.add(user);
        }
        if (_selectedContacts.isEmpty) {
          _isSelectionMode = false;
        }
      });
    } else if (user.uid != currentUid && (user.isDeleted || _isBlockedContact(user))) {
      // Deleted or blocked contacts cannot be chatted/called.
      // Open the profile instead so the user can see the status.
      Navigator.push(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              SenderProfileScreen(user: user),
          transitionsBuilder: PageTransition.slideFromRight,
        ),
      );
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) =>
              ChatScreen(contact: user),
          transitionsBuilder: PageTransition.slideFromRight,
        ),
      );
    }
  }

  /// True when [user] is blocked by me or has blocked me.
  bool _isBlockedContact(UserModel user) {
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    if (currentUid == null) return false;
    if (_myBlockedUids.contains(user.uid)) return true;
    return user.blockedUids.contains(currentUid);
  }

  void _onContactLongPressed(UserModel user) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (user.uid == currentUid) return;
    if (!_isSelectionMode) {
      setState(() {
        _isSelectionMode = true;
        _selectedContacts.add(user);
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: _isSelectionMode
            ? IconButton(
                icon: const Icon(Icons.close),
                onPressed: () {
                  setState(() {
                    _isSelectionMode = false;
                    _selectedContacts.clear();
                  });
                },
              )
            : null,
        title: CustomText(
            text: _isSelectionMode
                ? '${_selectedContacts.length} selected'
                : 'New Chat'),
        titleTextStyle: const TextStyle(
            color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        centerTitle: false,
        backgroundColor: Colors.lightBlueAccent,
        elevation: 1,
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
      ),
      body: _buildBody(context),
      floatingActionButton: _isSelectionMode && _selectedContacts.isNotEmpty
          ? FloatingActionButton(
              backgroundColor: Colors.lightBlueAccent,
              onPressed: () {
                Navigator.push(
                  context,
                  PageRouteBuilder(
                    pageBuilder: (context, animation, secondaryAnimation) =>
                        CreateGroupScreen(
                      initialMembers: _selectedContacts.toList(),
                    ),
                    transitionsBuilder: PageTransition.slideFromRight,
                  ),
                );
              },
              child: const Icon(Icons.arrow_forward, color: Colors.white),
            )
          : null,
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = FcAppColors.of(context);
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.lightBlueAccent));
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: CustomText(
            text: _errorMessage,
            textAlign: TextAlign.center,
            fontSize: 16.sp,
            textColor: colors.textSecondary),
      ));
    }
    if (_appContacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_search, size: 80, color: colors.textWeak),
              SizedBox(height: 16.h),
              CustomText(
                  text: 'No Contacts Found',
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  textColor: colors.textSecondary),
              SizedBox(height: 8.h),
              CustomText(
                text:
                    'None of your phone contacts seem to be using the app yet. Invite them to join!',
                textAlign: TextAlign.center,
                fontSize: 16.sp,
                textColor: colors.textSecondary,
              ),
            ],
          ),
        ),
      );
    }

    final filtered = _filteredContacts;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: (v) => setState(() => _searchQuery = v),
            style: TextStyle(color: colors.textPrimary, fontSize: 16.sp),
            cursorColor: Colors.lightBlueAccent,
            decoration: InputDecoration(
              hintText: 'Search by name or number',
              hintStyle: TextStyle(color: colors.textWeak, fontSize: 16.sp),
              prefixIcon: Icon(Icons.search, color: colors.textWeak),
              suffixIcon: _searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, color: colors.textWeak),
                      onPressed: () {
                        _searchController.clear();
                        setState(() => _searchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: colors.inputFill,
              isDense: true,
              contentPadding: EdgeInsets.symmetric(vertical: 14.h),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide.none,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide.none,
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12.r),
                borderSide: BorderSide(
                  color: Colors.lightBlueAccent,
                  width: 1.5.w,
                ),
              ),
            ),
          ),
        ),
        Divider(color: colors.divider, height: 1),
        Expanded(
          child: filtered.isEmpty
              ? Center(
                  child: CustomText(
                    text: 'No contacts match "$_searchQuery"',
                    textColor: colors.textWeak,
                    fontSize: 16.sp,
                  ),
                )
              : _buildContactList(filtered, colors),
        ),
      ],
    );
  }

  Widget _buildContactList(List<UserModel> contacts, FcAppColors colors) {
    return ListView.builder(
      padding: EdgeInsets.only(bottom: 80.h),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final user = contacts[index];
        final isCurrentUser =
            user.uid == FirebaseAuth.instance.currentUser?.uid;
        final isSelected = _selectedContacts.contains(user);
        final isBlocked = !isCurrentUser && _isBlockedContact(user);
        final isDeleted = user.isDeleted;
        final isMine = _appContacts.isNotEmpty &&
            _appContacts.first.uid == FirebaseAuth.instance.currentUser?.uid;
        final myNickname = isMine && !isCurrentUser
            ? _appContacts.first.nicknames[user.uid]
            : null;

        return ListTile(
          contentPadding: EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
          leading: CircleAvatar(
            radius: 28.r,
            backgroundColor: isSelected
                ? Colors.lightBlueAccent.withValues(alpha: 0.3)
                : colors.avatarBackground,
            child: Stack(
              alignment: Alignment.center,
              children: [
                CustomText(
                  text: isDeleted
                      ? '❌'
                      : (user.avatarEmoji.isNotEmpty ? user.avatarEmoji : '?'),
                  fontSize: 24.sp,
                ),
                if (isSelected)
                  const Icon(Icons.check_circle, color: Colors.white),
              ],
            ),
          ),
          title: Row(
            children: [
              Flexible(
                child: CustomText(
                  text: '${user.firstName} ${user.lastName}',
                  fontWeight: FontWeight.w600,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (myNickname != null)
                Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: CustomText(
                        text: '($myNickname)',
                        textColor: colors.textSecondary,
                        fontWeight: FontWeight.normal)),
              if (isCurrentUser)
                Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: CustomText(
                        text: '(You)',
                        textColor: colors.textSecondary,
                        fontWeight: FontWeight.normal)),
              if (isDeleted)
                Padding(
                  padding: EdgeInsets.only(left: 8.w),
                  child: Container(
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
                ),
              if (isBlocked && !isDeleted)
                Padding(
                  padding: EdgeInsets.only(left: 8.w),
                  child: Container(
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
                ),
            ],
          ),
          subtitle: CustomText(
              text: isCurrentUser
                  ? "Message yourself"
                  : (isDeleted
                      ? 'This user has deleted their account'
                      : (isBlocked
                          ? 'Blocked - you cannot message or call'
                          : user.phoneNumber)),
              textColor: isDeleted ? colors.textSecondary : (isBlocked ? Colors.red.shade400 : null)),
          onTap: () => _onContactTapped(user),
          onLongPress: () => _onContactLongPressed(user),
          tileColor: isSelected ? colors.avatarBackground : null,
        );
      },
    );
  }
}
