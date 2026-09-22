import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import '../../../core/utils/page_transition.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../chat/screens/chat_screen.dart';
import '../../contacts/screens/contacts_screen.dart';
import '../../groups/screens/group_chat_screen.dart';
import '../../profile/screens/profile_screen.dart';
import '../../sender_profile/screens/sender_profile_screen.dart';
import '../cubit/home_cubit.dart';
import '../cubit/home_state.dart';
import '../widgets/home_chat_list_tile.dart';
import '../widgets/home_delete_actions.dart';
import '../widgets/home_delete_dialogs.dart';
import '../widgets/home_empty_state.dart';
import '../widgets/home_tile_sheets.dart';

/// The Home tab (chats + groups). All data logic lives in [HomeCubit]; this
/// widget only renders [HomeState] and forwards user actions to the cubit.
class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeCubit _homeCubit;
  DateTime? _lastBackPressed;

  int _currentIndex = 0; // 0: Chats, 1: Groups

  @override
  void initState() {
    super.initState();
    _homeCubit = HomeCubit();
  }

  @override
  void dispose() {
    _homeCubit.close();
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

  void _showPinLimitSnackBar(BuildContext context) {
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: CustomText(text: 'You can pin up to 3 chats'),
        backgroundColor: Colors.lightBlueAccent,
        behavior: SnackBarBehavior.floating,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
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
      child: BlocProvider<HomeCubit>.value(
        value: _homeCubit,
        child: BlocBuilder<HomeCubit, HomeState>(
          builder: (context, state) {
            final currentUser = FirebaseAuth.instance.currentUser;
            return Scaffold(
              appBar: AppBar(
                automaticallyImplyLeading: false,
                backgroundColor: Colors.lightBlueAccent,
                elevation: 0,
                title: CustomText(
                  text: _currentIndex == 0
                      ? 'Hello, ${state.firstName ?? ''} 👋'
                      : 'Groups 👥',
                  textColor: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18.sp,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
                                pageBuilder:
                                    (context, animation, secondaryAnimation) =>
                                        const ProfileScreen(),
                                transitionsBuilder: PageTransition.slideFromRight,
                              ),
                            );
                          },
                          child: CircleAvatar(
                            radius: 20.r,
                            backgroundColor: colors.surface,
                            child: CustomText(
                                text: state.avatarEmoji ?? "👤",
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
                      child:
                          CircularProgressIndicator(color: Colors.lightBlueAccent))
                  : _currentIndex == 0
                      ? _buildChatsOrEmpty(context, state, currentUser)
                      : _buildGroupsOrEmpty(context, state, currentUser),
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
                  if (index == _currentIndex) return;
                  setState(() {
                    _currentIndex = index;
                  });
                  _homeCubit.setTab(index);
                },
                items: const [
                  BottomNavigationBarItem(
                      icon: Icon(Icons.chat_bubble_outline), label: "Chats"),
                  BottomNavigationBarItem(
                      icon: Icon(Icons.groups_outlined), label: "Groups"),
                ],
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildChatsOrEmpty(
      BuildContext context, HomeState state, User currentUser) {
    if (state.chatsLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.lightBlueAccent));
    }
    if (state.chatsError != null) {
      return HomeOfflineOrError(
          error: state.chatsError!, thing: 'chats');
    }
    if (state.chats.isEmpty) {
      return const HomeEmptyState(
          type: 'Chats', buttonLabel: 'message', actionLabel: 'chat');
    }

    final cubit = context.read<HomeCubit>();

    // Only show the full-screen spinner on the very first contact load;
    // afterwards the cached users power the list until the new batch lands.
    if (state.chatUsersLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.lightBlueAccent),
      );
    }
    if (state.chatUsersError != null) {
      return HomeOfflineOrError(
          error: state.chatUsersError!, thing: 'contact details');
    }

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      itemCount: state.chats.length,
      itemBuilder: (context, index) {
        final tile = state.chats[index];

        return HomeChatListTile(
          key: ValueKey(tile.chatDocId),
          chatDocId: tile.chatDocId,
          collectionName: 'chats',
          avatar: tile.avatar,
          title: tile.isSelfChat ? '${tile.displayName} (You)' : tile.displayName,
          prefixName: tile.displayName,
          isGroup: false,
          isSelfChat: tile.isSelfChat,
          currentUid: currentUser.uid,
          unreadCount: tile.unreadCount,
          isBlocked: tile.isBlocked,
          isDeleted: tile.isDeleted,
          isNewChat: tile.isNewChat,
          isPinned: tile.isPinned,
          onTap: () {
            if (tile.isDeleted) {
              // Show profile for deleted accounts
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      SenderProfileScreen(user: tile.contact),
                  transitionsBuilder: PageTransition.slideFromRight,
                ),
              ).then((_) => cubit.refreshMyUser());
            } else {
              Navigator.push(
                context,
                PageRouteBuilder(
                  pageBuilder: (context, animation, secondaryAnimation) =>
                      ChatScreen(contact: tile.contact),
                  transitionsBuilder: PageTransition.slideFromRight,
                ),
              ).then((_) => cubit.refreshMyUser());
            }
          },
          onLongPress: () => showHomeChatOptionsSheet(
            context: context,
            type: 'Chat',
            lowerType: 'chat',
            isPinned: tile.isPinned,
            isSelfChat: tile.isSelfChat,
            onTogglePin: () {
              if (tile.isPinned) {
                cubit.unpinChat(tile.pinId);
              } else if (cubit.state.pinnedChatIds.length >= 3) {
                _showPinLimitSnackBar(context);
              } else {
                cubit.pinChat(tile.pinId);
              }
            },
            onDeleteForMe: () => hideConversationForCurrentUser(
              firestore: FirebaseFirestore.instance,
              myUid: currentUser.uid,
              id: tile.actionChatId,
              collectionName: 'chats',
              context: context,
            ),
            onDeleteForEveryone: () => showConfirmDeleteEveryoneDialog(
              context,
              type: 'Chat',
              lowerType: 'chat',
              onConfirm: () => deleteConversationForEveryone(
                firestore: FirebaseFirestore.instance,
                id: tile.actionChatId,
                collectionName: 'chats',
                context: context,
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildGroupsOrEmpty(
      BuildContext context, HomeState state, User currentUser) {
    if (state.groupsLoading) {
      return const Center(
        child: CircularProgressIndicator(color: Colors.lightBlueAccent),
      );
    }
    if (state.groupsError != null) {
      return HomeOfflineOrError(
          error: state.groupsError!, thing: 'groups');
    }
    if (state.groups.isEmpty) {
      return const HomeEmptyState(
          type: 'Groups', buttonLabel: 'add group', actionLabel: 'group');
    }

    final cubit = context.read<HomeCubit>();

    return ListView.builder(
      padding: EdgeInsets.symmetric(vertical: 8.h),
      itemCount: state.groups.length,
      itemBuilder: (context, index) {
        final tile = state.groups[index];
        final group = tile.group;

        return HomeChatListTile(
          key: ValueKey(group.id),
          chatDocId: group.id,
          collectionName: 'groups',
          avatar: group.avatarEmoji,
          title: group.name,
          prefixName: group.name,
          isGroup: true,
          isSelfChat: false,
          currentUid: currentUser.uid,
          unreadCount: tile.unreadCount,
          groupLastSeenAt: tile.lastSeenAt,
          isPinned: tile.isPinned,
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
          onLongPress: () => showHomeGroupOptionsSheet(
            context: context,
            groupId: group.id,
            groupName: group.name,
            isPinned: tile.isPinned,
            isCreator: group.createdBy == currentUser.uid,
            isAdmin: group.adminUids.contains(currentUser.uid),
            isDeleted: group.isDeleted,
            onTogglePin: () {
              if (tile.isPinned) {
                cubit.unpinChat(group.id);
              } else if (cubit.state.pinnedChatIds.length >= 3) {
                _showPinLimitSnackBar(context);
              } else {
                cubit.pinChat(group.id);
              }
            },
            onDeleteForMe: () => hideConversationForCurrentUser(
              firestore: FirebaseFirestore.instance,
              myUid: currentUser.uid,
              id: group.id,
              collectionName: 'groups',
              context: context,
            ),
            onDeleteGroup: () => showConfirmDeleteGroupDialog(
              context,
              onConfirm: () => softDeleteGroupForEveryone(
                firestore: FirebaseFirestore.instance,
                myUid: currentUser.uid,
                group: group,
                context: context,
              ),
            ),
          ),
        );
      },
    );
  }
}