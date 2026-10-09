import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/utils/friendly_error_messages.dart';
import 'package:flash_chat_app/features/groups/cubit/group_cubit.dart';
import 'package:flash_chat_app/features/groups/models/group_model.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flutter/material.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../../core/theme/app_theme.dart';

class AddGroupMembersScreen extends StatefulWidget {
  final GroupModel group;
  final GroupCubit cubit;

  const AddGroupMembersScreen({
    super.key,
    required this.group,
    required this.cubit,
  });

  @override
  State<AddGroupMembersScreen> createState() => _AddGroupMembersScreenState();
}

class _AddGroupMembersScreenState extends State<AddGroupMembersScreen> {
  bool _isLoading = true;
  List<UserModel> _appContacts = [];
  String _errorMessage = '';

  bool _isSelectionMode = false;
  final Set<UserModel> _selectedContacts = {};

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _getContacts();
  }

  @override
  void dispose() {
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
        if (mounted) {
          setState(() => _errorMessage = 'You are not logged in.');
        }
        return;
      }

      // Read the freshest membership straight from Firestore instead of
      // trusting the GroupModel passed into this screen. The in-memory model
      // can be stale (e.g. it still lists a member who was just removed), which
      // would wrongly filter that contact out and prevent re-adding them.
      Set<String> currentMemberUids;
      try {
        final groupDoc = await FirebaseFirestore.instance
            .collection('groups')
            .doc(widget.group.id)
            .get();
        final rawUids =
            (groupDoc.data()?['memberUids'] as List<dynamic>?) ?? const [];
        currentMemberUids = rawUids.map((u) => u.toString()).toSet();
      } catch (_) {
        currentMemberUids = widget.group.memberUids.toSet();
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

        final List<UserModel> otherContacts = matchedContacts
            .where((matched) => matched.uid != currentUser.uid)
            .toList();

        otherContacts.sort(
          (a, b) =>
              a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()),
        );

        final List<UserModel> finalContacts = otherContacts
            .where((u) => !currentMemberUids.contains(u.uid))
            .where((u) => !u.isDeleted)
            .toList();

        if (mounted) {
          setState(() {
            _appContacts = finalContacts;
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
          _errorMessage = friendlyErrorMessage(
              e, fallback: 'We could not load your contacts. Please try again.');
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

  void _onContactTapped(UserModel user) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (user.uid == currentUid) return;

    setState(() {
      if (_selectedContacts.contains(user)) {
        _selectedContacts.remove(user);
      } else {
        _selectedContacts.add(user);
      }
      _isSelectionMode = _selectedContacts.isNotEmpty;
    });
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

  Future<void> _addMembers() async {
    if (_selectedContacts.isEmpty) return;

    final newUids = _selectedContacts.map((u) => u.uid).toList();

    // Membership changes go through the bloc, which enforces that only
    // group admins can add members (also enforced by Firestore rules).
    widget.cubit.addMembersToGroup(
      group: widget.group,
      newMemberUids: newUids,
    );

    if (mounted) {
      Navigator.pop(context);
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
                : 'Add Members'),
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
              onPressed: _addMembers,
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
                  text: 'No Contacts Available',
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  textColor: colors.textSecondary),
              SizedBox(height: 8.h),
              CustomText(
                text:
                    'No additional contacts from your phone are using the app or not already in the group.',
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
                  text: user.avatarEmoji.isNotEmpty ? user.avatarEmoji : '?',
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
                  maxLines: 1,
                ),
              ),
              if (isCurrentUser)
                Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: CustomText(
                        text: '(You)',
                        textColor: colors.textSecondary,
                        fontWeight: FontWeight.normal)),
            ],
          ),
          subtitle: CustomText(
              text: isCurrentUser ? "Message yourself" : user.phoneNumber),
          onTap: () => _onContactTapped(user),
          onLongPress: () => _onContactLongPressed(user),
          tileColor: isSelected ? Colors.lightBlue.shade50 : null,
        );
      },
    );
  }
}