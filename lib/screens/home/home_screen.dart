import 'package:animate_do/animate_do.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/screens/home/contacts_screen.dart';
import 'package:flash_chat_app/screens/profile/profile_screen.dart';
import 'package:flash_chat_app/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:lottie/lottie.dart';
import '../../utils/page_transition.dart';
import 'chat_screen.dart';
import 'group_chat_screen.dart';

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

  int _currentIndex = 0; // 0: Chats, 1: Groups

  @override
  void initState() {
    super.initState();
    _loadCurrentUser();
  }

  Future<void> _loadCurrentUser() async {
    final uid = _auth.currentUser?.uid;
    if (uid != null) {
      final userDoc = await _firestore.collection('users').doc(uid).get();
      if (mounted) {
        setState(() {
          _userData = userDoc.data();
        });
      }
    }
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

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
        appBar: AppBar(
          automaticallyImplyLeading: false,
          backgroundColor: Colors.lightBlueAccent,
          elevation: 0,
          title: Row(
            children: [
              Text(
                _currentIndex == 0
                    ? 'Hello, ${_userData?['firstName'] ?? ''} 👋'
                    : 'Groups 👥',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 18.sp,
                ),
              ),
              const Spacer(),
              FadeInDown(
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(
                      context,
                      PageRouteBuilder(
                        pageBuilder: (context, animation, secondaryAnimation) => const ProfileScreen(),
                        transitionsBuilder: PageTransition.slideFromRight,
                      ),
                    );
                  },
                  child: CircleAvatar(
                    radius: 20.r,
                    backgroundColor: Colors.white,
                    child: CustomText(
                        text: _userData?['avatarEmoji'] ?? "👤",
                        fontSize: 18.sp),
                  ),
                ),
              ),
            ],
          ),
        ),
        body: currentUser == null
            ? const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent))
            : _currentIndex == 0
            ? _buildChatsOrEmpty()
            : _buildGroupsOrEmpty(),
        floatingActionButton: FloatingActionButton(
          onPressed: () {
            Navigator.push(
              context,
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) => const ContactsScreen(),
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
          unselectedItemColor: Colors.grey,
          backgroundColor: Colors.white,
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
      final bool isSelfChat = chatUids.toSet().length == 1 && chatUids.isNotEmpty && chatUids.first == currentUid;

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

    var futures = uids
        .map((uid) => _firestore.collection('users').doc(uid).get())
        .toList();
    var userDocs = await Future.wait(futures);
    Map<String, UserModel> map = {};
    for (var doc in userDocs) {
      if (doc.exists) {
        map[doc.id] = UserModel.fromFirestore(doc);
      }
    }
    return map;
  }

  Future<Map<String, Map<String, dynamic>>> _loadLastMessages(
      List<QueryDocumentSnapshot> docs, String collectionName) async {
    var futures = docs.map((doc) async {
      var q = await _firestore
          .collection(collectionName)
          .doc(doc.id)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();
      if (q.docs.isNotEmpty) {
        return {doc.id: q.docs.first.data()};
      } else {
        return {doc.id: <String, dynamic>{}};
      }
    }).toList();
    var results = await Future.wait(futures);
    var map = <String, Map<String, dynamic>>{};
    for (var res in results) {
      map.addAll(res);
    }
    return map;
  }

  Widget _buildChatsOrEmpty() {
    final currentUser = _auth.currentUser!;
    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('chats')
          .where('uids', arrayContains: currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent));
        }
        if (snapshot.hasError) {
          return Center(child: CustomText(text: "Error: ${snapshot.error}"));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        var chatDocs = snapshot.data!.docs;

        chatDocs.removeWhere((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          final hiddenFor = data?['hiddenFor'] as List<dynamic>? ?? [];
          return hiddenFor.contains(currentUser.uid);
        });

        if (chatDocs.isEmpty) {
          return _buildEmptyState();
        }

        chatDocs.sort((a, b) {
          Timestamp? aTimestamp =
          (a.data() as Map<String, dynamic>)['lastMessageTimestamp'];
          Timestamp? bTimestamp =
          (b.data() as Map<String, dynamic>)['lastMessageTimestamp'];
          if (aTimestamp == null && bTimestamp == null) return 0;
          if (aTimestamp == null) return 1;
          if (bTimestamp == null) return -1;
          return bTimestamp.compareTo(aTimestamp);
        });

        return FutureBuilder<List<dynamic>>(
          future: Future.wait([
            _loadChatUsers(chatDocs, currentUser.uid),
            _loadLastMessages(chatDocs, 'chats'),
          ]),
          builder: (context, futureSnapshot) {
            if (futureSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent));
            }
            if (futureSnapshot.hasError) {
              return Center(child: CustomText(text: "Error: ${futureSnapshot.error}"));
            }

            final userMap = futureSnapshot.data?[0] as Map<String, UserModel>? ?? {};
            final msgMap = futureSnapshot.data?[1] as Map<String, Map<String, dynamic>>? ?? {};

            return ListView.builder(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              itemCount: chatDocs.length,
              itemBuilder: (context, index) {
                final chatDoc = chatDocs[index];
                final chatData = chatDoc.data() as Map<String, dynamic>;
                final List<dynamic> uids = chatData['uids'] ?? [];

                // --- MODIFIED: Logic to detect self-chat ---
                final bool isSelfChat = uids.toSet().length == 1 && uids.isNotEmpty && uids.first == currentUser.uid;

                // --- MODIFIED: Determine the correct user ID to display ---
                // For a self-chat, it's your own ID. For others, it's the other person's ID.
                final String? contactUid = isSelfChat
                    ? currentUser.uid
                    : uids.firstWhere((uid) => uid != currentUser.uid, orElse: () => null);


                if (contactUid == null) return const SizedBox.shrink();

                final contact = userMap[contactUid];
                if (contact == null) return const SizedBox.shrink();

                final msgData = msgMap[chatDoc.id] ?? {};

                String lastMessage = "No messages yet 👀";
                String prefix = "";
                String time = "";

                if (msgData.isNotEmpty) {
                  lastMessage = msgData['text'] ?? '';
                  if (msgData['timestamp'] != null) {
                    time = DateFormat('h:mm a').format(
                        (msgData['timestamp'] as Timestamp).toDate());
                  }
                  final senderId = msgData['senderId'] ?? '';
                  if (senderId == currentUser.uid) {
                    prefix = 'You: ';
                  } else {
                    prefix = '${contact.firstName} ${contact.lastName}: ';
                  }
                }

                return FadeInUp(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w, vertical: 4.h),
                      leading: CircleAvatar(
                        radius: 26.r,
                        backgroundColor: Colors.lightBlue.shade50,
                        child: CustomText(
                            text: contact.avatarEmoji, // This will be your own avatar for a self-chat
                            fontSize: 26.sp),
                      ),
                      // --- MODIFIED: Title now shows "(You)" for self-chats ---
                      title: CustomText(
                        text: isSelfChat
                            ? '${contact.firstName} ${contact.lastName} (You)'
                            : '${contact.firstName} ${contact.lastName}',
                        fontWeight: FontWeight.bold,
                        fontSize: 16.sp,
                        textColor: Colors.black87,
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
                                  color: Colors.grey.shade700,
                                  fontSize: 14.sp,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: CustomText(
                        text: time,
                        textColor: Colors.grey.shade600,
                        fontSize: 12.sp,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => ChatScreen(contact: contact),
                            transitionsBuilder: PageTransition.slideFromRight,
                          ),
                        );
                      },
                      onLongPress: () =>
                          _showDeleteOptions(context, chatDoc.id, 'chats'),
                    ),
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

    return StreamBuilder<QuerySnapshot>(
      stream: _firestore
          .collection('groups')
          .where('memberUids', arrayContains: currentUser.uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent,));
        }
        if (snapshot.hasError) {
          return Center(child: Text("Error: ${snapshot.error}"));
        }
        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return _buildEmptyState();
        }

        var groupDocs = snapshot.data!.docs;

        groupDocs.removeWhere((doc) {
          final data = doc.data() as Map<String, dynamic>?;
          final hiddenFor = data?['hiddenFor'] as List<dynamic>? ?? [];
          return hiddenFor.contains(currentUser.uid);
        });

        if (groupDocs.isEmpty) {
          return _buildEmptyState();
        }

        groupDocs.sort((a, b) {
          Timestamp? aTimestamp =
          (a.data() as Map<String, dynamic>)['lastMessageTimestamp'];
          Timestamp? bTimestamp =
          (b.data() as Map<String, dynamic>)['lastMessageTimestamp'];
          if (aTimestamp == null && bTimestamp == null) return 0;
          if (aTimestamp == null) return 1;
          if (bTimestamp == null) return -1;
          return bTimestamp.compareTo(aTimestamp);
        });

        return FutureBuilder<Map<String, Map<String, dynamic>>>(
          future: _loadLastMessages(groupDocs, 'groups'),
          builder: (context, futureSnapshot) {
            if (futureSnapshot.connectionState == ConnectionState.waiting) {
              return const Center(child: CircularProgressIndicator(color: Colors.lightBlueAccent));
            }
            if (futureSnapshot.hasError) {
              return Center(child: CustomText(text: "Error: ${futureSnapshot.error}"));
            }

            final msgMap = futureSnapshot.data ?? {};

            return ListView.builder(
              padding: EdgeInsets.symmetric(vertical: 8.h),
              itemCount: groupDocs.length,
              itemBuilder: (context, index) {
                final group = GroupModel.fromFirestore(groupDocs[index]);

                final msgData = msgMap[group.id] ?? {};

                String lastMessage = "No messages yet 👀";
                String prefix = "";
                String time = "";

                if (msgData.isNotEmpty) {
                  lastMessage = msgData['text'] ?? '';
                  if (msgData['timestamp'] != null) {
                    time = DateFormat('h:mm a').format(
                        (msgData['timestamp'] as Timestamp).toDate());
                  }
                  final senderId = msgData['senderId'] ?? '';
                  final senderName = msgData['senderName'] ?? 'Someone';
                  if (senderId == currentUser.uid) {
                    prefix = 'You: ';
                  } else {
                    prefix = '$senderName: ';
                  }
                }

                return FadeInUp(
                  duration: const Duration(milliseconds: 300),
                  child: Container(
                    margin: EdgeInsets.symmetric(horizontal: 12.w, vertical: 6.h),
                    padding: EdgeInsets.symmetric(vertical: 8.h),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16.r),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withOpacity(0.08),
                          blurRadius: 10,
                          offset: const Offset(0, 3),
                        ),
                      ],
                    ),
                    child: ListTile(
                      contentPadding: EdgeInsets.symmetric(
                          horizontal: 16.w, vertical: 4.h),
                      leading: CircleAvatar(
                        radius: 26.r,
                        backgroundColor: Colors.lightBlue.shade50,
                        child: CustomText(
                            text: group.avatarEmoji,
                            fontSize: 26.sp),
                      ),
                      title: CustomText(
                        text: group.name,
                        fontWeight: FontWeight.bold,
                        fontSize: 16.sp,
                        textColor: Colors.black87,
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
                                  color: Colors.grey.shade700,
                                  fontSize: 14.sp,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      trailing: CustomText(
                        text: time,
                        textColor: Colors.grey.shade600,
                        fontSize: 12.sp,
                      ),
                      onTap: () {
                        Navigator.push(
                          context,
                          PageRouteBuilder(
                            pageBuilder: (context, animation, secondaryAnimation) => GroupChatScreen(group: group),
                            transitionsBuilder: PageTransition.slideFromRight,
                          ),
                        );
                      },
                      onLongPress: () =>
                          _showDeleteOptions(context, group.id, 'groups'),
                    ),
                  ),
                );
              },
            );
          },
        );
      },
    );
  }

  Widget _buildEmptyState() {
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
          CustomText(text: 'No $type Yet',
              fontSize: 22.sp,
              fontWeight: FontWeight.bold,
              textColor: Colors.grey[800]),
          SizedBox(height: 8.h),
          CustomText(
              text: 'Tap the $buttonLabel button to start a new $actionLabel 👇',
              textAlign: TextAlign.center,
              fontSize: 16.sp, textColor: Colors.grey[600]),
        ],
      ),
    );
  }

  void _showDeleteOptions(
      BuildContext context, String id, String collectionName) {
    final String type = collectionName == 'chats' ? 'Chat' : 'Group';
    final String lowerType = type.toLowerCase();
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
            color: Colors.white,
            borderRadius: BorderRadius.circular(20.r),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
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
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2.r),
                  ),
                ),
                SizedBox(height: 20.h),

                // Title
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: 20.w),
                  child: CustomText(
                    text: 'Delete $type',
                    fontSize: 18.sp,
                    fontWeight: FontWeight.bold,
                    textColor: Colors.black87,
                  ),
                ),
                SizedBox(height: 16.h),

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
                                textColor: Colors.black87,
                              ),
                              SizedBox(height: 4.h),
                              CustomText(
                                text: 'Delete this $lowerType from your list',
                                fontSize: 13.sp,
                                textColor: Colors.grey.shade600,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Colors.grey.shade400,
                          size: 20.sp,
                        ),
                      ],
                    ),
                  ),
                ),

                Divider(
                    height: 1.h, thickness: 1, indent: 70.w, endIndent: 20.w),

                // Delete for everyone option
                InkWell(
                  onTap: () {
                    Navigator.pop(ctx);
                    _showConfirmDeleteEveryoneDialog(
                        context, id, collectionName);
                  },
                  child: Container(
                    padding:
                    EdgeInsets.symmetric(horizontal: 20.w, vertical: 16.h),
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
                                textColor: Colors.black87,
                              ),
                              SizedBox(height: 4.h),
                              CustomText(
                                text: 'Remove $lowerType and messages permanently',
                                fontSize: 13.sp,
                                textColor: Colors.grey.shade600,
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.chevron_right,
                          color: Colors.grey.shade400,
                          size: 20.sp,
                        ),
                      ],
                    ),
                  ),
                ),

                SizedBox(height: 12.h),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _deleteForCurrentUser(
      String id, String collectionName) async {
    final String type = collectionName == 'chats' ? 'Chat' : 'Group';
    final String lowerType = type.toLowerCase();
    final currentUser = _auth.currentUser!;
    try {
      await _firestore.collection(collectionName).doc(id).update({
        'hiddenFor': FieldValue.arrayUnion([currentUser.uid]),
      });

      // Show success message
      if (context.mounted) {
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r)),
            margin: EdgeInsets.all(16.w),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }

  void _showConfirmDeleteEveryoneDialog(
      BuildContext context, String id, String collectionName) {
    final String type = collectionName == 'chats' ? 'Chat' : 'Group';
    final String lowerType = type.toLowerCase();
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20.r)),
        elevation: 8,
        child: Container(
          padding: EdgeInsets.all(24.w),
          decoration: BoxDecoration(
            color: Colors.white,
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
                textColor: Colors.black87,
              ),
              SizedBox(height: 12.h),

              // Description
              Text(
                'This will permanently delete the $lowerType and all messages for everyone. This action cannot be undone.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontSize: 14.sp,
                  color: Colors.grey.shade700,
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
                        side: BorderSide(color: Colors.grey.shade300, width: 1.5),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12.r),
                        ),
                      ),
                      child: CustomText(
                        text: 'Cancel',
                        textColor: Colors.black87,
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

  Future<void> _deleteForEveryone(
      String id, String collectionName) async {
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
      if (context.mounted) {
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r)),
            margin: EdgeInsets.all(16.w),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      if (context.mounted) {
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
            shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10.r)),
            margin: EdgeInsets.all(16.w),
          ),
        );
      }
    }
  }
}