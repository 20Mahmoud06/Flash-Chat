import 'dart:async';
import 'dart:io';
import 'package:bloc/bloc.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flash_chat_app/features/chat/cubit/chat_state.dart';
import 'package:flutter/foundation.dart';
import 'package:flash_chat_app/models/message_model.dart';
import 'package:flash_chat_app/models/user_model.dart';
import 'package:flash_chat_app/services/fcm/fcm_v1_sender.dart';
import 'package:flash_chat_app/services/hms/hms_v1_sender.dart';
import 'package:flash_chat_app/services/mute/mute_service.dart';
import 'package:flash_chat_app/services/connectivity/connectivity_service.dart';
import '../../../services/block/block_service.dart';
import '../../../services/media/cloudinary_service.dart';
import '../../../config/cloudinary_config.dart';
import '../../../core/utils/reply_preview.dart';
import '../../../core/utils/video_playback_url.dart';
import '../../../services/offline_queue/offline_queue_service.dart';

class _PendingSend {
  final String label;

  /// Local-only id of the placeholder bubble shown while this message is
  /// queued (removed once the real send goes through).
  final String localId;

  /// WhatsApp-style pending bubble ("clock" instead of a tick) rendered in
  /// the chat while the message waits for a connection.
  final MessageModel placeholder;

  final Future<void> Function() action;

  /// Persistent metadata for disk serialization. Populated when the message
  /// is queued; used to reload the queue after an app restart.
  final PendingMessage persistentData;

  _PendingSend({
    required this.label,
    required this.localId,
    required this.placeholder,
    required this.action,
    required this.persistentData,
  });
}

class ChatCubit extends Cubit<ChatState> {
  /// Pending (offline) sends are kept per-chat so they survive leaving the
  /// chat screen and are flushed automatically as soon as we are online.
  static final Map<String, List<_PendingSend>> _pendingByChat = {};
  static final Map<String, bool> _flushingChats = {};

  /// Counter for unique local (pending) message ids.
  static int _localIdSeq = 0;

  final String chatId;
  final bool isGroupChat;
  final String? recipientId;
  final UserModel? recipient;
  DocumentSnapshot? _lastMessageDoc;
  bool _hasMore = true;
  bool _loadingMore = false;
  static const int _pageSize = 30;

  /// Every message loaded so far (newest first). Kept across realtime
  /// snapshot updates so paginated older messages are never lost.
  List<MessageModel> _cachedMessages = [];

  /// IDs of messages the current user deleted "for me" during this session.
  /// Kept independently of Firestore so the message disappears instantly and
  /// stays hidden even if a stale snapshot (that hasn't caught up with the
  /// write yet) tries to re-add it — Telegram-style immediate removal.
  final Set<String> _deletedForMeIds = {};

  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  StreamSubscription? _messagesSubscription;
  final _offlineFeedbackController = StreamController<int>.broadcast();

  List<_PendingSend> get _pendingSends =>
      _pendingByChat.putIfAbsent(chatId, () => []);

  /// Fires with the number of queued messages whenever the user tries to send
  /// something while offline, so the UI can inform them it will be auto-sent.
  Stream<int> get offlineFeedbackStream => _offlineFeedbackController.stream;
  List<String> _myBlockedUids = const [];
  bool _myBlockedUidsLoaded = false;
  Map<String, Timestamp> _groupMemberJoinTimestamps = {};
  Map<String, Timestamp> _groupMemberLeaveTimestamps = {};
  bool _groupMemberJoinTimestampsLoaded = false;
  List<String> _groupAdminUids = const [];
  String _groupCreatedBy = '';

  /// Set live from the group doc: once the creator deletes the whole group,
  /// every send path refuses to queue/write so the chat stays strictly
  /// read-only even if a stale composer or an offline flush fires late.
  bool _groupIsDeleted = false;

  bool get _canSendInGroupChat => !isGroupChat || !_groupIsDeleted;

  /// The currently pinned message (firestore map) or null. Powers the pinned
  /// banner and the bubble pin badge in realtime.
  final ValueNotifier<Map<String, dynamic>?> pinnedMessageNotifier =
      ValueNotifier(null);
  final _pinnedController = StreamController<Map<String, dynamic>?>.broadcast();
  StreamSubscription? _pinnedSubscription;
  Map<String, dynamic>? _currentPin;

  Stream<Map<String, dynamic>?> get pinnedMessageStream =>
      _pinnedController.stream;

  // ---------------------------------------------------------------------
  // Typing indicator
  // ---------------------------------------------------------------------
  static const Duration _typingWriteInterval = Duration(seconds: 5);

  /// Typing docs older than this are ignored (the writer may have left the
  /// chat without clearing its flag, so the reader self-heals).
  static const Duration _typingDocExpiry = Duration(seconds: 12);

  /// Emits the uids of the users currently typing in this chat
  /// (never includes the current user). Powers the typing bubble.
  final _typingController = StreamController<List<String>>.broadcast();
  StreamSubscription? _typingSubscription;
  DateTime? _lastTypingWrite;
  bool _typingActive = false;

  Stream<List<String>> get typingStream => _typingController.stream;

  /// Watches the `typing` subcollection (`chats|groups/{chatId}/typing`).
  /// Each doc is owned by the user who is typing and holds
  /// `{ typing: true, timestamp }`.
  void _listenToTyping() {
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    _typingSubscription = _firestore
        .collection(collectionPath)
        .doc(chatId)
        .collection('typing')
        .snapshots()
        .listen((snapshot) {
      final myUid = _auth.currentUser?.uid;
      final now = DateTime.now();
      final typing = <String>[];
      for (final doc in snapshot.docs) {
        if (doc.id == myUid) continue;
        final data = doc.data();
        if (data['typing'] != true) continue;
        final timestamp = data['timestamp'];
        if (timestamp is Timestamp) {
          final age = now.difference(timestamp.toDate());
          if (age > _typingDocExpiry) continue;
        }
        typing.add(doc.id);
      }
      if (!_typingController.isClosed) {
        _typingController.add(typing);
      }
    }, onError: (e) {
      debugPrint('Failed to load typing indicator: $e');
    });
  }

  /// Called by the composer on every keystroke while the user is typing.
  /// Writes (or refreshes) the user's typing flag, throttled to one write
  /// every [_typingWriteInterval] so we don't spam Firestore.
  Future<void> updateTyping() async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;

    final now = DateTime.now();
    final canWrite = _lastTypingWrite == null ||
        now.difference(_lastTypingWrite!) >= _typingWriteInterval;
    _typingActive = true;
    if (!canWrite) return;
    _lastTypingWrite = now;

