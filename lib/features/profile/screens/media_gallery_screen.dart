import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/core/theme/app_theme.dart';
import 'package:flash_chat_app/core/utils/full_image_viewer.dart';
import 'package:flash_chat_app/core/utils/full_video_viewer.dart';
import 'package:flash_chat_app/core/utils/video_playback_url.dart';
import 'package:flash_chat_app/models/group_model.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/services/connectivity/connectivity_service.dart';
import 'package:flash_chat_app/shared/widgets/custom_text.dart';
import 'package:flash_chat_app/shared/widgets/voice_message_player.dart';
import 'package:flutter/material.dart';
import 'package:flutter_screenutil/flutter_screenutil.dart';
import 'package:intl/intl.dart';
import 'package:url_launcher/url_launcher.dart';

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
  static final _urlRegExp = RegExp(r'''(https?://|www\.)[^\s<>"']+''');
  static final _trailingPunct = RegExp(r'[.,;:!?)]+$');

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
      // Firestore allows at most 30 uids per whereIn query, so large groups
      // are fetched in parallel chunks.
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

  /// Mirrors the chat's membership-window filtering: a group member sees only
  /// media sent while they were a member (a newly-added member can't see
  /// pre-join media; a removed/left member can't see post-leave media).
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
                _buildPhotosTab(docs),
                _buildVideosTab(docs),
                _buildVoiceTab(docs),
                _buildLinksTab(docs),
              ],
            );
          },
        ),
      ),
    );
  }

  // ---------------------------------------------------------------
  // PHOTOS — every image of every multi-photo message as its own tile
  // ---------------------------------------------------------------
  Widget _buildPhotosTab(List<MessageModel> messages) {
    final items = <({String url, MessageModel message, int mediaIndex})>[];
    for (final msg
        in messages.where((m) => m.messageType == MessageType.image)) {
      final urls = msg.mediaUrls ?? const [];
      for (var i = 0; i < urls.length; i++) {
        items.add((url: urls[i], message: msg, mediaIndex: i));
      }
    }
    if (items.isEmpty) {
      return _emptyState('No photos', Icons.photo_library_outlined);
    }
    return GridView.builder(
      padding: EdgeInsets.all(2.w),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: items.length,
      itemBuilder: (context, i) {
        final item = items[i];
        return GestureDetector(
          onTap: () => _openImage(item.url, item.message.id, item.mediaIndex),
          child: Image.network(
            item.url,
            fit: BoxFit.cover,
            loadingBuilder: (context, child, progress) => progress == null
                ? child
                : Container(
                    color: Colors.black12,
                    child: const Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.lightBlueAccent,
                        ),
                      ),
                    ),
                  ),
            errorBuilder: (context, error, stackTrace) => Container(
              color: Colors.black12,
              child: const Icon(Icons.broken_image_outlined,
                  color: Colors.grey, size: 28),
            ),
          ),
        );
      },
    );
  }

  void _openImage(String url, String messageId, int mediaIndex) {
    showDialog(
      context: context,
      barrierColor: Colors.transparent,
      builder: (_) => FullImageViewer(
        imageUrl: url,
        heroTag: 'media_gallery_${messageId}_$mediaIndex',
      ),
    );
  }

  // ---------------------------------------------------------------
  // VIDEOS — Cloudinary poster frames with a play overlay
  // ---------------------------------------------------------------
  Widget _buildVideosTab(List<MessageModel> messages) {
    final videos = messages
        .where((m) => m.messageType == MessageType.video && m.mediaUrls != null)
        .toList();
    if (videos.isEmpty) {
      return _emptyState('No videos', Icons.videocam_outlined);
    }
    return GridView.builder(
      padding: EdgeInsets.all(2.w),
      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 3,
        mainAxisSpacing: 2,
        crossAxisSpacing: 2,
      ),
      itemCount: videos.length,
      itemBuilder: (context, i) {
        final video = videos[i];
        final url = video.mediaUrls!.first;
        // The whole tile is tappable: keeping the GestureDetector on top of
        // the Stack so the play icon overlay can't swallow taps.
        return GestureDetector(
          onTap: () => _openVideo(url),
          child: Stack(
            fit: StackFit.expand,
            children: [
              Image.network(
                videoThumbnailUrl(url),
                fit: BoxFit.cover,
                loadingBuilder: (context, child, progress) => progress == null
                    ? child
                    : Container(
                        color: Colors.black26,
                        child: const Center(
                          child: SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(
                              strokeWidth: 2,
                              color: Colors.lightBlueAccent,
                            ),
                          ),
                        ),
                      ),
                errorBuilder: (context, error, stackTrace) => Container(
                  color: Colors.black38,
                  child: const Center(
                    child: Icon(Icons.videocam_outlined,
                        color: Colors.white70, size: 30),
                  ),
                ),
              ),
              const Center(
                child:
                    Icon(Icons.play_circle_fill, color: Colors.white, size: 40),
              ),
              if (video.videoDuration != null)
                Positioned(
                  right: 4,
                  bottom: 4,
                  child: Container(
                    padding:
                        EdgeInsets.symmetric(horizontal: 6.w, vertical: 2.h),
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      borderRadius: BorderRadius.circular(6.r),
                    ),
                    child: Text(
                      _formatDuration(video.videoDuration!),
                      style: const TextStyle(color: Colors.white, fontSize: 11),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  void _openVideo(String url) {
    Navigator.push(
      context,
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) => FullVideoViewer(videoUrl: url),
      ),
    );
  }

  String _formatDuration(int seconds) {
    final d = Duration(seconds: seconds);
    final m = d.inMinutes.toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  String _senderNameOf(MessageModel message) {
    if (message.senderId == _myUid) return 'You';
    if (_isGroup) {
      final sender = _groupMembers[message.senderId];
      return sender != null ? sender.fullName : 'Unknown';
    }
    return widget.contact!.fullName;
  }

  String _senderEmojiOf(MessageModel message) {
    if (message.senderId == _myUid) return _myUser?.avatarEmoji ?? '👤';
    if (_isGroup) return _groupMembers[message.senderId]?.avatarEmoji ?? '👤';
    return widget.contact!.avatarEmoji;
  }

  // ---------------------------------------------------------------
  // VOICE — playable, mirroring the chat voice bubbles: my messages sit
  // on the right with the mine-bubble palette, received ones on the left
  // with the incoming palette. All controls (play, waveform seek, time,
  // speed) are the same as in the chat.
  // ---------------------------------------------------------------
  Widget _buildVoiceTab(List<MessageModel> messages) {
    final voiceMessages = messages
        .where((m) => m.messageType == MessageType.voice && m.mediaUrls != null)
        .toList();
    if (voiceMessages.isEmpty) {
      return _emptyState('No voice messages', Icons.mic_none);
    }
    return ListView.separated(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      itemCount: voiceMessages.length,
      separatorBuilder: (context, i) => Divider(
        height: 16.h,
        thickness: 1.5,
        color: FcAppColors.of(context).divider,
      ),
      itemBuilder: (context, i) {
        final colors = FcAppColors.of(context);
        final msg = voiceMessages[i];
        final isMe = msg.senderId == _myUid;
        final senderEmoji = _senderEmojiOf(msg);
        final senderName = _senderNameOf(msg);

        // Exactly the palettes used by the chat bubble:
        // mine = white content on the light-blue bubble,
        // received = blue player on the surface card.
        final Color textColor =
            isMe ? colors.bubbleMineText : colors.textPrimary;
        final Color timeColor = isMe
            ? colors.bubbleMineText.withValues(alpha: 0.75)
            : colors.textWeak;
        final Color playedColor =
            isMe ? colors.bubbleMineText : Colors.lightBlueAccent.shade700;
        final Color idleColor = (isMe ? colors.bubbleMineText : Colors.blueGrey)
            .withValues(alpha: 0.35);

        final avatar = CircleAvatar(
          radius: 18.r,
          backgroundColor: colors.avatarBackground,
          child: CustomText(text: senderEmoji, fontSize: 16.sp),
        );
        final info = Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: CustomText(
                      text: senderName,
                      fontSize: 13.sp,
                      fontWeight: FontWeight.w600,
                      textColor: textColor,
                    ),
                  ),
                  CustomText(
                    text: _formatTime(msg.timestamp),
                    fontSize: 11.sp,
                    textColor: timeColor,
                  ),
                ],
              ),
              SizedBox(height: 6.h),
              VoiceMessagePlayer(
                audioUrl: msg.mediaUrls!.first,
                initialDuration: msg.voiceDuration != null
                    ? Duration(seconds: msg.voiceDuration!)
                    : null,
                playedColor: playedColor,
                idleColor: idleColor,
                textColor: textColor,
              ),
            ],
          ),
        );
        // Pin the card to the same side the chat would use: my own voice
        // messages sit on the right, received ones on the left — just like
        // the regular chat bubbles — instead of stretching the full width.
        final maxCardWidth = MediaQuery.of(context).size.width * 0.82;
        return Align(
          alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: maxCardWidth),
            child: Card(
              elevation: 1,
              margin: EdgeInsets.only(bottom: 10.h),
              color: isMe ? colors.bubbleMine : colors.surface,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(14.r),
                side:
                    isMe ? BorderSide.none : BorderSide(color: colors.divider),
              ),
              child: Padding(
                padding: EdgeInsets.symmetric(vertical: 10.h, horizontal: 12.w),
                child: isMe
                    ? Row(
                        mainAxisAlignment: MainAxisAlignment.end,
                        children: [info, SizedBox(width: 10.w), avatar],
                      )
                    : Row(
                        children: [avatar, SizedBox(width: 10.w), info],
                      ),
              ),
            ),
          ),
        );
      },
    );
  }

  // ---------------------------------------------------------------
  // LINKS — text messages containing URLs
  // ---------------------------------------------------------------
  Widget _buildLinksTab(List<MessageModel> messages) {
    final links = messages
        .where((m) => m.messageType == MessageType.text)
        .map((m) {
          final match = _urlRegExp.firstMatch(m.text);
          if (match == null) return null;
          final raw = match.group(0)!.replaceAll(_trailingPunct, '');
          return (message: m, url: raw);
        })
        .whereType<({MessageModel message, String url})>()
        .toList();
    if (links.isEmpty) return _emptyState('No links', Icons.link);
    return ListView.builder(
      padding: EdgeInsets.symmetric(horizontal: 16.w, vertical: 12.h),
      itemCount: links.length,
      itemBuilder: (context, i) {
        final item = links[i];
        final msg = item.message;
        final uri = Uri.tryParse(item.url);
        final host = uri != null && uri.hasScheme
            ? uri.host
            : Uri.tryParse('https://${item.url}')?.host ?? item.url;
        return Card(
          elevation: 1,
          margin: EdgeInsets.only(bottom: 10.h),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14.r),
            side: BorderSide(color: FcAppColors.of(context).divider),
          ),
          child: ListTile(
            contentPadding:
                EdgeInsets.symmetric(horizontal: 14.w, vertical: 4.h),
            leading: CircleAvatar(
              backgroundColor: Colors.lightBlueAccent.withValues(alpha: 0.15),
              child: const Icon(Icons.link, color: Colors.lightBlueAccent),
            ),
            title: CustomText(
              text: host,
              fontSize: 15.sp,
              fontWeight: FontWeight.w600,
              textColor: FcAppColors.of(context).textPrimary,
            ),
            subtitle: Padding(
              padding: EdgeInsets.only(top: 2.h),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CustomText(
                    text: item.url,
                    fontSize: 13.sp,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textColor: FcAppColors.of(context).textSecondary,
                  ),
                  SizedBox(height: 2.h),
                  CustomText(
                    text:
                        '${_senderNameOf(msg)} · ${_formatTime(msg.timestamp)}',
                    fontSize: 11.sp,
                    textColor: FcAppColors.of(context).textWeak,
                  ),
                ],
              ),
            ),
            isThreeLine: true,
            trailing: const Icon(Icons.open_in_new,
                size: 18, color: Colors.lightBlueAccent),
            onTap: () => _openLink(item.url),
          ),
        );
      },
    );
  }

  Future<void> _openLink(String url) async {
    var uri = Uri.tryParse(url);
    if (uri == null || !uri.hasScheme) {
      uri = Uri.parse('https://$url');
    }
    try {
      final launched =
          await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!launched) debugPrint('Failed to launch URL: $url');
    } catch (e) {
      debugPrint('Error launching URL $url: $e');
    }
  }

  // ---------------------------------------------------------------
  String _formatTime(Timestamp timestamp) {
    return DateFormat('d MMM, h:mm a').format(timestamp.toDate());
  }

  Widget _emptyState(String label, IconData icon) {
    final colors = FcAppColors.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: colors.textWeak),
          SizedBox(height: 12.h),
          CustomText(
            text: label,
            fontSize: 15.sp,
            textColor: colors.textSecondary,
          ),
        ],
      ),
    );
  }
}
