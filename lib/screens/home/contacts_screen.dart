import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter_contacts/flutter_contacts.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../models/user_model.dart';
import 'create_group_screen.dart';
import '../home/chat_screen.dart';
import '../../utils/page_transition.dart';

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

  @override
  void initState() {
    super.initState();
    _getContacts();
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
        otherContacts.sort(
                (a, b) => a.firstName.toLowerCase().compareTo(b.firstName.toLowerCase()));
        final List<UserModel> finalContacts = [];
        if (currentUserModel != null) {
          finalContacts.add(currentUserModel);
        }
        finalContacts.addAll(otherContacts);
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
    } else {
      Navigator.pushReplacement(
        context,
        PageRouteBuilder(
          pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(contact: user),
          transitionsBuilder: PageTransition.slideFromRight,
        ),
      );
    }
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
        titleTextStyle:
        const TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: 20),
        centerTitle: false,
        backgroundColor: Colors.lightBlueAccent,
        elevation: 1,
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
      ),
      body: _buildBody(),
      floatingActionButton: _isSelectionMode && _selectedContacts.isNotEmpty
          ? FloatingActionButton(
        backgroundColor: Colors.lightBlueAccent,
        onPressed: () {
          Navigator.push(
            context,
            PageRouteBuilder(
              pageBuilder: (context, animation, secondaryAnimation) => CreateGroupScreen(
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

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.lightBlueAccent));
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: CustomText(text: _errorMessage,
                textAlign: TextAlign.center,
                fontSize: 16.sp, textColor: Colors.grey[600]),
          ));
    }
    if (_appContacts.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(30.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.person_search, size: 80, color: Colors.grey.shade300),
              SizedBox(height: 16.h),
              CustomText(
                  text:  'No Contacts Found',
                  fontSize: 20.sp,
                  fontWeight: FontWeight.bold,
                  textColor: Colors.grey.shade700),
              SizedBox(height: 8.h),
              CustomText(
                text: 'None of your phone contacts seem to be using the app yet. Invite them to join!',
                textAlign: TextAlign.center,
                fontSize: 16.sp, textColor: Colors.grey[600],
              ),
            ],
          ),
        ),
      );
    }

    return ListView.builder(
      itemCount: _appContacts.length,
      itemBuilder: (context, index) {
        final user = _appContacts[index];
        final isCurrentUser =
            user.uid == FirebaseAuth.instance.currentUser?.uid;
        final isSelected = _selectedContacts.contains(user);

        return ListTile(
          contentPadding:
          EdgeInsets.symmetric(vertical: 8.h, horizontal: 16.w),
          leading: CircleAvatar(
            radius: 28.r,
            backgroundColor: isSelected ? Colors.lightBlueAccent.withOpacity(0.3) : Colors.lightBlue.shade50,
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
              CustomText(text: '${user.firstName} ${user.lastName}',
                  fontWeight: FontWeight.w600),
              if (isCurrentUser)
                Padding(
                    padding: EdgeInsets.only(left: 8.w),
                    child: CustomText(text: '(You)',
                        textColor: Colors.grey.shade600,
                        fontWeight: FontWeight.normal)),
            ],
          ),
          subtitle: CustomText(text: isCurrentUser ? "Message yourself" : user.phoneNumber),
          onTap: () => _onContactTapped(user),
          onLongPress: () => _onContactLongPressed(user),
          tileColor: isSelected ? Colors.lightBlue.shade50 : null,
        );
      },
    );
  }
}