    final collectionPath = isGroupChat ? 'groups' : 'chats';
    try {
      await _firestore
          .collection(collectionPath)
          .doc(chatId)
          .collection('typing')
          .doc(uid)
          .set({'typing': true, 'timestamp': FieldValue.serverTimestamp()});
    } catch (e) {
      debugPrint('Failed to update typing indicator: $e');
    }
  }

  /// Clears the user's typing flag (field emptied, message sent, or leaving
  /// the chat). No-op when nothing was ever written.
  Future<void> stopTyping() async {
    if (!_typingActive && _lastTypingWrite == null) return;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    _typingActive = false;
    _lastTypingWrite = null;

    final collectionPath = isGroupChat ? 'groups' : 'chats';
    try {
      await _firestore
          .collection(collectionPath)
          .doc(chatId)
          .collection('typing')
          .doc(uid)
          .delete();
    } catch (e) {
      debugPrint('Failed to clear typing indicator: $e');
    }
  }

  /// Groups: only admins (or the creator of legacy admin-less groups) may
  /// pin. Direct chats: anyone.
  bool get canPin {
    if (!isGroupChat) return true;
    final uid = _auth.currentUser?.uid;
    if (uid == null) return false;
    if (_groupAdminUids.isNotEmpty) return _groupAdminUids.contains(uid);
    return _groupCreatedBy == uid;
  }

  /// Returns true (1-to-1 only) when either the current user or the
  /// recipient has blocked the other, so sending must be prevented.
  Future<bool> _isBlockedConversation() async {
    if (isGroupChat || recipientId == null) return false;
    return BlockService.isEitherBlocked(recipientId!);
  }

  ChatCubit({
    required this.chatId,
    this.recipientId,
    this.recipient,
    this.isGroupChat = false,
  }) : super(ChatInitial()) {
    assert(isGroupChat || (recipientId != null && recipient != null),
        'Recipient info must be provided for one-on-one chats');

    // When the connection comes back, automatically send any queued messages.
    ConnectivityService.instance.isConnected
        .addListener(_onConnectivityChanged);

    // Load any messages that were persisted to disk while offline, then
    // flush the queue if we already have a connection.
    _loadPersistedQueue().then((_) {
      if (ConnectivityService.instance.isConnected.value) {
        _flushPendingSends();
      }
    });

    // Messages stay readable even when the recipient deleted their account
    // (the chat screen enforces read-only); only sending and calls are
    // blocked in the UI and in CallService.
    _listenToMessages();
    _listenToPinnedMessage();
    _listenToTyping();
  }

  void _onConnectivityChanged() {
    if (ConnectivityService.instance.isConnected.value) {
      _reconnect();
      _flushPendingSends();
    }
  }

  /// Restarts Firestore listeners that may have errored out while offline.
  /// Unlike a full cubit recreation, this keeps [_cachedMessages] so the UI
  /// stays on the current scroll position with no spinner flash.
  void _reconnect() {
    _messagesSubscription?.cancel();
    _pinnedSubscription?.cancel();
    _typingSubscription?.cancel();

    _resubscribeMessages();
    _listenToPinnedMessage();
    _listenToTyping();
  }

  /// Re-sorts the message cache newest-first by timestamp. Firestore only
  /// guarantees order for the first page delivered; the local cache can hand
  /// it in a slightly different order (local estimates for server timestamps,
  /// ties broken arbitrarily) and in-place refreshes never reorder. Sorting
  /// here keeps the list in the correct chronological order on the very first
  /// open and after any update, so the user never has to leave the chat and
  /// come back to fix the ordering.
  void _sortCacheNewestFirst() {
    _cachedMessages.sort((a, b) {
      final cmp = b.timestamp.compareTo(a.timestamp);
      if (cmp != 0) return cmp;
      // Deterministic tie-break for messages sharing a timestamp.
      return b.id.compareTo(a.id);
    });
  }

  /// Emits [ChatLoaded] from [_cachedMessages], preserving the reply context
  /// and the current pagination flags.
  void _emitLoaded() {
    _sortCacheNewestFirst();
    _syncPendingPlaceholders();
    final prev = state is ChatLoaded ? state as ChatLoaded : null;
    emit(ChatLoaded(
      _cachedMessages,
      replyingTo: prev?.replyingTo,
      replyingToSenderName: prev?.replyingToSenderName,
      replyingToMediaUrl: prev?.replyingToMediaUrl,
      replyingToMediaCount: prev?.replyingToMediaCount,
      hasMore: _hasMore,
      loadingMore: _loadingMore,
    ));
  }

  /// Returns false for 1v1 messages sent by a user I blocked, and for group
  /// messages sent before the sender joined the group OR outside the current
  /// viewer's own membership window (a newly-added member can't see messages
  /// sent before they joined; a removed/left member can only see messages
  /// sent while they were still in the group).
  bool _isMessageVisible(MessageModel message) {
    final myUid = _auth.currentUser?.uid;
    // A message I deleted "for me" is hidden only on my side. Check both the
    // persisted array and the in-memory set so a deletion is honored even
    // before Firestore has caught up.
    if (_deletedForMeIds.contains(message.id)) return false;
    if (myUid != null && message.deletedForMe.contains(myUid)) return false;
    if (!isGroupChat) {
      return !_myBlockedUids.contains(message.senderId);
    }
    final messageTimestamp = message.timestamp;
    final ms = messageTimestamp.millisecondsSinceEpoch;
    final senderJoinTimestamp = _groupMemberJoinTimestamps[message.senderId];
    if (senderJoinTimestamp != null &&
        ms < senderJoinTimestamp.millisecondsSinceEpoch) {
      return false;
    }

    if (myUid != null) {
      final myJoin = _groupMemberJoinTimestamps[myUid];
      if (myJoin != null && ms < myJoin.millisecondsSinceEpoch) return false;
      final myLeave = _groupMemberLeaveTimestamps[myUid];
      if (myLeave != null && ms > myLeave.millisecondsSinceEpoch) return false;
    }
    return true;
  }

  Future<void> loadMoreMessages() async {
    if (!_hasMore || _lastMessageDoc == null || _loadingMore) return;

    _loadingMore = true;
    _emitLoaded();

    try {
      final collectionPath = isGroupChat ? 'groups' : 'chats';

      final snapshot = await _firestore
          .collection(collectionPath)
          .doc(chatId)
          .collection('messages')
          .orderBy('timestamp', descending: true)
          .startAfterDocument(_lastMessageDoc!)
          .limit(_pageSize)
          .get();

      if (snapshot.docs.isEmpty) {
        _hasMore = false;
        return;
      }

      _lastMessageDoc = snapshot.docs.last;
      _hasMore = snapshot.docs.length >= _pageSize;

      final olderMessages = snapshot.docs
          .map((e) => MessageModel.fromFirestore(e))
          .where(_isMessageVisible)
          .toList();

      // Safety net: never append a doc that is already cached.
      final knownIds = {for (final m in _cachedMessages) m.id};
      final freshMessages =
          olderMessages.where((m) => !knownIds.contains(m.id)).toList();

      if (freshMessages.isEmpty) {
        _hasMore = false;
        return;
      }

      // Cache is newest-first (index 0 = newest). Older messages go AFTER
      // the existing ones so they appear above (end of a reversed list).
      _cachedMessages = [..._cachedMessages, ...freshMessages];
    } catch (e) {
      debugPrint('Failed to load older messages: $e');
    } finally {
      _loadingMore = false;
      _emitLoaded();
    }
  }

  /// Fetches every remaining page so the whole conversation lives in memory.
  /// Used by the in-chat search (needs all messages) and by "jump to
  /// message" (needs the target to be part of the rendered list).
  Future<void> loadAllMessages() async {
    if (!_hasMore || _lastMessageDoc == null || _loadingMore) return;

    // Serialize against loadMoreMessages: both paginate with the same
    // cursor, so running them concurrently could append overlapping pages.
    _loadingMore = true;
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    var lastDoc = _lastMessageDoc;
    final olderMessages = <MessageModel>[];
    // Safety net: never append a doc that is already cached.
    final knownIds = {for (final m in _cachedMessages) m.id};

    try {
      while (true) {
        final snapshot = await _firestore
            .collection(collectionPath)
            .doc(chatId)
            .collection('messages')
            .orderBy('timestamp', descending: true)
            .startAfterDocument(lastDoc!)
            .limit(_pageSize)
            .get();

        if (snapshot.docs.isEmpty) break;

        olderMessages.addAll(snapshot.docs
            .map((e) => MessageModel.fromFirestore(e))
            .where(_isMessageVisible)
            .where((m) => !knownIds.contains(m.id)));

        lastDoc = snapshot.docs.last;
        if (snapshot.docs.length < _pageSize) break;
      }
    } catch (e) {
      debugPrint('Failed to load all messages: $e');
    } finally {
      _loadingMore = false;
    }

    _lastMessageDoc = lastDoc;
    _hasMore = false;
    if (olderMessages.isNotEmpty) {
      _cachedMessages = [..._cachedMessages, ...olderMessages];
    }
    _emitLoaded();
  }

  /// Every message currently in memory, newest first.
  List<MessageModel> get allMessages => _cachedMessages;

  /// Refreshes the viewer's membership data when the group doc changes live
  /// (a member is added/removed, or I leave). Re-applies visibility filtering
  /// so messages outside my membership window disappear immediately and the
  /// app can switch to read-only mode.
  void refreshGroupMembership({
    required Map<String, Timestamp> memberJoinTimestamps,
    required Map<String, Timestamp> memberLeaveTimestamps,
  }) {
    if (!isGroupChat) return;
    _groupMemberJoinTimestamps = memberJoinTimestamps;
    _groupMemberLeaveTimestamps = memberLeaveTimestamps;
    _cachedMessages = _cachedMessages.where(_isMessageVisible).toList();
    _emitLoaded();
  }

  /// Inserts WhatsApp-style pending (clock) bubbles for any queued sends
  /// that are not visible in the list yet. Newest queued message goes to
  /// the top (the list is newest-first), ordered as they were sent.
  void _syncPendingPlaceholders() {
    final existingIds = {for (final m in _cachedMessages) m.id};
    final missing = _pendingSends
        .where((p) => !existingIds.contains(p.localId))
        .map((p) => p.placeholder)
        .toList();
    if (missing.isEmpty) return;
    _cachedMessages = [...missing.reversed, ..._cachedMessages];
  }

  /// Drops the local pending bubble after its send completed or failed.
  void _removePendingPlaceholder(String localId) {
    _cachedMessages.removeWhere((m) => m.id == localId);
    _emitLoaded();
  }

  String _nextLocalId() =>
      'pending_${DateTime.now().microsecondsSinceEpoch}_${_localIdSeq++}';

  /// Queues a message to be sent automatically once the connection is back.
  /// [placeholder] is shown immediately in the chat as a pending bubble
  /// (clock icon, WhatsApp-style). Also notifies the UI (via
  /// [offlineFeedbackStream]) so it can show a friendly "no internet,
  /// will retry automatically" message. The message is persisted to disk
  /// so it survives app restarts.
  void _enqueuePendingSend({
    required String label,
    required MessageModel placeholder,
    required Future<void> Function() action,
    required PendingMessage persistentData,
  }) {
    _pendingSends.add(_PendingSend(
      label: label,
      localId: placeholder.id,
      placeholder: placeholder,
      action: action,
      persistentData: persistentData,
    ));
    // Persist to disk so the message survives app restarts.
    OfflineQueueService.instance.enqueue(persistentData);
    _syncPendingPlaceholders();
    _emitLoaded();
    if (!_offlineFeedbackController.isClosed) {
      _offlineFeedbackController.add(_pendingSends.length);
    }
  }

  /// Sends every queued message in order as soon as the connection returns.
  ///
  /// On success the entry is removed from both the in-memory queue and
  /// the on-disk queue. Local media files are cleaned up. On failure the
  /// message is retried with exponential backoff (2s, 4s, 8s, 16s, 32s)
  /// up to [PendingMessage.maxRetries] times before being permanently
  /// dropped.
  Future<void> _flushPendingSends() async {
    final pending = _pendingSends;
    if (pending.isEmpty) return;
    if (_flushingChats[chatId] == true) return;

    _flushingChats[chatId] = true;
    try {
      final deferred = <_PendingSend>[];

      while (pending.isNotEmpty) {
        final current = pending.first;
        pending.removeAt(0);

        try {
          await current.action();
          // Success — remove from disk and clean up local media files.
          OfflineQueueService.instance.remove(chatId, current.localId);
          if (!_offlineFeedbackController.isClosed) {
            _offlineFeedbackController.add(_pendingSends.length);
          }
        } catch (e) {
          debugPrint('Failed to send queued ${current.label}: $e');
          final data = current.persistentData;
          final nextRetry = data.retryCount + 1;

          if (nextRetry < PendingMessage.maxRetries) {
            // Re-queue with incremented retry count.
            final updated = data.copyWith(retryCount: nextRetry);
            OfflineQueueService.instance
                .updateRetry(chatId, current.localId, nextRetry);

            final newAction =
                _reconstructSendAction(updated, _userFromMap(updated.sender));
            final updatedPending = _PendingSend(
              label: current.label,
              localId: current.localId,
              placeholder: current.placeholder,
              action: newAction,
              persistentData: updated,
            );
            deferred.add(updatedPending);

            debugPrint(
                'Will retry ${current.label} in ${updated.backoffDelay.inSeconds}s '
                '(attempt ${nextRetry + 1}/${PendingMessage.maxRetries})');
          } else {
            // Max retries exceeded — permanently fail.
            debugPrint(
                'Dropping ${current.label} after ${PendingMessage.maxRetries} retries');
            _removePendingPlaceholder(current.localId);
            OfflineQueueService.instance.remove(chatId, current.localId);
            if (!_offlineFeedbackController.isClosed) {
              _offlineFeedbackController.add(_pendingSends.length);
            }
          }
        }
      }

      // Re-append deferred messages with backoff delays applied.
      for (final msg in deferred) {
        final delay = msg.persistentData.backoffDelay;
        await Future.delayed(delay);
        if (isClosed) return;
        pending.add(msg);
      }

      // If deferred messages were re-appended, flush them now.
      if (pending.isNotEmpty && !isClosed) {
        _flushingChats[chatId] = false;
        _flushPendingSends();
        return;
      }
    } finally {
      _flushingChats[chatId] = false;
    }
  }

  /// Helper to reconstruct a [UserModel] from a serialized map.
  static UserModel _userFromMap(Map<String, dynamic> m) => UserModel(
        uid: m['uid'] as String? ?? '',
        email: m['email'] as String? ?? '',
        firstName: m['firstName'] as String? ?? '',
        lastName: m['lastName'] as String? ?? '',
        phoneNumber: m['phoneNumber'] as String? ?? '',
        avatarEmoji: m['avatarEmoji'] as String? ?? '👤',
      );

  /// Loads messages that were persisted to disk while the app was killed
  /// during an offline session. Reconstructs the in-memory queue and
  /// placeholder bubbles so the chat looks exactly as the user left it.
  Future<void> _loadPersistedQueue() async {
    final stored = await OfflineQueueService.instance.loadQueue(chatId);
    if (stored.isEmpty || isClosed) return;

    for (final msg in stored) {
      final senderModel = _userFromMap(msg.sender);

      final placeholder = MessageModel(
        id: msg.localId,
        senderId: senderModel.uid,
        recipientId: msg.recipientId,
        text: msg.text,
        timestamp: Timestamp.fromMillisecondsSinceEpoch(msg.createdAt),
        senderName: '${senderModel.firstName} ${senderModel.lastName}',
        status: 'pending',
        messageType: MessageType.values.byName(msg.messageType),
        repliedTo: msg.repliedTo,
        voiceDuration: msg.voiceDuration,
        videoDuration: msg.videoDuration,
      );

      final action = _reconstructSendAction(msg, senderModel);

      _pendingSends.add(_PendingSend(
        label: msg.messageType,
        localId: msg.localId,
        placeholder: placeholder,
        action: action,
        persistentData: msg,
      ));
    }

    _syncPendingPlaceholders();
    _emitLoaded();

    if (!_offlineFeedbackController.isClosed && _pendingSends.isNotEmpty) {
      _offlineFeedbackController.add(_pendingSends.length);
    }
  }

  /// Rebuilds the send closure for a persisted message. Called when the
  /// cubit is created after an app restart and the queue is reloaded from
  /// disk.
  Future<void> Function() _reconstructSendAction(
      PendingMessage msg, UserModel sender) {
    switch (msg.messageType) {
      case 'image':
        final files = msg.mediaPaths.map((p) => File(p)).toList();
        return () => _performSendImages(files, sender,
            caption: msg.text, repliedTo: msg.repliedTo, docId: msg.localId);
      case 'video':
        final file =
            File(msg.mediaPaths.isNotEmpty ? msg.mediaPaths.first : '');
        return () => _performSendVideo(file, sender,
            caption: msg.text,
            durationSeconds: msg.videoDuration,
            repliedTo: msg.repliedTo,
            docId: msg.localId);
      case 'voice':
        final file =
            File(msg.mediaPaths.isNotEmpty ? msg.mediaPaths.first : '');
        return () => _performSendVoiceMessage(
            file, msg.voiceDuration ?? 0, sender,
            repliedTo: msg.repliedTo, docId: msg.localId);
      default:
        return () => _performSend(msg.text, sender,
            repliedTo: msg.repliedTo, docId: msg.localId);
    }
  }

  void _listenToMessages() {
    emit(ChatLoading());

    final collectionPath = isGroupChat ? 'groups' : 'chats';

    final query = _firestore
        .collection(collectionPath)
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(_pageSize);
    _messagesSubscription = query.snapshots().listen((snapshot) async {
      // Seed the pagination cursor only from the FIRST snapshot. Live
      // updates (read receipts, edits, reactions...) must never move it,
      // otherwise already-paginated pages get fetched again and appended
      // as duplicates (the list then shows scrambled / repeated blocks).
      if (_lastMessageDoc == null) {
        _lastMessageDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length >= _pageSize;
      }

      if (!isGroupChat && !_myBlockedUidsLoaded) {
        _myBlockedUids = await BlockService.getBlockedUids();
        _myBlockedUidsLoaded = true;
      }

      // Load group member join timestamps for group chats
      if (isGroupChat && !_groupMemberJoinTimestampsLoaded) {
        try {
          final groupDoc =
              await _firestore.collection('groups').doc(chatId).get();
          if (groupDoc.exists) {
            final data = groupDoc.data() as Map<String, dynamic>;
            _groupMemberJoinTimestamps = data['memberJoinTimestamps'] != null
                ? Map<String, Timestamp>.from(data['memberJoinTimestamps'])
                : {};
            _groupMemberLeaveTimestamps = data['memberLeaveTimestamps'] != null
                ? Map<String, Timestamp>.from(data['memberLeaveTimestamps'])
                : {};
            _groupAdminUids = List<String>.from(data['adminUids'] ?? []);
            _groupCreatedBy = data['createdBy'] ?? '';
          }
        } catch (e) {
          // Permission denied when the user is no longer a group member.
          debugPrint('Failed to load group join timestamps: $e');
        }
        _groupMemberJoinTimestampsLoaded = true;
        _pinnedController.add(_currentPin);
      }

      final latestMessages = snapshot.docs
          .map((doc) => MessageModel.fromFirestore(doc))
          .where(_isMessageVisible)
          .toList();

      // Firestore removes hard-deleted docs from the snapshot (they no longer
      // have data). Drop the matching cached messages so entries like the
      // group call's "Join call" card disappear the moment it is deleted
      // (when the call ends), instead of lingering until the chat is
      // re-entered.
      final removedIds = {
        for (final change in snapshot.docChanges)
          if (change.type == DocumentChangeType.removed) change.doc.id,
      };
      if (removedIds.isNotEmpty) {
        _cachedMessages.removeWhere((m) => removedIds.contains(m.id));
      }

      // Merge the newest page into the cache instead of replacing it, so
      // older paginated messages stay visible when the snapshot fires
      // (new message, read receipt, reaction, edit...).
      if (_cachedMessages.isEmpty) {
        _cachedMessages = latestMessages;
      } else {
        final cache = List<MessageModel>.from(_cachedMessages);
        final cacheIds = {for (final m in cache) m.id};

        // Brand-new messages (not yet in cache) go to the top.
        final newOnes = latestMessages.where((m) => !cacheIds.contains(m.id));

        // Messages already loaded get refreshed in place (edits, reactions,
        // status changes).
        final latestById = {for (final m in latestMessages) m.id: m};
        for (int i = 0; i < cache.length; i++) {
          final updated = latestById[cache[i].id];
          if (updated != null) cache[i] = updated;
        }

        _cachedMessages = [...newOnes, ...cache];
      }

      // Always prune messages that are no longer visible for me (e.g. ones I
      // deleted "for me"). Without this, the snapshot fired by the deletion
      // write can re-add the message, so it only disappears after the screen
      // is rebuilt / re-entered.
      _cachedMessages = _cachedMessages.where(_isMessageVisible).toList();

      // A queued send confirmed by this snapshot (same client-generated id)
      // is now a real message — drop it from the pending queue so the clock
      // bubble merges into the sent message in place.
      _pendingSends
          .removeWhere((p) => _cachedMessages.any((m) => m.id == p.localId));

      _emitLoaded();

      if (!isGroupChat) {
        _markMessagesAsSeen();
      }
    }, onError: (e) {
      emit(const ChatError('Couldn\'t load messages. Please try again.'));
    });
  }

  /// Re-subscribes to the Firestore messages snapshot without emitting
  /// [ChatLoading]. Used by [_reconnect] so the cached list stays visible
  /// while the new listener warms up — no spinner, no scroll jump.
  void _resubscribeMessages() {
    final collectionPath = isGroupChat ? 'groups' : 'chats';

    final query = _firestore
        .collection(collectionPath)
        .doc(chatId)
        .collection('messages')
        .orderBy('timestamp', descending: true)
        .limit(_pageSize);
    _messagesSubscription = query.snapshots().listen((snapshot) async {
      // Only seed the pagination cursor when it hasn't been set yet (first
      // ever snapshot) or when reconnecting after an error. A reconnect
      // re-seeds so load-more still works with the fresh query.
      if (_lastMessageDoc == null) {
        _lastMessageDoc = snapshot.docs.isNotEmpty ? snapshot.docs.last : null;
        _hasMore = snapshot.docs.length >= _pageSize;
      }

      if (!isGroupChat && !_myBlockedUidsLoaded) {
        _myBlockedUids = await BlockService.getBlockedUids();
        _myBlockedUidsLoaded = true;
      }

      if (isGroupChat && !_groupMemberJoinTimestampsLoaded) {
        try {
          final groupDoc =
              await _firestore.collection('groups').doc(chatId).get();
          if (groupDoc.exists) {
            final data = groupDoc.data() as Map<String, dynamic>;
            _groupMemberJoinTimestamps = data['memberJoinTimestamps'] != null
                ? Map<String, Timestamp>.from(data['memberJoinTimestamps'])
                : {};
            _groupMemberLeaveTimestamps = data['memberLeaveTimestamps'] != null
                ? Map<String, Timestamp>.from(data['memberLeaveTimestamps'])
                : {};
            _groupAdminUids = List<String>.from(data['adminUids'] ?? []);
            _groupCreatedBy = data['createdBy'] ?? '';
          }
        } catch (e) {
          debugPrint('Failed to load group join timestamps: $e');
        }
        _groupMemberJoinTimestampsLoaded = true;
        _pinnedController.add(_currentPin);
      }

      final latestMessages = snapshot.docs
          .map((doc) => MessageModel.fromFirestore(doc))
          .where(_isMessageVisible)
          .toList();

      // Same hard-delete pruning as the initial listener: messages that
      // disappear from the snapshot (e.g. the "Join call" card when the group
      // call ends) must leave the cache immediately, not after a re-open.
      final removedIds = {
        for (final change in snapshot.docChanges)
          if (change.type == DocumentChangeType.removed) change.doc.id,
      };
      if (removedIds.isNotEmpty) {
        _cachedMessages.removeWhere((m) => removedIds.contains(m.id));
      }

      if (_cachedMessages.isEmpty) {
        _cachedMessages = latestMessages;
      } else {
        final cache = List<MessageModel>.from(_cachedMessages);
        final cacheIds = {for (final m in cache) m.id};

        final newOnes = latestMessages.where((m) => !cacheIds.contains(m.id));

        final latestById = {for (final m in latestMessages) m.id: m};
        for (int i = 0; i < cache.length; i++) {
          final updated = latestById[cache[i].id];
          if (updated != null) cache[i] = updated;
        }

        _cachedMessages = [...newOnes, ...cache];
      }

      _cachedMessages = _cachedMessages.where(_isMessageVisible).toList();

      _pendingSends
          .removeWhere((p) => _cachedMessages.any((m) => m.id == p.localId));

      _emitLoaded();

      if (!isGroupChat) {
        _markMessagesAsSeen();
      }
    }, onError: (e) {
      debugPrint('Re-subscribed listener error: $e');
    });
  }

  /// Watches the parent chat/group document for pinned-message changes and
  /// auto-unpins once the pin duration expires.
  void _listenToPinnedMessage() {
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    _pinnedSubscription = _firestore
        .collection(collectionPath)
        .doc(chatId)
        .snapshots()
        .listen((doc) {
      final data = doc.data();
      if (isGroupChat) {
        _groupIsDeleted = data?['isDeleted'] == true;
      }
      final pin = data?['pinnedMessage'] as Map<String, dynamic>?;
      final until = pin?['pinnedUntil'];
      if (until is Timestamp &&
          until.millisecondsSinceEpoch <=
              DateTime.now().millisecondsSinceEpoch) {
        _autoUnpin();
        return;
      }
      _currentPin = pin;
      pinnedMessageNotifier.value = pin;
      _pinnedController.add(pin);
    }, onError: (e) {
      debugPrint('Failed to load pinned message: $e');
    });
  }

  Future<void> _autoUnpin() async {
    pinnedMessageNotifier.value = null;
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    try {
      await _firestore
          .collection(collectionPath)
          .doc(chatId)
          .set({'pinnedMessage': FieldValue.delete()}, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Failed to auto-unpin expired message: $e');
    }
  }

  /// Pins [message] for the given [duration]. Group pins are admin-only,
  /// which the Firestore rules enforce server-side as well.
  Future<void> pinMessage(MessageModel message, Duration duration) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null || !canPin) return;
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    final pin = {
      'messageId': message.id,
      'text': message.text,
      'senderName': message.senderName ?? '',
      'senderId': message.senderId,
      'messageType': message.messageType.name,
      if (message.mediaUrls != null) 'mediaUrls': message.mediaUrls,
      if (message.voiceDuration != null) 'voiceDuration': message.voiceDuration,
      if (message.videoDuration != null) 'videoDuration': message.videoDuration,
      'pinnedBy': uid,
      'pinnedAt': FieldValue.serverTimestamp(),
      'pinnedUntil': Timestamp.fromDate(DateTime.now().add(duration)),
    };
    try {
      await _firestore
          .collection(collectionPath)
          .doc(chatId)
          .set({'pinnedMessage': pin}, SetOptions(merge: true));
    } catch (e) {
      emit(const ChatError('Couldn\'t pin message. Please try again.'));
      debugPrint('Failed to pin message: $e');
    }
  }

  Future<void> unpinMessage() async {
    if (!canPin) return;
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    try {
      await _firestore
          .collection(collectionPath)
          .doc(chatId)
          .set({'pinnedMessage': FieldValue.delete()}, SetOptions(merge: true));
      pinnedMessageNotifier.value = null;
    } catch (e) {
      emit(const ChatError('Couldn\'t unpin message. Please try again.'));
      debugPrint('Failed to unpin message: $e');
    }
  }

  Future<void> sendMessage(String text, UserModel sender) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    if (!_canSendInGroupChat) {
      emit(const ChatError(
          'This group was deleted. You can no longer send messages.'));
      return;
    }

    if (!ConnectivityService.instance.isConnected.value) {
      // Capture the reply BEFORE queueing: the queued re-run must keep the
      // reply composed now, not whatever reply is current when the
      // connection comes back.
      final repliedTo = _captureReplyingTo();
      final localId = _nextLocalId();
      final now = DateTime.now();
      _enqueuePendingSend(
        label: 'message',
        placeholder: MessageModel(
          id: localId,
          senderId: currentUser.uid,
          recipientId: recipientId ?? '',
          text: text,
          timestamp: Timestamp.now(),
          senderName: '${sender.firstName} ${sender.lastName}',
          status: 'pending',
          repliedTo: repliedTo,
        ),
        action: () =>
            _performSend(text, sender, repliedTo: repliedTo, docId: localId),
        persistentData: PendingMessage(
          localId: localId,
          chatId: chatId,
          isGroup: isGroupChat,
          recipientId: recipientId ?? '',
          messageType: 'text',
          text: text,
          sender: sender.toMap(),
          repliedTo: repliedTo,
          createdAt: now.millisecondsSinceEpoch,
        ),
      );
      return;
    }

    if (await _isBlockedConversation()) {
      emit(const ChatError('You cannot send messages to this user.'));
      return;
    }

    final repliedTo = _captureReplyingTo();
    try {
      await _performSend(text, sender,
          repliedTo: repliedTo, docId: _nextLocalId());
    } catch (e) {
      emit(const ChatError("Couldn't send message. Please try again."));
    }
  }

  /// Actual Firestore write. [repliedTo] is captured by the caller, never
  /// re-captured, so offline-queued sends can't pick up a stale reply.
  /// [docId] is a client-generated id: for queued messages it is the same id
  /// as the pending placeholder bubble, so the sent message replaces the
  /// "clock" bubble in place once the snapshot delivers it (no duplicates,
  /// no flash of a second bubble).
  Future<void> _performSend(
    String text,
    UserModel sender, {
    required Map<String, dynamic>? repliedTo,
    required String docId,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    final messageData = {
      'text': text,
      'senderId': currentUser.uid,
      'senderName': '${sender.firstName} ${sender.lastName}',
      if (!isGroupChat) 'recipientId': recipientId ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      // In a self-chat you are both sender and receiver, so the message is
      // instantly seen — never stuck as "sent".
      'status': (!isGroupChat && recipientId == currentUser.uid)
          ? 'seen'
          : 'sent',
      'reactions': {},
      'isDeleted': false,
      'isEdited': false,
      if (repliedTo != null) 'repliedTo': repliedTo,
    };

    final collectionPath = isGroupChat ? 'groups' : 'chats';
    final chatRef = _firestore.collection(collectionPath).doc(chatId);

    // Ensure parent document has required fields
    if (!isGroupChat) {
      final uids = [currentUser.uid, recipientId!]..sort();
      await chatRef.set({
        'uids': uids,
        'hiddenFor': [],
      }, SetOptions(merge: true));
    } else {
      await chatRef.set({
        'hiddenFor': [],
      }, SetOptions(merge: true));
    }

    // Add the message under the client-generated id (see [docId]). The
    // placeholder bubble shares this id, so it becomes the sent message.
    await chatRef.collection('messages').doc(docId).set(messageData);

    // Non-critical follow-ups: fire-and-forget so a failure here never
    // reverts the successfully sent message or causes a state flip that
    // tears the chat down and shows duplicates.
    try {
      stopTyping();
      await chatRef.set({
        'lastMessage': text,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastSenderId': currentUser.uid,
      }, SetOptions(merge: true));
      if (isGroupChat) {
        await _sendGroupNotification(sender, text);
      } else {
        await _sendDirectNotification(sender, text);
      }
    } catch (e) {
      debugPrint('Non-critical send follow-up failed: $e');
    }
  }

  Future<void> _sendDirectNotification(UserModel sender, String text) async {
    if (recipientId == null) return;

    // Self-chat: I'm messaging myself, so there's no "other side" to notify.
    // Sending a push to my own token would just notify me about my own message.
    if (recipientId == sender.uid) return;

    try {
      if (await BlockService.isEitherBlocked(recipientId!)) return;

      final doc = await _firestore.collection('users').doc(recipientId).get();
      if (!doc.exists) return;

      // Respect the recipient's mute: the message still arrives in the chat,
      // but no push is sent (this is what keeps muted contacts silent even on
      // iOS, where the system would otherwise render the APNs alert).
      final mutedChats = doc.data()?['mutedChats'];
      if (mutedChats is Map &&
          MuteService.isMutedEntry(mutedChats[sender.uid])) {
        debugPrint('Skipping notification: muted by recipient');
        return;
      }

      final tokens = List<String>.from(doc.data()?['fcmTokens'] ?? []);
      final hmsTokens = List<String>.from(doc.data()?['hmsTokens'] ?? []);

      // Initialize the V1 Sender
      final fcmSender = await FcmV1Sender.getInstance();

      for (final token in tokens) {
        await fcmSender.sendMessageToToken(
          token: token,
          title: '${sender.firstName} ${sender.lastName}',
          body: text,
          chatType: 'chat',
          targetId: sender.uid,
          receiverId: recipientId,
        );
      }

      // HMS devices (no GMS) are reached through the Huawei Push API.
      await HmsV1Sender.sendToTokens(
        tokens: hmsTokens,
        title: '${sender.firstName} ${sender.lastName}',
        body: text,
        chatType: 'chat',
        targetId: sender.uid,
        receiverId: recipientId,
      );
    } catch (e) {
      debugPrint("Error sending direct notification: $e");
    }
  }

  Future<void> _sendGroupNotification(UserModel sender, String text) async {
    try {
      final groupDoc = await _firestore.collection('groups').doc(chatId).get();
      if (!groupDoc.exists) return;

      final membersUids =
          List<String>.from(groupDoc.data()?['memberUids'] ?? []);
      // Don't send a notification to the person who sent the message
      final recipientUids =
          membersUids.where((uid) => uid != sender.uid).toList();

      if (recipientUids.isEmpty) return;

      // Initialize the V1 Sender
      final fcmSender = await FcmV1Sender.getInstance();

      // Chunk the queries if > 10 items (Firestore limit for 'whereIn' is 10)
      // For simplicity here we assume <= 10, but in prod you should chunk logic.
      final usersSnapshot = await _firestore
          .collection('users')
          .where(FieldPath.documentId, whereIn: recipientUids.take(10).toList())
          .get();

      for (final userDoc in usersSnapshot.docs) {
        // Skip members who blocked the sender so they never get notified.
        final blockedByMember =
            List<String>.from(userDoc.data()['blockedUids'] ?? const []);
        if (blockedByMember.contains(sender.uid)) continue;

        final tokens = List<String>.from(userDoc.data()['fcmTokens'] ?? []);
        final hmsTokens = List<String>.from(userDoc.data()['hmsTokens'] ?? []);

        for (final token in tokens) {
          await fcmSender.sendMessageToToken(
            token: token,
            title: groupDoc.data()?['name'] ?? 'New Group Message',
            body: '${sender.firstName}: $text',
            chatType: 'group_chat',
            targetId: chatId,
            receiverId: userDoc.id,
          );
        }

        await HmsV1Sender.sendToTokens(
          tokens: hmsTokens,
          title: groupDoc.data()?['name'] ?? 'New Group Message',
          body: '${sender.firstName}: $text',
          chatType: 'group_chat',
          targetId: chatId,
          receiverId: userDoc.id,
        );
      }
    } catch (e) {
      debugPrint("Error sending group notification: $e");
    }
  }

  void _markMessagesAsSeen() {
    // This logic is only for one-on-one chats
    if (isGroupChat || _auth.currentUser == null) return;

    // Never mark as seen when the conversation is blocked.
    if (_myBlockedUids.contains(recipientId)) return;

    final uid = _auth.currentUser!.uid;

    // Firestore rejects two `!=` filters in one query, so we only filter on
    // senderId here and exclude already-seen messages in-memory before
    // writing the batch.
    _firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .where('senderId', isNotEqualTo: uid)
        .get()
        .then((snapshot) {
      final docsToUpdate = snapshot.docs
          .where((doc) => doc.data()['status'] != 'seen')
          .toList();
      if (docsToUpdate.isEmpty) return;
      WriteBatch batch = _firestore.batch();
      for (var doc in docsToUpdate) {
        batch.update(doc.reference, {'status': 'seen'});
      }
      batch.commit();
    }).catchError((e) {
      debugPrint("Failed to update message status: $e");
    });

    _firestore.collection('chats').doc(chatId).update({
      'unreadCounts.$uid': 0,
    }).catchError((e) {
      debugPrint("Failed to reset unread count: $e");
    });
  }

  Future<void> _performMessageUpdate(
      String messageId, Map<String, dynamic> data) async {
    try {
      final collectionPath = isGroupChat ? 'groups' : 'chats';
      await _firestore
          .collection(collectionPath)
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update(data);
    } catch (e) {
      emit(const ChatError("Couldn't update message. Please try again."));
    }
  }

  Future<void> deleteMessage(String messageId) async {
    await _performMessageUpdate(messageId, {'isDeleted': true, 'text': ''});
  }

  /// Hides a message only from the current user's chat. The message stays
  /// intact in Firestore for the other side (unlike [deleteMessage], which
  /// deletes it for everyone). Implemented as an array of UIDs who chose to
  /// hide it for themselves, filtered out on this device.
  Future<void> deleteMessageForMe(String messageId) async {
    final uid = _auth.currentUser?.uid;
    if (uid == null) return;
    // Hide instantly and locally BEFORE any network round-trip, so the
    // message vanishes the moment the user taps (Telegram-style).
    _deletedForMeIds.add(messageId);
    final removed = _cachedMessages.any((m) => m.id == messageId);
    if (removed) {
      _cachedMessages.removeWhere((m) => m.id == messageId);
    }
    _cachedMessages = _cachedMessages.where(_isMessageVisible).toList();
    _emitLoaded();
    try {
      final collectionPath = isGroupChat ? 'groups' : 'chats';
      await _firestore
          .collection(collectionPath)
          .doc(chatId)
          .collection('messages')
          .doc(messageId)
          .update({
        'deletedForMe': FieldValue.arrayUnion([uid]),
      });
    } catch (e) {
      emit(const ChatError("Couldn't delete message. Please try again."));
    }
  }

  Future<void> editMessage(String messageId, String newText) async {
    await _performMessageUpdate(messageId, {'text': newText, 'isEdited': true});
  }

  Future<void> updateReaction(String messageId, String emoji) async {
    final uid = _auth.currentUser!.uid;
    await _performMessageUpdate(messageId, {'reactions.$uid': emoji});
    _notifyReaction(messageId, emoji);
  }

  /// Reacts to a specific photo inside a (multi-)image message. The reaction
  /// is stored under `imageReactions.<mediaIndex>.<uid>` so it only applies
  /// to that photo, like WhatsApp.
  Future<void> updateImageReaction(
      String messageId, int mediaIndex, String emoji) async {
    final uid = _auth.currentUser!.uid;
    await _performMessageUpdate(
        messageId, {'imageReactions.$mediaIndex.$uid': emoji});
    _notifyReaction(messageId, emoji);
  }

  /// Sends a push notification when the current user reacts to a message, so
  /// the other side knows even without opening the chat. Fire-and-forget:
  /// the senders swallow every error (offline, blocked...).
  Future<void> _notifyReaction(String messageId, String emoji) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    MessageModel? message;
    for (final m in _cachedMessages) {
      if (m.id == messageId) {
        message = m;
        break;
      }
    }
    if (message == null) return;

    final UserModel me;
    try {
      final doc =
          await _firestore.collection('users').doc(currentUser.uid).get();
      if (!doc.exists) return;
      me = UserModel.fromFirestore(doc);
    } catch (e) {
      debugPrint('Failed to fetch my user for reaction notification: $e');
      return;
    }

    var preview = replyPreviewString(message);
    if (preview.length > 60) {
      preview = '${preview.substring(0, 60)}…';
    }
    final body = 'Reacted $emoji to: $preview';

    if (isGroupChat) {
      await _sendGroupNotification(me, body);
    } else {
      if (recipientId == null) return;
      await _sendDirectNotification(me, body);
    }
  }

  void removeImageReaction(String messageId, int mediaIndex) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    FirebaseFirestore.instance
        .collection(collectionPath)
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'imageReactions.$mediaIndex.$uid': FieldValue.delete()});

    if (state is ChatLoaded) {
      final loadedState = state as ChatLoaded;
      final updatedMessages = List<MessageModel>.from(loadedState.messages);
      final index = updatedMessages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final current = updatedMessages[index];
        final key = '$mediaIndex';
        final imageReactions =
            Map<String, Map<String, String>>.from(current.imageReactions);
        if (imageReactions.containsKey(key)) {
          final inner = Map<String, String>.from(imageReactions[key]!);
          inner.remove(uid);
          if (inner.isEmpty) {
            imageReactions.remove(key);
          } else {
            imageReactions[key] = inner;
          }
        }
        updatedMessages[index] =
            current.copyWith(imageReactions: imageReactions);
        _cachedMessages = updatedMessages;
        _emitLoaded();
      }
    }
  }

  void removeReaction(String messageId) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    FirebaseFirestore.instance
        .collection(collectionPath)
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({'reactions.$uid': FieldValue.delete()});

    if (state is ChatLoaded) {
      final loadedState = state as ChatLoaded;
      final updatedMessages = List<MessageModel>.from(loadedState.messages);
      final index = updatedMessages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final updatedReactions =
            Map<String, String>.from(updatedMessages[index].reactions);
        updatedReactions.remove(uid);
        updatedMessages[index] =
            updatedMessages[index].copyWith(reactions: updatedReactions);
        _cachedMessages = updatedMessages;
        _emitLoaded();
      }
    }
  }

  /// Adds the current user to the message's `starredBy` (favorite) list.
  void starMessage(String messageId) {
    _updateStarredBy(messageId, add: true);
  }

  /// Removes the current user from the message's `starredBy` list.
  void unstarMessage(String messageId) {
    _updateStarredBy(messageId, add: false);
  }

  void _updateStarredBy(String messageId, {required bool add}) {
    final uid = FirebaseAuth.instance.currentUser!.uid;
    final collectionPath = isGroupChat ? 'groups' : 'chats';
    FirebaseFirestore.instance
        .collection(collectionPath)
        .doc(chatId)
        .collection('messages')
        .doc(messageId)
        .update({
      'starredBy':
          add ? FieldValue.arrayUnion([uid]) : FieldValue.arrayRemove([uid]),
    });

    if (state is ChatLoaded) {
      final loadedState = state as ChatLoaded;
      final updatedMessages = List<MessageModel>.from(loadedState.messages);
      final index = updatedMessages.indexWhere((m) => m.id == messageId);
      if (index != -1) {
        final current = updatedMessages[index];
        final starredBy = List<String>.from(current.starredBy);
        if (add) {
          if (!starredBy.contains(uid)) starredBy.add(uid);
        } else {
          starredBy.remove(uid);
        }
        updatedMessages[index] = current.copyWith(starredBy: starredBy);
        _cachedMessages = updatedMessages;
        _emitLoaded();
      }
    }
  }

  /// Builds rich `repliedTo` metadata (type, media URL, duration) so replies
  /// to media messages render with a thumbnail / proper label. Old messages
  /// without `type` still fall back to plain text previews on the receiver.
  Map<String, dynamic> _buildRepliedToMeta({
    required MessageModel message,
    required String? senderName,
    String? mediaUrl,
    int? mediaCount,
  }) {
    final duration =
        message.messageType == MessageType.voice ? message.voiceDuration : null;
    final videoDuration =
        message.messageType == MessageType.video ? message.videoDuration : null;

    return {
      'id': message.id,
      'senderName': senderName,
      'text': replyPreviewString(message, mediaCount: mediaCount),
      'type': message.messageType.name,
      if (mediaUrl != null && mediaUrl.isNotEmpty) 'mediaUrl': mediaUrl,
      if (mediaCount != null && mediaCount > 1) 'count': mediaCount,
      if (duration != null) 'duration': duration,
      if (videoDuration != null) 'duration': videoDuration,
    };
  }

  /// Snapshots the active reply context and clears it. Called before any
  /// send so the reply is captured even though uploading swaps the state.
  Map<String, dynamic>? _captureReplyingTo() {
    if (state is! ChatLoaded) return null;
    final replyingState = state as ChatLoaded;
    final replyingTo = replyingState.replyingTo;
    if (replyingTo == null) return null;

    // Single-media messages (video / single photo) always fall back to their
    // media URL so replies show a thumbnail even via swipe-to-reply.
    // Multi-photo groups fall back to the first photo + a count badge and
    // render a group "📷 Photos" preview.
    String? mediaUrl = replyingState.replyingToMediaUrl;
    int? mediaCount = replyingState.replyingToMediaCount;
    final urls = replyingTo.mediaUrls;
    if (mediaUrl == null && urls != null && urls.isNotEmpty) {
      mediaUrl = urls.first;
      if (replyingTo.messageType == MessageType.image && urls.length > 1) {
        mediaCount = urls.length;
      }
    }

    final meta = _buildRepliedToMeta(
      message: replyingTo,
      senderName: replyingState.replyingToSenderName,
      mediaUrl: mediaUrl,
      mediaCount: mediaCount,
    );
    setReplyingTo(null, null, mediaUrl: null, mediaCount: null);
    return meta;
  }

  void setReplyingTo(MessageModel? message, String? senderName,
      {String? mediaUrl, int? mediaCount}) {
    if (state is ChatLoaded) {
      // Swipe-to-reply doesn't pass a media URL — derive the thumbnail from
      // the replied message so photo / video previews render in the composer.
      if (message != null &&
          mediaUrl == null &&
          message.mediaUrls != null &&
          message.mediaUrls!.isNotEmpty) {
        mediaUrl = message.mediaUrls!.first;
        if (message.messageType == MessageType.image &&
            message.mediaUrls!.length > 1) {
          mediaCount = message.mediaUrls!.length;
        }
      }
      emit(ChatLoaded(
        _cachedMessages,
        replyingTo: message,
        replyingToSenderName: senderName,
        replyingToMediaUrl: mediaUrl,
        replyingToMediaCount: mediaCount,
        hasMore: _hasMore,
        loadingMore: _loadingMore,
      ));
    }
  }

  Future<void> sendImages(
    List<File> images,
    UserModel sender, {
    String caption = '',
  }) async {
    if (images.isEmpty) return;

    // Hard limit: at most 4 photos per message.
    images = images.take(4).toList();

    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    if (!_canSendInGroupChat) {
      emit(const ChatError(
          'This group was deleted. You can no longer send messages.'));
      return;
    }

    if (!ConnectivityService.instance.isConnected.value) {
      final repliedTo = _captureReplyingTo();
      final localId = _nextLocalId();
      // Copy images to persistent storage so they survive app restarts.
      final paths = <String>[];
      for (int i = 0; i < images.length; i++) {
        try {
          final path = await OfflineQueueService.instance
              .persistFile(images[i], localId, index: i);
          paths.add(path);
        } catch (e) {
          debugPrint('Failed to persist image $i: $e');
        }
      }
      final now = DateTime.now();
      _enqueuePendingSend(
        label: images.length > 1 ? 'message' : 'photo message',
        placeholder: MessageModel(
          id: localId,
          senderId: currentUser.uid,
          recipientId: recipientId ?? '',
          text: caption.isNotEmpty
              ? caption
              : (images.length > 1 ? '📷 Photos' : '📷 Photo'),
          timestamp: Timestamp.now(),
          senderName: '${sender.firstName} ${sender.lastName}',
          status: 'pending',
          repliedTo: repliedTo,
        ),
        // Upload from the PERSISTED copies (survive temp-dir purges), never
        // the original camera/gallery files that may be deleted while offline.
        action: () => _performSendImages(
          paths.map((p) => File(p)).toList(),
          sender,
          caption: caption,
          repliedTo: repliedTo,
          docId: localId,
        ),
        persistentData: PendingMessage(
          localId: localId,
          chatId: chatId,
          isGroup: isGroupChat,
          recipientId: recipientId ?? '',
          messageType: 'image',
          text: caption.isNotEmpty
              ? caption
              : (images.length > 1 ? '📷 Photos' : '📷 Photo'),
          sender: sender.toMap(),
          repliedTo: repliedTo,
          mediaPaths: paths,
          createdAt: now.millisecondsSinceEpoch,
        ),
      );
      return;
    }

    if (await _isBlockedConversation()) {
      emit(const ChatError('You cannot send messages to this user.'));
      return;
    }

    // Capture the reply BEFORE uploading: emitting ChatUploading replaces the
    // ChatLoaded state, which used to silently drop the reply context.
    final repliedTo = _captureReplyingTo();
    try {
      await _performSendImages(images, sender,
          caption: caption, repliedTo: repliedTo, docId: _nextLocalId());
    } catch (e) {
      emit(const ChatError('Couldn\'t send photos. Please try again.'));
    }
  }

  Future<void> _performSendImages(
    List<File> images,
    UserModel sender, {
    required String caption,
    required Map<String, dynamic>? repliedTo,
    required String docId,
  }) async {
    final urls = <String>[];
    final totalFiles = images.length;
    double lastEmitted = 0.0;

    for (int i = 0; i < images.length; i++) {
      try {
        final url = await CloudinaryService.uploadFileWithProgress(
          file: images[i],
          preset: CloudinaryConfig.imagePreset,
          resourceType: 'image',
          onProgress: (fileProgress) {
            final p = (i / totalFiles) + (fileProgress / totalFiles);
            if (p - lastEmitted >= 0.01 || p >= 1.0) {
              lastEmitted = p;
              emit(ChatUploading(p));
            }
          },
        );

        urls.add(url);
      } catch (e) {
        // One bad file shouldn't fail the whole batch.
        debugPrint('Image ${i + 1} upload failed: $e');
      }
    }

    if (urls.isEmpty) {
      throw Exception('Failed to upload any photos');
    }

    await _sendMediaMessage(
      sender: sender,
      messageType: MessageType.image,
      mediaUrls: urls,
      caption: caption,
      previewText: urls.length > 1 ? '📷 Photos' : '📷 Photo',
      repliedTo: repliedTo,
      docId: docId,
    );
  }

  Future<void> sendVideo(
    File video,
    UserModel sender, {
    String caption = '',
    int? durationSeconds,
  }) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    if (!_canSendInGroupChat) {
      emit(const ChatError(
          'This group was deleted. You can no longer send messages.'));
      return;
    }

    if (!ConnectivityService.instance.isConnected.value) {
      final repliedTo = _captureReplyingTo();
      final localId = _nextLocalId();
      // Copy video to persistent storage so it survives app restarts.
      final paths = <String>[];
      try {
        final path = await OfflineQueueService.instance
            .persistFile(video, localId, index: 0);
        paths.add(path);
      } catch (e) {
        debugPrint('Failed to persist video: $e');
      }
      final now = DateTime.now();
      _enqueuePendingSend(
        label: 'video',
        placeholder: MessageModel(
          id: localId,
          senderId: currentUser.uid,
          recipientId: recipientId ?? '',
          text: caption.isNotEmpty ? caption : '🎥 Video',
          timestamp: Timestamp.now(),
          senderName: '${sender.firstName} ${sender.lastName}',
          status: 'pending',
          repliedTo: repliedTo,
        ),
        // Upload from the PERSISTED copy (survives temp-dir purges), never
        // the original camera/gallery file that may be deleted while offline.
        action: () => _performSendVideo(
          File(paths.isNotEmpty ? paths.first : video.path),
          sender,
          caption: caption,
          durationSeconds: durationSeconds,
          repliedTo: repliedTo,
          docId: localId,
        ),
        persistentData: PendingMessage(
          localId: localId,
          chatId: chatId,
          isGroup: isGroupChat,
          recipientId: recipientId ?? '',
          messageType: 'video',
          text: caption.isNotEmpty ? caption : '🎥 Video',
          sender: sender.toMap(),
          repliedTo: repliedTo,
          mediaPaths: paths,
          videoDuration: durationSeconds,
          createdAt: now.millisecondsSinceEpoch,
        ),
      );
      return;
    }

    if (await _isBlockedConversation()) {
      emit(const ChatError('You cannot send messages to this user.'));
      return;
    }

    // Capture reply before ChatUploading replaces the loaded state.
    final repliedTo = _captureReplyingTo();
    try {
      await _performSendVideo(video, sender,
          caption: caption,
          durationSeconds: durationSeconds,
          repliedTo: repliedTo,
          docId: _nextLocalId());
    } catch (e) {
      emit(const ChatError('Couldn\'t send video. Please try again.'));
    }
  }

  Future<void> _performSendVideo(
    File video,
    UserModel sender, {
    required String caption,
    required int? durationSeconds,
    required Map<String, dynamic>? repliedTo,
    required String docId,
  }) async {
    final url = await CloudinaryService.uploadFileWithProgress(
      file: video,
      preset: CloudinaryConfig.videoPreset,
      resourceType: 'video',
      onProgress: (progress) {
        emit(ChatUploading(progress));
      },
    );
    final playableUrl = videoCompatUrl(url);

    await _sendMediaMessage(
      sender: sender,
      messageType: MessageType.video,
      mediaUrls: [playableUrl],
      caption: caption,
      previewText: '🎥 Video',
      videoDuration: durationSeconds,
      repliedTo: repliedTo,
      docId: docId,
    );
  }

  Future<void> sendVoiceMessage(
    File voiceFile,
    int durationSeconds,
    UserModel sender,
  ) async {
    final currentUser = _auth.currentUser;
    if (currentUser == null) return;

    if (!_canSendInGroupChat) {
      emit(const ChatError(
          'This group was deleted. You can no longer send messages.'));
      return;
    }

    if (!ConnectivityService.instance.isConnected.value) {
      final repliedTo = _captureReplyingTo();
      final localId = _nextLocalId();
      // Copy voice file to persistent storage so it survives app restarts.
      final paths = <String>[];
      try {
        final path = await OfflineQueueService.instance
            .persistFile(voiceFile, localId, index: 0);
        paths.add(path);
      } catch (e) {
        debugPrint('Failed to persist voice file: $e');
      }
      final now = DateTime.now();
      _enqueuePendingSend(
        label: 'voice message',
        placeholder: MessageModel(
          id: localId,
          senderId: currentUser.uid,
          recipientId: recipientId ?? '',
          text: '🎤 Voice message',
          timestamp: Timestamp.now(),
          senderName: '${sender.firstName} ${sender.lastName}',
          status: 'pending',
          repliedTo: repliedTo,
        ),
        // Upload from the PERSISTED copy (survives temp-dir purges), never
        // the original temp recording that may be deleted while offline.
        action: () => _performSendVoiceMessage(
          File(paths.isNotEmpty ? paths.first : voiceFile.path),
          durationSeconds,
          sender,
          repliedTo: repliedTo,
          docId: localId,
        ),
        persistentData: PendingMessage(
          localId: localId,
          chatId: chatId,
          isGroup: isGroupChat,
          recipientId: recipientId ?? '',
          messageType: 'voice',
          text: '🎤 Voice message',
          sender: sender.toMap(),
          repliedTo: repliedTo,
          mediaPaths: paths,
          voiceDuration: durationSeconds,
          createdAt: now.millisecondsSinceEpoch,
        ),
      );
      return;
    }

    if (await _isBlockedConversation()) {
      emit(const ChatError('You cannot send messages to this user.'));
      return;
    }

    // Capture reply before ChatUploading replaces the loaded state.
    final repliedTo = _captureReplyingTo();
    try {
      await _performSendVoiceMessage(voiceFile, durationSeconds, sender,
          repliedTo: repliedTo, docId: _nextLocalId());
    } catch (e) {
      emit(const ChatError('Couldn\'t send voice message. Please try again.'));
    }
  }

  Future<void> _performSendVoiceMessage(
    File voiceFile,
    int durationSeconds,
    UserModel sender, {
    required Map<String, dynamic>? repliedTo,
    required String docId,
  }) async {
    final url = await CloudinaryService.uploadFileWithProgress(
      file: voiceFile,
      preset: CloudinaryConfig.videoPreset,
      resourceType: 'video',
      onProgress: (progress) {
        emit(ChatUploading(progress));
      },
    );

    await _sendMediaMessage(
      sender: sender,
      messageType: MessageType.voice,
      mediaUrls: [url],
      voiceDuration: durationSeconds,
      previewText: '🎤 Voice message',
      repliedTo: repliedTo,
      docId: docId,
    );
  }

  Future<void> _sendMediaMessage({
    required UserModel sender,
    required MessageType messageType,
    required List<String> mediaUrls,
    int? voiceDuration,
    int? videoDuration,
    String caption = '',
    required String previewText,
    Map<String, dynamic>? repliedTo,
    required String docId,
  }) async {
    final currentUser = _auth.currentUser!;
    final collectionPath = isGroupChat ? 'groups' : 'chats';

    final messageData = {
      'text': caption,
      'senderId': currentUser.uid,
      'senderName': '${sender.firstName} ${sender.lastName}',
      if (!isGroupChat) 'recipientId': recipientId ?? '',
      'timestamp': FieldValue.serverTimestamp(),
      // In a self-chat you are both sender and receiver, so the message is
      // instantly seen — never stuck as "sent".
      'status': (!isGroupChat && recipientId == currentUser.uid)
          ? 'seen'
          : 'sent',
      'reactions': {},
      'isDeleted': false,
      'isEdited': false,
      'messageType': messageType.name,
      'mediaUrls': mediaUrls,
      if (voiceDuration != null) 'voiceDuration': voiceDuration,
      if (videoDuration != null) 'videoDuration': videoDuration,
      if (repliedTo != null) 'repliedTo': repliedTo,
    };

    final chatRef = _firestore.collection(collectionPath).doc(chatId);

    // Write under the client-generated id ([docId]) so a queued send's
    // pending bubble becomes the real message in place (idempotent, so a
    // re-flush can never double-send).
    await chatRef.collection('messages').doc(docId).set(messageData);

    // Non-critical follow-ups: fire-and-forget so a failure here never
    // reverts the successfully sent message or causes a state flip.
    try {
      stopTyping();
      await chatRef.set({
        'lastMessage': caption.isNotEmpty ? caption : previewText,
        'lastMessageTimestamp': FieldValue.serverTimestamp(),
        'lastSenderId': currentUser.uid,
      }, SetOptions(merge: true));

      // The notification body shows the caption when present (photos/videos)
      // and otherwise a friendly media label (📷 Photo / 🎥 Video / 🎤 Voice).
      final notificationBody = caption.isNotEmpty ? caption : previewText;
      if (isGroupChat) {
        await _sendGroupNotification(sender, notificationBody);
      } else {
        await _sendDirectNotification(sender, notificationBody);
      }
    } catch (e) {
      debugPrint('Non-critical media follow-up failed: $e');
    }
  }

  @override
  Future<void> close() {
    _messagesSubscription?.cancel();
    _pinnedSubscription?.cancel();
    _typingSubscription?.cancel();
    _typingController.close();
    stopTyping();
    pinnedMessageNotifier.dispose();
    _pinnedController.close();
    ConnectivityService.instance.isConnected
        .removeListener(_onConnectivityChanged);
    _offlineFeedbackController.close();
    return super.close();
  }
}
