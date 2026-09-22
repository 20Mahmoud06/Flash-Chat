import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/utils/friendly_error_messages.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flash_chat_app/services/block/block_service.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:quickalert/quickalert.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../../core/theme/app_theme.dart';
import '../../chat/screens/chat_screen.dart';

class BlockedUsersScreen extends StatefulWidget {
  const BlockedUsersScreen({super.key});

  @override
  State<BlockedUsersScreen> createState() => _BlockedUsersScreenState();
}

class _BlockedUsersScreenState extends State<BlockedUsersScreen> {
  List<UserModel> _blockedUsers = [];
  bool _loading = true;
  String _errorMessage = '';

  @override
  void initState() {
    super.initState();
    _loadBlockedUsers();
  }

  Future<void> _loadBlockedUsers() async {
    try {
      final users = await BlockService.getBlockedUsers();
      if (mounted) {
        setState(() {
          _blockedUsers = users;
          _loading = false;
        });
      }
    } catch (e) {
      debugPrint('Failed to load blocked users: $e');
      if (mounted) {
        setState(() {
          _errorMessage = friendlyErrorMessage(
              e, fallback: 'Could not load blocked users. Please try again.');
          _loading = false;
        });
      }
    }
  }

  Future<void> _unblock(UserModel user) async {
    QuickAlert.show(
      context: context,
      type: QuickAlertType.confirm,
      title: 'Unblock ${user.fullName}?',
      text: 'You will be able to send messages and calls to this user again.',
      confirmBtnText: 'Unblock',
      cancelBtnText: 'Cancel',
      confirmBtnColor: Colors.lightBlueAccent,
      showCancelBtn: true,
      backgroundColor: FcAppColors.of(context).surface,
      headerBackgroundColor: FcAppColors.of(context).surface,
      titleColor: FcAppColors.of(context).textPrimary,
      textColor: FcAppColors.of(context).textSecondary,
      onConfirmBtnTap: () async {
        Navigator.of(context, rootNavigator: true).pop();
        try {
          await BlockService.unblockUser(user.uid);
          if (mounted) {
            setState(() {
              _blockedUsers.removeWhere((u) => u.uid == user.uid);
            });
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content:
                    CustomText(text: '${user.fullName} has been unblocked'),
                backgroundColor: Colors.lightBlueAccent,
              ),
            );
          }
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: CustomText(text: 'Failed to unblock user. Try again.'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      },
    );
  }

  Future<void> _openChat(UserModel user) async {
    try {
      if (await BlockService.isBlockedPair(
          FirebaseAuth.instance.currentUser!.uid, user.uid)) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                CustomText(text: 'You cannot open this chat while blocked.'),
            backgroundColor: Colors.red,
          ),
        );
        return;
      }
      if (!mounted) return;
      Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ChatScreen(contact: user)),
      );
    } catch (e) {
      debugPrint('Error opening chat: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return Scaffold(
      backgroundColor: colors.surfaceMuted,
      appBar: AppBar(
        title: const CustomText(
          text: 'Blocked Users',
          textColor: Colors.white,
          fontWeight: FontWeight.bold,
          fontSize: 20,
        ),
        backgroundColor: Colors.lightBlueAccent,
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: _buildBody(context),
    );
  }

  Widget _buildBody(BuildContext context) {
    final colors = FcAppColors.of(context);
    if (_loading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.lightBlueAccent));
    }
    if (_errorMessage.isNotEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(20.w),
          child: CustomText(
            text: _errorMessage,
            textAlign: TextAlign.center,
            fontSize: 15.sp,
            textColor: colors.textSecondary,
          ),
        ),
      );
    }
    if (_blockedUsers.isEmpty) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(30.w),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.block, size: 80, color: colors.textWeak),
              SizedBox(height: 16.h),
              CustomText(
                text: 'No Blocked Users',
                fontSize: 20.sp,
                fontWeight: FontWeight.bold,
                textColor: colors.textSecondary,
              ),
              SizedBox(height: 8.h),
              CustomText(
                text: 'You have not blocked anyone. Users you block will '
                    'appear here so you can unblock them anytime.',
                textAlign: TextAlign.center,
                fontSize: 15.sp,
                textColor: colors.textSecondary,
              ),
            ],
          ),
        ),
      );
    }

    return StreamBuilder<DocumentSnapshot>(
      stream: FirebaseFirestore.instance
          .collection('users')
          .doc(FirebaseAuth.instance.currentUser!.uid)
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data() as Map<String, dynamic>?;
        final liveBlockedUids = snapshot.hasData
            ? List<String>.from(data?['blockedUids'] ?? const [])
            : _blockedUsers.map((u) => u.uid).toList();

        final visible = _blockedUsers
            .where((u) => liveBlockedUids.contains(u.uid))
            .where((u) => !u.isDeleted)
            .toList();

        if (visible.isEmpty) {
          return Center(
            child: CustomText(
              text: 'No Blocked Users',
              fontSize: 18.sp,
              textColor: colors.textSecondary,
            ),
          );
        }

        return ListView.builder(
          itemCount: visible.length,
          itemBuilder: (context, index) {
            final user = visible[index];
            return Card(
              margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
              elevation: 1,
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14.r),
                  side: BorderSide(color: colors.divider)),
              child: ListTile(
                leading: CircleAvatar(
                  radius: 24.r,
                  backgroundColor: colors.avatarBackground,
                  child: CustomText(
                    text: user.avatarEmoji.isNotEmpty ? user.avatarEmoji : '👤',
                    fontSize: 22.sp,
                  ),
                ),
                title: CustomText(
                  text: user.fullName,
                  fontWeight: FontWeight.w600,
                  fontSize: 15.sp,
                ),
                subtitle: CustomText(
                  text: user.phoneNumber,
                  fontSize: 13.sp,
                  textColor: colors.textSecondary,
                ),
                onTap: () => _openChat(user),
                trailing: ElevatedButton.icon(
                  onPressed: () => _unblock(user),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.lightBlueAccent,
                    elevation: 0,
                    padding:
                        EdgeInsets.symmetric(horizontal: 12.w, vertical: 8.h),
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(10.r)),
                  ),
                  icon: const Icon(Icons.lock_open,
                      size: 16, color: Colors.white),
                  label: CustomText(
                    text: 'Unblock',
                    fontSize: 13.sp,
                    textColor: Colors.white,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }
}