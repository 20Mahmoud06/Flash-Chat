import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/features/groups/models/group_model.dart';
import 'package:flash_chat_app/features/chat/models/message_model.dart';
import 'package:flash_chat_app/features/profile/models/user_model.dart';
import 'package:flash_chat_app/services/connectivity/connectivity_service.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';

import '../widgets/media_gallery/media_gallery_helpers.dart';
import '../widgets/media_gallery/media_gallery_links_tab.dart';
import '../widgets/media_gallery/media_gallery_photos_tab.dart';
import '../widgets/media_gallery/media_gallery_voice_tab.dart';
import '../widgets/media_gallery/media_gallery_videos_tab.dart';

/// WhatsApp-style "Media, Links and Voice" gallery for a chat (one-on-one
/// or group). Tabbed view: Photos (grid), Videos (grid with posters), Voice
/// messages (playable, showing who sent them) and Links (tappable URLs).
class MediaGalleryScreen extends StatefulWidget {
  final UserModel? contact;
  final GroupModel? group;
  final String chatId;
  final int initialTab;

  bool get _isGroup => group != null;

  const MediaGalleryScreen({
    super.key,
    required this.chatId,
    this.contact,
    this.group,
    this.initialTab = 0,
  }) : assert(contact != null || group != null,
            'Either a contact or a group must be provided');

  @override
  State<MediaGalleryScreen> createState() => _MediaGalleryScreenState();
}

class _MediaGalleryScreenState extends State<MediaGalleryScreen> {
  late final String _myUid = FirebaseAuth.instance.currentUser!.uid;
  UserModel? _myUser;
  Map<String, UserModel> _groupMembers = {};

  bool get _isGroup => widget._isGroup;

  Stream<QuerySnapshot<Map<String, dynamic>>> get _messagesStream =>
      FirebaseFirestore.instance
          .collection(_isGroup ? 'groups' : 'chats')
          .doc(widget.chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .snapshots();

  GallerySender get _sender => GallerySender(
        myUid: _myUid,
        isGroup: _isGroup,
        contact: widget.contact,
        myUser: _myUser,
        groupMembers: _groupMembers,
      );

  @override
  void initState() {
    super.initState();
    _loadMyUser();
    if (_isGroup) {
      _loadGroupMembers(widget.group!.memberUids);
    }
  }

  Future<void> _loadGroupMembers(List<String> uids) async {
    try {
      final chunks = <List<String>>[];
      for (int i = 0; i < uids.length; i += 30) {
        final end = i + 30 < uids.length ? i + 30 : uids.length;
        chunks.add(uids.sublist(i, end));
      }
      if (chunks.isEmpty) return;

      final snapshots = await Future.wait(chunks.map(
        (chunk) => FirebaseFirestore.instance
            .collection('users')
            .where(FieldPath.documentId, whereIn: chunk)
            .get(),
      ));

      if (!mounted) return;
      final members = <String, UserModel>{};
      for (final snapshot in snapshots) {
        for (final doc in snapshot.docs) {
          members[doc.id] = UserModel.fromFirestore(doc);
        }
      }
      setState(() => _groupMembers = members);
    } catch (e) {
      debugPrint('Failed to load group members: $e');
    }
  }

  Future<void> _loadMyUser() async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('users')
          .doc(_myUid)
          .get();
      if (doc.exists && mounted) {
        setState(() => _myUser = UserModel.fromFirestore(doc));
      }
    } catch (_) {}
  }

  bool _isViewerVisible(MessageModel m) {
    if (!_isGroup) return true;
    final group = widget.group;
    if (group == null) return true;
    final join = group.memberJoinTimestamps[_myUid];
    final leave = group.memberLeaveTimestamps[_myUid];
    final ms = m.timestamp.millisecondsSinceEpoch;
    if (join != null && ms < join.millisecondsSinceEpoch) return false;
    if (leave != null && ms > leave.millisecondsSinceEpoch) return false;
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final colors = FcAppColors.of(context);
    return DefaultTabController(
      initialIndex: widget.initialTab.clamp(0, 3),
      length: 4,
      child: Scaffold(
        backgroundColor: colors.surface,
        appBar: AppBar(
          backgroundColor: Colors.lightBlueAccent,
          iconTheme: const IconThemeData(color: Colors.white),
          title: const CustomText(
            text: 'Media, Links and Voice',
            textColor: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
          centerTitle: true,
          bottom: const TabBar(
            labelColor: Colors.white,
            unselectedLabelColor: Colors.white70,
            indicatorColor: Colors.white,
            indicatorWeight: 3,
            labelStyle: TextStyle(fontWeight: FontWeight.w600, fontSize: 13),
            unselectedLabelStyle: TextStyle(fontSize: 13),
            tabs: [
              Tab(text: 'Photos'),
              Tab(text: 'Videos'),
              Tab(text: 'Voice'),
              Tab(text: 'Links'),
            ],
          ),
        ),
        body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: _messagesStream,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              final offline = !ConnectivityService.instance.isConnected.value;
              return Center(
                child: Padding(
                  padding: EdgeInsets.all(24.w),
                  child: CustomText(
                    text: offline
                        ? 'No saved media to read offline yet.'
                        : 'Could not load media',
                    fontSize: 14.sp,
                    textAlign: TextAlign.center,
                  ),
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Center(
                child: CircularProgressIndicator(color: Colors.lightBlueAccent),
              );
            }
            final docs = snapshot.data!.docs
                .where((d) => d.data()['isDeleted'] != true)
                .map((d) => MessageModel.fromFirestore(d))
                .where(_isViewerVisible)
                .toList();
            return TabBarView(
              children: [
                MediaGalleryPhotosTab(messages: docs),
                MediaGalleryVideosTab(messages: docs),
                MediaGalleryVoiceTab(messages: docs, sender: _sender),
                MediaGalleryLinksTab(messages: docs, sender: _sender),
              ],
            );
          },
        ),
      ),
    );
  }
}