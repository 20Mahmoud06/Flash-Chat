import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import '../../../core/utils/page_transition.dart';
import '../../../shared/widgets/custom_text.dart';
import '../../chat/screens/chat_screen.dart';
import '../../groups/screens/create_group_screen.dart';
import '../../profile/models/user_model.dart' show UserModel;
import '../../sender_profile/screens/sender_profile_screen.dart';
import '../cubit/contacts_cubit.dart';
import '../cubit/contacts_state.dart';
import '../widgets/contacts_list_tile.dart';

class ContactsScreen extends StatefulWidget {
  const ContactsScreen({super.key});

  @override
  State<ContactsScreen> createState() => _ContactsScreenState();
}

class _ContactsScreenState extends State<ContactsScreen> {
  late final ContactsCubit _cubit;

  final TextEditingController _searchController = TextEditingController();
  final FocusNode _searchFocusNode = FocusNode();

  @override
  void initState() {
    super.initState();
    _cubit = ContactsCubit();
  }

  @override
  void dispose() {
    _cubit.close();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onContactTapped(UserModel user) {
    final cubitState = _cubit.state;
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (cubitState.isSelectionMode) {
      _cubit.toggleSelectContact(user);
    } else if (user.uid != currentUid &&
        (user.isDeleted || _cubit.isBlockedContact(user))) {
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

  void _onContactLongPressed(UserModel user) {
    final currentUid = FirebaseAuth.instance.currentUser!.uid;
    if (user.uid == currentUid) return;
    if (!_cubit.state.isSelectionMode) {
      _cubit.startSelection(user);
    }
  }

  @override
  Widget build(BuildContext context) {
    return BlocProvider<ContactsCubit>.value(
      value: _cubit,
      child: BlocBuilder<ContactsCubit, ContactsState>(
        builder: (context, state) {
          return GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Scaffold(
              appBar: AppBar(
                leading: state.isSelectionMode
                    ? IconButton(
                        icon: const Icon(Icons.close),
                        onPressed: () => _cubit.clearSelection(),
                      )
                    : null,
                title: CustomText(
                    text: state.isSelectionMode
                        ? '${state.selectedContacts.length} selected'
                        : 'New Chat'),
                titleTextStyle: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 20),
                centerTitle: false,
                backgroundColor: Colors.lightBlueAccent,
                elevation: 1,
                iconTheme: const IconThemeData(
                  color: Colors.white,
                ),
              ),
              body: _buildBody(context, state),
              floatingActionButton:
                  state.isSelectionMode && state.selectedContacts.isNotEmpty
                      ? FloatingActionButton(
                          backgroundColor: Colors.lightBlueAccent,
                          onPressed: () {
                            Navigator.push(
                              context,
                              PageRouteBuilder(
                                pageBuilder:
                                    (context, animation, secondaryAnimation) =>
                                        CreateGroupScreen(
                                  initialMembers:
                                      state.selectedContacts.toList(),
                                ),
                                transitionsBuilder: PageTransition.slideFromRight,
                              ),
                            );
                          },
                          child: const Icon(Icons.arrow_forward,
                              color: Colors.white),
                        )
                      : null,
            ),
          );
        },
      ),
    );
  }

  Widget _buildBody(BuildContext context, ContactsState state) {
    final colors = FcAppColors.of(context);
    final cubit = context.read<ContactsCubit>();
    if (state.isLoading) {
      return const Center(
          child: CircularProgressIndicator(color: Colors.lightBlueAccent));
    }
    if (state.errorMessage.isNotEmpty) {
      return Center(
          child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: CustomText(
            text: state.errorMessage,
            textAlign: TextAlign.center,
            fontSize: 16.sp,
            textColor: colors.textSecondary),
      ));
    }
    if (state.contacts.isEmpty) {
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

    final filtered = cubit.filteredContacts;

    return Column(
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(16.w, 12.h, 16.w, 8.h),
          child: TextField(
            controller: _searchController,
            focusNode: _searchFocusNode,
            onChanged: (v) => cubit.updateSearchQuery(v),
            style: TextStyle(color: colors.textPrimary, fontSize: 16.sp),
            cursorColor: Colors.lightBlueAccent,
            decoration: InputDecoration(
              hintText: 'Search by name or number',
              hintStyle: TextStyle(color: colors.textWeak, fontSize: 16.sp),
              prefixIcon: Icon(Icons.search, color: colors.textWeak),
              suffixIcon: state.searchQuery.isNotEmpty
                  ? IconButton(
                      icon: Icon(Icons.close, color: colors.textWeak),
                      onPressed: () {
                        _searchController.clear();
                        cubit.updateSearchQuery('');
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
                    text: 'No contacts match "${state.searchQuery}"',
                    textColor: colors.textWeak,
                    fontSize: 16.sp,
                  ),
                )
              : _buildContactList(context, state, filtered),
        ),
      ],
    );
  }

  Widget _buildContactList(
      BuildContext context, ContactsState state, List<UserModel> contacts) {
    final cubit = context.read<ContactsCubit>();
    final currentUid = FirebaseAuth.instance.currentUser?.uid;
    final isMine =
        state.contacts.isNotEmpty && state.contacts.first.uid == currentUid;
    final myNicknames =
        isMine ? state.contacts.first.nicknames : const <String, String>{};

    return ListView.builder(
      padding: EdgeInsets.only(bottom: 80.h),
      itemCount: contacts.length,
      itemBuilder: (context, index) {
        final user = contacts[index];
        final isCurrentUser = user.uid == currentUid;

        return ContactsListTile(
          user: user,
          isCurrentUser: isCurrentUser,
          isSelected: state.selectedContacts.contains(user),
          isBlocked: !isCurrentUser && cubit.isBlockedContact(user),
          isDeleted: user.isDeleted,
          isMine: isMine,
          myNicknames: myNicknames,
          onTap: () => _onContactTapped(user),
          onLongPress: () => _onContactLongPressed(user),
        );
      },
    );
  }
}